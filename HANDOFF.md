# Handoff — Zed Delta ↔ bifrost Responses API round-trip failure

**Status:** root cause **confirmed** from gateway ground truth. No fix applied.
**Written:** end of the lumquat session, 2026-10-08.
**Supersedes:** the earlier version of this file, whose two hypotheses are both
falsified (see "What this session killed").

---

## The failure

Zed's **Delta** tool (`Delta/0.19.1/stable (macos; aarch64)`) pointed at the
bifrost gateway fails on real tool-using conversations:

```
Bifrost error: Failed to deserialize the JSON body into the target type:
messages[4]: unknown variant `output_text`, expected one of `text`,
`image_url`, `file` at line 1 column 37691
```

And a **fresh** conversation fails differently, client-side:

```
The custom provider returned an invalid response.
```

Both are now explained by one defect. It is not auth, not the key, and not
DeepSeek.

## Root cause: bifrost's Responses→chat-completions bridge drops the part-type mapping on multi-part assistant messages

**Answer to "does Delta's endpoint choice matter?": no.** Delta already sends
`/v1/responses`, and the real failing body fails *on that endpoint*:

```
POST /v1/responses  (Delta's actual 169-item body, 124 KB)
-> 422 messages[3]: unknown variant `output_text` (request_id 9392de4a-…)
```

Switching Zed's provider from the Chat API to the Responses API would change
nothing, because the Responses path is where the failure already occurs. Switching
to the Chat API would not help either — Delta emits `output_text` by design.

### The exact trigger (bisected from the real body)

The bridge maps `output_text` → `text` correctly for a **single-part** assistant
message and stops mapping it at **two or more** parts:

| `input[]` assistant message content | result |
| -- | -- |
| `[{output_text, "a"}]` | **200 OK** |
| `[{text, "a"}, {text, "b"}]` (control) | **200 OK** |
| `[{output_text, "a"}, {output_text, "b"}]` | **422** `unknown variant output_text` |
| `[{output_text, "a"}, {text, "b"}]` | **422** `unknown variant output_text` |
| two separate assistant messages, one part each | **200 OK** |

Refined by `scripts/bifrost-responses-translation-probe.py`, which also shows the
bug is narrower than "multi-part":

| case | deepseek | qwen |
| -- | -- | -- |
| one `output_text` part | pass | pass |
| **two `output_text` parts** | **BUG 422** | **BUG 400** |
| **`output_text` + `text` in one message** | **BUG 422** | **BUG 400** |
| two `input_text` parts (user side) | pass | pass |
| two separate one-part assistant messages | pass | pass |
| two plain `text` parts (control) | pass | pass |

So the defect is specifically **multi-part *assistant* messages containing
`output_text`**. The user-side `input_text` equivalent translates fine, plain
`text` multi-part is fine, and the part count is per message, not per request.

Delta emits multi-part assistant messages routinely — its
`"Previous reasoning:\n\n…"` preamble plus the reply become two `output_text`
parts — so it fails constantly, but not deterministically. That non-determinism is
the whole reason this diagnosis took more than one pass.

This single bug accounts for **all** real failures. See "Retracted" below for a
false second bug that an earlier draft of this file reported.

### The two APIs disagree about the same token (why it looked like a config problem)

| Direction | Shape | Verdict |
| -- | -- | -- |
| Responses **response** (what bifrost emits) | `output[].content[].type == "output_text"` | produced by bifrost |
| chat-completions **request** (what bifrost accepts) | `messages[].content[].type ∈ {text, image_url, file}` | `output_text` **rejected** |

Verified live, same gateway, minutes apart:

```bash
# emits output_text (HTTP 200)
curl -sS https://ai.fluffy-walleye.ts.net/v1/responses \
  -H "Authorization: Bearer $VK_ZED_DELTA" -H 'Content-Type: application/json' \
  -d '{"model":"qwen-latest","input":"say ok"}'
# -> "output":[{"type":"reasoning",...},
#              {"type":"message",...,"content":[{"type":"output_text","text":"ok",...}]}]
```

So: Delta speaks the **Responses API**, bifrost answers in Responses shape, Delta
stores that history verbatim, replays it on the next turn, and bifrost's
translation layer — which must down-convert Responses items into
chat-completions `messages[]` — **passes `output_text` through unchanged** into a
deserializer that only knows `text`/`image_url`/`file`. The gateway rejects a body
it generated.

This also explains the fresh-conversation error: the *first* turn works, the
*second* fails, because only the second carries replayed `output_text`. A
"brand-new conversation" that still fails is one where Delta had already recorded
one assistant turn.

## Ground truth (this session)

Extracted from the gateway's own log DB. The log volume lives in the named
volume; the container has no `sqlite3`/`python3`, so copy it out first:

