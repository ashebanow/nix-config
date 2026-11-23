# Observability stack: least maintenance with data kept local

Research date: 2026-11-23. Ticket: BOX-312 (map BOX-311). Decision belongs to BOX-317; this note
recommends, it does not decide.

Constraints from the map: two NixOS servers (lumquat, calamansi); store, query, alerting and
dashboards on calamansi; collectors only on watched hosts; metrics + logs + alerting + dashboards,
no tracing; data never leaves the network (external services only for alert delivery and a
heartbeat); tailnet only; storage2 (UniFi UNAS Pro, SMB) is archive only. **Low ongoing
maintenance ranks first.**

nixpkgs reference point: this repo's pin, `nixos-unstable` at `d176bec6` (late October 2026).
Versions below come from the nixos MCP search index (unstable channel) on the research date.

**Headline: VictoriaMetrics + VictoriaLogs + vmalert, with Grafana for dashboards, ranks first.**
It is the only option that covers all four signals, has first-class NixOS modules *and* NixOS
tests for every server-side piece, has no schema/index migrations, two official MCP servers, and
stores data as plain per-day directories that rsync to an SMB share. Prometheus + Loki is the
runner-up (same coverage, more maintenance). Netdata and Beszel are lower-maintenance on day
one but each fails a hard requirement (see their sections). OpenObserve is a credible
"single binary" alternative but has no NixOS module. SigNoz is out.

---

## Ranked summary

| Rank | Stack | Moving parts on calamansi | NixOS modules (at pin) | Signals covered | Agent access | Archive to SMB |
|---|---|---|---|---|---|---|
| 1 | VictoriaMetrics + VictoriaLogs + vmalert + Alertmanager + Grafana | 5 services, all nixpkgs | all: `services.victoriametrics`, `.victorialogs`, `.vmalert`, `.prometheus.alertmanager`, `.grafana` (+ `vmagent`, `vlagent` for collectors) | metrics, logs, alerts, dashboards | official MCP for VM and VL; Prometheus-compatible HTTP + LogsQL HTTP | per-day log partitions via snapshot + rsync; `vmbackup fs://`; JSON/CSV export APIs |
| 2 | Prometheus + Alertmanager + Grafana + Loki (+ Alloy) | 4–5 services | all present: `services.prometheus`, `.loki`, `.grafana`, `.alloy` | all four | `grafana/mcp-grafana` (Prometheus + Loki) | Prometheus snapshots; Loki chunks are opaque, no plain export |
| 3 | Netdata (parent on calamansi, children stream) | 1 per host | `services.netdata` (dashboard UI *not* built by default) | metrics, alerts, dashboards; logs only via journald in place | built-in MCP (v2.6.0+) | dbengine files only; no plain export path |
| 4 | OpenObserve | 1 binary | **none** (package only, `openobserve` 1.1.2) | all four | built-in MCP | Parquet on disk |
| 5 | Beszel + a log store | hub + agent + separate log stack | `services.beszel.hub/agent` | metrics, alerts, dashboards; **no logs** | REST (PocketBase); no MCP found | PocketBase backups |
| 6 | SigNoz | ClickHouse, Keeper, Postgres, collector, server | **none** (not packaged) | all four (+traces) | optional MCP container | no |

---

## 1. VictoriaMetrics + VictoriaLogs + vmalert (± Grafana)

**Versions (nixpkgs unstable):** `victoriametrics` 1.156.0, `victorialogs` 1.54.0,
`grafana` 13.3.1, `grafanaPlugins.victoriametrics-logs-datasource` 0.34.0,
`grafanaPlugins.victoriametrics-metrics-datasource` 1.0.1.

**Maintenance burden.** Each store is one Go binary with flags, no config file required.
VictoriaMetrics can scrape directly from a Prometheus-style config (`-promscrape.config`, exposed
as `services.victoriametrics.prometheusConfig`), so no separate Prometheus is needed. Retention is
one flag each: VictoriaMetrics `-retentionPeriod` (nix option `retentionPeriod`, default one month,
minimum 1d); VictoriaLogs `-retentionPeriod` (default `7d`) plus optional
`-retention.maxDiskSpaceUsageBytes` / `-retention.maxDiskUsagePercent` (mutually exclusive).
Upgrades: both docs say upgrading is safe "unless release notes say otherwise"; VictoriaLogs adds
that skipping versions and downgrading are also safe under the same condition. There are no schema
or index-period migrations comparable to Loki's. Caveat: the native export format "may change in
incompatible way between releases", so use JSON/CSV export for long-lived archives.

