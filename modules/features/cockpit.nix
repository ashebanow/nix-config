# Cockpit module — web UI for system administration.
_: {
  my.modules.nixos.cockpit =
    {
      lib,
      pkgs,
      config,
      ...
    }:
    {
      config = lib.mkIf config.my.cockpit {
        # Cockpit web interface
        services.cockpit = {
          enable = true;
          port = config.my.cockpitPort;
          # services.cockpit.plugins wires each package's passthru.cockpitPath
          # into the cockpit systemd service so it's actually discovered —
          # unlike just putting the package in environment.systemPackages.
          plugins = [
            pkgs.cockpit-files
            pkgs.cockpit-podman
          ];
        };

        # Restrict Cockpit to local/Tailscale only
        networking.firewall = lib.mkIf config.my.access {
          allowedTCPPorts = [ config.my.cockpitPort ];
          trustedInterfaces = [ "tailscale0" ];
        };
      };
    };
}
