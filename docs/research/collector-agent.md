# Which collector agent should run on each server? (BOX-313)

Research date: 2026-11-23. Map: BOX-311 (observability for lumquat and calamansi). Decision
belongs to BOX-317; this note only recommends. nixpkgs reference is `nixos-unstable` as indexed
by search.nixos.org on the research date (the flake tracks `nixos-unstable`). Versions below are
from that index unless noted.

Constraints taken from the map: low ongoing maintenance ranks above power; metrics and logs stay
on the user's machines; each watched host runs only a collector; store/query/alert/dash on
calamansi; containers are rootless Podman under the `podman` user, moving to Quadlet
(docs/adr/0002); bifrost's `logs.db` has the readonly/uid sidecar trap (BOX-202,
`modules/features/bifrost.nix`).

## Headline

**Recommend Grafana Alloy on each server, with three agent-independent helpers that every
option needs anyway:** container logs via journald, container metrics via the nixpkgs podman
exporter, and custom checks (bifrost `logs.db`) via a systemd timer writing a node_exporter
textfile. **Runner-up: Vector**, which is the better fit for Nix (settings are a Nix attrset,
validated at build time) but leaves host and container metrics to separate exporters. If BOX-312
picks the VictoriaMetrics stack, Alloy still works (standard remote-write and Loki push), and
**vmagent + node_exporter + VictoriaLogs' native journald/syslog ingestion** is the
stack-native alternative. OpenTelemetry Collector, Fluent Bit, Netdata, Telegraf and the Beszel
agent are ranked lower for the reasons below.

One structural finding changes the question: **UniFi syslog should not go to a per-server agent
at all.** UniFi devices send to one address; the receiver belongs on calamansi (the
observability host), either the store's own syslog listener (VictoriaLogs has one) or a
collector instance there. The per-server agent does not need a syslog receiver.

## 1. Requirements shrink once the shared plumbing is fixed

These hold regardless of which agent is chosen, and they make the agent's job smaller.

| Requirement | How it is met | Source |
|---|---|---|
| Podman/Quadlet container **logs** | Podman's default `log_driver` is journald "if the systemd journal is readable and writable", otherwise `k8s-file`. The repo sets no `LogDriver`, so container stdout already lands in journald with `CONTAINER_NAME` etc. The agent's journald source covers it. | containers.conf(5), `log_driver` |
| Container **metrics** (state, restarts, CPU/mem) | `services.prometheus.exporters.podman` exists in nixpkgs (package `prometheus-podman-exporter` 2.0.0), with a `user` option so it can run as the rootless `podman` user against its socket. The agent scrapes it. | nixpkgs options |
| Host metrics incl. temperatures | node_exporter `hwmon` + `thermal_zone` collectors (Strix Halo GPU temps come through amdgpu's hwmon). Either embedded in the agent (Alloy, Fluent Bit) or `services.prometheus.exporters.node`. | Alloy `prometheus.exporter.unix` docs |
| Custom checks (bifrost `logs.db` size, rows, oldest row) | A systemd timer that writes `*.prom` into a textfile directory; the textfile collector exposes it. No agent offers a sqlite source worth using (OTel `sqlquery` has no sqlite driver; Alloy has none). | OTel sqlqueryreceiver README |
| Prometheus endpoints (llama.cpp `/metrics`) | Any agent's Prometheus scrape. | all |
| UniFi syslog | On calamansi, not the servers (see headline). | — |

**bifrost check, concretely:** file size needs no sqlite at all (`stat -c %s`). Rows and
oldest-row age need a query; the BOX-202 trap is that sqlite creates `-wal`/`-shm` as whoever
opens the file. The timer should open the db read-only *as the file's owning uid* (read it with
`stat -c '%u:%g'`, as `bifrost-vacuum` already does, then `setpriv --reuid --regid`), so any
sidecar it creates is owned correctly. Not prototyped; BOX-311 lists this as open fog.

## 2. Candidates

