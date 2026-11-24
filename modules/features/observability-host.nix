# Observability host — the one machine that stores, queries, alerts on and
# displays every server's logs and metrics. See CONTEXT.md's Observability
# section for the vocabulary and docs/adr/0006 for why every service here is
# native rather than a container.
#
# v1 of this module is metrics, logs and dashboards: VictoriaMetrics,
# VictoriaLogs and Grafana. vmalert + Alertmanager (BOX-329) and the archive
# jobs (BOX-336/337) land in this module too — same flag, same machine, one
# host. They are absent here because they are not this ticket, not because the
# shape does not allow them.
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
      agentHosts = lib.filterAttrs (
        _: host: host.config.my.observabilityAgent or false
      ) inputs.self.nixosConfigurations;

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

      prebuiltDashboards = {
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
      dashboardDir = pkgs.linkFarm "grafana-dashboards" (
        lib.mapAttrsToList (name: path: {
          name = "prebuilt-${name}.json";
          inherit path;
        }) prebuiltDashboards
        ++ lib.mapAttrsToList (name: dashboard: {
          name = "${name}.json";
          path = dashboard.path;
        }) gatheredDashboards
      );
    in
    {
      config = lib.mkIf config.my.observabilityHost {
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
          #   admin_password is set to a file-provider reference anyway,
          #     because the alternative is nixpkgs' literal "admin" default
          #     written into the world-readable store. The file does not exist,
          #     so the value is unusable rather than merely unadvertised: the
          #     account is the one created by the first Tailscale identity.
          #
          # The first identity through Serve becomes Grafana's admin, which is
          # the operator. There is deliberately no option to set a real
          # password, and no secret to store, rotate or leak.
          settings.security.disable_initial_admin_creation = true;
          settings.security.admin_password = "$__file{/run/grafana/does-not-exist}";

          # Grafana's own alerting is off: vmalert is the alert engine here
          # (BOX-329), and two alert engines evaluating different rule sets is
          # how an alert gets missed.
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
