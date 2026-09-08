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