### Grafana Alloy (rank 1)

- **NixOS:** `services.alloy` (enable, package, `configPath` default `/etc/alloy`,
  `environmentFile`, `extraFlags`). Package `grafana-alloy` 1.21.3 on search.nixos.org (NixHub
  shows 1.17.1 at 2026-10-08; index lag, not verified which is current on our pin). The module
  reads **every `*.alloy` file in `/etc/alloy`** and adds them to `reloadTriggers`, so config
  changes reload on `nixos-rebuild switch` without a restart.
- **Config style:** Alloy's own HCL-like syntax, written as text from Nix
  (`environment.etc."alloy/<name>.alloy".text`). Not a Nix attrset and not validated at build
  time by the module. Upside for the dendritic model: each feature module can drop its own
  `alloy/<feature>.alloy` file, which is a clean "new source" story (BOX-318). Component names
  must be unique across files.
- **Coverage:** `loki.source.journal` (default reads `/var/log/journal` and `/run/log/journal`);
  `loki.source.syslog` (TCP/UDP, `rfc5424` default, `rfc3164` supported, `raw` experimental);
  `prometheus.exporter.unix` = embedded node_exporter with `hwmon`, `thermal_zone`, `textfile`
  **on by default**; `prometheus.scrape`; `prometheus.remote_write`; `loki.write`; full OTLP via
  `otelcol.*`. `prometheus.exporter.cadvisor` lists Docker/containerd/CRI-O/systemd, not Podman,
  so use the podman exporter instead. `loki.source.docker` takes a Docker socket address; it
  is not documented for Podman's compatible socket and is unnecessary given journald.
- **Footprint:** Grafana's published estimate is ~11 GiB per 1M active series and ~120 MiB per
  1 MiB/s of logs. At this scale (low thousands of series, KB/s of logs) that implies well under
  200 MiB; not measured here.
- **Maintenance:** one daemon replaces node_exporter + promtail + a scraper. Promtail reached
  EOL on 2026-03-02 and Grafana says new log-shipping work happens only in Alloy, so Alloy is
  the supported path on the Grafana side. Alloy ships minor releases frequently; nixpkgs tracks
  them. Built-in UI on :12345 shows component health, useful when debugging.
- **Pairs with:** Loki/Prometheus/Mimir natively; VictoriaMetrics (remote-write) and
  VictoriaLogs (Loki push API is a listed ingestion path); OpenObserve/SigNoz via OTLP.

### Vector (rank 2)

- **NixOS:** `services.vector` (`settings` as a JSON value, `journaldAccess`,
  `validateConfig` checks the config at build time, `gracefulShutdownLimitSecs`). Package 0.62.0.
- **Config style:** the most Nix-native of the set. `settings` is an attrset, so feature modules
  can merge their own `sources.*`/`transforms.*` through the module system, and a bad config fails
  the build instead of the service.
- **Coverage:** `journald`, `syslog` (TCP/UDP/unix stream; best-effort RFC 3164/5424/6587),
  `prometheus_scrape`, `host_metrics`, `exec` (custom checks without the textfile trick),
  `docker_logs`; no Podman source. `host_metrics` has a `temperature` collector (via the `sysinfo`
  crate) but it is **not in the default list** and its metric names are not node_exporter's, so
  prebuilt node_exporter dashboards and alert rules do not apply. Practically you would run
  `services.prometheus.exporters.node` beside it.
- **Sinks:** `loki`, `prometheus_remote_write`, `elasticsearch`, `http`, `opentelemetry`.
  VictoriaLogs lists Vector as a supported shipper.
- **Footprint:** Rust, generally light; no first-party figure found.
- **Maintenance:** the strongest Nix story but a weaker metrics story. Two daemons (vector +
  node_exporter) instead of one.

### VictoriaMetrics agents: vmagent (+ vlagent) (stack-dependent)

