# Secrets module — SOPS-nix bootstrap for declarative secret management.
# Individual secret declarations live in their owning feature modules:
#   access.nix → tailscale-auth-key
#   llm.nix    → litellm-*, openwebui-*, API keys (deepseek, anthropic, minimax, exa)
#   honcho.nix → honcho-*
#
# Devshell-only secrets (gemini-api-key, bws-access-token) are fetched
# from Bitwarden Secrets Manager and do not need sops.secrets declarations.
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
        };
      };
    };
}
