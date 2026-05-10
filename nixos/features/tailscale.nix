{ self, ... }: {
  flake.nixosModules.tailscale = { config, pkgs, ... }: {
    services.tailscale.enable = true;

    services.tailscale.useRoutingFeatures = true;
    services.tailscale.extraSetFlags = ["--netfilter-mode=nodivert"];
    networking.firewall.checkReversePath = "loose";

    networking.firewall.trustedInterfaces = [ "tailscale0" ];
    networking.firewall.allowedUDPPorts = [ config.services.tailscale.port ];
  };
}
