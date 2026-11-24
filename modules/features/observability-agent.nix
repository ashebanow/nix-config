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
# v1 of this module is metrics only. `systemd-journal-upload` (BOX-330) and the
# podman exporter (BOX-331) belong here too — same flag, same machine, one
# agent — and are deliberately absent rather than forgotten.
_: {
  my.modules.nixos.observability-agent =
    {
      lib,
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
        # `drm` (lumquat's AMD GPU) is BOX-327's business: it is meaningless on
        # a host without a GPU, and enabling it there costs a futile sysfs scan.
        services.prometheus.exporters.node = {
          enable = true;
          listenAddress = "127.0.0.1";
          enabledCollectors = [
            "systemd"
            "processes"
            "hwmon"
          ];
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
      };
    };
}
