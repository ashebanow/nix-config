# Alert delivery and dead-man's-switch heartbeat

Research for BOX-316 (map BOX-311). All prices and limits checked **2026-11-23** against
the vendors' own pages. Recommendation only; the decision belongs to BOX-320.

## Constraints from the map

- External services only for alert delivery and the heartbeat. Metrics and logs stay local.
- Paid only for a significant advantage (ease, maintenance, DR, reliability).
- Alerts must reach the phone even when calamansi or the home network is down, including
  while travelling.
- Low maintenance beats flexibility.

## Recommendation

1. **Heartbeat: hosted healthchecks.io, free Hobbyist plan.** One check (or a few) pinged by
   the alerting pipeline on calamansi. If pings stop (calamansi dead, home WAN down, power
   cut, or the alerting component itself wedged), healthchecks.io alerts the phone from
   outside the house.
2. **Phone delivery: Pushover** ($4.99 one-time per platform). Both the in-house alerter
   (Alertmanager / Grafana / Netdata) and healthchecks.io send to it natively, so one app on
   the phone receives everything, and the heartbeat's path never touches home
   infrastructure.
3. **Fallback / zero-cost alternative: hosted ntfy.sh** (free, anonymous, hard-to-guess
   topic). Works with every candidate stack, but has no SLA (single droplet) and a weaker
   iOS app. Do **not** self-host ntfy on calamansi for v1: it adds a service to maintain and
   it cannot announce its own host's death or reach the phone when the home WAN is down.
4. **Wire the heartbeat to the alert pipeline, not to a cron job**: an always-firing
   "Watchdog" alert routed to a webhook receiver whose URL is the healthchecks.io ping URL.
   This proves collector -> store -> rule evaluation -> notifier -> internet egress are all
   alive, not merely that calamansi has power.

Why Pushover clears the "paid only if significant" bar: emergency priority repeats until
acknowledged (useful for host-down at 3am), the iOS app holds Apple's Critical Alert
entitlement (can sound through mute/Focus if the user enables it), it is a native receiver
in Alertmanager, Grafana, Netdata and healthchecks.io (no templates or bridges), and it is a
single $5 purchase with no subscription. If the user's phone is Android and they are content
with ntfy.sh's best-effort uptime, ntfy.sh is a reasonable free choice; the difference is
small.

## Survivability matrix

| Failure | Self-hosted ntfy on calamansi | ntfy.sh (hosted) | Pushover | healthchecks.io heartbeat |
| --- | --- | --- | --- | --- |
| calamansi down | Dead; cannot alert | Nothing left at home to send | Nothing left at home to send | **Alerts** (missed pings) |
| Home WAN / power down | Phone can't reach it (unless Tailscale path, which is also down) | Nothing at home can send | Nothing at home can send | **Alerts** |
| lumquat down, calamansi up | Works | Works | Works | n/a (rule on calamansi alerts) |
| User travelling | Needs phone on tailnet, iOS still relays through ntfy.sh | Works | Works | Works |

Conclusion: for "watcher is dead" cases, *only* the external heartbeat can speak, and its
notification channel must itself be external (Pushover or ntfy.sh), never self-hosted ntfy.

## Heartbeat candidates

| Service | Free tier (2026-11-23) | Phone push on free tier | Notes |
| --- | --- | --- | --- |
| **healthchecks.io** Hobbyist | $0: 20 checks, 100 log entries per check | Yes, via Pushover / ntfy / Telegram / Signal / etc. integrations | Paid: Supporter $5 (same limits), Business $20 (100 checks, 50 SMS/WhatsApp, 20 calls), Business Plus $80. [pricing] |
| Better Stack | 10 monitors+heartbeats combined | No: "Slack & e-mail alerts" only | Push/SMS/calls are paid. [betterstack] |
| Cronitor Hacker | 5 monitors, 1 user | Email + chat/webhook; no on-call | [cronitor] |
| Dead Man's Snitch | 1 snitch, no integrations listed | No | Little Birdy $5/mo for 3. [dms] |
| UptimeRobot Free | 50 monitors, 5-min interval | Heartbeat availability on Free **not confirmed** from the page | [uptimerobot] |

