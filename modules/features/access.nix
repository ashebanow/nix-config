# Access module — Tailscale VPN and SSH fallback for remote access.
_: {
  my.modules.nixos.access = {
    lib,
    pkgs,
    config,
    ...
  }: {
    config = lib.mkIf config.my.access {
      # Tailscale
      services.tailscale = {
        enable = true;
        useRoutingFeatures = if config.my.accessEnableExitNode then "server" else "client";
        extraUpFlags = [
          "--hostname=${config.my.accessTailnetName}"
        ] ++ lib.optionals config.my.accessEnableSSH [
          "--ssh"
        ];
      };

      # Tailscale auth key from SOPS secrets
      systemd.services.tailscale-autoconnect = {
        description = "Automatic connection to Tailscale";
        wantedBy = ["multi-user.target"];
        after = ["tailscale.service"];
        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
          ExecStart = lib.mkForce "${lib.getExe pkgs.tailscale} up --authkey=@/run/secrets/tailscale-auth-key --ssh";
        };
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
