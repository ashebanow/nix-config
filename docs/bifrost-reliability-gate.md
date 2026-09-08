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

### 2026-09-08 — bifrost v2.0.0, first full pass

| check | result | detail |
|---|---|---|
| `stream-body-over-12kb` | **PASS** | 18 KB body, 100 chunks, 9.6 s |
| `prompt-100k-tokens` | **FAIL → fix pending deploy** | Hit the gateway's 600 s per-provider timeout (`error, latency: 600041 ms`). Prefill measured at 166 tok/s ⇒ ~603 s for 100 K tokens, before generation. Fix: `network_config.default_request_timeout_in_seconds` 600 → 2700 (covers a ~224 K-token prefill even at a pessimistic ~90 tok/s). Re-verify after deploy. |
| `long-sustained-stream` | **PASS** | 3999 chunks, 16.3 K chars, 330 s, max gap 0.5 s |
| `tool-roundtrip-anthropic` | **PASS** | tool_call → result → "The temperature in Paris is **18°C**…" |
| `tool-roundtrip-deepseek` | **PASS** | tool_call → result → "The temperature in Paris is currently **18°C**…" |

Related fixes surfaced by this gate: the local-model path was moved off the
Tailscale/DERP relay onto a host-local bridge (BOX-140, commit `1a19e9c`) —
without that, `stream-body-over-12kb` failed with a 400 because DERP mangles
request bodies over ~5 KB.
