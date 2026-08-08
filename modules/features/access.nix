# Access module — Tailscale VPN and SSH fallback for remote access.
_: {
  my.modules.nixos.access = {
    lib,
    config,
    ...
  }: {
    config = lib.mkIf config.my.access {
      # SOPS secrets for access module
      sops.secrets."tailscale-auth-key" = {
        mode = "0640";
        group = "root";
      };

      # Tailscale — uses built-in autoconnect via authKeyFile + extraUpFlags.
      # useRoutingFeatures: "client" keeps the node able to *use* routing
      # features (exit nodes / subnet routes from other nodes); serving any of
      # them ourselves (exit node, subnet router) is additive, so flip to
      # "both" rather than downgrading to a pure "server" role.
      services.tailscale = {
        enable = true;
        authKeyFile = "/run/secrets/tailscale-auth-key";
        useRoutingFeatures =
          if (config.my.accessEnableExitNode || config.my.accessEnableSubnetRouting)
          then "both"
          else "client";
        extraUpFlags =
          [
            "--hostname=${config.my.accessTailnetName}"
          ]
          ++ lib.optionals config.my.accessEnableSSH [
            "--ssh"
          ]
          ++ lib.optionals config.my.accessEnableExitNode [
            "--advertise-exit-node"
          ]
          ++ lib.optionals config.my.accessEnableSubnetRouting [
            "--advertise-routes=${lib.concatStringsSep "," config.my.accessSubnetRoutes}"
          ];
      };

      # Subnet routing needs concrete CIDRs; catch misconfiguration early.
      assertions = [
        {
          assertion = !config.my.accessEnableSubnetRouting || config.my.accessSubnetRoutes != [];
          message = "my.accessEnableSubnetRouting is enabled but my.accessSubnetRoutes is empty — add at least one CIDR (e.g. \"192.168.1.0/24\").";
        }
      ];

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
