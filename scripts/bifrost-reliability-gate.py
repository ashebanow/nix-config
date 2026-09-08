#!/usr/bin/env python3
"""Bifrost reliability gate — reproduces the conditions that made LiteLLM unusable.

A smoke test passed on LiteLLM too. What broke it was size- and duration-dependent:
streaming request bodies truncated at ~12 KB, and long connections that hung. This
gate reproduces those conditions specifically, plus tool-calling round trips through
the remote providers, against a running bifrost gateway.

Usage:
    scripts/bifrost-reliability-gate.py [BASE_URL] [--only NAME[,NAME...]] [--list]

BASE_URL defaults to https://ai.fluffy-walleye.ts.net (the served gateway hostname).
Point it elsewhere to gate a different deployment, or at the base URL a client is
configured with. Stdlib only — no dependencies.

Exit code is 0 only if every selected check passes.
"""

from __future__ import annotations

import argparse
import json
import sys
import time
import urllib.error
import urllib.request

DEFAULT_BASE_URL = "https://ai.fluffy-walleye.ts.net"
LOCAL_MODEL = "qwen-latest"

# --------------------------------------------------------------------------- io


def _request(base_url, path, payload, timeout):
    """POST JSON, return (status, raw_bytes, elapsed_seconds). Never raises for HTTP
    errors — a non-2xx is returned like any other response so a check can assert on it."""
    body = json.dumps(payload).encode()
    req = urllib.request.Request(
        base_url.rstrip("/") + path,
        data=body,
        headers={"Content-Type": "application/json", "Authorization": "Bearer sk-gate"},
        method="POST",
    )
    start = time.monotonic()
    try:
        with urllib.request.urlopen(req, timeout=timeout) as resp:
            return resp.status, resp.read(), time.monotonic() - start
    except urllib.error.HTTPError as e:
        return e.code, e.read(), time.monotonic() - start
    except (TimeoutError, urllib.error.URLError) as e:
        reason = getattr(e, "reason", e)
        return 0, f"<no response after {timeout}s: {reason}>".encode(), time.monotonic() - start


def _stream(base_url, path, payload, timeout):
    """POST JSON with stream=true. Returns a dict:
        status, text (reassembled assistant content + reasoning), done (saw `[DONE]`),
        chunks (count of SSE data events), elapsed, gap (longest silence between chunks),
        error (upstream error text seen in-stream or in a non-2xx body, or None).
    A non-2xx response is returned like any other — never raised — so a check can
    assert on it and see the body."""
    payload = {**payload, "stream": True}
    body = json.dumps(payload).encode()
    req = urllib.request.Request(
        base_url.rstrip("/") + path,
        data=body,
        headers={"Content-Type": "application/json", "Authorization": "Bearer sk-gate"},
        method="POST",
    )
    text_parts = []
    chunks = 0
    done = False
    error = None
    start = time.monotonic()
    last = start
    gap = 0.0
    try:
        resp = urllib.request.urlopen(req, timeout=timeout)
    except urllib.error.HTTPError as e:
        return {
            "status": e.code,
            "text": "",
            "done": False,
            "chunks": 0,
            "elapsed": time.monotonic() - start,
            "gap": 0.0,
            "error": e.read().decode("utf-8", "replace")[:300],
        }
    with resp:
        status = resp.status
        for raw in resp:
            line = raw.decode("utf-8", "replace").strip()
            if not line.startswith("data:"):
                continue
            data = line[len("data:") :].strip()
            now = time.monotonic()
            gap = max(gap, now - last)
            last = now
            if data == "[DONE]":
                done = True
                break
            chunks += 1
            try:
                obj = json.loads(data)
            except json.JSONDecodeError:
                continue
            if isinstance(obj, dict) and obj.get("error"):
                error = json.dumps(obj["error"])[:300]
            try:
                delta = obj["choices"][0]["delta"]
                text_parts.append(delta.get("content") or delta.get("reasoning_content") or "")
            except (KeyError, IndexError, TypeError):
                pass
    return {
        "status": status,
        "text": "".join(text_parts),
        "done": done,
        "chunks": chunks,
        "elapsed": time.monotonic() - start,
        "gap": gap,
        "error": error,
    }


# ------------------------------------------------------------------------ checks
# Each check is `name -> fn(base_url) -> (ok: bool, note: str)`. Keep the note short;
# it lands in the summary table and the recorded run log.

CHECKS = {}


def check(name):
    def register(fn):
        CHECKS[name] = fn
        return fn

    return register


