#!/usr/bin/env python3
"""Probe which content-part variants bifrost's deserializer accepts in messages[].

Reproduces the Zed Delta failure:

    Failed to deserialize the JSON body into the target type: messages[4]:
    unknown variant `output_text`, expected one of `text`, `image_url`, `file`

The hypothesis under test is that the offending part is not in the *new* turn but
in a *replayed* prior turn: a reasoning-model response (deepseek-v4-flash) stored
by the client and echoed back in `messages[]` on the next request. A fresh
conversation therefore succeeds while a conversation that already contains a
reasoning turn fails.

This probe separates the two variables that matter:

  1. **Part placement** — is a non-standard part rejected only when it appears as
     assistant content in a replayed turn, or anywhere in the body?
  2. **Provider path** — is the rejection the same on `deepseek` (declared
     *native* in bifrost-config.json) as on `qwen` (declared custom with
     `base_provider_type: "openai"`)? If the two differ, the fix is to declare
     DeepSeek as an OpenAI-compatible custom provider, the same shape qwen uses.

Every case is a single request assembled locally — nothing is read from the
gateway, and no state is mutated, so this is safe to run against the live
gateway repeatedly.

Usage:
    scripts/bifrost-content-part-probe.py [BASE_URL] [--models M1,M2] [--only NAME[,NAME...]]
                                           [--list] [--verbose]

BASE_URL defaults to https://ai.fluffy-walleye.ts.net (the served gateway
hostname). The virtual key comes from VK_ZED_DELTA in the environment; if it is
absent the probe still runs and reports the 401/403 it gets, which is itself a
useful signal about whether the key is reaching the gateway.

Stdlib only — no dependencies. Exit code is 0 if the probe ran to completion;
this is a diagnostic, not a pass/fail gate, so the exit code does not encode
which cases failed.
"""

from __future__ import annotations

import argparse
import json
import os
import sys
import time
import urllib.error
import urllib.request

DEFAULT_BASE_URL = "https://ai.fluffy-walleye.ts.net"

# The probe rides the new Zed Delta key, because the failure being diagnosed was
# reported under it. It is accepted on `Authorization: Bearer` today (enforcement
# is off), but the probe sends `x-bf-vk` so it keeps working across the BOX-193
# flip, matching bifrost-reliability-gate.py.
PROBE_VK = os.environ.get("VK_ZED_DELTA", "sk-bf-zed-delta")

CHAT_PATH = "/v1/chat/completions"


# --------------------------------------------------------------------------
# fixtures
# --------------------------------------------------------------------------

def _user(content):
    return {"role": "user", "content": content}


def _assistant_string(content):
    """The baseline: assistant content as a plain string. Every client sends this."""
    return {"role": "assistant", "content": content}


def _assistant_parts(parts):
    """Assistant content as a typed-part array — the shape that fails."""
    return {"role": "assistant", "content": parts}


# A minimal question, so the provider's reply is short and the probe is fast.
ASK = "Reply with the single word: ok"


def _cases():
    """Each case is (name, description, messages, expectation).

    `expectation` is a human-readable prediction, printed next to the observed
    outcome so a surprise is legible rather than buried in a wall of PASS/FAIL.
    """
    return [
        (
            "baseline-string",
            "assistant turn as a plain string — the control",
            [_user("hello"), _assistant_string("hi"), _user(ASK)],
            "accepts (2xx)",
        ),
        (
            "parts-text",
            "assistant turn as typed parts, standard `text` only",
            [
                _user("hello"),
                _assistant_parts([{"type": "text", "text": "hi"}]),
                _user(ASK),
            ],
            "accepts — the documented OpenAI shape",
        ),
        (
            "parts-output_text",
            "assistant turn with `output_text` — the exact reported failure",
            [
                _user("hello"),
                _assistant_parts([{"type": "output_text", "text": "hi"}]),
                _user(ASK),
            ],
            "rejects with `unknown variant output_text`",
        ),
        (
            "parts-reasoning",
            "assistant turn with a `reasoning` part",
            [
                _user("hello"),
                _assistant_parts([{"type": "reasoning", "text": "thinking"}]),
                _user(ASK),
            ],
            "unknown — is DeepSeek's reasoning part also rejected?",
        ),
        (
            "parts-output_text-in-user",
            "`output_text` as *user* content, not assistant",
            [
                _user("hello"),
                _assistant_string("hi"),
                _user([{"type": "output_text", "text": ASK}]),
            ],
            "unknown — does placement within the message list matter?",
        ),
        (
            "parts-output_text-deep",
            "`output_text` in messages[4], reproducing the reported index",
            [
                _user("m0"),
                _assistant_parts([{"type": "output_text", "text": "m1"}]),
                _user("m2"),
                _assistant_string("m3"),
                _user(ASK),
            ],
            "rejects — same error, and the index is reported as 1, not 4",
        ),
        (
            "top-level-reasoning",
            "assistant turn carrying a top-level `reasoning` field (not a part)",
            [
                _user("hello"),
                {"role": "assistant", "content": "hi", "reasoning": "thinking"},
                _user(ASK),
            ],
            "unknown — does a non-part extra field survive?",
        ),
    ]


# --------------------------------------------------------------------------
# transport
# --------------------------------------------------------------------------

def _headers():
    return {"Content-Type": "application/json", "x-bf-vk": PROBE_VK}


