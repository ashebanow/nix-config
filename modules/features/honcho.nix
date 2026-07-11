# Honcho module — declarative podman-compose stack for AI agent memory.
#
# Image: ghcr.io/plastic-labs/honcho:v3.0.11
#   - Honcho is an open-source memory library for stateful AI agents.
#   - Provides persistent memory across sessions: observations, peer
#     representations, dialectic reasoning, and dream consolidation.
#   - https://honcho.dev
#
# Architecture:
#   - API (FastAPI, port 8000) + Deriver (background worker)
#   - PostgreSQL + pgvector for embeddings storage
#   - Redis for caching
#   - Tailscale sidecar for zero-trust access
#
# LLM routing:
#   - Primary: qwen-35b-a3b via LiteLLM proxy (all features)
#   - Deriver fallback: deepseek-v4-flash via DeepSeek API direct
#   - Embeddings: deepseek-v4-flash via DeepSeek API direct
_: {
  my.modules.nixos.honcho =
    {
      lib,
      pkgs,
      config,
      ...
    }:
    let
      cfg = config.my;
    in
    {
      config = lib.mkIf cfg.llm {
        # SOPS secrets for Honcho
        sops.secrets = {
          "honcho-tailscale-auth-key" = {
            mode = "0640";
            group = "root";
          };
          "honcho-db-password" = {
            mode = "0640";
            group = "root";
          };
          "gemini-api-key" = {
            mode = "0600";
            group = "root";
          };
        };

        # Symlink compose file into /etc/honcho
        systemd.tmpfiles.rules = [
          "d /etc/honcho 0755 root root -"
          "L+ /etc/honcho/compose.yml - - - - ${../../compose/llm/honcho-compose.yml}"
        ];

        # Honcho memory layer with Tailscale sidecar (podman-compose).
        # Serves at https://honcho.fluffy-walleye.ts.net.
        # Uses LiteLLM proxy for primary LLM (qwen-35b-a3b) with
        # DeepSeek v4 Flash direct as deriver fallback + embeddings.
        # Secrets are fed from SOPS at /run/secrets/ at boot — no .env on disk.
        # Compose is symlinked to /etc/honcho via tmpfiles above.
        systemd.services.honcho-compose = lib.mkIf cfg.llmServe (
          let
            honchoTsAuthKeyPath = config.sops.secrets."honcho-tailscale-auth-key".path;
            honchoDbPasswordPath = config.sops.secrets."honcho-db-password".path;
            litellmMasterKeyPath = config.sops.secrets."litellm-master-key".path;
            deepseekKeyPath = config.sops.secrets."deepseek-api-key".path;
            geminiKeyPath = config.sops.secrets."gemini-api-key".path;
          in
          {
            description = "Honcho memory layer compose stack";
            after = [ "network.target" ];
            wants = [ "network.target" ];
            wantedBy = [ "multi-user.target" ];
            path = [ pkgs.podman-compose ];
            serviceConfig = {
              Type = "oneshot";
              RemainAfterExit = "yes";
              User = cfg.baseUsername;
              Environment = [
                "PATH=${pkgs.podman-compose}/bin:/run/current-system/sw/bin"
              ];
              LoadCredential = [
                "ts-auth-key:${honchoTsAuthKeyPath}"
                "honcho-db-password:${honchoDbPasswordPath}"
                "litellm-master-key:${litellmMasterKeyPath}"
                "deepseek-api-key:${deepseekKeyPath}"
                "gemini-api-key:${geminiKeyPath}"
              ];
              ExecStart = pkgs.writeShellScript "honcho-compose-start" ''
                set -e
                export XDG_RUNTIME_DIR="/run/user/$(id -u)"
                export HONCHO_TS_AUTHKEY="$(cat $CREDENTIALS_DIRECTORY/ts-auth-key)"
                export HONCHO_DB_PASSWORD="$(cat $CREDENTIALS_DIRECTORY/honcho-db-password)"
                export LITELLM_MASTER_KEY="$(cat $CREDENTIALS_DIRECTORY/litellm-master-key)"
                export DEEPSEEK_API_KEY="$(cat $CREDENTIALS_DIRECTORY/deepseek-api-key)"
                export GEMINI_API_KEY="$(cat $CREDENTIALS_DIRECTORY/gemini-api-key)"
                # podman-compose reads env vars from .env file
                cat > /etc/honcho/.env << EOF
LITELLM_MASTER_KEY=$LITELLM_MASTER_KEY
DEEPSEEK_API_KEY=$DEEPSEEK_API_KEY
HONCHO_DB_PASSWORD=$HONCHO_DB_PASSWORD
HONCHO_TS_AUTHKEY=$HONCHO_TS_AUTHKEY
GEMINI_API_KEY=$GEMINI_API_KEY
LLM_GEMINI_API_KEY=$GEMINI_API_KEY
EOF
                exec podman-compose -f /etc/honcho/compose.yml up -d
              '';
              ExecStop = "${pkgs.podman-compose}/bin/podman-compose -f /etc/honcho/compose.yml down";
            };
          }
        );
      };
    };
}
