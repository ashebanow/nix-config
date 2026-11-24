# Rendering helpers for the `my.observability` option set.
#
# These turn the collections declared in lib/my-options-module.nix into the
# native config formats the services actually read: Prometheus scrape config
# for vmagent, and Grafana provisioning for the host. The point of keeping them
# here rather than inline in a module is that two consumers need the same
# shape — the agent renders what it scrapes, the host renders what it gathers
# from everyone — and a single implementation cannot drift from itself.
#
# Deliberately NOT here yet: the textfile-check builder helpers (BOX-332's
# `obs.sqliteCheck` and friends) and the rule gathering (BOX-329). This file
# gains them; nothing in it needs reshaping for them.
{ lib }:
rec {
  # ── Scrape targets ────────────────────────────────────────────────────
  #
  # One `scrape_configs` entry per named target. The entry's name is the
  # `job_name`, which is what a dashboard filters on, so it is deliberately
  # the key from `my.observability.scrapeTargets` and nothing else.
  #
  # `targets` is a list even for a single address because that is what
  # Prometheus' config requires; the option takes a string and may carry
  # several comma-separated addresses for a multi-instance service.
  scrapeTargetToJob =
    name: target:
    let
      hosts = map (s: lib.trim s) (lib.splitString "," target.address);
      staticConfig = {
        targets = hosts;
      }
      // lib.optionalAttrs (target.labels != { }) {
        labels = target.labels;
      };
    in
    {
      job_name = name;
      metrics_path = target.metricsPath;
      static_configs = [ staticConfig ];
    }
    // lib.optionalAttrs (target.interval != null) { scrape_interval = target.interval; }
    // lib.optionalAttrs (target.scrapeTimeout != null) { scrape_timeout = target.scrapeTimeout; };

  # `scrapeTargets` attrset -> the `scrape_configs` list vmagent reads.
  # Sorted by name so the rendered config is byte-stable: an attrset's order
  # is not defined, and a config that reorders on every eval would restart
  # vmagent for no reason and make the diff worthless.
  renderScrapeConfigs = scrapeTargets: lib.mapAttrsToList scrapeTargetToJob scrapeTargets;

  # The whole Prometheus scrape config document. Named after the file the
  # service consumes so a reader can go straight from a rendered path to this
  # function.
  mkPrometheusScrapeConfig = scrapeTargets: {
    scrape_configs = renderScrapeConfigs scrapeTargets;
  };

  # ── Dashboards ────────────────────────────────────────────────────────
  #
  # A dashboard provider watches a directory, so gathering every host's
  # dashboards is a link farm: one symlink per declared file, named after the
  # collection key. Two hosts declaring the same key is a collision, and the
  # assertion in observability-host.nix catches it — a silent overwrite would
  # look like one host's dashboard simply not existing.
  mkDashboardLinks =
    dashboards:
    lib.mapAttrs' (name: dashboard: lib.nameValuePair "${name}.json" dashboard.path) dashboards;

  # ── VictoriaLogs endpoints ────────────────────────────────────────────
  #
  # The journald ingest URL, in one place because two modules need to agree on
  # it: the host opens a firewall port for it, the agent uploads to it. A
  # mismatch there is the worst kind of bug — the firewall looks right, the
  # uploader looks right, and nothing arrives.
  #
  # `/insert/journald` is VictoriaLogs' native systemd-journal ingest endpoint:
  # it accepts the journal's own binary encoding
  # (`application/vnd.fdo.journal`), which is exactly what
  # `systemd-journal-upload` sends. It is not a JSON endpoint with a journald
  # name; VictoriaLogs' own error string is "only application/vnd.fdo.journal
  # encoding is supported for Journald". So no translation layer is needed — see
  # the module header in modules/features/observability-agent.nix for the
  # alternatives that were rejected.
  #
  # Upstream writes the same URL path (`/insert/journald`) in its setup docs;
  # `/insert/journald/upload` also exists and is what the metric name
  # `vl_http_request_duration_seconds{path="/insert/journald/upload"}` reports,
  # but the documented value is used here so a future reader comparing our
  # config to the upstream page sees the same string.
  journalUploadUrl = hostAddress: port: "http://${hostAddress}:${toString port}/insert/journald";

  # ── Grafana datasource UIDs ───────────────────────────────────────────
  #
  # Fixed, because dashboards and the Alertmanager links inside them reference
  # a datasource by UID and a generated UID would break them on every rebuild.
  # VictoriaLogs was reserved before it existed (BOX-326) and is now provisioned
  # by BOX-330; Alertmanager is still reserved and is BOX-329's.
  datasourceUids = {
    victoriaMetrics = "victoriametrics";
    victoriaLogs = "victorialogs";
    alertmanager = "alertmanager";
  };
}