def _post(base_url, payload, timeout):
    """POST a chat-completions body. Returns (status, body_text, elapsed).

    Never raises for HTTP errors: a 422 is the interesting outcome here, so it is
    returned like any other response. A transport failure returns status 0.
    """
    body = json.dumps(payload).encode()
    req = urllib.request.Request(
        base_url.rstrip("/") + CHAT_PATH,
        data=body,
        headers=_headers(),
        method="POST",
    )
    start = time.monotonic()
    try:
        with urllib.request.urlopen(req, timeout=timeout) as resp:
            return resp.status, resp.read().decode("utf-8", "replace"), time.monotonic() - start
    except urllib.error.HTTPError as e:
        return e.code, e.read().decode("utf-8", "replace"), time.monotonic() - start
    except (TimeoutError, urllib.error.URLError) as e:
        reason = getattr(e, "reason", e)
        return 0, f"<no response after {timeout}s: {reason}>", time.monotonic() - start


def _summarize(status, body, verbose):
    """One line describing what came back, plus the interesting detail.

    The signal we care about is the deserializer complaint, which appears in a
    non-2xx body. For a 2xx we confirm the model actually replied rather than
    silently no-op'ing.
    """
    if status == 0:
        return "NO RESPONSE", body[:200]

    if 200 <= status < 300:
        try:
            data = json.loads(body)
            content = data["choices"][0]["message"].get("content") or ""
            return f"HTTP {status} ACCEPTED", f"reply={content.strip()[:60]!r}"
        except (ValueError, KeyError, IndexError):
            return f"HTTP {status} ACCEPTED", "<unparseable 2xx body>"

    # An error. Lift the deserializer message out if it is there, since that is
    # the whole point of the probe.
    detail = body
    try:
        data = json.loads(body)
        err = data.get("error")
        if isinstance(err, dict):
            detail = err.get("message") or json.dumps(err)
        elif err:
            detail = str(err)
    except ValueError:
        pass

    detail = detail[:400] if not verbose else detail
    return f"HTTP {status} REJECTED", detail


# --------------------------------------------------------------------------
# main
# --------------------------------------------------------------------------

def main():
    ap = argparse.ArgumentParser(
        description="Probe which content-part variants bifrost accepts in messages[].",
    )
    ap.add_argument("base_url", nargs="?", default=DEFAULT_BASE_URL)
    ap.add_argument(
        "--models",
        default="deepseek-v4-flash,qwen-latest",
        help=(
            "Comma-separated models to run every case against. Default runs one "
            "native provider (deepseek) and one OpenAI-compatible custom provider "
            "(qwen), which is the comparison that decides the fix."
        ),
    )
    ap.add_argument("--only", default=None, help="Comma-separated case names to run.")
    ap.add_argument("--list", action="store_true", help="List case names and exit.")
    ap.add_argument("--timeout", type=float, default=120.0)
    ap.add_argument("--verbose", action="store_true", help="Print full error bodies.")
    args = ap.parse_args()

    cases = _cases()
    if args.list:
        for name, desc, _, expect in cases:
            print(f"{name:28} {desc}")
            print(f"{'':28} expect: {expect}")
        return 0

    if args.only:
        wanted = {s.strip() for s in args.only.split(",") if s.strip()}
        cases = [c for c in cases if c[0] in wanted]
        missing = wanted - {c[0] for c in cases}
        if missing:
            print(f"error: unknown case(s): {sorted(missing)}", file=sys.stderr)
            return 2

    models = [m.strip() for m in args.models.split(",") if m.strip()]

    print(f"base url : {args.base_url}")
    print(f"vk       : {'set' if os.environ.get('VK_ZED_DELTA') else 'NOT SET (expect auth errors)'}")
    print(f"models   : {', '.join(models)}")
    print(f"cases    : {len(cases)}")
    print()

    # observed[case][model] = "ACCEPTED" | "REJECTED" | "NO RESPONSE", so the
    # summary can state the provider-path difference directly.
    observed = {}

    for model in models:
        print(f"=== {model} " + "=" * max(0, 58 - len(model)))
        for name, desc, messages, expect in cases:
            payload = {"model": model, "messages": messages}
            status, body, elapsed = _post(args.base_url, payload, args.timeout)
            verdict, detail = _summarize(status, body, args.verbose)
            label = verdict.split()[-1] if status else "NO-RESPONSE"
            observed.setdefault(name, {})[model] = label

            print(f"  {name}")
            print(f"    what : {desc}")
            print(f"    want : {expect}")
            print(f"    got  : {verdict}  ({elapsed:.2f}s)")
            if detail:
                print(f"    body : {detail}")
            print()

    # The comparison that decides the fix: same case, different provider path.
    print("=== provider-path comparison " + "=" * 31)
    print("A case that is ACCEPTED on qwen but REJECTED on deepseek points at the")
    print("native DeepSeek integration; declaring DeepSeek as an OpenAI-compatible")
    print("custom provider (the shape `qwen` already uses) is then the candidate fix.")
    print()
    if len(models) < 2:
        print("  (only one model given — no comparison possible)")
    else:
        a, b = models[0], models[1]
        for name, _, _, _ in cases:
            va = observed.get(name, {}).get(a, "?")
            vb = observed.get(name, {}).get(b, "?")
            mark = "  <-- DIFFERS" if va != vb else ""
            print(f"  {name:28} {a}={va:10} {b}={vb:10}{mark}")

    return 0


if __name__ == "__main__":
    sys.exit(main())