healthchecks.io wins clearly: the most generous free tier, native integrations to both
Pushover and ntfy, open source (so self-hostable later), and a nixpkgs module
(`services.healthchecks`) exists. Self-hosting it is pointless here, since it would share a
failure domain with what it watches.

### How it is pinged ([http_api])

- `https://hc-ping.com/<uuid>` success; `/start`, `/fail`, `/log`, `/<exit-status>` (0-255)
  variants; slug form `https://hc-ping.com/<ping-key>/<slug>`.
- HEAD, GET or POST accepted; POST body stored (first 100 kB).
- "Please do not ping a single check more than 5 times per minute."
- Schedules: simple (period + grace), cron, or systemd `OnCalendar`. Alert fires when a ping
  is later than period + grace, or on a `/fail` ping. [configuring_checks]
- Pushover "Emergency" priority recommended by healthchecks.io for repeated alerts until
  acknowledged. [configuring_notifications]

Supported integrations in the source tree (`hc/integrations/`, checked via GitHub API):
apprise, call, discord, email, github, googlechat, gotify, group, matrix, mattermost,
msteamsw, ntfy, opsgenie, pagertree, pd, po (Pushover), prometheus, pushbullet, rocketchat,
shell, signal, slack, sms, spike, telegram, trello, victorops, webhook, whatsapp, zulip.
Whether any of these is restricted on the free plan: the docs only gate SMS/WhatsApp/calls
by plan. **Unverified** that the hosted Hobbyist plan exposes every one (expected yes).

### Suggested wiring

- Alertmanager: a `Watchdog` rule (`vector(1)`) always firing, routed to a receiver with
  `webhook_configs: [{ url: https://hc-ping.com/<uuid> }]`, `repeat_interval` around 1-5 min
  (under the 5/min cap). Check period ~5 min, grace ~10 min. Same pattern works with vmalert
  (which sends to Alertmanager). Grafana alerting: an always-firing rule to a Webhook contact
  point. Netdata: no Watchdog concept; fall back to a systemd timer that curls the ping URL
  (weaker: proves only that calamansi is up and online).
- Keep the ping URL in the secrets mechanism (it is a write capability, low sensitivity).

## Delivery candidates

### Pushover ([pushover pricing], [pushover api])

- $4.99 USD one-time per platform (iOS, Android, Desktop); 30-day free trial; no
  subscription for individuals.
- 10,000 messages/month per account, shared across apps; 429 when exceeded.
- Priorities -2..2. 1 bypasses quiet hours. 2 (emergency) repeats until acknowledged;
  `retry` >= 30 s, `expire` <= 10800 s (3 h), capped at 50 retries; receipts and an
  acknowledgement callback.
- iOS Critical Alerts: Pushover has the Apple entitlement and a user-enabled setting for
  high/emergency priority (per Pushover support/blog threads). **Exact current behaviour
  (which priorities, Focus interaction) not confirmed against a current first-party doc.**
- Native receivers: Alertmanager `pushover_configs` (defaults priority 2 when firing, 0 when
  resolved; `retry` 1m, `expire` 1h), Grafana contact point "Pushover", Netdata
  "PushOver", healthchecks.io `po`.

### ntfy.sh hosted ([ntfy tiers], [ntfy pricing], [ntfy faq])

- Anonymous free tier (from `https://ntfy.sh/v1/tiers`): 250 messages/day per IP, 12 h
  message expiry, 5 emails, 0 calls, 0 reserved topics, 2 MB attachments.
- Paid: Supporter $5/mo (2,500 msgs/day, 3 reserved topics, 3 calls), Pro $10/mo,
  Business $20/mo. A reserved topic is the only way to stop others posting to "your" topic;
  without it the topic name is the password.
- No SLA: "Best effort"; "runs on a single DigitalOcean droplet, without any scale out
  strategy or redundancies" (FAQ, dated Dec 2022; may be stale). iOS app described by its
  author as "bare bones and ... a little buggy".
- Priorities 1-5; 5 = "Really long vibration bursts ... pop-over notification" on Android.
  No iOS critical-alert support documented.
