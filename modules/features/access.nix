# Access module — Tailscale VPN and SSH fallback for remote access.
_: {
  my.modules.nixos.access =
    {
      lib,
      config,
      ...
    }:
    {
      config = lib.mkIf config.my.access {
        # Tailscale — uses built-in autoconnect via authKeyFile + extraUpFlags.
        # The auth key file is written by host-secrets-populate.service
        # (modules/features/secrets.nix), which resolves it from BWS via secretspec
        # before tailscaled-autoconnect reads it.
        # useRoutingFeatures: "client" keeps the node able to *use* routing
        # features (exit nodes / subnet routes from other nodes); serving any of
        # them ourselves (exit node, subnet router) is additive, so flip to
        # "both" rather than downgrading to a pure "server" role.
        services.tailscale = {
          enable = true;
          authKeyFile = "/run/secrets/tailscale-auth-key";
          useRoutingFeatures =
            if (config.my.accessEnableExitNode || config.my.accessEnableSubnetRouting) then
              "both"
            else
              "client";
          extraUpFlags = [
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
            assertion = !config.my.accessEnableSubnetRouting || config.my.accessSubnetRoutes != [ ];
            message = "my.accessEnableSubnetRouting is enabled but my.accessSubnetRoutes is empty — add at least one CIDR (e.g. \"192.168.1.0/24\").";
          }
        ];

        # Fallback SSH must be *listened* on, not merely firewalled. The
        # firewall rule below has always opened accessFallbackPort, but nothing
        # told sshd to bind it, so the "way back in when Tailscale is down" has
        # never actually existed on any host (verified on lumquat: firewall
        # accepted 22 and 2222, sshd listened on 22 alone). Opening a port no
        # daemon binds is not a fallback, it is a hole.
        #
        # Both ports are declared: 2222 is the fallback, 22 stays because it is
        # what a freshly installed host answers on before this config lands, and
        # dropping it would remove the only way in during bootstrap.
        services.openssh.ports = lib.mkIf config.my.accessEnableFallbackSSH [
          config.my.accessFallbackPort
        ];

        # Firewall configuration
        networking.firewall = {
          enable = true;
          checkReversePath = "loose";
          trustedInterfaces = [ "tailscale0" ];
          allowedTCPPorts = lib.optionals config.my.accessEnableFallbackSSH [
            config.my.accessFallbackPort
          ];
        };
      };
    };
}