- **NixOS:** `services.vmagent` (`prometheusConfig` as attrset, `remoteWrite.url`,
  `checkConfig`) and `services.vlagent` (`remoteWrite.url`, `maxDiskUsagePerUrl`).
  victoriametrics 1.156.0.
- **Coverage:** vmagent is **metrics only** (scrape + many push protocols, disk buffering via
  `-remoteWrite.tmpDataPath`); it needs node_exporter for host metrics. vlagent collects from
  files and Kubernetes and accepts pushes "in the same way as VictoriaLogs does"; its flags
  mention journald-protocol ingestion, but whether it *reads* the local journal itself was not
  confirmed. VictoriaLogs itself accepts journald export format and syslog directly.
- **Assessment:** three or four small, well-behaved daemons (node_exporter, podman exporter,
  vmagent, plus a journal shipper such as `systemd-journal-upload` or vlagent). Only sensible if
  BOX-312 picks VictoriaMetrics + VictoriaLogs; even then Alloy can feed that stack with one
  daemon.

### Fluent Bit (rank 4)

- **NixOS:** `services.fluent-bit` (`settings` YAML attrset or `configurationFile`,
  `graceLimit`). Package 5.1.5.
- **Coverage:** inputs `systemd`, `syslog`, `node_exporter_metrics` (a **subset** of
  node_exporter, includes `hwmon` and `thermal_zone`; `textfile` is not on by default and needs
  `collector.textfile.path`), `prometheus_scrape`, `exec`, `podman_metrics` (reads
  `containers.json` + cgroups; default path is the rootful store, rootless support not
  documented), `thermal`. Outputs include Loki and Prometheus remote write.
- **Assessment:** very capable and light, Nix-friendly settings, but it is logs-first; its
  metrics pipeline and node_exporter subset are less conventional than Alloy's, and rootless
  Podman metrics are unproven. No memory figure found in first-party docs.

### OpenTelemetry Collector (contrib) (rank 5)

- **NixOS:** `services.opentelemetry-collector` (`settings` YAML attrset or `configFile`,
  `validateConfigFile`). `opentelemetry-collector-contrib` 0.155.0 (a large binary).
- **Coverage:** `journaldreceiver` is **alpha** and shells out to `journalctl` (needs the binary
  and `systemd-journal` group); `syslogreceiver`; `hostmetrics` (beta) now has a Linux `hardware`
  scraper for hwmon temperatures; `prometheusreceiver`; `podmanreceiver` is **alpha** (supports
  rootless socket); `sqlqueryreceiver` has **no sqlite driver**.
- **Assessment:** most power, most churn: 0.x versions, alpha receivers for two of our core
  inputs, and OTel semantic-convention metric names that don't match node_exporter dashboards.
  Only worth it if BOX-312 picks an OTLP-native store (SigNoz, OpenObserve). Note Alloy *is* an
  OTel Collector distribution, so it covers that case too.

### Netdata (stack-bound, not a shipper)

- **NixOS:** `services.netdata` (config attrs, `configDir`, python plugins,
  `claimTokenFile`). Package 2.12.3.
- **Coverage:** collects nearly everything out of the box (cgroups incl. Podman, sensors,
  Prometheus endpoints via go.d), but it is not a general shipper: it streams metrics only to a
  Netdata parent, and its journal plugin **queries journals in place** rather than shipping them.
- **Blocker vs. the map:** the systemd-journal plugin is a Netdata Function, and Functions
  (including log viewing) require a free **Netdata Cloud sign-in**. Data flows agent to browser,
  but this adds an external dependency the map reserves for alert delivery and heartbeat only.
  Only relevant if BOX-312 picks Netdata as the whole stack.

### Others noted

- **Telegraf** (`services.telegraf`, 1.40.3): metrics agent with TOML attrset config; no journald
  log shipping. Not a single-agent answer.
- **Beszel agent** (`services.beszel.agent`): metrics only (with AMD GPU via `amd_sysfs`, systemd
  services, and a journal view) for the Beszel hub only. Only relevant if BOX-312 picks Beszel.
