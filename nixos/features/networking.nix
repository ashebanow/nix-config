{ self, ... }: {
  flake.nixosModules.networking = { config, pkgs, ... }: {

    services.openssh = {
      enable = true;
      openFirewall = true;
      settings = {
        PermitRootLogin = "no";
        PasswordAuthentication = false;
      };
    };

    services.tailscale.enable = true;

    services.tailscale.useRoutingFeatures = true;
    services.tailscale.extraSetFlags = ["--netfilter-mode=nodivert"];
    networking.firewall.checkReversePath = "loose";

    networking.firewall.trustedInterfaces = [ "tailscale0" ];
    networking.firewall.allowedUDPPorts = [ config.services.tailscale.port ];
  };
}
