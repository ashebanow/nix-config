# BOX-149 — Per-client attribution in the gateway log view

Design record. The issue: BOX-149, *Per-client attribution in the gateway log
view*, filed out of BOX-137 as an explicit follow-up.

## Problem

BOX-137 moved pi, hermes, Zed, Raycast and Open WebUI onto the bifrost gateway
and verified per-client presence by sending a distinctive marker prompt from
each client and finding that string in the log. That satisfies BOX-137's
acceptance criterion, but it is manual and proves only that *something*
reached the gateway — not *which client* sent it.

The gateway runs with `client.enforce_auth_on_inference: false` and no client
sends a credential, so every request arrives anonymous. The log cannot be
filtered or grouped by origin.

## Mechanism

bifrost supports governance virtual keys (VKs). A VK is supplied by the client
in any of `x-bf-vk`, `Authorization: Bearer`, `x-api-key`, `x-goog-api-key` or
`api-key`, and it is recorded on every log row as `virtual_key_id` /
`virtual_key_name`. The dashboard's logs view exposes both a virtual-key
filter and a free-text User filter, and `GET /api/logs/filterdata` returns the
distinct VKs seen in the log.

That is real, first-class attribution — not a heuristic over content — so VKs
are the mechanism this design uses. Header-based attribution
(Raycast's `include_user_email`) is retained as a secondary signal, not as the
mechanism.

## Decisions

### D1 — Seed virtual keys, but do not enforce them

`enforce_auth_on_inference` **stays `false`**. Clients send VKs; the gateway
records them without requiring them.

Rejected: flipping enforcement on in this ticket. That makes every migrated
client mandatory in a single step: any client whose credential is miswired, or
any client not yet migrated, starts receiving 401s from a shared gateway. The
attribution requirement does not need enforcement, so enforcement is a
separate, independently revertible decision (see *Follow-ups*).

The consequence to keep in view: an unmigrated client does not fail. It
silently appears anonymous in the log. Verification (D6) exists to catch
exactly that.

> **Correction (2026-09-16, verified against v2.0.0).** This originally read
> "an unmigrated *or misconfigured* client does not fail". That is wrong for
> the misconfigured case. `enforce_auth_on_inference: false` means the gateway
> does not *require* a key; it still *validates* any key presented. Measured:
> no key returns `200` (anonymous), an unknown key returns
> `401 virtual_key_not_found`. So a typo'd, revoked or stale key is a hard
> failure for that client, not a silent degradation to anonymous. Found by the
> D6 negative test (BOX-195).

### D2 — One virtual key per client tool

| client | virtual key name | value |
| -- | -- | -- |
| pi | `pi` | `sk-bf-…` |
| hermes | `hermes` | `sk-bf-…` |
| Zed | `zed` | `sk-bf-…` |
| Raycast | `raycast` | `sk-bf-…` |
| Open WebUI | `openwebui` | `sk-bf-…` |
| reliability gate | `gate` | `sk-bf-…` |

Granularity is the client tool, matching the client table in the issue and the
natural grain of the log filter. Rejected: per-person keys (pi runs on more
than one machine; Open WebUI is a multiuser surface whose own session identity
is a different problem, not a shared key) and per-machine keys (no consumer
needs that axis yet).

### D3 — Values are random, generated once, and held in BWS

VK values are **randomly generated** (`sk-bf-` + 32 hex characters) and stored
in BWS. They are never authored by hand, never appear in git, and never appear
in a document, ticket or commit message as a literal.

Rejected: hand-written labels committed to `bifrost-config.json`. A value that
is typed into a config file and then copied into BWS is not a secret; the BWS
entry would be ceremony, and the literal would leak into the design doc and the
ticket. Random generation makes the BWS entry load-bearing *now*, so the
enforcement follow-up (D7) becomes a boolean plus budgets rather than a
rotation and migration.

The `sk-bf-` prefix is kept deliberately: it makes a VK self-describing in a
log, distinguishable at a glance from a provider key.

### D4 — Both sides resolve the value from BWS

The gateway and the client each resolve the *same* BWS item:

- **Gateway**: `bifrost-config.json` references the value by name —
  `"value": "env.VK_PI"` — exactly as it already does for
  `env.ANTHROPIC_API_KEY`. `bifrost-compose.yml` passes `VK_PI=${VK_PI}` and the
  `bifrost` secretspec scope supplies it.
- **Client**: chezmoi resolves it at apply time via `bitwardenSecrets`, the same
  function `private_config.yaml.tmpl` already uses for an `x-api-key`.

This means **rotating a VK requires redeploying the gateway and re-applying
chezmoi on each client host.** Named here rather than discovered later.

> **Correction (2026-09-16).** This originally said a missed re-apply "costs
> attribution only" with enforcement off. It does not. A stale key is an
> *unknown* key, and an unknown key is rejected with `401` even when
> enforcement is off (see the D1 correction). Rotation is an outage risk for
> the un-re-applied client today, not only after BOX-193.

### D5 — Each client uses its native credential surface

bifrost accepts a VK on several headers, so no client needs bespoke machinery.

| client | surface | note |
| -- | -- | -- |
| pi | `apiKey` on the `bifrost` provider | becomes `Authorization: Bearer` |
| hermes | `api_key` under `providers.bifrost` | **new field; acceptance unverified** |
| Zed | `custom_headers: { x-bf-vk: … }` | `openai_compatible` refuses `api_key`; only `api_url`, `available_models`, `custom_headers` are accepted |
| Raycast | `api_keys` | present in schema, absent today |
| Open WebUI | `OPENAI_API_KEY` | see D6 — the env var seeds a fresh DB only |
| reliability gate | `Authorization: Bearer` | currently a hardcoded `sk-gate` |

Where a client can express `x-bf-vk` directly it should, because `x-bf-vk`
works identically whether or not enforcement is on, whereas
`Authorization: Bearer` only carries a VK while `disable_auth_on_inference` is
true — the exact condition the enforcement follow-up changes. Zed uses
`custom_headers`; the rest use their native field, and the enforcement ticket
must revisit any client still on `Authorization`.

### D6 — Verification

An `attribution` check is added to the reliability gate
(`scripts/bifrost-reliability-gate.py`), reusing the machinery that already
issues requests and asserts on responses.

**The gate gets its own VK (`gate`).** It currently sends a hardcoded
`Authorization: Bearer sk-gate`, which is not a valid VK. Attributing it keeps
20 minutes of synthetic traffic distinguishable from real client traffic, and
gives the ticket a machine-checkable path that does not depend on a human
running a client.

The check issues a request under a known VK and asserts the log row carries the
expected `virtual_key_name`. Open cost: the logs endpoint needs
dashboard/management credentials, which the gate does not hold today. If that
cost is unacceptable, the fallback is a documented manual check per client — but
that is the approach that rots, and it is what BOX-137 already did.

Two traps this check exists to catch:

- **Open WebUI**: its `OPENAI_*` environment variables seed a *fresh database
  only*. Open WebUI persists connections in its own DB, so editing the compose
  env var has no effect on a running deployment and the log stays anonymous
  while the config looks correct. The change must also be applied in the admin
  UI, or the volume re-seeded.
- **hermes**: `providers.bifrost` has no `api_key` field today (all existing
  `api_key` occurrences are under `auxiliary.*`). That the loader accepts one at
  provider level is unverified and must be confirmed at implementation.

**Raycast is explicitly best-effort.** It is the one client whose attribution
may be allowed to degrade to an "other/misc" bucket rather than block the
ticket. Raycast's `X-User-Email` is kept (D8), but if its `api_keys` field
proves awkward, Raycast does not hold up the rest.

### D7 — Enforcement, budgets and rate limits are out of scope

Filed as a follow-up ticket referencing this design. That ticket owns: flipping
`enforce_auth_on_inference` to `true`, attaching per-VK budgets and rate limits,
and revisiting any client still sending the VK on `Authorization` (D5).

Out of scope here because it has a different risk profile (it can 401 every
client at once) and because D3 already put the values in BWS, so nothing needs
to be rotated or migrated when it lands.

### D8 — Raycast keeps `include_user_email`

`X-User-Email` lands in the log's User field (`user_id` / `user_name`), which is
a *different* column from `virtual_key_name` — so it is not a duplicate of the
VK. It is the only per-human signal any client provides. Keep the setting;
remove the comment that frames it as BOX-149's mechanism, since that is now the
VK.

## Acceptance criteria

| criterion | how it is met |
| -- | -- |
| Each gateway client's requests are attributable | D1/D2/D5 — VK recorded as `virtual_key_name`; D6 asserts it |
| Attribution survives a gateway restart and config reload | `source_of_truth: "config.json"` means the VK seed wins on every restart; VKs are not UI-authored state |
| No client credential committed in plaintext | True **by construction** (D3/D4) — values are random and live only in BWS. Nothing to argue about |
| Enabling attribution does not break the direct bypass paths | D1 — enforcement stays off, so nothing is rejected |

On the bypass criterion: no client is wired to a bypass today. `qwen-35b-a3b` is
reachable only on the `llm-internal` bridge and the direct serve paths on
lumquat are published but unused as a revert affordance (BOX-137 dropped that
requirement). The criterion is therefore about *not introducing* a bypass, which
D1 satisfies.

## Rejected alternatives

- **Enforced VKs now** — a flag day across every client. See D1.
- **Header-based attribution as the mechanism** — Raycast can send
  `X-User-Email`, but pi, hermes and Zed send nothing distinguishing, and the
  header lands in a different log field than VKs. Not a mechanism; kept as a
  supplementary signal (D8).
- **Committed label values** — see D3.
- **Per-person or per-machine keys** — see D2.
- **No automation, manual per-client check** — see D6.

No ADR. The unenforced-VK choice fails the *hard to reverse* bar: flipping
enforcement is one boolean and the design deliberately keeps it reversible. It
clears the other two (surprising without context; a genuine trade-off), so the
reasoning is recorded here instead.

## Implementation notes

- **pi, Zed and Raycast configs are not `.tmpl` files** today — only their
  `symlink_*.json.tmpl` wrappers are. Resolving a VK from BWS at apply time
  requires converting `editable-models.json`, `editable-settings.json` and
  `providers.yaml` to templated forms. hermes is already a `.tmpl`, and its
  line 101 shows the `bitwardenSecrets` pattern to follow.
- **`bifrost-config.json` and `bifrost-compose.yml` are both `restartTriggers`**
  on `bifrost-compose.service`, so a VK change restarts the stack; the named
  data volume and its logs survive (`down`, no `-v`).
- Adding `VK_*` to the `bifrost` secretspec scope is the only manifest change;
  the scope is consumed only by that service, so least-privilege holds.
- `docs/architecture.md` describes access as "no virtual key" and must be
  updated to "virtual keys recorded, not enforced".

## Follow-ups

- **Enforcement + budgets** (new ticket, references this design) — D7.
- **Open WebUI per-person attribution** — its own session identity, not a
  shared VK (D2).