@check("stream-body-over-12kb")
def _stream_body_over_12kb(base_url):
    """A streaming completion whose request body is well over 12 KB, with the only
    instruction that matters placed at the very end. LiteLLM truncated the body at
    ~12 KB, so the trailing instruction was lost and the marker never came back."""
    marker = f"GATE-OK-{int(time.time())}"
    filler = ("The quick brown fox jumps over the lazy dog. " * 400).strip()
    assert len(filler) > 12_000, "filler must exceed the 12 KB truncation point"
    prompt = (
        f"{filler}\n\n"
        f"Ignore every sentence above. Reply with exactly this token and nothing else: {marker}"
    )
    r = _stream(
        base_url,
        "/v1/chat/completions",
        {
            "model": LOCAL_MODEL,
            "messages": [{"role": "user", "content": prompt}],
            "max_tokens": 512,
        },
        timeout=180,
    )
    body_kb = len(prompt) / 1024
    if r["status"] != 200:
        return False, f"HTTP {r['status']} (body {body_kb:.0f} KB): {r['error']}"
    if not r["done"]:
        return False, f"stream did not terminate with [DONE] (body {body_kb:.0f} KB)"
    if marker not in r["text"]:
        return False, (
            f"trailing instruction not honoured — marker absent "
            f"(body {body_kb:.0f} KB, got {r['text'][-80:]!r})"
        )
    return True, f"body {body_kb:.0f} KB, {r['chunks']} chunks, {r['elapsed']:.1f}s"


@check("prompt-100k-tokens")
def _prompt_100k_tokens(base_url):
    """A ~100K-token prompt against the local model. The gateway must forward the
    whole body and the model must ingest it — a truncated prompt shows up as a far
    smaller prompt_tokens count, or an outright failure.

    Slow by nature: local prefill on this box is ~160 tok/s, so this check takes
    ~10-12 minutes. It validates the >100K path; the gateway's per-provider
    timeout (network_config.default_request_timeout_in_seconds) is sized larger
    still, for prompts approaching qwen's full 256K context."""
    # ~10 tokens per pangram; 12000 of them clears 100K with margin.
    prompt = ("The quick brown fox jumps over the lazy dog. " * 12_000).strip()
    prompt += "\n\nIn one short sentence, what animal is mentioned above?"
    status, raw, elapsed = _request(
        base_url,
        "/v1/chat/completions",
        {
            "model": LOCAL_MODEL,
            "messages": [{"role": "user", "content": prompt}],
            "max_tokens": 64,
        },
        timeout=2700,
    )
    body_kb = len(prompt) / 1024
    if status != 200:
        return False, f"HTTP {status} (body {body_kb:.0f} KB): {raw[:200]!r}"
    try:
        obj = json.loads(raw)
        prompt_tokens = obj["usage"]["prompt_tokens"]
        finish = obj["choices"][0]["finish_reason"]
    except (json.JSONDecodeError, KeyError, IndexError) as e:
        return False, f"unparseable 200 response: {e} ({raw[:150]!r})"
    if prompt_tokens < 90_000:
        return False, f"prompt truncated — only {prompt_tokens} prompt_tokens ingested"
    return True, f"body {body_kb:.0f} KB, {prompt_tokens} prompt_tokens, finish={finish}, {elapsed:.0f}s"


@check("long-sustained-stream")
def _long_sustained_stream(base_url):
    """A long generation streamed to completion. LiteLLM would hang mid-stream or
    tear the connection down; this asserts the stream reaches [DONE] with no
    silent gap longer than 30 s between chunks."""
    prompt = (
        "Write a thorough, self-contained technical explanation of how TCP "
        "congestion control works: slow start, congestion avoidance, fast "
        "retransmit/recovery, CUBIC vs Reno, bufferbloat, and ECN. Aim for at "
        "least 1500 words. Do not stop early."
    )
    r = _stream(
        base_url,
        "/v1/chat/completions",
        {
            "model": LOCAL_MODEL,
            "messages": [{"role": "user", "content": prompt}],
            "max_tokens": 4000,
        },
        timeout=2700,
    )
    if r["status"] != 200:
        return False, f"HTTP {r['status']}: {r['error']}"
    if not r["done"]:
        return False, f"stream ended without [DONE] after {r['elapsed']:.0f}s / {r['chunks']} chunks"
    if r["gap"] > 30:
        return False, f"stalled {r['gap']:.0f}s mid-stream (chunk {r['chunks']}, total {r['elapsed']:.0f}s)"
    if r["chunks"] < 200 or r["elapsed"] < 60:
        return False, f"stream too short to be a real test ({r['chunks']} chunks, {r['elapsed']:.0f}s)"
    return True, f"{r['chunks']} chunks, {len(r['text'])} chars, {r['elapsed']:.0f}s, max gap {r['gap']:.1f}s"


