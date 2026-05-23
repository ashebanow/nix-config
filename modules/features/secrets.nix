# Secrets module — SOPS-nix setup for declarative secret management.
# Self-contained module following dendritic pattern principles.
{
  lib,
  config,
  ...
}: {
  config = lib.mkIf (config.my.access || config.my.llm) {
    # SOPS configuration
    sops = {
      defaultSopsFile = ../../secrets/secrets.yaml;
      age = {
        generateKey = true;
      };
      secrets = {
        "tailscale-auth-key" = {
          mode = "0640";
          group = "root";
          key = "data";
        };
      };
    };
  };
}
