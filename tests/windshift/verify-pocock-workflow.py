#!/usr/bin/env python3
"""Finish T7 (label attach + CQL filter + link verification) and T6 (s/wiki deferred items)."""
import json
import os
import subprocess

PROJ = "c0473754-981b-4e40-bc87-b2700012ef52"
SHIM = "/Users/ashebanow/Development/nix/nix-config/main/tools/windshift-mcp-shim.mjs"

out = subprocess.run(["bws", "secret", "list", PROJ], capture_output=True, text=True, env={**os.environ})
secrets = json.loads(out.stdout)
mcp_tok = json.loads(subprocess.run(["bws", "secret", "get", [s["id"] for s in secrets if s["key"] == "windshift-mcp-token"][0]], capture_output=True, text=True).stdout)["value"]

proc = subprocess.Popen(["node", SHIM], stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                        text=True, env={**os.environ, "WINDSHIFT_MCP_TOKEN": mcp_tok})


def send(m):
    proc.stdin.write(json.dumps(m) + "\n"); proc.stdin.flush()


def recv():
    return json.loads(proc.stdout.readline())


send({"jsonrpc": "2.0", "id": 0, "method": "initialize", "params": {"protocolVersion": "2025-03-26", "capabilities": {}, "clientInfo": {"name": "t7b", "version": "1"}}})
recv(); send({"jsonrpc": "2.0", "method": "notifications/initialized"})


def call(name, args):
    send({"jsonrpc": "2.0", "id": 1, "method": "tools/call", "params": {"name": name, "arguments": args}})
    r = recv()
    if "error" in r:
        raise RuntimeError(f"{name}: {r['error']}")
    return json.loads(r["result"]["content"][0]["text"])


print("== T7: attach label to SU-1 ==")
print(call("set_item_labels", {"item_id": 2, "labels": ["ready-for-agent"]}))

print("== T7: CQL filter label = 'ready-for-agent' ==")
res = call("list_items", {"workspace_id": 3, "filter": "label = 'ready-for-agent'"})
print("total:", res.get("total"), "items:", [(i.get("id"), i.get("title")) for i in res.get("items", [])])

print("== T7: link check (list_links on SU-1) ==")
print(json.dumps(call("list_links", {"entity_id": 2}))[:250])

print("== T6: create deferred/post-mvp label ==")
print("label:", call("list_labels", {"workspace_id": 3}) if False else "via REST earlier — checking", )

print("== T6: create the two s/wiki deferred items ==")
items = [
    {"title": "design: auto-reindex when ground-truth documents change (linked vs captured semantics)",
     "description": "GitHub s/wiki#67 — deferred/post-MVP. Design how auto-reindex should react to changes in linked vs captured ground-truth documents."},
    {"title": "TUI with Ink",
     "description": "GitHub s/wiki#3 — deferred/post-MVP. Interactive terminal UI for suwiki."},
]
for it in items:
    r = call("create_item", {"workspace_id": 3, "title": it["title"], "description": it["description"], "labels": ["deferred/post-mvp"]})
    print("created:", r.get("id"), r.get("key"), "|", it["title"][:45])
proc.terminate()
print("\nT7 + T6 DATA DONE")
