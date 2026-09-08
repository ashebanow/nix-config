# Bifrost reliability gate

Documented, repeatable proof that the bifrost gateway survives the conditions
that made LiteLLM unusable. This is the go/no-go for pointing clients at it
(BOX-135). A smoke test passed on LiteLLM too — the failures were size- and
duration-dependent, so the gate reproduces those specifically.

## Running it

```
just reliability-gate                       # against https://ai.fluffy-walleye.ts.net
just reliability-gate https://other.host    # against another deployment
scripts/bifrost-reliability-gate.py --only long-sustained-stream,tool-roundtrip-deepseek
```

Exit code is 0 only if every selected check passes. Stdlib only, no deps.
Run it after a bifrost version bump, a config change, or whenever something
feels off.

## Checks

| name | what it reproduces | notes |
|---|---|---|
| `stream-body-over-12kb` | Streaming completion with an ~18 KB request body; the only instruction is at the tail. LiteLLM truncated the body at ~12 KB so the tail was lost. | Local model. ~10 s. |
| `prompt-100k-tokens` | A ~130 K-token prompt to the local model; asserts `prompt_tokens ≥ 90 K` so a truncated prompt is caught. | Local model. **~10–12 min** — prefill on this box is ~160 tok/s. The gateway's per-provider timeout is sized for prompts near qwen's full 256 K context, well beyond this. |
| `long-sustained-stream` | A multi-minute generation streamed to completion; asserts `[DONE]` with no silent gap > 30 s. LiteLLM hung mid-stream / tore the connection down. | Local model. ~5 min. |
| `tool-roundtrip-anthropic` | Forced `get_weather` tool call → tool result fed back → final answer that used it, through the native Anthropic provider. | Remote. ~3 s. |
| `tool-roundtrip-deepseek` | Same round trip through the DeepSeek provider. | Remote. ~2 s. |

## Run log

### 2026-09-08 — bifrost v2.0.0 — **5/5 PASS**

| check | result | detail |
|---|---|---|
| `stream-body-over-12kb` | **PASS** | 18 KB body, 185 chunks, 15 s |
| `prompt-100k-tokens` | **PASS** | 527 KB body, 120 022 prompt_tokens ingested, `finish=length`, 827 s |
| `long-sustained-stream` | **PASS** | 3501 chunks, 14.3 K chars, 289 s, max gap 0.4 s |
| `tool-roundtrip-anthropic` | **PASS** | tool_call → result → "The temperature in Paris is **18°C**…" |
| `tool-roundtrip-deepseek` | **PASS** | tool_call → result → "The temperature in Paris is **18°C**…" |

Two fixes were required to reach this pass, both surfaced by the gate itself:

- **BOX-140** (`1a19e9c`) — the local-model hop went over a Tailscale DERP
  relay (two nodes, one host, no hole-punch), which mangles request bodies
  over ~5 KB. `stream-body-over-12kb` failed with a 400 until bifrost was
  moved onto a host-local bridge (`qwen-35b-a3b:8080`).
- **Timeout** (`73f3966`) — `prompt-100k-tokens` hit the gateway's 600 s
  per-provider timeout (`error, latency: 600041 ms`); prefill on this box is
  ~160 tok/s so 100 K tokens needs ~600 s alone. Raised
  `network_config.default_request_timeout_in_seconds` to 2700 (headroom for a
  ~224 K-token prefill near qwen's 256 K context). llama-server itself runs
  `--timeout 0`.

First-pass history (superseded): `stream-body-over-12kb` and
`long-sustained-stream` were green before deploy; `prompt-100k-tokens` was
red on the 600 s timeout; the two tool round trips were green throughout.
