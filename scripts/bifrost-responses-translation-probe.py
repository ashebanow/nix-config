#!/usr/bin/env python3
"""Regression probe for the bifrost Responses→chat-completions translation bug.

Background
----------

bifrost exposes both an OpenAI **Responses API** (`/v1/responses`) and an OpenAI
**chat-completions API** (`/v1/chat/completions`). To reach an upstream provider
it translates Responses `input[]` items into chat-completions `messages[]`.

On bifrost v2.0.0 that translation maps the Responses-only content-part types
(`output_text` for assistant messages, `input_text` for user messages) onto the
chat-completions `text` type **only when the message has a single content part**.
At two or more parts it stops mapping and passes the Responses-only type through
into a deserializer that accepts only `text` / `image_url` / `file`:

    Failed to deserialize the JSON body into the target type: messages[1]:
    unknown variant `output_text`, expected one of `text`, `image_url`, `file`

Real clients hit this constantly and non-deterministically, because an assistant
turn with a "Previous reasoning: ..." preamble plus a reply is two `output_text`
parts, while a bare one-part reply is fine.

This is why the existing `bifrost-content-part-probe.py` never found it: that
probe targets `/v1/chat/completions`, where rejecting `output_text` is *correct*,
and its cases all use a single part. The bug lives on `/v1/responses`.

What this probe asserts
-----------------------

    1-part assistant content  -> expect 2xx   (works on v2.0.0)
    2-part assistant content  -> expect 2xx   (FAILS on v2.0.0: the bug)
    2-part mixed with `text`  -> expect 2xx   (FAILS on v2.0.0)
    2 user parts              -> expect 2xx   (input_text equivalent)
    control, no Responses-only parts -> 2xx   (must always pass)

Exit code is **1 if the bug is present**, 0 if every case passes. That makes it
usable as a gate: run it after a bifrost upgrade and a 0 means the upgrade fixed
it. (Note the contrast with the older probe, which deliberately never signals
pass/fail.)

Usage
-----

    export VK_ZED_DELTA=<value from BWS item bifrost-vk-zed-delta>
    scripts/bifrost-responses-translation-probe.py
    scripts/bifrost-responses-translation-probe.py --models deepseek-v4-flash
    scripts/bifrost-responses-translation-probe.py --list

Stdlib only. Read-only: every request is a single non-streaming POST assembled
locally, nothing is written to the gateway's config or logs store beyond the
ordinary request log.
"""

from __future__ import annotations

import argparse
import json
import os
import sys
import urllib.error
import urllib.request

DEFAULT_BASE_URL = "https://ai.fluffy-walleye.ts.net"
RESPONSES_PATH = "/v1/responses"

# Same key the rest of the tooling uses; enforcement is off today (BOX-193), so
# an unset/incorrect key still serves but logs anonymously.
PROBE_VK = os.environ.get("VK_ZED_DELTA", "sk-bf-zed-delta")

ASK = "Reply with the single word: ok"


def _user(parts):
    """A Responses-API user message. `parts` is a list of content parts."""
    return {"type": "message", "role": "user", "content": parts}


def _assistant(parts):
    """A Responses-API assistant message. `parts` is a list of content parts."""
    return {"type": "message", "role": "assistant", "content": parts}


def _in_text(text):
    return {"type": "input_text", "text": text}


def _out_text(text):
    return {"type": "output_text", "text": text}


def _cases():
    """(name, description, input[], expect_ok) — expect_ok is the CORRECT behaviour."""
    return [
        (
            "single-part-assistant",
            "one `output_text` part — the shape bifrost translates correctly",
            [_user([_in_text("hi")]), _assistant([_out_text("a")]), _user([_in_text(ASK)])],
            True,
        ),
        (
            "two-part-assistant",
            "two `output_text` parts — THE BUG; Delta's preamble+reply shape",
            [
                _user([_in_text("hi")]),
                _assistant([_out_text("a"), _out_text("b")]),
                _user([_in_text(ASK)]),
            ],
            True,
        ),
        (
            "two-part-assistant-mixed",
            "`output_text` + `text` in one message — same failure, shows it is not a count of output_text",
            [
                _user([_in_text("hi")]),
                _assistant([_out_text("a"), {"type": "text", "text": "b"}]),
                _user([_in_text(ASK)]),
            ],
            True,
        ),
        (
            "two-part-user",
            "two `input_text` parts — the user-side equivalent",
            [_user([_in_text("hi"), _in_text("there")]), _user([_in_text(ASK)])],
            True,
        ),
        (
            "two-messages-one-part-each",
            "two separate one-part assistant turns — must keep working",
            [
                _user([_in_text("hi")]),
                _assistant([_out_text("a")]),
                _user([_in_text("q")]),
                _assistant([_out_text("b")]),
                _user([_in_text(ASK)]),
            ],
            True,
        ),
        (
            "control-multi-part-plain-text",
            "two plain `text` parts — no Responses-only type, must always pass",
            [
                _user([{"type": "text", "text": "hi"}]),
                _assistant([{"type": "text", "text": "a"}, {"type": "text", "text": "b"}]),
                _user([_in_text(ASK)]),
            ],
            True,
        ),
    ]


