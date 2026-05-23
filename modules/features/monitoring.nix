# Monitoring module — Cockpit web UI for system administration.
# Self-contained module following dendritic pattern principles.
{
  lib,
  pkgs,
  config,
  ...
}: {
  config = lib.mkIf config.my.monitoring {
    # Cockpit web interface
    services.cockpit = {
      enable = true;
      port = config.my.monitoringPort;
    };

    # Cockpit podman integration
    environment.systemPackages = [pkgs.cockpit-podman];

    # Restrict Cockpit to local/Tailscale only
    networking.firewall = lib.mkIf config.my.access {
      allowedTCPPorts = [config.my.monitoringPort];
      trustedInterfaces = ["tailscale0"];
    };
  };
}
