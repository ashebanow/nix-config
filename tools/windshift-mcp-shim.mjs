#!/usr/bin/env node
// Windshift MCP stdio shim for pi (pi-mcp-extension cannot set headers/OAuth).
// Bridges MCP stdio <-> Streamable HTTP at $WINDSHIFT_MCP_URL, injecting the
// bearer token. Token resolution order:
//   1. WINDSHIFT_MCP_TOKEN env
//   2. bws secret get (BWS_ACCESS_TOKEN in env; item windshift-mcp-token)
//   3. ~/.config/windshift-mcp/token file (0600)
import { createInterface } from "node:readline";
import { readFileSync } from "node:fs";
import { homedir } from "node:os";
import path from "node:path";
import { execFileSync } from "node:child_process";

const URL = process.env.WINDSHIFT_MCP_URL || "https://windshift.fluffy-walleye.ts.net/mcp";

function resolveToken() {
  if (process.env.WINDSHIFT_MCP_TOKEN) return process.env.WINDSHIFT_MCP_TOKEN;
  try {
    const out = execFileSync("bws", ["secret", "get", "windshift-mcp-token"], {
      encoding: "utf8",
      env: { ...process.env },
    });
    const v = JSON.parse(out).value;
    if (v) return v;
  } catch {}
  try {
    return readFileSync(path.join(homedir(), ".config/windshift-mcp/token"), "utf8").trim();
  } catch {}
  throw new Error("windshift-mcp: no token (WINDSHIFT_MCP_TOKEN / BWS windshift-mcp-token / ~/.config/windshift-mcp/token)");
}

const TOKEN = resolveToken();

async function post(payload) {
  const res = await fetch(URL, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      Accept: "application/json, text/event-stream",
      Authorization: `Bearer ${TOKEN}`,
      "Sec-Fetch-Site": "none",
    },
    body: JSON.stringify(payload),
  });
  const text = await res.text();
  if (res.status !== 200 && res.status !== 202) {
    throw new Error(`windshift-mcp: HTTP ${res.status}: ${text.slice(0, 300)}`);
  }
  if (!text.trim()) return null; // 202 for notifications
  const ctype = res.headers.get("content-type") || "";
  if (ctype.includes("text/event-stream")) {
    const data = text
      .split("\n")
      .filter((l) => l.startsWith("data:"))
      .map((l) => l.slice(5).trim())
      .join("");
    return data ? JSON.parse(data) : null;
  }
  return JSON.parse(text);
}

const rl = createInterface({ input: process.stdin, terminal: false });
rl.on("line", async (line) => {
  let msg;
  try {
    msg = JSON.parse(line);
  } catch {
    return;
  }
  try {
    const result = await post(msg);
    if (result && msg.id !== undefined) process.stdout.write(JSON.stringify(result) + "\n");
  } catch (err) {
    if (msg.id !== undefined) {
      process.stdout.write(
        JSON.stringify({ jsonrpc: "2.0", id: msg.id, error: { code: -32000, message: String(err.message) } }) + "\n"
      );
    }
  }
});
