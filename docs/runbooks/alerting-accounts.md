# Runbook: alerting accounts and secrets (Pushover + healthchecks.io)

Human-only setup for alert delivery. Nothing here is declared in Nix: these are
accounts, an app purchase and a hosted check that the config can only consume —
which is why they live in a runbook rather than in a module.

Ticketed as BOX-328, part of the observability map (BOX-311, §7 alerting and
§10 setup only the user can do). The delivery design is BOX-320 (`vmalert` →
Alertmanager → Pushover, two severities, quiet hours on the phone) and BOX-316
(healthchecks.io as the dead-man's switch).

**Time:** about 20 minutes. **Cost:** $4.99 one-time (Pushover iOS), no
subscriptions. healthchecks.io free tier is sufficient (20 checks).

Every step ends in something you can see. If a step's check fails, stop there —
the next step cannot mask it.

---

## 1. Buy the Pushover iOS app

1. On the iPhone, open the App Store and buy **Pushover** ($4.99, one-time).
2. Open the app and sign in (or create the account — one account per person,
   not per device).
3. Note the **user key**: on the Pushover dashboard at
   <https://pushover.net>, the user key is in the top-right of the home page
   (30 characters, the "Your User Key" block).
**Check:** the app is installed and signed in, and <https://pushover.net>
shows the iPhone under *Your Devices*.

> The user key is per person, not per application: it is the same one every
> Pushover application of yours will address. Keep it out of screenshots — it
> is one half of the pair that lets anything push to your phone.

## 2. Create the Pushover application

1. At <https://pushover.net/apps/build>, register an application named for this
   stack. Use **`nix-config-alerting`** — the name shows up in every
   notification, and a stack-specific name keeps it distinguishable from any
   other Pushover app added later.
2. Type: **Application** (not a service integration).
3. Ticking the description/URL boxes is optional and not needed here.
4. Create it, then note the **API Token/Key** shown on the application's page
   (30 characters). That is the "app token".

**Check:** the application appears at <https://pushover.net/apps> with the token
visible on its page.

## 3. Set quiet hours on the phone

Quiet hours live in the phone app, not in Alertmanager (BOX-320): they then
follow the phone's time zone while travelling, which a server-side time interval
cannot do.

In the Pushover iOS app: **Settings → Quiet Hours** — pick the window (e.g.
23:00–07:00) and leave the **critical** option as configured, so critical
alerts (priority 1) still sound once through the window while warnings
(priority 0) wait.

**Check:** the app shows the quiet-hours window as enabled.

> Not to be confused with iOS Focus modes. Quiet hours are a Pushover setting
> and work independently of Focus.

## 4. Create the healthchecks.io check

1. Sign up / sign in at <https://healthchecks.io> (free Hobbyist plan).
2. Create a project named `homelab` (or use the default one).
3. Add a check, name **`calamansi-watchdog`**:
   - **Period: 1 minute**
   - **Grace time: 10 minutes**
   - Schedule: simple (not cron)
4. Save, then open the check's page and copy the **ping URL**
   (`https://hc-ping.com/<uuid>`).
5. Integrations (check page → *Integrations*): add **Pushover** — paste the
   Pushover user key from step 1 (healthchecks.io asks for the user key; it
   sends from its own application). Add **Email** as the second channel and
   confirm the address.

**Check:** the check's page shows period 1 min, grace 10 min, and two
integrations (Pushover, Email). Press *Send test notification* and confirm the
phone receives it.

> **The ping URL is a secret.** It looks like an address, but it is a capability
> URL: anyone holding it can ping the check and keep the dead-man's switch
> quiet, which is exactly the failure this check exists to catch. It goes into
> BWS like the tokens do — never into git, the Nix store, a chat message or a
> screenshot.

> The ping URL must not be confused with the check's *manage* URL, which is
> another capability URL. Only the ping URL is stored.

## 5. Put the three values in BWS

In the BW web console → **Secrets Manager → Homelab**, create three items. The
key conventions match `secretspec.toml`: env var lowercased, underscores →
dashes.

| BWS item key | Value | Where it came from |
|---|---|---|
| `pushover-app-token` | the application's API Token/Key | step 2 |
| `pushover-user-key` | your Pushover user key | step 1 |
| `healthchecks-ping-url` | the check's full ping URL, `https://hc-ping.com/<uuid>` | step 4 |

The values are already secret in BWS — no other store, no local file. The
declarations in `secretspec.toml` (`[scopes.alerting]`) reference exactly these
item keys; a typo here shows up as a failed resolution in step 6, not as a
silent hole.

**Check:** the Homelab project lists all three items, spelled exactly as above.

## 6. Verify

From a machine with `BWS_ACCESS_TOKEN` in the environment (see
[`SECRET_SYNC.md`](../../SECRET_SYNC.md)):

```bash
# Whole manifest — every secret, including the alerting scope. Agents must pass
# a reason (secretspec require_reason policy, BOX-184); humans can omit it.
just secrets-check "BOX-328: verify alerting secrets"

# Just this scope, value-free trace of how each secret resolved
SECRETSPEC_PROVIDER=bws secretspec check -f secretspec.toml -P production \
  -S alerting --no-prompt --explain
```

A clean run means all three declarations resolve against their BWS items.
`--explain` (or `--json`) shows provider and resolution per secret and never
prints a value, so it is safe to paste into a ticket.

Without a BWS token you can still check that the manifest itself is well formed:

```bash
secretspec check -f secretspec.toml -P production -S alerting --no-prompt
```

This fails on a missing `BWS_ACCESS_TOKEN` *before* it can tell you anything
about the values — it parses and validates the manifest first, so a syntax
error and a missing token look different (a manifest problem is reported as a
parse/validation error; a provider problem names the missing credential).

---

## What consumes this scope

Nothing yet — the declarations land first, wiring lands with BOX-329, *Alerting:
Pushover delivery, watchdog and generic rules*:

- **Alertmanager** (on calamansi) receives `PUSHOVER_APP_TOKEN` and
  `PUSHOVER_USER_KEY` as systemd credentials, resolved with
  `secretspec run -P production -S alerting`.
- **vmalert's always-firing Watchdog alert** pings `HEALTHCHECKS_PING_URL` via
  `webhook_configs` through Alertmanager, every minute.

So a green step 6 is a prerequisite for BOX-329, not a substitute for it: until
that module exists, no alert actually reaches the phone. To prove the accounts
work end-to-end before then, use the *Send test notification* button in
healthchecks.io (step 4) and the Pushover app's own *Send test notification*.

## Why these are a separate scope

`[scopes.alerting]` is deliberately not folded into a host or operator scope.
These are delivery credentials for a third party outside the tailnet — a
different trust class from device credentials (`unifi-snmp`) and from operator
tools (`dev`). Whoever holds them can push notifications to the phone or silence
the heartbeat; nothing else on either host needs to see them. The rationale and
the `required = true` decision are in the comments above the declarations in
[`secretspec.toml`](../../secretspec.toml).

## Related

- [`SECRET_SYNC.md`](../../SECRET_SYNC.md) — how secrets are declared, resolved
  and bootstrapped.
- [`docs/architecture.md`](../architecture.md#secrets-bws--secretspec) — the
  architecture section.
- BOX-311 — the observability map (§7 alerting, §9 secrets, §10 this setup).
- BOX-320 — the v1 alert rules, severities and delivery path.
- BOX-316 — why healthchecks.io is the dead-man's switch and Pushover the phone
  channel.
