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
# v1 of this module is metrics and logs. The podman exporter (BOX-331) belongs
# here too — same flag, same machine, one agent — and is deliberately absent
# rather than forgotten.
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
      # consumes. Two sources, in the order they matter:
      #
      #   node_exporter       the host itself (CPU, memory, disk, hwmon, drm)
      #   my.observability    whatever a feature module declared
      #
      # Built as one list rather than two so a scrape-config collision is
      # impossible by construction: `renderScrapeConfigs` keys by name, and
      # "node" is reserved here.
      scrapeConfig = {
        scrape_configs = [
          {
            job_name = "node";
            static_configs = [
              { targets = [ "127.0.0.1:${toString config.services.prometheus.exporters.node.port}" ]; }
            ];
          }
        ]
        ++ obs.renderScrapeConfigs config.my.observability.scrapeTargets;
      };

      # ── Textfile checks (BOX-332) ────────────────────────────────────
      #
      # One systemd service + timer pair per `my.observability.textfileChecks`
      # entry. A check answers a question only a command can answer (a
      # database's size, a certificate's remaining days), so the shape is
      # timer → run → write `<name>.prom` into node_exporter's textfile
      # directory; the next scrape exposes it as metrics with no exporter to
      # write.
      #
      # Built outside the `mkIf` so they can be named in `in`, then attached
      # under it. `lib.mkIf` cannot be applied to a bare attrset of units
      # without naming each one, so the whole conditional fragment uses
      # `mkIf` and merges these lists.
      #
      # Why a service unit per check instead of the timer's own ExecStart:
      # systemd timers cannot run commands. The service is also what gives a
      # check its own `User=`, its own failed state (visible as
      # `node_systemd_unit_state{state="failed"}`, which the generic rules
      # already alert on) and its own journal stream. One shared service would
      # make "which check broke" unanswerable.
      textfileCheckServices = lib.mapAttrs' (
        name: check:
        let
          unitUser = obs.checkUnitUser check;
        in
        lib.nameValuePair "textfile-check-${name}" {
          description = "Textfile check ${name} for node_exporter";
          path = with pkgs; [
            sqlite
            coreutils
            jq
            util-linux
          ];
          serviceConfig = {
            Type = "oneshot";
            # The owning user of whatever the check reads. A check with an
            # escape hatch (`unreadableAs`) must be able to become root, so its
            # unit is root and the script drops to the owning user itself —
            # see obs.checkUnitUser.
            User = unitUser;
            # No `Group=`: systemd then derives the primary group from the user,
            # which is right for both cases — `podman:podman` for a check that
            # runs as the owning account, and `root:root` for one that may drop
            # to it. Setting it explicitly here was wrong for the first case.
            # The check must be able to write exactly one file, in the textfile
            # directory, and nothing else anywhere.
            ProtectSystem = "strict";
            PrivateTmp = true;
            NoNewPrivileges = true;
            ReadWritePaths = [ obs.textfileDirectory ];
          };
          script = obs.checkPrelude check + "\n" + check.script;
        }
      ) config.my.observability.textfileChecks;

      textfileCheckTimers = lib.mapAttrs' (
        name: check:
        lib.nameValuePair "textfile-check-${name}" {
          description = "Periodic textfile check ${name}";
          wantedBy = [ "timers.target" ];
          timerConfig = {
            # A check reads a file or queries a database, so it runs on a
            # multi-minute clock, not a scrape interval.
            OnBootSec = "2m";
            OnUnitInactiveSec = check.interval;
            # `Persistent` only means something with a calendar spec, so it is
            # deliberately absent: `OnUnitInactiveSec` schedules from the last
            # run, and systemd's monotonic timers fire once on return anyway.
            RandomizedDelaySec = "30s";
            Unit = "textfile-check-${name}.service";
          };
        }
      ) config.my.observability.textfileChecks;
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
          ] ++ lib.optional config.my.observabilityGpuMetrics "drm";
          # textfile: the directory BOX-332's checks write `<name>.prom` into.
          # Enabled with the directory created and empty, so the collector is
          # not switched on later as a second change to the same unit. The path
          # comes from `obs.textfileDirectory` so the collector's flag and the
          # checks' target cannot drift apart.
          extraFlags = [
            "--collector.textfile.directory=${obs.textfileDirectory}"
          ];
        };

        # Root-owned and 0755 — deliberately NOT writable by the accounts the
        # checks run as. A check that could create files here could also
        # replace another check's output; a check writes into it because its
        # unit is granted it (`ReadWritePaths`), not because the mode allows it.
        systemd.tmpfiles.rules = [
          "d ${obs.textfileDirectory} 0755 root root -"
        ];

        # The checks themselves, if a feature declared any.
        systemd.services = textfileCheckServices;
        systemd.timers = textfileCheckTimers;

        # A GPU host needs no extra device access for this: the drm and hwmon
        # collectors read `/sys/class/drm` and `/sys/class/hwmon`, which are
        # world-readable, so the exporter keeps its default hardening
        # (`DeviceAllow = [ "" ]`, `PrivateDevices = true`). Nothing here opens
        # `/dev/dri/cardN`; that would only be needed to talk to the GPU, which
        # a metrics scrape never does. See docs/lumquat-hardware.md for which
        # metrics the Strix Halo APU actually populates.

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