- **Promtail:** EOL 2026-03-02; no `services.promtail` options on the current index.

## 3. Pairing with BOX-312's candidate stacks

| Stack (BOX-312) | Natural agent | Alloy works? |
|---|---|---|
| Prometheus + Loki + Grafana | Alloy | native |
| VictoriaMetrics + VictoriaLogs | vmagent + node_exporter + journald shipping | yes (remote-write, Loki push) |
| Netdata | Netdata child | n/a |
| Beszel + log store | Beszel agent + a log shipper | logs side only |
| OpenObserve / SigNoz | OTel Collector | yes (OTLP) |

## 4. Not verified

- Memory footprints are not measured; only Grafana publishes a sizing formula. Measure on
  lumquat before deciding if footprint matters.
- That Alloy's `loki.source.journal` reads the rootless `podman` user's journal files
  (`user-<uid>.journal` under `/var/log/journal`). It reads the directory, so it should; check
  for `CONTAINER_NAME` entries once deployed.
- That `prometheus-podman-exporter` running as `podman` sees Quadlet containers started by the
  system-level units (it should via `/run/user/<uid>/podman/podman.sock`).
- Whether the amdgpu hwmon on Strix Halo exposes GPU temperature/power (BOX-315 covers it).
- The bifrost read-only query as the owning uid (not prototyped).
- Alloy's version on our actual `flake.lock` pin (index says 1.21.3, NixHub 1.17.1).

## Sources

- nixpkgs options and packages via search.nixos.org / NixHub (MCP `nixos`), 2026-11-23:
  `services.alloy`, `services.vector`, `services.fluent-bit`, `services.opentelemetry-collector`,
  `services.vmagent`, `services.vlagent`, `services.netdata`, `services.telegraf`,
  `services.beszel.agent`, `services.prometheus.exporters.podman`,
  `services.prometheus.exporters.node`.
- containers.conf(5): https://github.com/containers/common/blob/main/docs/containers.conf.5.md
- Alloy: https://grafana.com/docs/alloy/latest/reference/components/loki/ ,
  `.../loki/loki.source.syslog/`, `.../loki/loki.source.journal/`, `.../loki/loki.source.docker/`,
  `.../prometheus/`, `.../prometheus/prometheus.exporter.unix/`,
  `.../prometheus/prometheus.exporter.cadvisor/`,
  https://grafana.com/docs/alloy/latest/introduction/estimate-resource-usage/
- Promtail EOL: https://grafana.com/docs/loki/latest/send-data/promtail/ ,
  https://grafana.com/docs/alloy/latest/set-up/migrate/from-promtail/
- Vector: https://vector.dev/docs/reference/configuration/sources/ ,
  `.../sources/host_metrics/`, `.../sources/syslog/`, https://vector.dev/docs/reference/configuration/sinks/
- Fluent Bit: https://docs.fluentbit.io/manual/llms.txt ,
  https://docs.fluentbit.io/manual/data-pipeline/inputs/node-exporter-metrics ,
  https://docs.fluentbit.io/manual/data-pipeline/inputs/podman-metrics
- OTel Collector contrib READMEs (main branch): `receiver/journaldreceiver`,
  `receiver/podmanreceiver`, `receiver/sqlqueryreceiver`, `receiver/hostmetricsreceiver`
- VictoriaMetrics: https://docs.victoriametrics.com/victoriametrics/vmagent/ ,
  https://docs.victoriametrics.com/victorialogs/vlagent/ ,
  https://docs.victoriametrics.com/victorialogs/data-ingestion/
- Netdata: https://learn.netdata.cloud/docs/logs/systemd-journal-logs/systemd-journal-plugin-reference ,
  https://github.com/netdata/netdata/blob/master/docs/dashboards-and-charts/README.md
- Repo: `modules/features/bifrost.nix` (vacuum script, uid trap), `modules/features/llm.nix`
  (rootless `podman.user`), `docs/adr/0002-container-workloads-use-quadlet.md`.