```bash
podman cp bifrost-app:/app/data/logs.db /tmp/logs.db   # + -wal, -shm
sqlite3 /tmp/logs.db "select ... from logs where ..."
```

Useful columns: `timestamp`, `object_type`, `model`, `status`,
`virtual_key_name`, `user_agent`, `error_details`, `responses_input_history`,
`raw_request`, `passthrough_request_body`.

- The original `request_id 18116cad-…` was located. `raw_request` and
  `passthrough_request_body` are **empty** — the request died in deserialization,
  before recording. The body survives in **`responses_input_history`** (122 KB)
  on row `f1cbf988-7b19-4bec-80a3-3537254268ba`.
- That body is a **Responses-shaped `input[]` of 169 items** — `function_call` ×61,
  `function_call_output` ×61, `message` ×47 — **not** `messages[]`. Item 1 is an
  assistant message whose content is exactly
  `[{"type":"output_text","text":"Previous reasoning:\n\n…"}]`. Items 8, 11, 31,
  36, 39, 41 … are the same shape with two `output_text` parts.
- **There are no `reasoning` items in the real body at all** (`reasoning` count
  = 0). The offending part is `output_text` in a replayed **assistant message**.
- Delta's traffic is `responses_stream` (5 × `claude-fable-5-1` — all `cancelled`,
  499 client-disconnect, i.e. Delta gave up; 4 × `deepseek-v4-flash` — the 422s,
  three of them the *identical* 37 KB body).

## What this session killed

Both hypotheses in the previous handoff are **falsified**. Do not act on them.

1. **"The native DeepSeek integration is at fault" — dead.** The probe's
   decisive row is *rejected on both models*:

   | case | deepseek-v4-flash | qwen-latest |
   | -- | -- | -- |
   | baseline-string | ACCEPTED | ACCEPTED |
   | parts-text | ACCEPTED | ACCEPTED |
   | parts-output_text | REJECTED 422 | REJECTED 400 |
   | parts-reasoning | REJECTED 422 | REJECTED 400 |
   | parts-output_text-in-user | REJECTED 422 | REJECTED 400 |
   | parts-output_text-deep | REJECTED 422 | REJECTED 400 |
   | top-level-reasoning | ACCEPTED | ACCEPTED |

   `qwen` is *already* declared `base_provider_type: "openai"` and still rejects.
   The proposed fix — redeclare DeepSeek as a custom OpenAI-compatible provider —
   **would have changed nothing**. (The 422-vs-400 split is only *which layer*
   rejects: native Rust deserializer vs. custom-provider passthrough.)

   Note these rejections are on the **chat-completions** endpoint, where
   `output_text` is invalid regardless of part count — so they are *correct*
   behaviour and are **not** evidence for the real bug. The probe was built
   against the wrong endpoint; only the `responses_stream` rows in the gateway
   log and the direct `/v1/responses` reproduction expose the actual defect.
2. **"A replayed *reasoning* turn is the trigger; placement matters" — dead.**
   `parts-output_text-in-user` rejects too. Placement is irrelevant: any part
   outside `text|image_url|file` is rejected anywhere in `messages[]`. And the
   real body contains no `reasoning` items whatsoever.
3. **"The gateway/key/routing might be involved" — still dead**, as before.

The previous handoff's step 1 ("start a fresh conversation") was run and failed
— that failure, not a pass, is what pointed at the Responses API.

## The fix (not yet applied) — upstream bifrost, and NO version fixes it

**Verified in bifrost source.** The defect is a missing `case` in
`core/schemas/mux.go`, in `ToChatMessages()` (v2.2.6, lines ~919-937):

```go
if rm.Content.ContentStr != nil ||
    (len(rm.Content.ContentBlocks) == 1 &&
        (rm.Content.ContentBlocks[0].Type == ResponsesInputMessageContentBlockTypeText ||
         rm.Content.ContentBlocks[0].Type == ResponsesOutputMessageContentTypeText)) {
    // <- single-part short-circuit: handles BOTH input_text and output_text.
    //    This is why 1 part works.
} else if rm.Content.ContentBlocks != nil {
    for i, block := range rm.Content.ContentBlocks {
        switch block.Type {
        case ResponsesInputMessageContentBlockTypeText:  // "input_text" -> "text"
        case ResponsesInputMessageContentBlockTypeImage: // "input_image" -> "image_url"
        case ResponsesInputMessageContentBlockTypeFile:  // "input_file" -> "file"
        case ResponsesInputMessageContentBlockTypeAudio: // "input_audio"
        default:
            chatBlockType = ChatContentBlockType(block.Type)  // <-- BUG: "output_text" passed through
        }
    }
}
```

