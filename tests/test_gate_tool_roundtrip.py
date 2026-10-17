#!/usr/bin/env python3
"""Behavioural tests for the reliability gate's tool round trip.

A stub gateway answers turn 1 with a tool call, attaching reasoning only from a
chosen attempt onward, and answers turn 2 with a final text. The tests pin the
retry contract of the thinking check: reasoning that appears on a later attempt
passes, reasoning that never appears fails after exactly the allowed attempts, and
a non-thinking round trip never retries.

Run:  python3 -m unittest discover -s tests -v
"""

from __future__ import annotations

import importlib.util
import json
import pathlib
import threading
import unittest
from http.server import BaseHTTPRequestHandler, HTTPServer

_spec = importlib.util.spec_from_file_location(
    "gate",
    pathlib.Path(__file__).resolve().parent.parent / "scripts" / "bifrost-reliability-gate.py",
)
gate = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(gate)


class _ChatStub(BaseHTTPRequestHandler):
    """Turn 1 (no tool message yet) returns a get_weather call, with reasoning from
    attempt `reasoning_from` onward (0 = never). Turn 2 returns a final answer."""

    reasoning_from = 0
    city = "Berlin"
    turn1_attempts = 0

    def log_message(self, *a):  # silence
        pass

    def do_POST(self):
        length = int(self.headers.get("Content-Length") or 0)
        req = json.loads(self.rfile.read(length))
        cls = type(self)
        if any(m.get("role") == "tool" for m in req["messages"]):
            message = {"role": "assistant", "content": "It is 18°C."}
        else:
            cls.turn1_attempts += 1
            message = {
                "role": "assistant",
                "content": None,
                "tool_calls": [
                    {
                        "id": "call-1",
                        "type": "function",
                        "function": {
                            "name": "get_weather",
                            "arguments": json.dumps({"city": cls.city}),
                        },
                    }
                ],
            }
            if cls.reasoning_from and cls.turn1_attempts >= cls.reasoning_from:
                message["reasoning_content"] = "Germany is the longest name."
        body = json.dumps({"choices": [{"message": message}]}).encode()
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)


class ToolRoundtripTestCase(unittest.TestCase):
    reasoning_from = 0
    city = "Berlin"

    def setUp(self):
        _ChatStub.reasoning_from = self.reasoning_from
        _ChatStub.city = self.city
        _ChatStub.turn1_attempts = 0
        self.server = HTTPServer(("127.0.0.1", 0), _ChatStub)
        self.base_url = f"http://127.0.0.1:{self.server.server_port}"
        threading.Thread(target=self.server.serve_forever, daemon=True).start()
        self.addCleanup(self.server.shutdown)

    def thinking_check(self):
        return gate.CHECKS["tool-roundtrip-deepseek-thinking"](self.base_url)


class TestReasoningOnALaterAttempt(ToolRoundtripTestCase):
    reasoning_from = 4

    def test_passes_and_reports_the_attempt(self):
        ok, note = self.thinking_check()
        self.assertTrue(ok, note)
        self.assertEqual(_ChatStub.turn1_attempts, 4)
        self.assertIn(f"attempt 4/{gate.REASONING_ATTEMPTS}", note)


class TestReasoningNeverAppears(ToolRoundtripTestCase):
    reasoning_from = 0

    def test_fails_after_exactly_the_allowed_attempts(self):
        ok, note = self.thinking_check()
        self.assertFalse(ok)
        self.assertEqual(_ChatStub.turn1_attempts, gate.REASONING_ATTEMPTS)
        self.assertIn("no reasoning_content", note)


class TestWrongCityIsNotRetried(ToolRoundtripTestCase):
    reasoning_from = 0
    city = "Paris"

    def test_a_wrong_tool_call_fails_on_the_first_attempt(self):
        ok, note = self.thinking_check()
        self.assertFalse(ok)
        self.assertEqual(_ChatStub.turn1_attempts, 1)
        self.assertIn("wrong tool call", note)


class TestNonThinkingRoundtripDoesNotRetry(ToolRoundtripTestCase):
    reasoning_from = 0
    city = "Paris"

    def test_plain_deepseek_check_makes_one_turn1_request(self):
        ok, note = gate.CHECKS["tool-roundtrip-deepseek"](self.base_url)
        self.assertTrue(ok, note)
        self.assertEqual(_ChatStub.turn1_attempts, 1)


if __name__ == "__main__":
    unittest.main()
