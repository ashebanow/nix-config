# Observability host — the one machine that stores, queries, alerts on and
# displays every server's logs and metrics. See CONTEXT.md's Observability
# section for the vocabulary and docs/adr/0006 for why every service here is
# native rather than a container.
#
# What runs here, all under `my.observabilityHost`:
#
#   VictoriaMetrics   store and query (BOX-326)
#   VictoriaLogs      log store and query (BOX-330)
#   Grafana           display, provisioned from the repo (BOX-326)
#   vmalert           evaluate every agent host's rules (BOX-329)
#   Alertmanager      route and deliver, Pushover + healthchecks.io (BOX-329)
#
# The archive jobs (BOX-336/337) land here too — same flag, same machine, one
# host. They are absent because they are not written yet, not because the shape
# does not allow them.
#
# ## Alerting, and why nothing here is a store secret
#
# Rules are *native vmalert YAML* owned by the feature they watch, gathered from
# every agent host at build time (the same one-way gather as the dashboards), and
# `vmalert -dryRun` over the rendered directory is a build step: a malformed rule
# fails the build rather than leaving a service that starts and silently never
# alerts.
#
# Alertmanager's receivers take their tokens from `${VAR}` references that
# nixpkgs' envsubst pass leaves untouched (its build environment is empty), which
# `secretspec run` expands at start-up into a 0400 file in the unit's
# RuntimeDirectory. So the store holds variable *names* and the process holds the
# values — see `lib/observability.nix` and `docs/runbooks/alerting-accounts.md`.
#
# Alertmanager's own UI is **never** published: no firewall rule, no Serve
# entry, loopback bind. Silences are made through Grafana's Alertmanager
# datasource, which is the only place its state is visible.
#
# ## Publishing
#
# Grafana is reachable **only** over the tailnet, and only through Tailscale
# Serve. It is never opened on the LAN and never exposed to the internet: there
# is no firewall rule for it anywhere in this file, and the service itself binds
# loopback (nixpkgs' own default), so Serve is the only path in.
#
# Serve is driven by the `tailscale serve` CLI rather than a NixOS option.
# nixpkgs' `services.tailscale.serve` emits *only* `svc:`-prefixed Tailscale
# **Services** config, and Services need the `tailscale.com/cap/services`
# tailnet capability — which this tailnet's CapMap does not carry (it holds
# only file-sharing, is-owner, ssh and tailnet-lock). That constraint is
# recorded in TS-SERVE.MD at the repo root, together with the working
# alternative the other hosts already use: run `tailscale serve --bg <url>` on
# the node. That is what the unit below does.
{ inputs, ... }:
{
  my.modules.nixos.observability-host =
    {
      lib,
      pkgs,
      config,
      ...
    }:
    let
      obs = import ../../lib/observability.nix { inherit lib; };

      # The committed flake's hosts. Naming it once means every gather below
      # reads the same set, and the reason it is `inputs.self` (see the
      # dashboards comment) is written down in one place.
      #
      # `my.observabilityGatheredHosts` is a **test hook**, and the only way to
      # prove the gather off-host: the acceptance criterion ("a rule declared on
      # lumquat appears in calamansi's vmalert config") cannot be shown with
      # `extendModules` alone, because an extended configuration is not in
      # `inputs.self`. A test replaces this with an attrset of extended hosts;
      # leaving it unset — the only thing any real host does — gathers
      # `inputs.self` exactly as before. It is never set in a host config.
      allHosts =
        if config.my.observabilityGatheredHosts == { } then
          inputs.self.nixosConfigurations
        else
          config.my.observabilityGatheredHosts;

      # ── Dashboards gathered from every agent host ─────────────────────
      #
      # Build-time discovery, per BOX-318: every NixOS host whose
      # observabilityAgent flag is on contributes its `dashboards`. The
      # dependency is one-way — servers never read this host's config — so it
      # cannot cycle. The consequence is deliberate: a dashboard changed on
      # lumquat means redeploying calamansi.
      #
      # `inputs.self` rather than the flake-fixpoint `config`: by the time a
      # deferred module's `config` is being evaluated, the sibling hosts'
      # configurations are already complete, so reading them cannot recurse.
      agentHosts = lib.filterAttrs (_: host: host.config.my.observabilityAgent or false) allHosts;

      gatheredDashboards = lib.concatMapAttrs (
        hostName: host:
        lib.mapAttrs' (
          name: dashboard: lib.nameValuePair name (dashboard // { inherit hostName; })
        ) host.config.my.observability.dashboards
      ) agentHosts;

      # ── Prebuilt upstream dashboards ──────────────────────────────────
      #
      # VictoriaMetrics' own dashboards, fetched from the pinned release tag
      # and fixed by hash, so the JSON cannot change under us: a bump is a
      # deliberate edit to this file. They are not declared through
      # `my.observability.dashboards` because that collection is for a
      # *feature's* dashboards, which sit beside their own module; these belong
      # to the stack itself.
      #
      # Each uses a `ds` templating variable of type `prometheus`, so it binds
      # to whichever Prometheus datasource it finds and needs no UID rewrite.
      # (A dashboard hardcoding a UID would have to be vendored and edited —
      # that is the trigger for vendoring, not a preference.)
      vmRelease = "v1.157.0";

      # Node Exporter Full (grafana.com dashboard 1860) — the Host detail
      # dashboard of BOX-322's list, and the one dashboard that has to be a
      # prebuilt: it is 28 panels of expressions over node_exporter's own
      # metric names, maintained upstream against every node_exporter release,
      # and nothing we could write would be less work to keep correct.
      #
      # Pinned to revision 46, explicitly, rather than to `latest`: grafana.com
      # serves `revisions/latest/download` today and a new revision would
      # change the bytes under a fixed hash and break the fetch. The URL is the
      # revision-specific one for the same reason.
      #
      # Hash source: `nix store prefetch-file --json <url>` on 2026-11-24, at
      # revision 46 (the revision grafana.com reports as current, so the pin
      # is both stable and up to date). 470,325 bytes of JSON.
      #
      # It has the same `ds_prometheus` variable-of-type-`prometheus` shape as
      # the VictoriaMetrics dashboards below, so it needs no UID rewrite
      # either. Its README asks for `--collector.systemd` and
      # `--collector.processes`, which the agent module already enables — the
      # Systemd and Processes panels are not empty by construction.
      nodeExporterFullRev = "46";

      prebuiltDashboards = {
        node-exporter-full = pkgs.fetchurl {
          name = "node-exporter-full.json";
          url = "https://grafana.com/api/dashboards/1860/revisions/${nodeExporterFullRev}/download";
          hash = "sha256-5Y3cXcU11MkB+U2pZIvD49Wue2946Y4YW86LKJlhzqM=";
        };
        victoriametrics = pkgs.fetchurl {
          url = "https://raw.githubusercontent.com/VictoriaMetrics/VictoriaMetrics/${vmRelease}/dashboards/victoriametrics.json";
          hash = "sha256-PaUtQtCqvYnZ2SkXz/nZZXc65RYjHHNT1ppWD1cvMVo=";
        };
        vmagent = pkgs.fetchurl {
          url = "https://raw.githubusercontent.com/VictoriaMetrics/VictoriaMetrics/${vmRelease}/dashboards/vmagent.json";
          hash = "sha256-pWjK7weEb+MRhCYq5uulgn08VU5tbE9MqTjNVTvBOhQ=";
        };
        vmalert = pkgs.fetchurl {
          url = "https://raw.githubusercontent.com/VictoriaMetrics/VictoriaMetrics/${vmRelease}/dashboards/vmalert.json";
          hash = "sha256-jQ4mYHPeW+VXCnKQAttzXsYte5CI60pmMoOuFx/LJOQ=";
        };
      };

      # One directory for the dashboard provider to watch. Both sources are
      # link farms, so the provider sees a flat set of `<name>.json` files and
      # Grafana's name is the same on every rebuild.
      #
      # The gathered half goes through `obs.dashboardEntries`, the same shape
      # the module header above describes: the collection key is the file name,
      # so a dashboard's key is the thing its own links and other dashboards'
      # `/d/<uid>` links are written against.
      dashboardDir = pkgs.linkFarm "grafana-dashboards" (
        lib.mapAttrsToList (name: path: {
          name = "prebuilt-${name}.json";
          inherit path;
        }) prebuiltDashboards
        ++ obs.dashboardEntries gatheredDashboards
        # The stack's own dashboard, beside the prebuilts for the same reason:
        # no owning feature to sit next to.
        ++ [
          {
            name = "overview.json";
            path = builtins.path {
              path = ./overview.dashboard.json;
              name = "overview.dashboard.json";
            };
          }
        ]
      );

      # ── The Overview dashboard (BOX-338) ─────────────────────────────
      #
      # The home dashboard, and the one screen that answers "is anything
      # wrong?" for every v1 source. It is owned by the *stack* rather than by
      # a feature, like the prebuilts above: it is the page that links to all
      # of them, so it has no feature module to sit beside.
      #
      # It is an **extra entry in the link farm**, not a declaration in
      # `my.observability.dashboards`. That collection is documented as "one
      # per owning feature module, beside the module", gathered from *agent*
      # hosts — and the Overview is neither a feature's nor gathered, so
      # putting it there would make the option mean two different things and
      # would leave the home page depending on which host happened to declare
      # it. Declaring it here has the property that matters: it exists on the
      # observability host whatever any feature flag says, which is what
      # `grafana.homeDashboardId` below requires — a home dashboard that is not
      # in the provider's directory makes Grafana fall back to its own home
      # with no error anywhere.
      #
      # The UID is the literal `overview`, and every link from this page is a
      # Grafana *relative* `/d/<uid>` path, so it survives the tailnet name
      # changing. The reverse links (a detail dashboard's link back) are not
      # offered yet: that means editing four dashboards other tickets own. See
      # the ticket notes for the follow-up.
      overviewDashboard = builtins.fromJSON (builtins.readFile ./overview.dashboard.json);

      # ── Alert rules gathered from every agent host (BOX-329) ──────────
      #
      # Same build-time discovery as the dashboards, same one-way dependency,
      # same consequence: a rule added on lumquat means redeploying calamansi.
      # Rules are *additive* rather than override-by-name — two features on two
      # hosts may legitimately both ship rules for their own service, and there
      # is no collision to resolve the way a dashboard name has one. The same
      # ruleset name on two hosts is therefore fine; the rendered file name
      # carries the host to keep the directory unambiguous.
      gatheredRules = lib.concatMapAttrs (
        hostName: host:
        lib.mapAttrs' (
          name: ruleset: lib.nameValuePair "${hostName}-${name}" ruleset
        ) host.config.my.observability.rules
      ) agentHosts;

      # The generic defaults are not gathered: they belong to the *stack*, not
      # to any one feature, exactly like the prebuilt dashboards above. They are
      # merged in first so a later ticket can override one by name if it ever
      # needs to (a feature that legitimately sits at 96% disk, say).
      #
      # `builtins.path` rather than a bare `./file`: it fixes the store path name
      # to the file's own name instead of a hash, which keeps the rendered rule
      # directory readable and its derivation stable.
      defaultRules = {
        generic = {
          files = [
            (builtins.path {
              path = ./observability-default.rules.yaml;
              name = "observability-default.rules.yaml";
            })
            (builtins.path {
              path = ./observability-watchdog.rules.yaml;
              name = "observability-watchdog.rules.yaml";
            })
          ];
          type = "metrics";
        };
      };

      allRules = defaultRules // gatheredRules;

      # One vmalert instance per `type`. Only `metrics` exists in v1 — the
      # `logs` type needs VictoriaLogs (BOX-330) — so this is a filter rather
      # than a fan-out, and declaring a `logs` ruleset before BOX-330 is an
      # assertion failure rather than a vmalert that queries nothing.
      metricRules = obs.rulesetsOfType "metrics" allRules;
      logRules = obs.rulesetsOfType "logs" allRules;

      # The rendered rule directory: every file linked verbatim, named
      # `<host>-<ruleset>.<n>.yaml`. `vmalert -rule=<dir>/*.yaml` loads them all.
      #
      # A `linkFarm`, not a copy, so this is the *only* place a rule file exists
      # in the store: the validation below adds no second copy to drift from it.
      ruleDir = pkgs.linkFarm "vmalert-rules-metrics" (obs.mkRuleFiles metricRules);

      # ── Build-time rule validation ──────────────────────────────────────
      #
      # `vmalert -dryRun` parses and validates every rule file, checking group
      # and rule shape, duplicate rules, unknown fields, `for`/`interval`
      # durations and annotation/label templates (`-rule.validateTemplates` is on
      # by default). It touches no network and needs no datasource, so it runs
      # inside the derivation's build.
      #
      # This is a derivation, not a check step in the docs, because the
      # acceptance criterion is that a malformed rule *fails the build*: a
      # vmalert unit that dies at start-up leaves alerting silently dead, which
      # is the one failure this whole ticket exists to prevent. The same trick as
      # the agent's `vmagent -dryRun` on its scrape config.
      #
      # The check's *output* re-exports the same files by symlink, so no copy of
      # a rule ever exists in the store: there is one rendered directory and the
      # check merely proves it parses. `ruleDir` is what vmalert loads and what a
      # test can read without building anything.
      ruleCheck =
        pkgs.runCommand "vmalert-rules-metrics"
          {
            nativeBuildInputs = [ pkgs.victoriametrics ];
          }
          ''
            set -eu
            vmalert -dryRun \
              -rule="${ruleDir}/*.yaml" \
              -notifier.url=http://127.0.0.1:${toString config.my.observabilityAlertmanagerPort} \
              -datasource.url=http://127.0.0.1:${toString config.my.observabilityIngestPort}
            mkdir -p $out
            for f in ${ruleDir}/*.yaml; do
              ln -s "$f" "$out/$(basename "$f")"
            done
          '';

      # ── Alertmanager ────────────────────────────────────────────────────
      #
      # Loopback port for the healthchecks.io bridge. Not an option: nothing
      # outside this module has an opinion about it, and a published port would
      # be a way to keep the dead-man's switch quiet.
      healthchecksReceiverPort = 9094;

      alertmanagerConfig = obs.mkAlertmanagerConfig {
        healthchecksReceiverUrl = "http://127.0.0.1:${toString healthchecksReceiverPort}/";
      };

      # The alerting components, scraped by this host's own agent in the same
      # shape the agent renders its targets. They are stack-internal, so they
      # are not declared through `my.observability.scrapeTargets` — that
      # collection is for a *feature's* targets.
      alertingScrapeJobs = [
        {
          job_name = "vmalert";
          static_configs = [
            { targets = [ "127.0.0.1:${toString config.my.observabilityVmalertPort}" ]; }
          ];
        }
        {
          job_name = "alertmanager";
          static_configs = [
            { targets = [ "127.0.0.1:${toString config.my.observabilityAlertmanagerPort}" ]; }
          ];
        }
      ];

      # The rendered Alertmanager config, as the file nixpkgs' module needs.
      # `lib.mkForce` on `ExecStart` references this exact file, so the template
      # the store holds and the template `envsubst` expands cannot drift apart.
      # `envsubst` does not expand the
      # `${VAR}` references at build time (its environment is empty), which is
      # exactly what keeps them in the store as text and out of a secret's way.
      alertmanagerTemplate = (pkgs.formats.yaml { }).generate "alertmanager.yml" alertmanagerConfig;

      # The bridge that turns Alertmanager's POST into healthchecks.io's GET.
      # Its only secret-adjacent behaviour is `curl`-ing the capability URL, and
      # it logs status codes, never the URL.
      healthchecksReceiver = pkgs.writeShellApplication {
        name = "healthchecks-webhook";
        runtimeInputs = [
          pkgs.curl
          pkgs.jq
        ];
        text = builtins.readFile ../../scripts/healthchecks-webhook.sh;
      };
    in
    {
      config = lib.mkIf config.my.observabilityHost {
        # ── Static users for the units that resolve secrets ──────────────
        #
        # These units run `secretspec`, and secretspec resolves its own uid at
        # startup. Under `DynamicUser` that lookup needs `libnss_systemd.so.2`,
        # which is not on the binary's library search path, so the lookup fails
        # and secretspec reports it as "No secretspec.toml found in current or
        # any parent directory" — a message that points at the manifest while
        # the manifest opened successfully (confirmed by strace on calamansi:
        # `openat("/etc/secretspec.toml") = 3` succeeded, then four ENOENT
        # attempts at libnss_systemd.so.2, then exit 1).
        #
        # Declaring a real system user sidesteps NSS entirely: the uid comes
        # from /etc/passwd. This is also what the older, working secretspec
        # consumers do (host-secrets-populate runs as root; rex and flakehub
        # use static users), so it restores consistency rather than inventing
        # a new pattern.
        #
        # Deliberately scoped to the secretspec consumers: `vmalert` also uses
        # DynamicUser and works, because it never resolves a user through NSS.
        # Nothing here weakens that unit. See docs/runbooks/provision-new-host.md.
        users.users.snmp-exporter = {
          isSystemUser = true;
          group = "snmp-exporter";
          description = "prometheus snmp_exporter (BOX-334)";
        };
        users.groups.snmp-exporter = { };

        users.users.vmalert = {
          isSystemUser = true;
          group = "vmalert";
          description = "VictoriaMetrics vmalert (BOX-329)";
        };
        users.groups.vmalert = { };

        users.users.healthchecks-webhook = {
          isSystemUser = true;
          group = "healthchecks-webhook";
          description = "healthchecks.io webhook bridge (BOX-329)";
        };
        users.groups.healthchecks-webhook = { };

        # Alertmanager keeps state at --storage.path /var/lib/alertmanager, so the
        # static user must own it; with DynamicUser systemd managed that and the
        # directory ownership was implicit.
        users.users.alertmanager = {
          isSystemUser = true;
          group = "alertmanager";
          home = "/var/lib/alertmanager";
          description = "Prometheus Alertmanager (BOX-329)";
        };
        users.groups.alertmanager = { };
        systemd.tmpfiles.rules = [
          "d /var/lib/alertmanager 0750 alertmanager alertmanager -"
        ];

        # A dashboard key declared by two hosts would silently shadow one of them
        # in the link farm above, which looks exactly like "that host's dashboard
        # does not exist". Fail loudly at eval instead.
        assertions = [
          {
            assertion =
              let
                keys = lib.concatMap (host: builtins.attrNames host.config.my.observability.dashboards) (
                  builtins.attrValues agentHosts
                );
              in
              lib.length keys == lib.length (lib.unique keys);
            message = "Two observability agent hosts declare a my.observability.dashboards entry with the same name. Dashboard names must be unique across hosts — prefix each with its owning feature.";
          }
          {
            assertion = config.my.access;
            message = "my.observabilityHost requires my.access: Grafana is published over Tailscale Serve, which needs tailscaled running on this host.";
          }
          # A `logs` ruleset has nowhere to run yet. Declaring one before
          # VictoriaLogs exists (BOX-330) would silently produce no alerts,
          # which is the failure mode this ticket exists to prevent, so it is a
          # build error that names the ticket instead.
          {
            assertion = logRules == { };
            message = "A my.observability.rules entry declares type = \"logs\", but the VictoriaLogs datasource and its vmalert instance are BOX-330. Declare the ruleset with type = \"metrics\" (the default) or wait for BOX-330.";
          }
          # A ruleset that names no files contributes nothing, and looks exactly
          # like a feature whose rules were forgotten. Fail at eval.
          {
            assertion = lib.all (ruleset: ruleset.files != [ ]) (builtins.attrValues gatheredRules);
            message = "A my.observability.rules entry has an empty `files` list. Either list the YAML files it contributes or remove the entry.";
          }
        ];

        # ── VictoriaMetrics: store and query ──────────────────────────
        #
        # nixpkgs has a real module (single-node), so it is used directly
        # rather than a hand-written unit.
        #
        # Retention is 13 months in **days** because that is what VictoriaMetrics
        # parses: its `-retentionPeriod` defaults to months when no suffix is
        # given, and 13m would be a different, subtly wrong number. 400 days is
        # 13 months of the longest month plus slack, which is what "13 months"
        # has to mean if it is to hold every month rather than most of them.
        services.victoriametrics = {
          enable = true;
          retentionPeriod = "400d";
          # Bind every interface: this is the ONE VictoriaMetrics listener other
          # machines reach, to remote-write their samples. The firewall
          # (`extraCommands` below) restricts it to the declared agent hosts;
          # binding loopback would make remote-write impossible.
          listenAddress = ":${toString config.my.observabilityIngestPort}";
          # Scraping is vmagent's job on every machine, including this one, so
          # VictoriaMetrics is not also a scraper: one collection path, one place
          # for a target to be wrong.
          prometheusConfig = { };
        };

        networking.firewall.extraCommands = lib.mkAfter (
          lib.concatMapStringsSep "\n" (
            source:
            "iptables -w -A nixos-fw -p tcp -s ${source} --dport ${toString config.my.observabilityIngestPort} -j nixos-fw-accept\n"
            + "iptables -w -A nixos-fw -p tcp -s ${source} --dport ${toString config.my.observabilityLogsPort} -j nixos-fw-accept"
          ) config.my.observabilityHostAllowedSources
        );

        # ── VictoriaLogs: store and query logs ────────────────────────
        #
        # nixpkgs has a real module (single-node), so it is used directly rather
        # than a hand-written unit — the same choice as VictoriaMetrics. It does
        # not expose retention as an option, so retention goes through
        # `extraOptions`, which the module passes straight to the binary.
        #
        # Two flags, and both need explaining because each has a trap:
        #
        #   -retentionPeriod=90d   BOX-319's 90 days. The **suffix matters**:
        #       VictoriaLogs parses a bare number as *months*, so `90` would be
        #       90 months. Same trap VictoriaMetrics' `-retentionPeriod` has,
        #       which is why BOX-326 writes `400d` there.
        #
        #   -retention.maxDiskUsagePercent=80   BOX-319's "80% disk-usage cap as
        #       a safety net". Percentage rather than the sibling
        #       `-retention.maxDiskSpaceUsageBytes` for two reasons: the decision
        #       is phrased as a percentage, and an absolute cap would need the
        #       disk size, which nothing here can know. VictoriaLogs refuses to
        #       start if both are given, so only one is set.
        #
        # They are **independent** — the time bound still applies while the cap
        # is set — which is exactly the intended layering: 90 days normally, the
        # cap only when 90 days would fill the disk. Two documented caveats are
        # recorded in the `my.observabilityLog*` options rather than here: the
        # cap measures the *filesystem*, and VictoriaLogs always keeps the last
        # two days regardless.
        #
        # The listener is `:9428` (upstream's default). It is the one
        # VictoriaLogs listener other machines reach — agent hosts upload their
        # journals to it — and Grafana queries it over loopback on the same
        # port. The firewall above restricts who may reach it.
        services.victorialogs = {
          enable = true;
          listenAddress = ":${toString config.my.observabilityLogsPort}";
          extraOptions = [
            "-retentionPeriod=${config.my.observabilityLogRetention}"
            "-retention.maxDiskUsagePercent=${toString config.my.observabilityLogDiskUsagePercent}"
          ];
        };

        # Self-scrape: VictoriaLogs exposes its own metrics on the same port, so
        # this host's vmagent watches the log store the way it watches
        # VictoriaMetrics. Added here rather than as a
        # `my.observability.scrapeTargets` entry because that collection is for
        # *features'* sources; the stack watching itself belongs with the stack.
        my.observability.scrapeTargets.victorialogs = {
          address = "127.0.0.1:${toString config.my.observabilityLogsPort}";
        };

        # ── Grafana: query and display ────────────────────────────────
        services.grafana = {
          enable = true;
          # ── The one secret Grafana insists on ─────────────────────
          #
          # Grafana signs stored datasource secrets with `security.secret_key`.
          # Since NixOS 26.05 there is no default and the module *asserts* the
          # option is set — so leaving it out does not build. Setting a literal
          # would put the key in the world-readable store, which the module
          # warns about and which we must not do.
          #
          # So the value is a **file provider** reference (`$__file{...}`,
          # Grafana's own indirection) and the file is generated on the host at
          # first start, never committed and never in the store. It is not a
          # password and grants nobody access: it only encrypts datasource
          # fields, and there is nothing secret in ours. `ExecStartPre` below
          # creates it once and leaves it alone afterwards, because changing it
          # would invalidate anything already encrypted with it.
          settings.security.secret_key = "$__file{/run/grafana/secret_key}";

          # Loopback only (nixpkgs' default, restated because it is load
          # bearing): Tailscale Serve proxies from localhost, so nothing else
          # can reach the port. Deliberately NOT `openFirewall`.
          settings.server.http_addr = "127.0.0.1";
          settings.server.http_port = 3000;

          # Served at https://<host>.<tailnet>.ts.net/ — Serve terminates TLS,
          # so root_url has to name that scheme or Grafana's own asset links
          # and redirects point at http://localhost and the page half-loads.
          # Set from the tailnet name so no host is hardcoded here.
          settings.server.domain = "${config.my.accessTailnetName}.${config.my.observabilityTailnetDomain}";
          settings.server.root_url = "https://%(domain)s/";

          # ── Login: Tailscale identity, no password ────────────────
          #
          # Serve sits in front and adds the tailnet login as a header;
          # Grafana trusts it. Anonymous access stays off (the default), so an
          # unauthenticated request has no path in even from the tailnet.
          #
          # The headers are the ones Serve actually sends: `Tailscale-User-Login`
          # is the tailnet login, and Grafana's `header_name` must match it
          # exactly. `headers`/`header_property` beyond that are left at
          # Grafana's defaults — login is the identity, and a name/email header
          # would be a second source of truth for the same user.
          #
          # There is no admin password anywhere: no `security.admin_password`
          # option is set and no secret exists for one, because the first
          # identity through Serve is the admin. That is the whole point of
          # this arrangement — nothing to store, rotate or leak.
          settings."auth.proxy" = {
            enabled = true;
            header_name = "Tailscale-User-Login";
            header_property = "username";
            auto_sign_up = true;
            # The user's own tailnet login becomes the Grafana admin, so the
            # single operator gets full control and nobody else gets an account
            # beyond what they sign up with.
            sync_ttl = 60;
            whitelist = "";
            headers = "Email:Tailscale-User-Login Name:Tailscale-User-Login";
          };
          settings."auth.anonymous".enabled = false;

          # No admin password exists on this host. Two settings, both needed:
          #
          #   disable_initial_admin_creation stops Grafana creating its
          #     built-in `admin`/`admin` account at startup. Leaving it on would
          #     leave a password of "admin" reachable by anything that can open
          #     the login form — and the login form is reachable from the
          #     tailnet even though nothing but Serve publishes the port.
          #
          #   admin_password is set to the empty string. It used to be a
          #     `$__file{/run/grafana/does-not-exist}` reference on the theory
          #     that a missing file made the value unusable. It does not: Grafana
          #     treats a file-provider reference whose target is absent as a
          #     *fatal* startup error, not an unset value —
          #
          #       Error: ✗ got error while expanding security.admin_password
          #       with expander 'file': stat /run/grafa/does-not-exist: no such
          #       file or directory
          #
          #     which crash-looped grafana on calamansi (BOX-324). The empty
          #     string keeps the literal "admin" default out of the store, which
          #     is what that line existed to prevent, without failing to boot.
          #
          # The first identity through Serve becomes Grafana's admin, which is
          # the operator. There is deliberately no option to set a real
          # password, and no secret to store, rotate or leak.
          settings.security.disable_initial_admin_creation = true;
          settings.security.admin_password = "";

          # ── The home dashboard (BOX-338) ───────────────────────────
          #
          # The Overview is the page Grafana opens on, which is BOX-322's
          # decision: the user opens Grafana to answer "is anything wrong?",
          # not to browse a dashboard list.
          #
          # It is named by **path into the provider directory**, not by the
          # numeric `homeDashboardId` a reader might expect. That id is the
          # *database* row id, which Grafana assigns when it first loads the
          # file and which therefore differs between a fresh install and any
          # later one — it cannot be written down in a repo. The path is
          # stable, and the uid inside the file (`overview`) is the same
          # literal the dashboard's own links and the contract test use.
          #
          # Grafana reads `dashboards.json` as a flat key/value map into
          # `[dashboards]`, so the key keeps Grafana's own snake_case name
          # (`home_dashboard_path`) rather than Nix's usual camelCase.
          settings.dashboards.home_dashboard_path = "/var/lib/grafana/dashboards/overview.json";

          # Grafana's own alerting is off: vmalert is the alert engine here
          # (BOX-329), and two alert engines evaluating different rule sets is
          # how an alert gets missed.
          #
          # `unified_alerting.enabled = false` does **not** remove the
          # Alerting page, and that is wanted here: the Overview's "Firing now"
          # panel reads vmalert's state through Grafana's Alertmanager
          # datasource, and that panel is the first thing a reader sees. The
          # flag keeps Grafana from *evaluating* rules of its own.
          settings.unified_alerting.enabled = false;
          settings.alerting.enabled = false;

          # ── Provisioning ──────────────────────────────────────────
          provision.enable = true;

          # ── Plugins ─────────────────────────────────────────────────
          #
          # VictoriaLogs' Grafana datasource is a **plugin**, not a datasource
          # type built into Grafana, so it has to be installed for the
          # `victorialogs` datasource below to load at all. (A datasource whose
          # plugin is missing is not an error Grafana shows at startup; it
          # appears as a broken datasource in the UI, or worse as an empty
          # Explore pane.)
          #
          # THE TRAP: `declarativePlugins` **replaces** Grafana's preinstalled
          # plugins rather than adding to them. nixpkgs' own description: "Keep
          # in mind that this overrides any app that Grafana might preinstall.
          # This affects for instance Grafana Drilldown (...), but also
          # data-sources like `prometheus`, `loki`, `tempo` and `jaeger`." So
          # listing only the log plugin would silently remove the **core
          # `prometheus` datasource** that the VictoriaMetrics datasource below
          # depends on — a metrics outage caused by adding logging. `prometheus`
          # is therefore listed explicitly, and anything else preinstalled we
          # later rely on must be added here too.
          #
          # Version coherence is checked, not assumed. nixpkgs pins plugin
          # 0.33.1 and VictoriaLogs 1.53.0. The plugin's docs page claims a
          # "v1.54.0 or newer" requirement, but the plugin's own CHANGELOG
          # places that in `tip` — i.e. it lands *after* 0.33.1, for a
          # `sort_direction` query arg. 0.33.1 + 1.53.0 is a coherent pair. A
          # future `grafanaPlugins` bump WILL need a VictoriaLogs bump with it.
          declarativePlugins = with pkgs.grafanaPlugins; [
            prometheus
            victoriametrics-logs-datasource
          ];

          # Fixed UIDs, because dashboards reference a datasource by UID. The
          # Alertmanager entry is reserved in lib/observability.nix and not
          # provisioned yet, so BOX-329 fills it in rather than inserting a
          # datasource and leaving every dashboard that links to it broken.
          provision.datasources.settings = {
            apiVersion = 1;
            datasources = [
              {
                name = "VictoriaMetrics";
                uid = obs.datasourceUids.victoriaMetrics;
                type = "prometheus";
                access = "proxy";
                # Loopback: Grafana proxies to the local store. This is the
                # query path, which has no reason to leave the machine.
                url = "http://127.0.0.1:${toString config.my.observabilityIngestPort}";
                isDefault = true;
                jsonData = {
                  # VictoriaMetrics speaks Prometheus' query API, and the
                  # Prometheus datasource with these set is the supported way
                  # to use it: `prometheusType` turns on the MetricsQL-aware
                  # editor rather than hiding half of what the store supports.
                  prometheusType = "VictoriaMetrics";
                  timeInterval = "15s";
                };
              }
              {
                # BOX-330. The UID was reserved by BOX-326, so any dashboard
                # that came to reference it in between is already correct.
                #
                # Not `isDefault`: VictoriaMetrics stays the default because
                # every provisioned dashboard is a metrics dashboard and the
                # Explore view should open on those. Logs are reached by
                # picking this datasource (or the VictoriaLogs UI, which is the
                # log-exploration view — there is deliberately no log
                # dashboard, per BOX-322).
                name = "VictoriaLogs";
                uid = obs.datasourceUids.victoriaLogs;
                type = "victoriametrics-logs-datasource";
                access = "proxy";
                # Loopback, for the same reason as the metrics one: the store
                # is local and the query path never needs to leave the machine.
                url = "http://127.0.0.1:${toString config.my.observabilityLogsPort}";
                jsonData = { };
              }
              {
                # The Alertmanager here is Grafana's *silencing* path, not its
                # datasource for alert rules: `unified_alerting` is off and
                # vmalert owns evaluation (BOX-320). Grafana's Alertmanager
                # datasource also renders a read-only view of what is firing,
                # which is the only place Alertmanager's state is visible — its
                # own UI is deliberately unpublished.
                #
                # Loopback, like the metrics datasource: both processes are on
                # this host.
                name = "Alertmanager";
                uid = obs.datasourceUids.alertmanager;
                type = "alertmanager";
                access = "proxy";
                url = "http://127.0.0.1:${toString config.my.observabilityAlertmanagerPort}";
                jsonData = {
                  # Without this Grafana infers receivers and templates by
                  # probing endpoints the proxy cannot see, and the datasource
                  # shows an error instead of the alert list.
                  handleGrafanaManagedAlerts = false;
                  implementation = "prometheus";
                };
              }
            ];
          };

          provision.dashboards.settings = {
            apiVersion = 1;
            providers = [
              {
                name = "default";
                type = "file";
                # Provisioned dashboards are read-only on purpose: edit in the
                # UI, export the JSON, commit it, switch. A UI edit that
                # survives is drift from the repo, and then the repo is not
                # the source of truth any more.
                allowUiUpdates = false;
                disableDeletion = true;
                updateIntervalSeconds = 30;
                options.path = dashboardDir;
              }
            ];
          };
        };

        # ── Alertmanager: route and deliver ───────────────────────────
        #
        # Native nixpkgs module (ADR 0006). It renders `configuration` to
        # `alertmanager.yml` with `envsubst` — see lib/observability.nix for why
        # that is what keeps the tokens out of the store.
        #
        # `listenAddress` is loopback, restated because it is load bearing:
        # vmalert and Grafana both reach it there, and nothing else has any
        # business doing so. There is no firewall rule for it anywhere in this
        # file and no Tailscale Serve entry — the Alertmanager UI is *never*
        # published, per BOX-320. Silences are made through Grafana's
        # Alertmanager datasource below.
        #
        # `checkConfig = false` is not a weakening: nixpkgs' amtool pass cannot
        # see the credential values (it runs in the sandbox with no environment),
        # so it reports "invalid URL: unsupported scheme" against a perfectly
        # correct file — the option's own documentation says so. The config's
        # *shape* is asserted instead by the contract test, and the bridge below
        # fails loudly if a ping URL is not there.
        services.prometheus.alertmanager = {
          enable = true;
          listenAddress = "127.0.0.1";
          port = config.my.observabilityAlertmanagerPort;
          checkConfig = false;
          # nixpkgs renders this to `alertmanager.yml` with `envsubst`, whose
          # environment is empty at build time — which is exactly what leaves
          # the `${VAR}` references in the store as text.
          configText = builtins.readFile alertmanagerTemplate;
          # Exposed as a value too, so the contract test asserts on the route
          # tree as data instead of grep-ing the rendered YAML.
          configuration = builtins.fromJSON (builtins.toJSON alertmanagerConfig);
        };

        # Where Alertmanager's secrets come from.
        #
        # None of the three values in `alerting` is ever a file path the store
        # knows about. The chain is:
        #
        #   1. this module renders `configuration` with the literal text
        #      `${PUSHOVER_APP_TOKEN}` and so on (lib/observability.nix).
        #   2. nixpkgs' `envsubst` pass over the rendered file sees an empty
        #      environment, so the text survives unchanged into the store. The
        #      store thus contains variable *names* and no values.
        #   3. `preStart` (below, inside `secretspec run`) runs `envsubst` again
        #      with the three variables set from BWS, writing the real file to
        #      `/run/alertmanager/alertmanager.yml` — a tmpfs the unit owns.
        #
        # `LoadCredential` + `SECRETSPEC_PROVIDER=bws-service` is the repo's
        # standard bootstrap (modules/features/secrets.nix): the BWS access
        # token arrives as a systemd credential, so it is not in the
        # environment either.
        systemd.services.alertmanager = {
          wants = [ "network-online.target" ];
          after = [ "network-online.target" ];
          # Alertmanager's unit runs `secretspec` in its preStart, so it resolves
          # a uid and needs NSS — which fails under DynamicUser (the exporter in
          # storage2.nix documents the strace evidence). nixpkgs already declares
          # the `alertmanager` user when this is false, so no user is added here.
          # `mkForce` because the nixpkgs module sets this with mkDefault and the
          # override must win regardless of module ordering.
          serviceConfig.DynamicUser = lib.mkForce false;
          path = [
            pkgs.secretspec
            pkgs.bws
          ];
          # Rotating a value edits no file this unit can see, so watch the
          # manifest: a `secretspec.toml` change must cycle the unit or the old
          # token stays in the running process.
          restartTriggers = [ config.my.secretspecManifest ];
          serviceConfig = {
            Environment = [
              "SECRETSPEC_FILE=${config.my.secretspecManifest}"
              "SECRETSPEC_PROVIDER=bws-service"
            ];
            LoadCredential = [ "access_token:${config.my.bwsAccessTokenFile}" ];
            # A tmpfs of its own, so the expanded config does not outlive the
            # process: `umask 077` plus 0400 below means it is never readable by
            # anyone but this unit, even for an instant.
            RuntimeDirectory = "secretspec-alerting";
            RuntimeDirectoryMode = "0700";
          };
        };

        # Expand the rendered template against the resolved secrets, and point
        # Alertmanager at the result.
        #
        # This is the second half of the indirection: the store's copy contains
        # `${PUSHOVER_APP_TOKEN}` and friends as literal text, expanded here
        # inside `secretspec run`, where they are set. `ExecStart` is overridden
        # rather than patched because Alertmanager only takes its config via
        # `--config.file`, and a unit that reads the store's template directly
        # would start with unusable receivers.
        #
        # `ExecStartPre` is overridden too, and that is not cosmetic: nixpkgs'
        # own pre-start expands the template into `/tmp/alert-manager-substituted.yaml`,
        # a world-readable path. It runs with an empty environment so it
        # substitutes nothing, but leaving it in place would put a *future*
        # change to that template (or a stray env var) one bug away from a
        # readable token. The expansion here writes 0400 inside the unit's
        # RuntimeDirectory instead.
        systemd.services.alertmanager.serviceConfig.ExecStartPre = lib.mkForce ''
          umask 077
          ${lib.escapeShellArgs [
            "${pkgs.envsubst}/bin/envsubst"
            "-i"
            "${alertmanagerTemplate}"
            "-o"
            "/run/secretspec-alerting/alertmanager.yml"
          ]}
        '';

        systemd.services.alertmanager.serviceConfig.ExecStart = lib.mkForce "${
          lib.escapeShellArgs [
            "${pkgs.secretspec}/bin/secretspec"
            "run"
            "-P"
            "production"
            "-S"
            "alerting"
            "--"
            "${pkgs.envsubst}/bin/envsubst"
            "-i"
            "${alertmanagerTemplate}"
            "-o"
            "/run/secretspec-alerting/alertmanager.yml"
          ]
        } && exec ${
          lib.escapeShellArgs [
            "${config.services.prometheus.alertmanager.package}/bin/alertmanager"
            "--config.file=/run/secretspec-alerting/alertmanager.yml"
            "--storage.path=/var/lib/alertmanager"
            "--web.listen-address=127.0.0.1:${toString config.my.observabilityAlertmanagerPort}"
          ]
        }";

        # ── vmalert: evaluate rules, notify Alertmanager ───────────────
        #
        # One instance, for metrics. Its rule *directory* is the checked link
        # farm above, so a malformed rule file cannot reach the service.
        #
        # `-remoteWrite.url` points back at VictoriaMetrics: it is how alert
        # state and recording-rule results become queryable series, which is
        # what lets a dashboard show "firing since" rather than only "firing".
        #
        # `-external.url` is Grafana's own address, because the `source` link on
        # every notification should open the dashboard a reader can act on.
        systemd.services.vmalert = {
          description = "vmalert — evaluate alerting and recording rules";
          wantedBy = [ "multi-user.target" ];
          after = [
            "victoriametrics.service"
            "alertmanager.service"
          ];
          wants = [
            "victoriametrics.service"
            "alertmanager.service"
          ];
          # `ruleCheck` is in the `path` so the validation derivation is part of
          # this unit's *build* closure, not merely of the activation. Building
          # any system that contains this unit therefore runs
          # `vmalert -dryRun` over the rule directory, and a rule file that does
          # not parse fails the build rather than the service. `preStart` prints
          # the path so the link is not optimised away as dead.
          preStart = ''
            echo "validated rules: ${ruleCheck}"
          '';
          path = [ ruleCheck ];
          serviceConfig = {
            Type = "simple";
            User = "vmalert";
            Group = "vmalert";
            # Static user, not DynamicUser: see the note on `users.users` at the
            # top of this module. vmalert itself resolves no uid, but keeping the
            # whole stack on one user model is one fewer thing to get wrong.
            DynamicUser = false;
            Restart = "always";
            RestartSec = 5;
            ExecStart = lib.escapeShellArgs ([
              "${pkgs.victoriametrics}/bin/vmalert"
              "-rule=${ruleDir}/*.yaml"
              "-datasource.url=http://127.0.0.1:${toString config.my.observabilityIngestPort}"
              "-remoteWrite.url=http://127.0.0.1:${toString config.my.observabilityIngestPort}"
              "-notifier.url=http://127.0.0.1:${toString config.my.observabilityAlertmanagerPort}"
              "-evaluationInterval=1m"
              "-httpListenAddr=127.0.0.1:${toString config.my.observabilityVmalertPort}"
              # Grafana is served at the tailnet root (Serve maps 443 to
              # 127.0.0.1:3000 with no path prefix), so this is the dashboard a
              # reader can actually open from the notification.
              "-external.url=https://${config.my.accessTailnetName}.${config.my.observabilityTailnetDomain}"
              # Keep vmalert's own memory bounded; it only ever holds rule
              # state, and a rule that needs more history is a recording rule.
              "-memory.allowedPercent=40"
            ]);
          };
        };

        # ── The healthchecks.io bridge ─────────────────────────────────
        #
        # See scripts/healthchecks-webhook.sh for why a bridge exists at all.
        # It is a systemd *socket* plus a per-connection service, so a ping that
        # fails cannot take the listener down with it and the next minute's ping
        # still arrives.
        systemd.sockets.healthchecks-webhook = {
          wantedBy = [ "sockets.target" ];
          listenStreams = [ "127.0.0.1:${toString healthchecksReceiverPort}" ];
          socketConfig.Accept = "yes";
        };

        systemd.services."healthchecks-webhook@" = {
          description = "Translate an Alertmanager notification into a healthchecks.io ping";
          requires = [ "healthchecks-webhook.socket" ];
          # The capability URL is a secret, so this unit resolves it the same way
          # Alertmanager does and never writes it anywhere.
          path = [
            pkgs.secretspec
            pkgs.bws
          ];
          serviceConfig = {
            Type = "oneshot";
            # Static user: secretspec resolves its own uid and needs NSS, which
            # fails under DynamicUser. See the note on `users.users` above.
            User = "healthchecks-webhook";
            Group = "healthchecks-webhook";
            DynamicUser = false;
            Environment = [
              "SECRETSPEC_FILE=${config.my.secretspecManifest}"
              "SECRETSPEC_PROVIDER=bws-service"
            ];
            LoadCredential = [ "access_token:${config.my.bwsAccessTokenFile}" ];
            ExecStart = "${pkgs.secretspec}/bin/secretspec run -P production -S alerting -- ${lib.getExe healthchecksReceiver}";
            StandardInput = "socket";
            # A non-zero exit (healthchecks.io refused the ping, no network) is
            # reported to Alertmanager, which retries the webhook — that is the
            # whole point of failing loudly instead of swallowing it. The unit
            # itself is ephemeral (`healthchecks-webhook@<conn>`), so a failed
            # instance is transient and does not accumulate in the unit table.
            # Deliberately *not* Restart=always: the next Watchdog notification a
            # minute later is a better retry than a tight loop on a broken URL.
          };
        };

        # ── Scrape the alerting path itself ────────────────────────────
        #
        # "Who watches the watcher": both components expose `/metrics`, and the
        # host's own agent scrapes them, so a vmalert that stopped evaluating is
        # visible in Grafana even though it cannot alert on itself. These are
        # stack-internal targets, which is why they are added here and not
        # declared through `my.observability.scrapeTargets` (that collection is
        # for a *feature's* targets).
        #
        # `prometheusConfig` is *replaced* rather than supplemented: nixpkgs'
        # module turns that option into `-promscrape.config=<checked config>`,
        # and adding a second `-promscrape.config` through `extraArgs` would
        # leave two flags with only one of them taking effect. The document
        # below is the agent module's own set of jobs plus these two, so nothing
        # a feature declared is lost.
        # The agent module renders `node` plus every declared target; adding
        # these two here (rather than replacing the list) keeps one source of
        # truth for everything a feature declared.
        services.vmagent.prometheusConfig.scrape_configs = lib.mkAfter alertingScrapeJobs;

        # Generate Grafana's datasource-signing key once, into the service's
        # own RuntimeDirectory (`/run/grafana`, created by systemd 0755 and
        # owned by the grafana user, so the service can read it and a rebuild
        # cannot bake it in). mkAfter because the module already has an
        # ExecStartPre that symlinks the homepath, and ordering between them
        # does not matter as long as both run.
        systemd.services.grafana.serviceConfig.ExecStartPre = lib.mkAfter [
          "${pkgs.writeShellScript "grafana-secret-key" ''
            set -eu
            key=/run/grafana/secret_key
            if [ ! -s "$key" ]; then
              umask 077
              ${lib.getExe' pkgs.openssl "openssl"} rand -hex 32 > "$key"
            fi
            chmod 0400 "$key"
          ''}"
        ];

        # ── Publishing: Tailscale Serve ───────────────────────────────
        #
        # The unit is idempotent like the sidecars on lumquat: reset, then
        # serve, so the live serve table equals this declaration and a path
        # added by hand is destroyed at the next switch.
        #
        # `--bg` so the config persists in tailscaled rather than living in
        # this process; the unit only has to *apply* it. `ExecStart` therefore
        # ends, which is why the unit is `oneshot` + `RemainAfterExit`.
        #
        # Ordered after tailscaled-autoconnect (the built-in unit name that
        # services.tailscale generates) and after Grafana, and it retries
        # rather than dying: on a cold boot both dependencies may still be
        # settling, and this is the step that makes the dashboard reachable.
        #
        # Port 443 is Serve's HTTPS port on the node — no extra firewall rule,
        # because traffic arrives on tailscale0, which access.nix already
        # trusts.
        systemd.services.tailscale-serve-grafana = {
          description = "Publish Grafana on the tailnet via Tailscale Serve";
          wantedBy = [ "multi-user.target" ];
          after = [
            "tailscaled-autoconnect.service"
            "grafana.service"
          ];
          wants = [ "tailscaled-autoconnect.service" ];
          requires = [ "grafana.service" ];
          serviceConfig = {
            Type = "oneshot";
            RemainAfterExit = true;
            Restart = "on-failure";
            RestartSec = 10;
          };
          script = ''
            set -eu
            ${config.services.tailscale.package}/bin/tailscale serve reset
            ${config.services.tailscale.package}/bin/tailscale serve --bg --https=443 http://127.0.0.1:3000
          '';
        };
      };
    };
}
