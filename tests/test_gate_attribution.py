#!/usr/bin/env python3
"""Behavioural tests for the reliability gate's attribution check (BOX-195).

These test behaviour, not parameter validation: each test drives a real code path
against a stub HTTP server and asserts on the *outcome* — whether a request is
judged attributable, whether a missing log row is caught, whether the VK header
reaches the gateway.

The stub server stands in for bifrost's `/api/logs`, so the tests pin the
contract the gate depends on (log rows carry `virtual_key_name`; filtering by it
narrows results) without needing a live gateway. The live path is covered by
`just reliability-gate` itself.

Run:  python3 -m unittest discover -s tests -v
"""

from __future__ import annotations

import json
import pathlib
import sys
import threading
import unittest
import urllib.error
from http.server import BaseHTTPRequestHandler, HTTPServer

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent.parent / "scripts"))

import importlib.util

_spec = importlib.util.spec_from_file_location(
    "gate",
    pathlib.Path(__file__).resolve().parent.parent / "scripts" / "bifrost-reliability-gate.py",
)
gate = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(gate)
# Keep the failing-path tests off the clock: the poll deadline is real behaviour,
# but waiting it out would add ~90s of sleep across the suite. Set after exec so
# the module's own default (read from the environment at import) does not win.
gate.ATTRIBUTION_DEADLINE_S = 0


class _StubHandler(BaseHTTPRequestHandler):
    """Serves `/api/logs` from a fixture list, honouring a virtual_key_name filter
    the way bifrost's real endpoint does."""

    rows: list = []
    seen_headers: list = []

    def log_message(self, *a):  # silence
        pass

    def do_POST(self):
        length = int(self.headers.get("Content-Length") or 0)
        self.rfile.read(length)
        type(self).seen_headers.append(dict(self.headers))
        body = json.dumps({"choices": [{"message": {"content": "ok"}}]}).encode()
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self):
        from urllib.parse import parse_qs, urlparse

        q = parse_qs(urlparse(self.path).query)
        rows = list(type(self).rows)
        vk = (q.get("virtual_key_name") or [None])[0]
        if vk:
            rows = [r for r in rows if r.get("virtual_key_name") == vk]
        body = json.dumps({"logs": rows}).encode()
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)


class AttributionTestCase(unittest.TestCase):
    """Base: run a stub gateway for the duration of a test."""

    rows: list = []

    def setUp(self):
        _StubHandler.rows = list(self.rows)
        _StubHandler.seen_headers = []
        self.server = HTTPServer(("127.0.0.1", 0), _StubHandler)
        self.base_url = f"http://127.0.0.1:{self.server.server_port}"
        t = threading.Thread(target=self.server.serve_forever, daemon=True)
        t.start()
        self.addCleanup(self.server.shutdown)

    def headers_seen(self):
        return _StubHandler.seen_headers


def _row(vk_name, vk_id="vk-1", ts="2026-09-16T18:00:00Z", user=None):
    row = {
        "id": "log-1",
        "timestamp": ts,
        "virtual_key_id": vk_id if vk_name else None,
        "virtual_key_name": vk_name,
        "user_id": None,
        "user_name": user,
    }
    return row


class TestFindLogRow(AttributionTestCase):
    """The gate must locate the log row for a request it just made."""

    rows = [_row("gate")]

    def test_finds_row_by_virtual_key_name(self):
        row = gate._find_log_row(self.base_url, "gate", timeout=5)
        self.assertIsNotNone(row, "expected to find the gate's own log row")
        self.assertEqual(row["virtual_key_name"], "gate")

    def test_returns_none_when_no_row_carries_that_key(self):
        row = gate._find_log_row(self.base_url, "pi", timeout=5)
        self.assertIsNone(row, "a key with no traffic must not resolve to a row")

    def test_anonymous_traffic_does_not_satisfy_a_named_key(self):
        """The whole point: rows exist, but none is attributed. Must not pass."""
        row = gate._find_log_row(self.base_url, "raycast", timeout=5)
        self.assertIsNone(row)