The single-part path explicitly accepts `ResponsesOutputMessageContentTypeText`;
the multi-part `switch` does **not** have that case, so `output_text` falls to
`default:` and is copied verbatim into a chat block. `chatcompletions.go:1300-1307`
allows only `text`/`image_url`/`input_audio`/`file`, which is exactly the error
(`expected one of \`text\`, \`image_url\`, \`file\``).

Upstream one-line fix:

```go
case ResponsesOutputMessageContentTypeText:
    chatBlockType = ChatContentBlockTypeText // "output_text" -> "text"
```

### No released version fixes this — do not upgrade for it

**The bug is present in every release after v2.0.0, and on `main` and `dev`.**
The `case` list above is unchanged in `transports/v2.0.0`, `v2.1.0`, `v2.2.0`,
`v2.2.6`, `main`, and `dev`. No `output_text` case has ever been added.

- Releases after v2.0.0 (all `transports/*`; the image tracks this line):
v2.1.0 (2026-09-08), v2.1.1, v2.2.0 (09-15), v2.2.1, v2.2.2, v2.2.3, v2.2.4,
v2.2.5 (10-02), **v2.2.6 (10-06, latest)**. v2.0.0 is ~6 weeks and 10 releases
behind — but none of them help here.
- Open PR **#8142** ("keep Responses assistant output in one Chat choice")
touches `mux.go` but only the *reverse* direction (`ToBifrostChatResponse`). It
will **not** fix this if merged.
- Release-note hits for `output_text`/`input_text` in v2.2.0 are a **different**
bug (#7074/#7075, Bedrock Responses `input_text` mistagging). Not this one.
- **No upstream issue exists for this.** Filing is warranted.

Options, cheapest first:

1. **File upstream.** No issue exists, the defect is one missing `case`, and the
   reproducer below is 3 lines. Highest-value action.
2. **Patch and run a locally-built image** if a fix is wanted before upstream
   responds. Note the build/publish burden of a forked gateway image.
3. **Upgrade to v2.2.6 only for other reasons** — not for this. It also carries
   real migration cost: `setup_token` now required for non-public `/api`,
   **`enforce_auth_on_inference` now defaults to `true`** (would flip BOX-193's
   intent), `mcp_servers`→`mcp_configs`, `routing_debug`→`routing_metadata`, and
   VK budget/rate-limit DB migrations. Do not bundle that into this fix.
4. **Client-side workaround: none.** Delta emits `output_text` by design (it is
   the Responses API's own assistant-part name) and its API surface is not ours
   to shape. Do not spend time here.
4. **A translation shim in front of bifrost** that rewrites `output_text`/`input_text`
   → `text`. Last resort; adds a hop and a second place to get wrong.

Minimal reproducer (verified, no client needed — fails on v2.0.0):

```bash
# a SINGLE output_text part -> 200
# TWO OR MORE parts in one assistant message -> 422 (the bug)
curl -sS https://ai.fluffy-walleye.ts.net/v1/responses \
  -H "Authorization: Bearer $VK_ZED_DELTA" -H 'Content-Type: application/json' \
  -d '{"model":"deepseek-v4-flash","input":[
        {"type":"message","role":"user","content":[{"type":"input_text","text":"hi"}]},
        {"type":"message","role":"assistant","content":[
          {"type":"output_text","text":"a"},{"type":"output_text","text":"b"}]}]}'
# -> 422 messages[1]: unknown variant `output_text`
```

Build the upstream bug report around the 2-part case; it is 3 lines and fails
reliably. Do **not** cite the probe's `chat_completion` rejections as part of this
bug — `output_text` is legitimately invalid on `/v1/chat/completions`.

## Other problems found on the way

Unrelated to the bug above, but worth its own issue.

1. **`list_models is not supported by qwen provider`** — every Delta session
   opens with 1–2 failed `list_models` calls. Harmless today (Delta copes), but
   it is the first thing in every session and it is noise in the gateway log.
   Note `qwen` is a custom provider with `allowed_requests` naming only
   `chat_completion`/`chat_completion_stream`; `list_models` is simply not
   declared for it, while the native providers do answer it.

## Retracted: there is no second bug, and no `tool_calls` defect

The `An assistant message with 'tool_calls' must be followed by tool messages
responding to each 'tool_call_id'` error at 22:25:00 is **correct behaviour**, not
a bug. A draft of this file reported it as a second symptom. Evidence:

- From the real body, `[user, assistant, fc2, fc3, fco2, fco3]` (both calls, both
  outputs) -> **200 OK**.
- The same list minus `fco3` -> 400. That missing output was *my* truncation, and
  bifrost's error accurately described the request I sent.
- Every `input[:3]`..`input[:8]` 400 from bisection is the same artifact — a prefix
  cut before the matching `function_call_output` items, which sit later in the
  169-item array (calls at 2..41, most outputs at 42..74).
- Batching is fine: synthetic `call,call,out,out` -> 200, on both models.
- The real body's pairs are intact: 61 `function_call`, 61 `function_call_output`,
  all `call_id`s matched.

Consequences: (a) a **single** upstream defect causes **all** the real failures;
(b) `input[:N]` bisection is only trustworthy once `N` extends past the last
`function_call_output`, since earlier prefixes fail for an unrelated and correct
reason.

## Probes (both committed)

`scripts/bifrost-responses-translation-probe.py` — **the regression test for this
bug.** Targets `/v1/responses`, asserts the 1-part/2-part boundary, and exits **1
if the bug is present**. Run it after any bifrost upgrade: a clean exit 0 means
the upgrade fixed it.

```bash
export VK_ZED_DELTA=<from BWS item bifrost-vk-zed-delta>
scripts/bifrost-responses-translation-probe.py          # exit 1 = bug present
scripts/bifrost-responses-translation-probe.py --list
```

`scripts/bifrost-content-part-probe.py` — older, and **misleading for this bug.**
It targets `/v1/chat/completions`, where rejecting `output_text`/`reasoning` is
*correct*, so its REJECTED rows are not a defect; and all its cases use a single
part, so it cannot see the multi-part bug at all. Keep it as a chat-completions
contract check only. It is what sent the previous session down the wrong path.

```bash
export VK_ZED_DELTA=<from BWS item bifrost-vk-zed-delta>
python3 scripts/bifrost-content-part-probe.py          # 7 cases x 2 models
python3 scripts/bifrost-content-part-probe.py --only parts-output_text --verbose
```

Stdlib only, mutates no state, safe to re-run. Its job is now regression
evidence: after any bifrost upgrade, `parts-output_text` and `parts-reasoning`
should flip to ACCEPTED on both models. Note the probe's own results are what
populate `virtual_key_name='zed-delta'`, `user_agent='Python-urllib/3.14'` in the
gateway log — do not mistake those rows for real Delta traffic.

## Gotchas (unchanged, all still true)

- **`bifrost-config.json` and `bifrost-compose.yml` are both `restartTriggers`**
  on `bifrost-compose.service`. Editing either restarts the stack on the next
  rebuild (`down`, no `-v` — the named volume and its logs survive).
- **`enforce_auth_on_inference` is still `false`, and Delta is sending no key at
  all.** An unknown key is rejected `401` even with enforcement off; a *missing*
  key is served and logged as anonymous. **Every real Delta inference request in
  the log — including all four 422s and all four `responses_stream` attempts —
  has an empty `virtual_key_name`.** The `zed` VK appears only on a subset of
  `list_models` calls; the traffic we were actually trying to attribute carries
  nothing. So `VK_ZED_DELTA` is **not** reaching the gateway from Delta, and
  BOX-149 does not yet cover Delta. Confirm BOX-193 enforcement before trusting
  any Delta attribution number.
- **Delta is not necessarily using the API shape its config declares.** The
  anonymous rows include `chat_completion_stream` at 22:25:00 *and*
  `responses_stream` at 22:27–22:41 — Delta drifted between the two APIs within
  one session. Any fix must be validated against the *Responses* path.
- **The BWS service-route scope is unverified.** The item was created with the
  operator token. `just secrets-check` covers the operator route **only** — it
  passed for that reason and proves nothing about the service route. Worth
  confirming in the BWS console, since it is a silent-failure mode.
- **Zed's VK delivery is non-declarative and macOS-only** (keychain; no env
  interpolation in `settings.json`, and `custom_headers` cannot override a
  provider-managed header). See `docs/box-149-per-client-attribution.md`. **Delta
  may have a different credential surface — still never verified**, and the
  anonymous rows above show Delta is *not* sending the key it was given. Note
  the earlier `zed` VK is still live on `list_models`, so the old key was never
  removed; it is Delta's inference path specifically that is unauthenticated.
- **`git` is on `main`.** Per the global `AGENTS.md`, commits and pushes to
  `main` need explicit confirmation.

## Related

- `docs/box-149-per-client-attribution.md` — the VK design; D5 records the
  Zed-client limits.
- `docs/architecture.md` — gateway access model, client key list.
- `scripts/bifrost-reliability-gate.py` — the serving smoke test
  (`just reliability-gate`). Passing it does **not** cover this bug: it sends
  well-formed bodies only, and never exercises the Responses API.
- BOX-149 (attribution, landed), BOX-193 (enforcement, open).
