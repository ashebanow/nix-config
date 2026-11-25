# Observability agent — the collector set for one machine.
#
# Per CONTEXT.md an agent is "the set of collector processes on a machine that
# gathers its logs and metrics and ships them to the observability host. There
# is one per machine, shared by every service on it; a service never brings its
# own." So this module is the only place a collector is defined; feature modules
# contribute *sources* through `my.observability` and never a collector of their
# own.
#
# Native services, not containers: docs/adr/0006.
#
# v1 of this module is metrics and logs, plus the podman container exporter
# (BOX-331) — same flag, same machine, one agent.
#
# ## Log shipping: why `systemd-journal-upload` and nothing in between
#
# The whole local journal — every unit's, and every podman container's, because
# podman's default log driver is `journald` — is shipped to VictoriaLogs by
# `systemd-journal-upload`. VictoriaLogs has a native systemd-journal ingest
# endpoint (`/insert/journald`) that accepts the journal's own binary encoding
# (`application/vnd.fdo.journal`), which is exactly what this uploader emits. So
# there is **no bridge, no parser and no sidecar**: no `journalctl -o json`
# shipper, no `vector`, no `promtail`. That is the least-maintenance option,
# which is this project's first criterion, and it is why the plan's
# "systemd-journal-upload to VictoriaLogs' journald endpoint" was checked rather
# than replaced — it is correct.
#
# The alternatives were considered and rejected:
#   journalctl -o json + a cursor shipper   a second daemon to write, package,
#                                           alert on and debug, to re-speak a
#                                           protocol VictoriaLogs already speaks
#   vector / promtail / fluent-bit          a whole extra agent runtime and
#                                           config language beside
#                                           node_exporter + vmagent, reversing
#                                           BOX-317's one-collector decision
#                                           (and promtail is EOL upstream)
#   vlagent                                 a disk-buffered *push* agent for
#                                           files and syslog, not the journal:
#                                           it would add a hop, not remove one.
#                                           (It is the right answer for
#                                           BOX-335's CEF syslog, which has no
#                                           journal to read.)
#   systemd-journal-remote                  receives; it does not forward to
#                                           VictoriaLogs. Wrong direction.
#
# What matters going forward is the two properties this arrangement gives us
# for free, because a future ticket must not accidentally lose them:
#
#   - AC4 ("logs written while the host was down arrive after it returns").
#     `systemd-journal-upload` uploads from a cursor and systemd's own unit
#     passes `--save-state`, so the cursor is persisted to
#     /var/lib/systemd/journal-upload/state after each successfully uploaded
#     entry and the upload resumes there on reconnect. Entries that piled up
#     while the observability host was unreachable are therefore delivered when
#     it comes back. The bound on that catch-up is **local** journal retention,
#     not VictoriaLogs — a long outage on a small disk can outrun the local
#     journal. Do not set `NetworkTimeoutSec`: unset, the uploader waits out an
#     outage instead of exiting, which is what a home server rebooting needs.
#
#   - BOX-318's "logs need no declaration". Shipping the whole journal means a
#     new service is indexed by existing, with no change to this module and no
#     `my.observability` entry. That is why this module has no per-unit option
#     and no allowlist — an allowlist is the thing that would make a new service
#     silently unmonitored.
#
# NOT covered here: the UniFi gateway and storage2, which send CEF syslog over
# the network rather than writing to any journal (BOX-335).
_: {
  my.modules.nixos.observability-agent =
    {
      lib,
      pkgs,
      config,
      ...
    }:
    let
      obs = import ../../lib/observability.nix { inherit lib; };

      # Everything the agent scrapes, as the Prometheus document vmagent
      # consumes. Three sources, in the order they matter:
      #
      #   node_exporter       the host itself (CPU, memory, disk, hwmon, drm)
      #   podman exporter     the containers (BOX-331), when there are any
      #   my.observability    whatever a feature module declared
      #
      # Built as one list rather than three so a scrape-config collision is
      # impossible by construction: `renderScrapeConfigs` keys by name, and
      # "node" and "podman" are reserved here.
      scrapeConfig = {
        scrape_configs = [
          {
            job_name = "node";
            static_configs = [
              { targets = [ "127.0.0.1:${toString config.services.prometheus.exporters.node.port}" ]; }
            ];
          }
        ]
        ++ lib.optional config.my.observabilityContainerMetrics {
          job_name = "podman";
          static_configs = [
            { targets = [ "127.0.0.1:${toString config.my.observabilityPodmanExporterPort}" ]; }
          ];
        }
        ++ obs.renderScrapeConfigs config.my.observability.scrapeTargets;
      };
    in
    {
      config = lib.mkIf config.my.observabilityAgent {
        # ── Host metrics ────────────────────────────────────────────────
        #
        # node_exporter binds loopback: only this machine's vmagent scrapes it,
        # and a metrics endpoint on the LAN is an information leak with no
        # upside. `openFirewall` stays off for the same reason.
        #
        # Collectors: the defaults are the right baseline (cpu, meminfo,
        # filesystem, netdev, loadavg, ...). Added here are the three that
        # matter for a headless server and are not on by default —
        #   systemd   unit states, so a failed unit is visible as a metric
        #   processes per-unit counts rather than none
        #   hwmon     temperatures and fans, which is how "hot hardware"
        #             becomes alertable
        # `drm` is per-host rather than universal: `my.observabilityGpuMetrics`
        # (lib/my-options-module.nix) is set by a host that has a GPU whose
        # telemetry node_exporter reads. Enabling it everywhere is meaningless
        # on a host without a GPU and costs a futile sysfs scan per scrape.
        services.prometheus.exporters.node = {
          enable = true;
          listenAddress = "127.0.0.1";
          enabledCollectors = [
            "systemd"
            "processes"
            "hwmon"
          ]
          ++ lib.optional config.my.observabilityGpuMetrics "drm";
          # textfile: the directory BOX-332's checks write `<name>.prom` into.
          # Enabled with the directory created and empty, so the collector is
          # not switched on later as a second change to the same unit.
          extraFlags = [
            "--collector.textfile.directory=/var/lib/node_exporter/textfile"
          ];
        };

        systemd.tmpfiles.rules = [
          "d /var/lib/node_exporter/textfile 0755 root root -"
        ];

        # A GPU host needs no extra device access for this: the drm and hwmon
        # collectors read `/sys/class/drm` and `/sys/class/hwmon`, which are
        # world-readable, so the exporter keeps its default hardening
        # (`DeviceAllow = [ "" ]`, `PrivateDevices = true`). Nothing here opens
        # `/dev/dri/cardN`; that would only be needed to talk to the GPU, which
        # a metrics scrape never does. See docs/lumquat-hardware.md for which
        # metrics the Strix Halo APU actually populates.

        # ── Container metrics (BOX-331) ─────────────────────────────────
        #
        # prometheus-podman-exporter speaks podman's own REST API, so what it
        # reports is labelled with the container names and pods this host
        # already thinks in, and it needs no cgroup or /sys/fs/cgroup access.
        # (`cadvisor` was the fallback and was not needed: our nixpkgs lacks the
        # exporter, so BOX-331 packages it in
        # lib/overlays/prometheus-podman-exporter.nix.)
        #
        # ## Why it runs as the podman user, not root, and why that is the hard part
        #
        # lumquat's containers are **rootless**: `my.baseUsername` owns them and
        # the API socket is that user's
        # `/run/user/<uid>/podman/podman.sock`. So the exporter must run as that
        # user — a root exporter would see an empty container list and report
        # nothing, which looks identical to "no containers are running". Two
        # things follow:
        #
        #   * `CONTAINER_HOST` points at the user socket by explicit absolute
        #     path when the podman API service unit is present, so the exporter
        #     never has to guess the socket location from $XDG_RUNTIME_DIR.
        #     `podman.socket` (system) and `podman-user-api.socket` are both
        #     candidates; the user one is what rootless podman creates.
        #   * `XDG_RUNTIME_DIR` is set explicitly for the same reason — a system
        #     unit does not get one, and podman's Go client uses it as a
        #     fallback when CONTAINER_HOST is unset.
        #
        # The user must exist in the podman group's runtime dir *before* the
        # user's session starts, so this unit binds after `podman.socket` and
        # `linger-users` (which is what makes `/run/user/<uid>` exist for a user
        # who is not logged in — the same ordering `podman-network-llm-internal`
        # relies on in modules/features/llm.nix).
        #
        # ## Binding
        #
        # Loopback only, on `my.observabilityPodmanExporterPort`. Same argument
        # as node_exporter: a metrics endpoint on the LAN leaks which containers
        # exist on the machine for no benefit. `openFirewall` is deliberately not
        # used — there is no nixpkgs module here, so there is no firewall to
        # toggle; the bind address is the control.
        #
        # ## Collectors
        #
        # `--collector.enable-all` turns on container, pod, image, volume, network
        # and system. That is more than v1's dashboards use (containers and pods),
        # but the extras are cheap API reads against the same socket and they are
        # what makes "is the model image still on disk" answerable later without
        # another rebuild. `--collector.enhance-metrics` is NOT set: it puts every
        # container label into every metric's label set, which multiplies series
        # with no v1 consumer.
        #
        # `--collector.container-stats-timeout` is raised from upstream's 2 s: a
        # rootless podman `stats` call for a container holding a 31 GB model can
        # exceed 2 s under load, and a timed-out stats read makes the whole
        # scrape fail rather than return stale numbers.
        systemd.services.prometheus-podman-exporter = lib.mkIf config.my.observabilityContainerMetrics {
          description = "Prometheus exporter for podman containers";
          after = [
            "network-online.target"
            "podman.socket"
            "linger-users.service"
          ];
          wants = [ "network-online.target" ];
          wantedBy = [ "multi-user.target" ];
          # The runtime bump argument from llm.nix's container units applies
          # here too: the exporter was started against the old podman's API
          # socket, and after a bump the new podman serves a different one.
          restartTriggers = [ config.virtualisation.podman.package ];
          serviceConfig = {
            User = config.my.baseUsername;
            Group = config.my.baseUsername;
            # A system unit running as a user has no $HOME or $XDG_RUNTIME_DIR.
            # podman's client needs both to find the rootless socket.
            Environment = [
              "HOME=/home/${config.my.baseUsername}"
              "XDG_RUNTIME_DIR=/run/user/%U"
              "CONTAINER_HOST=unix:/run/user/%U/podman/podman.sock"
            ];
            ExecStart = lib.concatStringsSep " " [
              "${pkgs.prometheus-podman-exporter}/bin/prometheus-podman-exporter"
              "--web.listen-address=127.0.0.1:${toString config.my.observabilityPodmanExporterPort}"
              "--collector.enable-all"
              "--collector.container-stats-timeout=10s"
            ];
            Restart = "always";
            RestartSec = "10s";
          };
        };

        # ── Shipping ────────────────────────────────────────────────────
        #
        # vmagent, not a second VictoriaMetrics: the split is scrape-here,
        # store-there, and on the observability host "there" happens to be
        # localhost. Keeping one binary per role means an agent host never
        # carries a time-series database it does not use.
        #
        # Disk buffering is the point of vmagent rather than a nice-to-have:
        # nixpkgs' module always passes `-remoteWrite.tmpDataPath` when a
        # remote-write URL is set, so samples survive a vmagent restart, a
        # calamansi reboot, or a network outage, and are delivered when the
        # path comes back. `checkConfig` runs `vmagent -dryRun` over the
        # rendered scrape config at build time, so a malformed target fails the
        # build rather than the host.
        services.vmagent = {
          enable = true;
          remoteWrite.url = "http://${config.my.observabilityHostAddress}:${toString config.my.observabilityIngestPort}/api/v1/write";
          prometheusConfig = scrapeConfig;
        };

        # vmagent's own metrics are the "who watches the watcher" layer: the
        # host's VictoriaMetrics scrapes this port, so a silent vmagent is
        # visible. Loopback, like everything else on an agent host.
        services.vmagent.extraArgs = [
          "-httpListenAddr=127.0.0.1:8429"
        ];

        # ── Logs ────────────────────────────────────────────────────────
        #
        # The whole journal, to the observability host's VictoriaLogs. See this
        # file's header for why `systemd-journal-upload` alone is the right
        # answer and what its two free properties are (offline catch-up, and no
        # per-service declaration).
        #
        # `services.journald.upload` is a real nixpkgs module, so the unit is
        # systemd's own `systemd-journal-upload.service` with nixpkgs'
        # `Restart = "always"` (upstream says `on-failure`) and a native
        # `journal-upload.conf` generated from `settings`. Nothing is
        # hand-written here, which is the point: the collector needs the
        # `systemd-journal` group to read the journal, and the upstream unit
        # already declares `SupplementaryGroups=systemd-journal` — so there is no
        # group membership for us to add, and nothing to get wrong on a new
        # host.
        #
        # The URL goes to `my.observabilityHostAddress`, which every agent host
        # already sets for vmagent, so logs and metrics cannot point at
        # different machines. On the observability host itself that is
        # loopback, which is correct: it stores its own journal locally and
        # ships it over the loopback interface.
        #
        # No `NetworkTimeoutSec`: unset means the uploader waits out an outage
        # rather than exiting, so a calamansi reboot does not need the unit to
        # be resurrected. Combined with `--save-state` in the upstream unit, that
        # is what makes "written while it was down, delivered after" work.
        services.journald.upload = {
          enable = true;
          settings.Upload.URL = obs.journalUploadUrl config.my.observabilityHostAddress config.my.observabilityLogsPort;
        };
      };
    };
}
