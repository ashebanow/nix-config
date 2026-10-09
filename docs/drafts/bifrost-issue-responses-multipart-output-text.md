# Draft: upstream bifrost issue

**Target repo:** `maximhq/bifrost`
**Status:** FILED — https://github.com/maximhq/bifrost/issues/8196 (2026-10-08)
**Suggested title:**
`[Bug]: /v1/responses rejects multi-part assistant messages — output_text is not mapped to text in ToChatMessages`

**Labels (if available):** `bug`

---

## Prerequisites

- [x] I have searched existing issues and discussions to avoid duplicates
- [x] I am using the latest version (or have tested against main/nightly)

## Description

On the OpenAI-compatible **Responses API** (`/v1/responses`), a request that
replays an assistant message containing **more than one content part** is
rejected with a deserialization error on the gateway's own internal
chat-completions type:

```
Failed to deserialize the JSON body into the target type: messages[1]:
unknown variant `output_text`, expected one of `text`, `image_url`, `file`
```

The request is valid Responses-API input; `output_text` is the correct part type
for assistant content, and bifrost's own `/v1/responses` responses emit exactly
that type. The failure is in bifrost's translation from Responses `input[]` to
chat-completions `messages[]`: the conversion of `output_text` → `text` is
applied only when the message has a **single** content part, and is skipped at
**two or more** parts.

This is not a one-off: any client that speaks the Responses API and replays
assistant history where a turn has multiple parts hits it on every subsequent
request. An assistant turn whose text is split across two parts — e.g. a
reasoning preamble plus the reply — is the common shape.

### Confirmed not to be any of these

- **Not a provider issue.** Reproduces identically on a native provider
  (`deepseek`) and on a custom OpenAI-compatible provider
  (`base_provider_type: "openai"`). Only the error code differs (422 vs 400),
  which reflects which layer rejects it.
- **Not a fixed-upstream issue.** The relevant `case` list is identical in
  `transports/v2.0.0`, `v2.1.0`, `v2.2.0`, `v2.2.6`, `main`, and `dev`.
- **Not the client's fault.** Verified against a plain `curl`, no SDK involved.

## Steps to reproduce

Against a running gateway (`v2.0.0` observed; source unchanged in `v2.2.6`).
The `curl` needs no provider key — any configured provider and model works.

**Fails — two `output_text` parts in one assistant message:**

```bash
curl -sS https://<gateway>/v1/responses \
  -H "Authorization: Bearer $BIFROST_VK" -H 'Content-Type: application/json' \
  -d '{
    "model": "deepseek-v4-flash",
    "input": [
      {"type":"message","role":"user",
       "content":[{"type":"input_text","text":"hi"}]},
      {"type":"message","role":"assistant",
       "content":[{"type":"output_text","text":"a"},
                  {"type":"output_text","text":"b"}]},
      {"type":"message","role":"user",
       "content":[{"type":"input_text","text":"say ok"}]}
    ]
  }'
# -> HTTP 422
# {"error":{"message":"Failed to deserialize the JSON body into the target type:
#   messages[1]: unknown variant `output_text`, expected one of `text`,
#   `image_url`, `file` ..."}}
```

**Works — the identical request with the assistant content collapsed to one
part:**

```bash
# same body, but "content":[{"type":"output_text","text":"a"}]
# -> HTTP 200
```

Other variants, all against `/v1/responses` on the same build:

| assistant message content | result |
| --- | --- |
| `[{output_text, "a"}]` | **200 OK** |
| `[{output_text, "a"}, {output_text, "b"}]` | **422** `unknown variant output_text` |
| `[{output_text, "a"}, {text, "b"}]` | **422** `unknown variant output_text` |
| `[{text, "a"}, {text, "b"}]` (no Responses-only type) | **200 OK** |
| two separate assistant messages, one part each | **200 OK** |

User-side `input_text` is **not** affected — two `input_text` parts in a user
message translate fine. Only multi-part **assistant** messages containing
`output_text` fail.

## Expected behavior

