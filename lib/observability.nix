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

  # ── Grafana datasource UIDs ───────────────────────────────────────────
  #
  # Fixed, because dashboards and the Alertmanager links inside them reference
  # a datasource by UID and a generated UID would break them on every rebuild.
  # VictoriaLogs' UID is already reserved so BOX-330 adds the datasource
  # without every dashboard in between having to change.
  datasourceUids = {
    victoriaMetrics = "victoriametrics";
    victoriaLogs = "victorialogs";
    alertmanager = "alertmanager";
  };
}