def _post(base_url, payload, timeout):
    body = json.dumps(payload).encode()
    req = urllib.request.Request(
        base_url.rstrip("/") + RESPONSES_PATH,
        data=body,
        headers={"Content-Type": "application/json", "x-bf-vk": PROBE_VK},
        method="POST",
    )
    try:
        with urllib.request.urlopen(req, timeout=timeout) as resp:
            return resp.status, resp.read().decode("utf-8", "replace")
    except urllib.error.HTTPError as e:
        return e.code, e.read().decode("utf-8", "replace")
    except (TimeoutError, urllib.error.URLError) as e:
        return 0, f"<no response: {getattr(e, 'reason', e)}>"


def _detail(status, body):
    """Lift the deserializer message out, since that is the signal."""
    if status == 0:
        return body[:200]
    try:
        data = json.loads(body)
    except ValueError:
        return body[:200]
    if 200 <= status < 300:
        try:
            for item in data.get("output", []):
                if item.get("type") == "message":
                    for part in item.get("content", []):
                        if part.get("type") == "output_text":
                            return f"reply={part.get('text', '').strip()[:50]!r}"
            return "<2xx, no output_text found>"
        except (AttributeError, TypeError):
            return "<unparseable 2xx body>"
    err = data.get("error")
    if isinstance(err, dict):
        return (err.get("message") or json.dumps(err))[:300]
    return str(err)[:300] if err else body[:200]


def main():
    ap = argparse.ArgumentParser(
        description="Regression probe for bifrost's Responses->chat-completions part-type bug.",
    )
    ap.add_argument("base_url", nargs="?", default=DEFAULT_BASE_URL)
    ap.add_argument("--models", default="deepseek-v4-flash,qwen-latest")
    ap.add_argument("--only", default=None, help="Comma-separated case names.")
    ap.add_argument("--timeout", type=float, default=180.0)
    ap.add_argument("--list", action="store_true")
    args = ap.parse_args()

    cases = _cases()
    if args.list:
        for name, desc, _, _ in cases:
            print(f"{name:34} {desc}")
        return 0

    if args.only:
        wanted = {s.strip() for s in args.only.split(",") if s.strip()}
        cases = [c for c in cases if c[0] in wanted]
        missing = wanted - {c[0] for c in cases}
        if missing:
            print(f"error: unknown case(s): {sorted(missing)}", file=sys.stderr)
            return 2

    models = [m.strip() for m in args.models.split(",") if m.strip()]

    print(f"base url : {args.base_url}{RESPONSES_PATH}")
    print(f"vk       : {'set' if os.environ.get('VK_ZED_DELTA') else 'NOT SET'}")
    print(f"models   : {', '.join(models)}")
    print()

    failures = []

    for model in models:
        print(f"=== {model} " + "=" * max(0, 55 - len(model)))
        for name, desc, messages, expect_ok in cases:
            status, body = _post(
                args.base_url, {"model": model, "input": messages}, args.timeout
            )
            ok = 200 <= status < 300
            bug = ok != expect_ok
            verdict = "pass" if not bug else "BUG"
            if bug:
                failures.append((model, name))
            print(f"  [{verdict}] {name}")
            print(f"          {desc}")
            print(f"          HTTP {status}: {_detail(status, body)}")
        print()

    print("=== summary " + "=" * 46)
    if failures:
        print(f"The translation bug is PRESENT ({len(failures)} failing case(s)):")
        for model, name in failures:
            print(f"  - {name} on {model}")
        print()
        print("Expected on bifrost v2.0.0. Re-run after upgrading bifrost; a")
        print("clean run means the upgrade fixed it.")
        return 1
    print("All cases passed — the Responses translation bug appears FIXED.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
