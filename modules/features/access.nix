# Access module — Tailscale VPN and SSH fallback for remote access.
_: {
  my.modules.nixos.access = {
    lib,
    pkgs,
    config,
    ...
  }: {
    config = lib.mkIf config.my.access {
      # Tailscale — uses built-in autoconnect via authKeyFile + extraUpFlags
      services.tailscale = {
        enable = true;
        authKeyFile = "/run/secrets/tailscale-auth-key";
        useRoutingFeatures =
          if config.my.accessEnableExitNode
          then "server"
          else "client";
        extraUpFlags =
          [
            "--hostname=${config.my.accessTailnetName}"
          ]
          ++ lib.optionals config.my.accessEnableSSH [
            "--ssh"
          ];
      };

      # Firewall configuration
      networking.firewall = {
        enable = true;
        checkReversePath = "loose";
        trustedInterfaces = ["tailscale0"];
        allowedTCPPorts = lib.optionals config.my.accessEnableFallbackSSH [
          config.my.accessFallbackPort
        ];
      };
    };
  };
}