The request should be accepted. A multi-part assistant message should translate
each `output_text` part to a chat-completions `text` part, exactly as the
single-part case already does.

## Actual behavior

The request is rejected with a 422 deserialization error naming
`messages[N]: unknown variant output_text`, where `N` is the index in bifrost's
**internally translated** chat-completions array, not in the client's `input[]`.

## Root cause (source)

`core/schemas/mux.go`, in `ToChatMessages()`.

The single-part short-circuit explicitly accepts both input- and output-side text
types, which is why one part works (lines ~908-910):

```go
if rm.Content.ContentStr != nil ||
    (len(rm.Content.ContentBlocks) == 1 &&
        (rm.Content.ContentBlocks[0].Type == ResponsesInputMessageContentBlockTypeText ||
         rm.Content.ContentBlocks[0].Type == ResponsesOutputMessageContentTypeText)) {
    // ...collapses to a plain string
```

The multi-part branch has no case for the output-side type, so it falls through
`default:` and copies the Responses-only type verbatim into a chat block
(lines ~924-936):

```go
switch block.Type {
case ResponsesInputMessageContentBlockTypeText:
    chatBlockType = ChatContentBlockTypeText  // "input_text" -> "text"
case ResponsesInputMessageContentBlockTypeImage:
    chatBlockType = ChatContentBlockTypeImage // "input_image" -> "image_url"
case ResponsesInputMessageContentBlockTypeFile:
    chatBlockType = ChatContentBlockTypeFile  // "input_file" -> "file"
case ResponsesInputMessageContentBlockTypeAudio:
    chatBlockType = ChatContentBlockTypeInputAudio // "input_audio" -> "input_audio"
default:
    // For unknown types, fall back to direct conversion
    chatBlockType = ChatContentBlockType(block.Type)  // "output_text" passes through
}
```

`chatcompletions.go:1292-1295` defines only four valid chat block types —
`text`, `image_url`, `input_audio`, `file` — which is exactly the set named in
the error message.

## Suggested fix

Add the missing case to the multi-part `switch`:

```go
case ResponsesOutputMessageContentTypeText:
    chatBlockType = ChatContentBlockTypeText // "output_text" -> "text"
```

The single-part branch already treats the two text types identically, so this is
consistent with existing intent rather than new behaviour.

## Impact

Blocks Responses-API clients from doing multi-turn tool-using work against
bifrost. Observed with Zed's agent (Delta) on macOS, which replays assistant
history in Responses form; because Zed splits a reasoning preamble and the reply
into two `output_text` parts, it fails on most turns of any real session while
occasionally succeeding on trivial one-part ones, making it look intermittent.
The first turn of a fresh conversation succeeds and the second fails.

## Version

- bifrost image: `docker.io/maximhq/bifrost:v2.0.0`
- Also checked and unfixed in `transports/v2.1.0`, `v2.2.0`, `v2.2.6`, `main`, `dev`.

## Notes for maintainers

- Not a duplicate of #7074: that is the Anthropic/Messages → Responses ingress
  path mistagging replayed history for Bedrock models (`output_text` vs
  `input_text`). This is the reverse-ish direction — Responses `input[]` →
  chat-completions `messages[]` — and is independent of provider or ingress.
- PR #8142 touches `mux.go` but only `ToBifrostChatResponse` (the response
  direction), so it does not address this.

---

## Filing notes (resolved)

- Filed as issue only, no PR (waiting on a maintainer to confirm the intended
  mapping).
- Log excerpt deliberately omitted — the `curl` reproducer is self-contained.
- Deployment details deliberately omitted.
- The `bug` label could not be applied via API (`AddLabelsToLabelable` denied for
  a non-collaborator); a maintainer will need to add it. The bug-report template
  normally does this automatically, but filing via `gh issue create` bypasses
  the template.
- Filed body is the flattened version that fits the repo's `bug_report.yml`
  fields. Template has no Root cause / Suggested fix / Impact fields, so those
  went into **Description** (with a short maintainer-notes section at the end).
