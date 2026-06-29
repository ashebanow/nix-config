# Secrets module — SOPS-nix setup for declarative secret management.
_: {
  my.modules.nixos.secrets =
    {
      lib,
      config,
      ...
    }:
    {
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
            };
            "litellm-tailscale-auth-key" = {
              mode = "0640";
              group = "root";
            };
            "litellm-master-key" = {
              mode = "0640";
              group = "root";
            };
            "litellm-db-password" = {
              mode = "0640";
              group = "root";
            };
            "deepseek-api-key" = {
              mode = "0600";
              group = "root";
            };
            "exa-api-key" = {
              mode = "0600";
              group = "root";
            };
            "gemini-api-key" = {
              mode = "0600";
              group = "root";
            };
            "anthropic-api-key" = {
              mode = "0600";
              group = "root";
            };
            "minimax-api-key" = {
              mode = "0600";
              group = "root";
            };
          };
        };
      };
    };
}