class TestAttributionCheck(AttributionTestCase):
    """End-to-end behaviour of the `attribution` check."""

    rows = [_row("gate")]

    def test_passes_when_the_request_is_attributed(self):
        ok, note = gate.CHECKS["attribution"](self.base_url)
        self.assertTrue(ok, f"expected PASS, got: {note}")
        self.assertIn("gate", note)

    def test_fails_when_the_gateway_did_not_record_a_virtual_key(self):
        """The regression this exists to catch: a client silently drops out of the
        log and nothing else notices, because enforcement is off."""
        _StubHandler.rows = [_row(None)]
        ok, note = gate.CHECKS["attribution"](self.base_url)
        self.assertFalse(ok, "unattributed traffic must FAIL the gate")
        self.assertIn("not attributed", note.lower())

    def test_fails_when_no_log_rows_exist_at_all(self):
        _StubHandler.rows = []
        ok, note = gate.CHECKS["attribution"](self.base_url)
        self.assertFalse(ok)

    def test_sends_the_virtual_key_so_the_gateway_can_attribute_it(self):
        gate.CHECKS["attribution"](self.base_url)
        seen = self.headers_seen()
        self.assertTrue(seen, "check must actually issue a request")
        hdrs = {k.lower(): v for k, v in seen[0].items()}
        self.assertIn("x-bf-vk", hdrs, "VK must ride x-bf-vk, which survives enforcement")
        self.assertEqual(hdrs["x-bf-vk"], gate.GATE_VK)


class TestVKIsNotAuthorization(AttributionTestCase):
    """x-bf-vk works whether or not enforcement is on; Authorization only works
    while `disable_auth_on_inference` is true. The gate must not depend on the
    latter, or BOX-193 silently breaks it."""

    rows = [_row("gate")]

    def test_key_is_sent_on_x_bf_vk_not_authorization(self):
        gate.CHECKS["attribution"](self.base_url)
        hdrs = {k.lower(): v for k, v in self.headers_seen()[0].items()}
        self.assertEqual(hdrs.get("x-bf-vk"), gate.GATE_VK)
        auth = hdrs.get("authorization", "")
        self.assertNotIn(
            gate.GATE_VK, auth, "the VK must not be carried on Authorization"
        )


class TestDeclaredClientKeys(unittest.TestCase):
    """The gate's VK must be one of the keys the gateway is told to declare. This
    catches the drift where a ticket adds traffic under a name T1 never seeded."""

    def test_gate_vk_is_declared_in_gateway_config(self):
        cfg_path = (
            pathlib.Path(__file__).resolve().parent.parent
            / "compose"
            / "llm"
            / "bifrost-config.json"
        )
        cfg = json.loads(cfg_path.read_text())
        keys = cfg.get("governance", {}).get("virtual_keys", [])
        names = {k.get("name") for k in keys}
        self.assertIn(
            gate.GATE_VK_NAME,
            names,
            f"gate VK {gate.GATE_VK_NAME!r} is not declared in bifrost-config.json; "
            f"declared: {sorted(names)}",
        )

    def test_every_declared_key_resolves_from_the_environment(self):
        """No key value may be committed. Every declared value must be env-indirected."""
        cfg_path = (
            pathlib.Path(__file__).resolve().parent.parent
            / "compose"
            / "llm"
            / "bifrost-config.json"
        )
        cfg = json.loads(cfg_path.read_text())
        keys = cfg.get("governance", {}).get("virtual_keys", [])
        self.assertTrue(keys, "no virtual keys declared — nothing to verify")
        for k in keys:
            self.assertTrue(
                str(k.get("value", "")).startswith("env."),
                f"virtual key {k.get('name')!r} has a literal value; "
                f"values must be `env.NAME` indirection",
            )

    def test_enforcement_is_still_off(self):
        """BOX-194 must not flip this; that is BOX-193's job and a separate risk."""
        cfg_path = (
            pathlib.Path(__file__).resolve().parent.parent
            / "compose"
            / "llm"
            / "bifrost-config.json"
        )
        cfg = json.loads(cfg_path.read_text())
        self.assertFalse(
            cfg["client"]["enforce_auth_on_inference"],
            "enforce_auth_on_inference must remain false in BOX-194",
        )


