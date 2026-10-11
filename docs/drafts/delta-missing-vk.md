# Draft: Delta isn't sending its virtual key

Casual writeup of the attribution gap found while debugging the multipart
`output_text` thing. For Linear (BOX-149 follow-up) or for me to paste into
wherever it's useful. Facts checked against the gateway log on 2026-10-08.

---

## What I found

While chasing the Delta/`output_text` bug I went looking in the gateway log to
see the actual request, and noticed Delta's traffic isn't attributed at all.
Every real inference request it makes lands with an empty `virtual_key_name`.
The key is configured, the gateway would accept it — Delta just isn't sending
it.

Concretely, from `logs.db`, grouping by user agent:

| virtual key | user agent | rows |
| -- | -- | -- |
| `pi` | `pi (linux…)` | 157 |
| `zed-delta` | `Python-urllib/3.14` | 80 |
| `pi` | `pi (darwin…)` | 59 |
| **(empty)** | `Delta/0.19.1/stable (macos; aarch64)` | **26** |
| `zed-delta` | `curl/8.22.0` | 13 |
| `zed` | `Delta/0.19.1/stable (macos; aarch64)` | 8 |
| (empty) | `curl/8.22.0` | 2 |

The `zed-delta` rows are mine — that's the probe I was running, from Python and
curl. Delta itself only ever produced empty rows and 8 rows tagged `zed`.

## The bit that's actually interesting

Those 8 `zed` rows are tagged `vk-zed` — the **old** Zed key, not `vk-zed-delta`,
which is the one we added for Delta. And they're only `list_models` calls, never
inference. Chronologically:

```
22:06:28   zed       list_models   x4     <- old vk-zed
22:09:47   (empty)   list_models   x4
22:24:10   (empty)   list_models   x4
22:24:20   zed       list_models   x4     <- old vk-zed again
22:24:22   (empty)   list_models   x4
22:25:00   (empty)   chat_completion_stream
22:27:35   (empty)   responses_stream   <- the ones that 422'd
22:30:07   (empty)   responses_stream
22:30:27   (empty)   responses_stream
22:41:35   (empty)   responses_stream
22:41:45   (empty)   responses_stream
```

So it's inconsistent — sometimes a key, sometimes not, and when it is one it's
the wrong key. Every inference call, including the four failures we were
actually debugging, is anonymous.

## Why this happens (or, why this was always going to happen)

This isn't a surprise, it's the thing BOX-149's D5 already predicted and I'd
forgotten about: **Zed has no declarative way to deliver a per-provider custom
header.** zed#26043 — no env var interpolation in `settings.json` — and
`custom_headers` can't override a header the provider manages. So the only
delivery path is a manual macOS keychain entry, which lands on `Authorization:
Bearer` rather than `x-bf-vk`.

Which means: Delta probably needs its *own* provider entry in `settings.json`
with its own keychain item, separate from the plain Zed one. If it's inheriting
Zed's provider config, that would explain both symptoms exactly — it sends the
old `vk-zed` when the keychain item resolves, and nothing when it doesn't. The
intermittency is the tell: two different code paths in Delta picking up
different credentials, or one of them racing/falling back.

I have not verified what Delta's provider config actually looks like. That's the
next thing to check, and it's client-side (macOS, keychain) so I can't inspect it
from here.

## Why it matters

Right now it's latent, because `enforce_auth_on_inference` is `false` — Delta's
requests get served and logged as anonymous. The moment BOX-193 flips
enforcement, **Delta starts getting 401s**, along with anything else that's
silently anonymous. And note the failure mode is asymmetric in a nasty way: a
*missing* key is served anonymous, but an *unknown* key is rejected `401` even
with enforcement off. So a stale or wrong key isn't a silent degradation, it's a
hard failure for that client only. Worth remembering when we audit who's
actually sending what before flipping that switch.

It also means BOX-149's attribution isn't actually complete for Delta. The
design says each client tool gets an identity; in practice Delta has none, so we
can't filter or bill its traffic, and when we were debugging the `output_text`
bug the log gave us the request body but attached it to nobody.

## What I'd do

1. Check Delta's provider config in Zed on the Mac — does it have its own
   provider entry and its own keychain item, or is it sharing Zed's?
2. Give it its own entry pointing at `vk-zed-delta`, and confirm the keychain
   item is the Delta one and not the stale Zed one.
3. Verify in the log that a fresh Delta request lands as `zed-delta`, not
   `zed` and not empty.
4. Before flipping BOX-193, do a pass over the log for `virtual_key_name IS
   NULL` and find every client that's still anonymous. Delta won't be the only
   one.

Longer term this is the BOX-205 factorseal thing — the per-machine keychain
entry is the root cause and it's fragile (manual, no ACL, re-prompts, and doesn't
work on Linux at all). Not fixing it this week, but it's why this keeps coming
back.

## Caveat

The `zed`-vs-empty split is inferred from 8 rows over ~18 minutes of one evening,
during a debugging session where I was also hammering the gateway with my own
probes. It's a real observation but a thin sample. Worth reproducing cleanly —
fresh Delta session, no other traffic, see what lands.

---

## Notes (not for posting)

- Kept the table and the timestamp block. The chronological interleaving is the
  most persuasive part — it shows the intermittency rather than asserting it.
- Deliberately says "I have not verified what Delta's provider config actually
  looks like" and keeps the caveat about the thin sample. Your reliability-gate
  doc is explicit about the difference between measured and theorised ("Measured
  in the log, not theorised"), and this one is partly theorised.
- The BOX-193 risk framing is the strongest argument for caring now. If you want
  it shorter, cut "What I'd do" to just items 1–3.
- No hostname, no key values.
- If this goes to Linear, it probably wants splitting: the Delta key gap is one
  issue, and "audit for anonymous clients before enabling enforcement" is
  arguably a separate one under BOX-193.