**NixOS support.** Modules at the pin: `nixos/modules/services/databases/victoriametrics.nix`,
`.../databases/victorialogs.nix`, `.../monitoring/vmalert.nix` (multi-instance,
`rules` declarable in Nix), `.../monitoring/vmagent.nix`, `.../monitoring/vlagent.nix`. NixOS
tests at the pin: `nixos/tests/victoriametrics/{default,remote-write,external-promscrape-config,vmalert}.nix`
and `nixos/tests/victorialogs/{default,local-write,remote-write-with-vlagent}.nix`. Package
maintainers: yorickvp, leona, shawn8901, ryan4yin. The `victorialogs` module runs with
`DynamicUser = true` and exposes no `retentionPeriod` option, so retention goes through
`extraOptions`.

**Resource cost (estimate, not measured).** VictoriaLogs recommends 50% free RAM, 50% spare CPU,
20% free disk, and claims ~10x log compression and "up to 30x less RAM and up to 15x less disk"
than Loki/Elasticsearch (vendor claims). For two hosts (~5–10k active series at 15–30 s scrape)
13 months of metrics should land in the low tens of GB; 30 days of journald from two hosts
(guess 0.5–2 GB/day raw) should be single-digit GB after compression. RAM for both stores at
this scale is likely well under 1 GB. **Unverified:** VictoriaMetrics' docs give no per-sample
figure in the sections read; they tell you to measure and extrapolate.

**Coverage.** Metrics (VM), logs (VL; journald ingest natively at `/insert/journald` via
`systemd-journal-upload`, so no extra log shipper is strictly required), alerting (vmalert on
both: `type: vlogs` rules use VL's `stats_query` APIs; notifications go to Alertmanager via
`-notifier.url`), dashboards (vmui and VL's built-in UI for ad-hoc queries; vmui has a minimal
`Dashboards` tab; Grafana for real dashboards). Gap: vmalert has no notification routing of its
own, so Alertmanager is still needed for phone push (or a webhook receiver). Grafana Alerting
cannot display datasource-managed rules through the VL plugin, so alert rules live in vmalert,
not Grafana.

**Agent access.** Official MCP servers in the VictoriaMetrics GitHub org:
`VictoriaMetrics/mcp-victoriametrics` (tools `query`, `query_range`, `alerts`, `rules`; supports
`VM_INSTANCE_TYPE=single`) and `mcp-victorialogs` (LogsQL `query`, `stats_query`, `facets`,
`streams`, etc.). Both stores also have plain HTTP query APIs (Prometheus-compatible / LogsQL).

**Archiving.** VictoriaLogs stores logs in per-day partition directories
(`<storageDataPath>/partitions/YYYYMMDD`); the documented backup is: snapshot the partition via
the HTTP endpoint, `rsync` it, delete the snapshot. That maps directly onto "copy closed days to
storage2". For human-readable archives, LogsQL queries return JSON lines. VictoriaMetrics:
`vmbackup -dst=fs:///path` (local filesystem destination supported) or `/api/v1/export` (JSON
lines) / `/api/v1/export/csv`. **Unverified:** whether `vmbackup fs://` behaves well on a mounted
SMB share; the docs neither endorse nor forbid network filesystems for backup destinations.

**Without Grafana?** Possible (vmui + VL UI + vmalert), and one fewer service, but there are no
persistent multi-panel dashboards worth the name. Grafana with declaratively provisioned
datasources and dashboards (`services.grafana.provision`) is low-churn on NixOS and recommended.

## 2. Prometheus + Alertmanager + Grafana + Loki

**Versions:** `prometheus` 3.16.0, `grafana-loki` 3.7.10, `grafana` 13.3.1; collector Grafana
Alloy (`services.alloy`). Promtail reached end of life on 2026-03-02 (Grafana Loki docs), so
the log shipper is Alloy, which has its own config language.

**Maintenance burden.** Same number of services as option 1, but Loki is the high-friction
piece: retention only runs in the compactor and needs `compactor.retention_enabled: true`, a
`delete_request_store`, `limits_config.retention_period`, and a 24h index period (TSDB `v13`
schema). The `schema_config` is versioned by date and changing it later means adding a new
period entry. Loki 3.0 broke configs (removed `shared_store`, required `tsdb`/`v13` for structured
metadata, many flag renames), with further breaking changes in 3.2, 3.3, 3.4. Prometheus itself is
low-maintenance (`--storage.tsdb.retention.time` / `.size`).