class TestProviderAccess(unittest.TestCase):
    """A virtual key with no `provider_configs` is denied *every* provider, even
    with enforcement off — the gateway answers 403 `provider_blocked`, which
    breaks a client the moment it starts sending its key.

    Found by hand against the live gateway (BOX-194): anonymous → 200, keyed →
    403. These tests pin the fix so a future key cannot be added without provider
    access and silently 403 its client.
    """

    @staticmethod
    def _keys():
        cfg_path = (
            pathlib.Path(__file__).resolve().parent.parent
            / "compose"
            / "llm"
            / "bifrost-config.json"
        )
        return json.loads(cfg_path.read_text()).get("governance", {}).get("virtual_keys", [])

    def test_every_key_grants_provider_access(self):
        keys = self._keys()
        self.assertTrue(keys, "no virtual keys declared")
        for k in keys:
            self.assertTrue(
                k.get("provider_configs"),
                f"virtual key {k.get('name')!r} declares no provider_configs — "
                f"it will be denied every provider with 403 provider_blocked",
            )

    def test_every_key_can_reach_each_declared_provider(self):
        """The provider set is shared across clients today; assert it matches the
        gateway's configured providers so a new provider is not silently
        unreachable to every key."""
        cfg_path = (
            pathlib.Path(__file__).resolve().parent.parent
            / "compose"
            / "llm"
            / "bifrost-config.json"
        )
        cfg = json.loads(cfg_path.read_text())
        providers = set(cfg.get("providers", {}))
        self.assertTrue(providers, "no providers configured")
        for k in cfg["governance"]["virtual_keys"]:
            allowed = {p.get("provider") for p in k.get("provider_configs", [])}
            self.assertEqual(
                providers,
                allowed,
                f"virtual key {k.get('name')!r} cannot reach "
                f"{sorted(providers - allowed)}; a client using it would 403",
            )

    def test_provider_configs_carry_weight_and_explicit_models(self):
        """`provider_configs` needs `weight` and `allowed_models`, and `["*"]` is
        documented but unreliably blocks every model (upstream #6657, #2717).

        Both were found by hand against the live gateway: entries with only
        `provider` were dropped on config.json → DB sync (the
        `governance_virtual_key_provider_configs` table stayed empty), and the
        key then 403'd with `provider_blocked`. Enumerate models explicitly.
        """
        cfg_path = (
            pathlib.Path(__file__).resolve().parent.parent
            / "compose"
            / "llm"
            / "bifrost-config.json"
        )
        cfg = json.loads(cfg_path.read_text())
        for k in cfg["governance"]["virtual_keys"]:
            for pc in k.get("provider_configs", []):
                where = f"{k.get('name')}/{pc.get('provider')}"
                self.assertIn("weight", pc, f"{where}: provider_config needs a weight")
                models = pc.get("allowed_models")
                self.assertTrue(models, f"{where}: allowed_models must not be empty")
                self.assertNotIn(
                    "*", models, f"{where}: wildcard models are unreliable upstream; list them"
                )

    def test_allowed_models_match_what_the_provider_declares(self):
        """A key may only reach models the provider actually serves — an allowed
        model that no provider key offers is a latent `model_blocked`."""
        cfg_path = (
            pathlib.Path(__file__).resolve().parent.parent
            / "compose"
            / "llm"
            / "bifrost-config.json"
        )
        cfg = json.loads(cfg_path.read_text())
        declared = {
            prov: {m for k2 in pcfg.get("keys", []) for m in k2.get("models", [])}
            for prov, pcfg in cfg["providers"].items()
        }
        for k in cfg["governance"]["virtual_keys"]:
            for pc in k.get("provider_configs", []):
                allowed = set(pc.get("allowed_models") or [])
                served = declared.get(pc.get("provider"), set())
                extra = allowed - served
                self.assertFalse(
                    extra,
                    f"{k.get('name')}/{pc.get('provider')} allows {sorted(extra)}, "
                    f"which that provider does not declare",
                )


class TestExpectedClients(unittest.TestCase):
    """One key per client tool, per the design's D2."""

    def test_all_client_keys_are_declared(self):
        cfg_path = (
            pathlib.Path(__file__).resolve().parent.parent
            / "compose"
            / "llm"
            / "bifrost-config.json"
        )
        cfg = json.loads(cfg_path.read_text())
        keys = cfg.get("governance", {}).get("virtual_keys", [])
        names = {k.get("name") for k in keys}
        expected = {"pi", "hermes", "zed", "raycast", "openwebui", "gate"}
        self.assertEqual(
            expected,
            names,
            f"declared keys and the design's client set diverge; "
            f"missing: {sorted(expected - names)}, extra: {sorted(names - expected)}",
        )

    def test_every_key_carries_a_distinct_env_var(self):
        """Two keys sharing a value would collapse into one identity in the log."""
        cfg_path = (
            pathlib.Path(__file__).resolve().parent.parent
            / "compose"
            / "llm"
            / "bifrost-config.json"
        )
        cfg = json.loads(cfg_path.read_text())
        vals = [
            k.get("value") for k in cfg.get("governance", {}).get("virtual_keys", [])
        ]
        self.assertTrue(vals, "no virtual keys declared — nothing to verify")
        self.assertEqual(len(vals), len(set(vals)), f"duplicate VK values: {vals}")


if __name__ == "__main__":
    unittest.main()