def _tool_roundtrip(base_url, model):
    """Two-turn tool call: force a function call, feed the result back, expect a
    final text answer that used it. Returns (ok, note)."""
    tools = [
        {
            "type": "function",
            "function": {
                "name": "get_weather",
                "description": "Current weather for a city.",
                "parameters": {
                    "type": "object",
                    "properties": {"city": {"type": "string"}},
                    "required": ["city"],
                },
            },
        }
    ]
    msgs = [{"role": "user", "content": "Use the get_weather tool for Paris, then tell me the temperature."}]
    status, raw, _ = _request(
        base_url,
        "/v1/chat/completions",
        {"model": model, "messages": msgs, "tools": tools, "max_tokens": 512},
        timeout=120,
    )
    if status != 200:
        return False, f"turn 1 HTTP {status}: {raw[:200]!r}"
    try:
        m = json.loads(raw)["choices"][0]["message"]
        call = m["tool_calls"][0]
        args = json.loads(call["function"]["arguments"])
    except (json.JSONDecodeError, KeyError, IndexError) as e:
        return False, f"turn 1: no usable tool_call ({e}); got {raw[:200]!r}"
    if call["function"]["name"] != "get_weather" or "paris" not in json.dumps(args).lower():
        return False, f"turn 1: wrong tool call {call['function']['name']}({args})"

    msgs += [
        {"role": "assistant", "content": m.get("content"), "tool_calls": m["tool_calls"]},
        {"role": "tool", "tool_call_id": call["id"], "content": "18°C, partly cloudy"},
    ]
    status, raw, _ = _request(
        base_url,
        "/v1/chat/completions",
        {"model": model, "messages": msgs, "tools": tools, "max_tokens": 512},
        timeout=120,
    )
    if status != 200:
        return False, f"turn 2 HTTP {status}: {raw[:200]!r}"
    try:
        final = json.loads(raw)["choices"][0]["message"]["content"] or ""
    except (json.JSONDecodeError, KeyError, IndexError) as e:
        return False, f"turn 2: unparseable ({e})"
    if "18" not in final:
        return False, f"turn 2: answer did not use the tool result: {final[:120]!r}"
    return True, f"tool_call → result → {final[:60]!r}"


@check("tool-roundtrip-anthropic")
def _tool_roundtrip_anthropic(base_url):
    """A tool-calling round trip through the Anthropic provider — native provider
    type, so bifrost maps tool_use/tool_result correctly."""
    return _tool_roundtrip(base_url, "anthropic/claude-haiku-4-5")


@check("tool-roundtrip-deepseek")
def _tool_roundtrip_deepseek(base_url):
    """A tool-calling round trip through the DeepSeek provider."""
    return _tool_roundtrip(base_url, "deepseek/deepseek-chat")


# ----------------------------------------------------------------------- harness


def main(argv=None):
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument("base_url", nargs="?", default=DEFAULT_BASE_URL)
    p.add_argument("--only", help="comma-separated check names to run (default: all)")
    p.add_argument("--list", action="store_true", help="list check names and exit")
    args = p.parse_args(argv)

    if args.list:
        for name in CHECKS:
            print(name)
        return 0

    selected = list(CHECKS)
    if args.only:
        selected = [n.strip() for n in args.only.split(",")]
        unknown = [n for n in selected if n not in CHECKS]
        if unknown:
            p.error(f"unknown check(s): {', '.join(unknown)}")

    print(f"bifrost reliability gate → {args.base_url}\n")
    results = []
    for name in selected:
        print(f"  {name} ... ", end="", flush=True)
        start = time.monotonic()
        try:
            ok, note = CHECKS[name](args.base_url)
        except Exception as e:  # noqa: BLE001 — a crashed check is a failed check
            ok, note = False, f"{type(e).__name__}: {e}"
        dur = time.monotonic() - start
        results.append((name, ok, note, dur))
        print(f"{'PASS' if ok else 'FAIL'}  ({dur:.1f}s)  {note}")

    print(f"\n{'=' * 72}")
    width = max(len(n) for n, *_ in results)
    for name, ok, note, dur in results:
        print(f"  {'PASS' if ok else 'FAIL'}  {name:<{width}}  {note}")
    passed = sum(1 for _, ok, *_ in results if ok)
    print(f"\n{passed}/{len(results)} checks passed")
    return 0 if passed == len(results) else 1


if __name__ == "__main__":
    sys.exit(main())
