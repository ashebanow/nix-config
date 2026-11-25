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
# `obs.sqliteCheck` and friends). This file gains them; nothing in it needs
# reshaping for them.
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

  # ── Alert rules ───────────────────────────────────────────────────────
  #
  # A ruleset is a named entry in `my.observability.rules` with a list of YAML
  # files; vmalert loads a *directory* of them. Two transformations are needed
  # and both are here because the host and the contract test must agree on the
  # result exactly.
  #
  # The file name is derived from the ruleset key and the position in `files`
  # (`<ruleset>.0.yaml`, `<ruleset>.1.yaml`), never from the source file's own
  # name: two features may both ship `alerts.yaml`, and a collision there would
  # silently drop one of them. Sorting by name makes the directory listing
  # byte-stable, so a rebuild that changed nothing re-uses the same derivation.
  mkRuleFiles =
    rulesets:
    lib.sort (a: b: a.name < b.name) (
      lib.concatLists (
        lib.mapAttrsToList (
          name: ruleset:
          lib.imap0 (index: path: {
            name = "${name}.${toString index}.yaml";
            inherit path;
          }) ruleset.files
        ) rulesets
      )
    );

  # The rulesets that belong to one vmalert instance. `type` is `metrics` or
  # `logs`, and it selects which datasource the files are evaluated against.
  rulesetsOfType = type: rulesets: lib.filterAttrs (_: ruleset: ruleset.type == type) rulesets;

  # ── Alertmanager configuration ────────────────────────────────────────
  #
  # Rendered as an attrset and serialised by the caller, so the route tree can
  # be read (and asserted on) as data rather than as YAML text.
  #
  # ## The secret indirection
  #
  # `token`/`user_key`/`url` below are `${VAR}` *references*, not values: the
  # Alertmanager module runs `envsubst` over the rendered file at build time, and
  # the environment it sees has none of these variables set — so they survive
  # into the store as literal `${PUSHOVER_APP_TOKEN}` text and are substituted at
  # start-up by `secretspec run`, which holds the only copy of the values. That
  # is the whole mechanism, and it is why the store never contains a token.
  #
  # The `${VAR}` text is deliberate, and `\${` is what the caller writes so
  # that Nix emits exactly it — not an interpolation of a Nix variable, and not
  # the `$${VAR}` escaping Alertmanager documents for a `$` it should keep.
  #
  # ## Grouping
  #
  # BOX-320: group by rule and host, 30 s group wait, repeat critical hourly and
  # warning every 12 h. `host` is not a label the rules have to carry: vmagent
  # attaches `instance` to every series it scrapes and vmalert copies the
  # alerting series' labels onto the alert, so the generic rules get their
  # hostname for free. The Watchdog (`vector(1)`) has no `instance`, so it
  # groups by `alertname` alone — which for a single always-firing alert is the
  # same thing.
  #
  # ## Severity → Pushover priority
  #
  # Pushover's `priority` is a per-notification value, so the receiver's is a
  # Go template over the alert's severity label rather than two receivers. The
  # `pushover_configs` field is a string so the template survives serialisation
  # unquoted.
  mkAlertmanagerConfig =
    {
      healthchecksReceiverUrl,
    }:
    {
      global = {
        resolve_timeout = "5m";
      };
      route = {
        receiver = "pushover";
        group_by = [
          "alertname"
          "host"
        ];
        group_wait = "30s";
        group_interval = "5m";
        repeat_interval = "1h";
        routes = [
          {
            # The Watchdog is not an alert for a human: it goes only to the
            # healthchecks.io bridge, at the one-minute cadence that service
            # expects, and never to the phone.
            receiver = "healthchecks";
            matchers = [ "severity=\"none\"" ];
            group_wait = "0s";
            group_interval = "1m";
            repeat_interval = "1m";
          }
          {
            # BOX-320: a warning repeats every 12 h rather than hourly, so a
            # slow-burning condition does not become a phone that buzzes all
            # day. Critical keeps the route default (hourly).
            receiver = "pushover";
            matchers = [ "severity=\"warning\"" ];
            repeat_interval = "12h";
          }
        ];
      };
      receivers = [
        {
          name = "pushover";
          pushover_configs = [
            {
              token = "\${PUSHOVER_APP_TOKEN}";
              user_key = "\${PUSHOVER_USER_KEY}";
              # 1 for critical (sounds once, bypasses quiet hours), 0 for
              # warning (respects them). No emergency priority in v1: an
              # unacknowledged repeat-until-ack at 3 a.m. is how Pushover gets
              # muted, and then nothing arrives at all.
              priority = "{{ if eq .CommonLabels.severity \"critical\" }}1{{ else }}0{{ end }}";
              # A resolve is worth knowing about; Pushover shows it at normal
              # priority because Alertmanager sends its own notification.
              send_resolved = true;
              title = "{{ .CommonLabels.alertname }}";
              message = "{{ range .Alerts }}{{ .Annotations.summary }}{{ if .Annotations.description }}\n{{ .Annotations.description }}{{ end }}{{ end }}";
            }
          ];
        }
        {
          name = "healthchecks";
          webhook_configs = [
            {
              # Loopback: the bridge is a sidecar of this host and is not
              # reachable from anywhere else.
              url = healthchecksReceiverUrl;
              send_resolved = false;
              max_alerts = 1;
            }
          ];
        }
      ];
      # No `inhibit_rules`: v1's rule list has no alert whose firing makes
      # another meaningless, and an unnecessary inhibition is an alert that
      # silently never arrives. Add one only alongside the rule that needs it.
      inhibit_rules = [ ];
    };

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