- Integration: no native Alertmanager receiver; use `webhook_configs` to
  `https://ntfy.sh/<topic>?template=alertmanager` (ntfy's built-in template). Grafana: webhook
  contact point with `?template=grafana`; nixpkgs also ships `services.grafana-to-ntfy`.
  Netdata and healthchecks.io: native ntfy.

### Self-hosted ntfy on calamansi (`services.ntfy-sh` in nixpkgs)

- Rejected for v1. Shares a failure domain with the observability host, adds a service, and
  iOS instant delivery still requires `upstream-base-url` relaying poll requests via ntfy.sh
  -> Firebase -> APNs ("delivery can take hours" without it). [ntfy config] The map also
  forbids publishing endpoints to the internet, so a travelling phone would need to be on the
  tailnet to fetch message bodies.

## Integration summary

| Alerter | Pushover | ntfy | Heartbeat ping |
| --- | --- | --- | --- |
| Alertmanager (also vmalert) | native `pushover_configs` | `webhook_configs` + `?template=alertmanager` | Watchdog -> `webhook_configs` |
| Grafana alerting | native contact point | Webhook + `?template=grafana`, or `grafana-to-ntfy` | always-firing rule -> Webhook |
| Netdata agent | native | native | systemd timer + curl |
| healthchecks.io | native (`po`) | native | n/a |

## Cost

- Recommended: healthchecks.io $0 + Pushover $4.99 once (per phone platform; add $4.99 if a
  desktop client is wanted). No recurring cost.
- Paid tiers that do **not** clear the bar: healthchecks.io Business ($20/mo; SMS/calls
  unnecessary with Pushover emergency priority), ntfy.sh Supporter ($5/mo; reserved topic is
  nice but not significant), Better Stack/Cronitor paid tiers.

## Unverified / open

- Which phone platform the user carries (iOS vs Android) shifts the Pushover-vs-ntfy margin.
- Pushover iOS Critical Alert behaviour today (source is support threads, 2020-2023).
- ntfy.sh infrastructure claim is from a 2022 FAQ entry.
- UptimeRobot Free heartbeat availability.
- healthchecks.io: any per-integration restriction on the Hobbyist plan (none documented).

## Sources

- [pricing]: https://healthchecks.io/pricing/
- [http_api]: https://healthchecks.io/docs/http_api/
- [configuring_checks]: https://healthchecks.io/docs/configuring_checks/
- [configuring_notifications]: https://healthchecks.io/docs/configuring_notifications/
- healthchecks source: https://github.com/healthchecks/healthchecks/tree/master/hc/integrations
- [pushover pricing]: https://pushover.net/pricing
- [pushover api]: https://pushover.net/api
- Pushover critical alerts threads: https://support.pushover.net/i59-ios-implement-critical-alerts-for-priority-emergency , https://support.pushover.net/i148-option-to-have-critical-alerts-on-ios-for-emergency-priority-messages-only-not-high-priority-and-emergency-priority-as-it-is-now
- [ntfy pricing]: https://ntfy.sh/#pricing
- [ntfy tiers]: https://ntfy.sh/v1/tiers
- [ntfy faq]: https://docs.ntfy.sh/faq/
- ntfy publish (priorities, templates): https://docs.ntfy.sh/publish/
- [ntfy config]: https://docs.ntfy.sh/config/
- Alertmanager configuration: https://prometheus.io/docs/alerting/latest/configuration/
- Grafana contact points: https://grafana.com/docs/grafana/latest/alerting/fundamentals/notifications/contact-points/
- Netdata agent notifications: https://learn.netdata.cloud/docs/alerts-&-notifications/notifications/agent-dispatched-notifications
- [betterstack]: https://betterstack.com/pricing
- [cronitor]: https://cronitor.io/pricing
- [dms]: https://deadmanssnitch.com/plans
- [uptimerobot]: https://uptimerobot.com/pricing/
- nixpkgs options `services.healthchecks.*`, `services.ntfy-sh.*`, `services.grafana-to-ntfy.*` (search.nixos.org, via nixos MCP)
