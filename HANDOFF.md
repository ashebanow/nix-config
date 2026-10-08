# Handoff — Zed Delta ↔ bifrost content-part rejection

**Status:** diagnosing an open bug. No fix applied. One commit landed
(`182192e`), one diagnostic script uncommitted at the time of writing.
**Written:** end of a session on the dev machine (bergamot/miraclemax).
**Continue on:** lumquat, where the gateway and the client both live.

---

## The failure

Zed's **Delta** tool, configured to use the bifrost gateway, is rejected on
request:

```
Bifrost error: Failed to deserialize the JSON body into the target type:
messages[4]: unknown variant `output_text`, expected one of `text`,
`image_url`, `file` at line 1 column 37691
(request_id: 18116cad-08dc-403a-a805-9db28af75d92)
```

This is **not** an auth or key problem. The key works — see "What is ruled
out" below.

## Work completed this session

**`VK_ZED_DELTA` was added end to end and pushed** (commit `182192e`, `main`).
That work is done and correct; it is the *precondition* for the bug, not the
cause. Files touched:

| File | Change |
| -- | -- |
| `secretspec.toml` | declaration + membership in the `bifrost` scope |
| `compose/llm/bifrost-compose.yml` | `VK_ZED_DELTA=${VK_ZED_DELTA}` passthrough |
| `compose/llm/bifrost-config.json` | `vk-zed-delta` virtual key (name `zed-delta`) |
| `tests/test_gate_attribution.py` | the hardcoded expected-client set |
| `docs/architecture.md` | the prose client-key enumeration |

BWS item: **`bifrost-vk-zed-delta`** in the Homelab project, value `sk-bf-` + 32
hex. `just secrets-check` resolves all 23 secrets against the operator route.

The Zed Delta failure appeared **after** that deploy, when the operator
configured Delta to use the new key.

## What is ruled out (do not re-test these)

- **The gateway, the key, and routing all work.** A plain chat-completions
  request through the live gateway succeeds:

  ```
  curl -sS https://ai.fluffy-walleye.ts.net/v1/chat/completions \
    -H "Authorization: Bearer $VK_ZED_DELTA" -H 'Content-Type: application/json' \
    -d '{"model":"qwen-latest","messages":[{"role":"user","content":"ping"}]}'
  # -> 200, content "pong"
  ```

- **Env indirection resolves.** `VK_ZED_DELTA` reached the container; the
  request was not rejected with 401/403.
- **All three client API shapes fail identically.** The operator tried the
  OpenAI Chat Completions API, the OpenAI Responses API, and the Anthropic API,
  all against the same `/v1` selector — same class of failure each time. This is
  consistent with the working hypothesis below, because **bifrost routes by
  provider and model, not by which client API was spoken**: `deepseek` is
  declared *native* in `bifrost-config.json`, so all three attempts exercised
  one server-side path.
- **The string `output_text` appears nowhere in this repo.** Confirmed by
  `grep -rn`. Nothing in our config generates it, so there is no local edit that
  would obviously fix it. Whatever emits it is the client or the provider
  integration.

## Working hypothesis

Delta stores a reasoning-model assistant turn (it targeted
**`deepseek-v4-flash`**) and **replays it in `messages[]`** on the next request.
bifrost's OpenAI-schema deserializer accepts only `text`, `image_url`, `file`
and rejects the `output_text` part.

Supporting evidence:

- The error is at `messages[4]` in a **37 KB** body (`column 37691`). A large
  body with a deep index means the offending part is in a *replayed* turn, not
  the new prompt. **A fresh conversation should therefore work; a conversation
  that has already had a reasoning turn should not.** This prediction is
  untested and is the cheapest thing to check first.
- bifrost's own responses carry `reasoning` and `reasoning_details` alongside
  `content` (visible in the probe output above), so structured reasoning
  round-trips are in play.

**This hypothesis is unconfirmed.** The real 37 KB body was never retrieved.

## Next steps, in order

1. **Cheapest test first: start a brand-new Delta conversation.** If a fresh
   conversation succeeds and a continued one fails, the hypothesis holds and the
   problem is specifically replayed reasoning turns.

2. **Run the probe** (committed alongside this file):

   ```bash
   export VK_ZED_DELTA=<value from BWS item bifrost-vk-zed-delta>
   python3 scripts/bifrost-content-part-probe.py
   ```

   Seven cases × two models (`deepseek-v4-flash`, `qwen-latest`). Stdlib only,
   mutates no state, safe to re-run. `--list` shows the cases; `--only NAME` and
   `--models M1,M2` narrow a run; `--verbose` prints full error bodies.

3. **Read the final comparison table — it decides the fix.**

   | Outcome | Interpretation | Candidate fix |
   | -- | -- | -- |
   | accepted on `qwen`, rejected on `deepseek` | bifrost's **native** DeepSeek integration | declare DeepSeek as a custom OpenAI-compatible provider (`base_provider_type: "openai"` + `network_config.base_url`), the shape `qwen` already uses |
   | rejected on **both** models | bifrost's deserializer itself | different problem: upstream bifrost issue, or a client-side workaround |

4. **If still ambiguous, get the actual body** for
   `request_id 18116cad-08dc-403a-a805-9db28af75d92` from the gateway log view.
   That is ground truth and beats any inference here.

### Caveats on the probe's expected output

- `parts-output_text-deep` will likely report **`messages[1]`**, not
  `messages[4]`. The index is positional and the fixture is short. A different
  index with the same variant name **confirms** the diagnosis; do not read it as
  a contradiction.
- `parts-reasoning` and `top-level-reasoning` are expected to **pass**, since
  bifrost already models those fields. If they fail, the hypothesis above is
  wrong and the output should be read from scratch.

## Gotchas for the lumquat session

- **`bifrost-config.json` and `bifrost-compose.yml` are both `restartTriggers`**
  on `bifrost-compose.service`. Editing either restarts the stack on the next
  rebuild (`down`, no `-v` — the named volume and its logs survive).
- **`enforce_auth_on_inference` is still `false`.** An unknown key is rejected
  `401` even with enforcement off; a *missing* key is served and logged as
  anonymous. Relevant because a malformed config could fail quietly rather than
  loudly.
- **The BWS service-route scope is unverified.** The item was created with the
  operator token. If the bifrost service token is scoped to the six
  pre-existing items rather than the whole Homelab project, it cannot see the
  new item. `just secrets-check` covers the operator route **only** — it passed
  for that reason and proves nothing about the service route. Worth confirming
  in the BWS console, since it is a silent-failure mode.
- **`git` is on `main` and in sync with `origin/main`.** Per the global
  `AGENTS.md`, commits and pushes to `main` need explicit confirmation.
- **Zed's VK delivery is non-declarative and macOS-only** (keychain; no env
  interpolation in `settings.json`, and `custom_headers` cannot override a
  provider-managed header). See `docs/box-149-per-client-attribution.md`. Delta
  may have a different credential surface — **that was never verified.**

## Related

- `docs/box-149-per-client-attribution.md` — the VK design; D5 records the
  Zed-client limits.
- `docs/architecture.md` — gateway access model, client key list.
- `scripts/bifrost-reliability-gate.py` — the serving smoke test
  (`just reliability-gate`). Passing it does **not** cover this bug: it sends
  well-formed bodies only.
- BOX-149 (attribution, landed), BOX-193 (enforcement, open).