**NixOS support.** Excellent: `services.prometheus` (with exporters and Alertmanager),
`services.loki` (config as Nix JSON value), `services.grafana`, `services.alloy`; NixOS tests
`prometheus`, `loki`, `grafana`, `alloy` all present at the pin.

**Resource cost.** Prometheus: "1–2 bytes per sample" (official). 13 months at ~10k series ×
1/15 s ≈ 22 billion samples ≈ 22–45 GB (estimate). Loki on a filesystem store is modest at this
scale. Prometheus docs warn that NFS and non-POSIX filesystems are unsupported, which is fine
since live data stays on calamansi's disk.

**Coverage.** All four. Grafana unified alerting can be used instead of Alertmanager, but that
moves alert rules into Grafana's database unless provisioned.

**Agent access.** `grafana/mcp-grafana` (Grafana Labs org) queries Prometheus and Loki through
Grafana.

**Archiving.** Prometheus: snapshot API, then copy the TSDB block directories (not plain text).
Loki: chunks and index are opaque; export means running LogQL queries (`logcli`) to files.

## 3. Netdata

**Version:** `netdata` 2.12.3. Lowest setup effort for metrics: one daemon per host, auto-detects
thousands of metrics, ships with prebuilt alerts, children stream to a parent on calamansi.

**Why it fails here:**
- **Dashboard and logs gated by Netdata Cloud.** Netdata's own access-control docs (updated
  2026-11-19): the systemd-journal logs explorer is a "sensitive function" that needs a signed-in
  (free) Netdata Cloud account; a Parent's local dashboard showing its children is limited to 5
  nodes when not connected to Cloud (fine for 2 hosts, but a dependency on an external auth
  service for a local tool). Notification configuration and dynamic configuration are paid-only.
- **nixpkgs builds it without the dashboard by default.** At the pin,
  `pkgs/tools/system/netdata/default.nix` has `withCloudUi ? false` and
  `ENABLE_DASHBOARD = withCloudUi`; enabling it adds the unfree `ncul1` license.
- **Logs are not stored.** Netdata reads journald files in place (or a
  `systemd-journal-remote` aggregation); there is no log retention/archive of its own outside the
  paid OpenTelemetry logs path.
- **Archiving:** dbengine tiers, no documented plain-file export.

Upside: built-in MCP server at `http://host:19999/mcp` on v2.6.0+, free and local.

## 4. OpenObserve

Single Rust binary covering logs, metrics, traces, alerting and dashboards; SQL and PromQL;
Parquet storage; built-in MCP server on by default (`ZO_MCP_ENABLED=true`). AGPL-3.0 open-source
edition; enterprise edition free up to 50 GB/day with registration.

**Why not first:** no NixOS module (only the `openobserve` / `openobserve-ee` packages, 1.1.2 in
the index), so we would write and maintain our own systemd unit or run a container; ingestion of
journald and Prometheus remote-write is not named on its docs landing page (OTLP, Fluent Bit,
Vector, Telegraf are), so a collector such as Alloy/Vector/OTel would be required; a single
vendor owns every layer, and its dashboards and alerts live in its own database rather than in
Nix. **Unverified:** exact on-disk layout for local mode and whether old Parquet files can be
copied out cleanly; the package version string 1.1.2 looks odd against upstream's history.

## 5. Beszel (+ a separate log store)

**Version:** `beszel` 0.21.2; modules `services.beszel.hub` and `services.beszel.agent`, NixOS
test `beszel`. Lowest-effort host metrics: CPU, memory, disk, network, temperatures, SMART,
Docker/Podman containers, AMD/Nvidia/Intel GPU (agent option `extraPath` for `rocm-smi`), with
built-in alerts to many services (ntfy, Discord, Telegram, ...).

**Why not:** no logs at all, so it still needs a second stack for logs (which then would want its
own alerting), defeating the low-maintenance goal. Long-term history is coarse: retention is a
fixed ~30-day window today; configurable 30d–5y retention is an **open, unmerged** PR (#2257,
opened 2026-08-23), so 13 months of metrics is not available in a release. No arbitrary custom
metrics (llama.cpp, bifrost) and no MCP server found.

## 6. SigNoz

Not packaged in nixpkgs. Deployment is ClickHouse + ClickHouse Keeper + PostgreSQL + SigNoz OTel
Collector + SigNoz server (+ optional MCP container), minimum 4 GB RAM to Docker. Install via
the new `foundryctl` tool; the Compose files and `install.sh` were deprecated in v0.130.0 with a
migration guide. That is the opposite of low maintenance for two hosts. Ruled out.

---

## Hosted / paid services against the bar

The map allows a paid service only for a significant advantage in ease of use, maintenance,
disaster recovery or reliability.

- **Grafana Cloud Free:** 10k active series, 50 GB logs/month, **14-day retention** for both,
  3 users. Fails 13-month metrics and 30-day logs.
- **Grafana Cloud Pro:** from $19/month platform fee + usage; metrics retention 13 months, logs
  30 days. Meets retention, removes store maintenance and gives off-site DR, but all metrics and
  logs leave the network, and collectors (Alloy) still need maintaining locally. The local
  options above are low-maintenance enough that the advantage is not "significant" by the map's
  definition.
- **Better Stack Free:** 3 GB logs kept 3 days, 30 GB metrics, 10 monitors/heartbeats; paid from
  $29–34/month. Logs retention fails. Its free heartbeat monitors are relevant to BOX-316
  (dead-man's switch), not to the store.

Conclusion: no hosted service clears the bar for the store; hosted services stay limited to alert
delivery and the heartbeat, as the map already says.

---

## Unverified / open

- Disk and RAM sizes are back-of-envelope estimates; measure after a week of real ingestion.
- `vmbackup fs://` and VictoriaLogs partition rsync onto an SMB mount: plausible, not documented.
- OpenObserve local storage layout and the 1.1.2 nixpkgs version string.
- Beszel PR #2257 may merge later and change its retention story (it still lacks logs).
- Whether Netdata's free Cloud sign-in requirement for logs could be avoided by an
  agent-local setting; docs say no.

## Sources

- nixos MCP search (search.nixos.org index, unstable, 2026-11-23): package versions and option
  names for victoriametrics, victorialogs, vmalert, vlagent, loki, alloy, netdata, beszel,
  openobserve, grafanaPlugins.
- nixpkgs at `d176bec6d3f7dc613eb18ae8cec9397610ef826f`: module and test file tree;
  `pkgs/by-name/vi/victoriametrics/package.nix` (maintainers);
  `nixos/modules/services/databases/victorialogs.nix`; `pkgs/tools/system/netdata/default.nix`
  (`withCloudUi`, `ncul1`).
- VictoriaLogs docs: https://docs.victoriametrics.com/victorialogs/ (retention flags, partitions,
  backup via snapshot+rsync, upgrades);
  https://docs.victoriametrics.com/victorialogs/data-ingestion/journald/ ;
  https://docs.victoriametrics.com/victorialogs/vmalert/
- VictoriaMetrics docs: https://docs.victoriametrics.com/victoriametrics/single-server-victoriametrics/
  (retention, export APIs, upgrade safety, vmui, promscrape);
  https://docs.victoriametrics.com/victoriametrics/vmbackup/ (`fs://`)
- MCP: https://github.com/VictoriaMetrics/mcp-victoriametrics ,
  https://github.com/VictoriaMetrics-Community/mcp-victorialogs ,
  https://github.com/grafana/mcp-grafana ,
  https://learn.netdata.cloud/docs/netdata-ai/mcp , https://openobserve.ai/docs/integration/ai/mcp/
- Loki: https://grafana.com/docs/loki/latest/operations/storage/retention/ ,
  https://grafana.com/docs/loki/latest/setup/upgrade/ ,
  https://grafana.com/docs/loki/latest/send-data/promtail/ (EOL 2026-03-02)
- Prometheus: https://prometheus.io/docs/prometheus/latest/storage/
- Netdata: https://learn.netdata.cloud/docs/security-and-privacy-design/access-control-and-feature-availability ,
  https://learn.netdata.cloud/docs/logs/systemd-journal-logs/systemd-journal-plugin-reference
- Beszel: https://github.com/henrygd/beszel , https://beszel.dev/guide/what-is-beszel ,
  https://github.com/henrygd/beszel/pull/2257
- OpenObserve: https://github.com/openobserve/openobserve , https://openobserve.ai/docs/
- SigNoz: https://signoz.io/docs/install/docker/
- Pricing: https://grafana.com/pricing/ , https://betterstack.com/pricing
