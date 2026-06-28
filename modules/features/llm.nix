# LLM module — declarative podman containers for llama.cpp inference.
#
# Image: kyuz0/amd-strix-halo-toolboxes:rocm-7.2.3-mtp
#   - ROCm 7.2.3 compiled for Strix Halo RDNA 3.5
#   - MTP (Multi-Token Prediction) via am17an/llama.cpp mtp-clean fork
#   - https://github.com/kyuz0/amd-strix-halo-toolboxes
#
# Model catalog: lib/models.nix (adapted from Doug Campos)
#   https://random.qmx.me/posts/2026/01/08/nixifying-local-llms/
#
# Critical Strix Halo flags (from toolboxes README):
#   -fa on       Flash attention (required to avoid crashes; newer llama-server expects on|off|auto)
#   --no-mmap    Disable mmap (required for stability)
_: {
  my.modules.nixos.llm =
    {
      lib,
      pkgs,
      config,
      ...
    }:
    let
      cfg = config.my;
      modelsDir = cfg.llmModelStorage;
      hfCacheDir = "${modelsDir}/huggingface-cache";
      modelsLib = import ../../lib/models.nix { inherit lib; };

      # Shared container options for all LLM containers
      baseOptions = [
        "--device"
        "/dev/dri"
        "--device"
        "/dev/kfd"
        "--group-add"
        "video"
        "--group-add"
        "render"
        "--security-opt"
        "seccomp=unconfined"
      ];

      # Base llama-server flags shared by all models
      baseFlags = [
        "-fa"
        "on" # Flash attention (required on Strix Halo, newer llama-server expects on|off|auto)
        "--no-mmap" # Required for Strix Halo stability
        "--metrics"
      ];

      # Resolve model: Nix store path if promoted, null otherwise
      resolveModel =
        hfRef:
        modelsLib.fetchModel {
          inherit pkgs;
          inherit hfRef;
        };

      # Build container config for a single model
      mkContainer =
        name: modelCfg: extraConfig:
        let
          modelPath = resolveModel modelCfg.hf;
          isPromoted = modelPath != null;
          gguf = modelsLib.ggufs.${modelCfg.hf} or { };
          portStr = toString modelCfg.port;
        in
        {
          image = "docker.io/kyuz0/amd-strix-halo-toolboxes:rocm-7.2.3-mtp";
          ports = [ "${portStr}:8080" ];
          autoStart = true;
          extraOptions = baseOptions;
          podman.user = cfg.baseUsername; # Run rootless as the podman user
          volumes = [
            "${hfCacheDir}:/root/.cache/huggingface"
          ]
          ++ (
            if isPromoted then
              [ "${modelPath}:/models/${gguf.file}:ro" ]
            else
              [ "${modelsDir}:/root/.cache/llama.cpp" ]
          );
          cmd = [
            "llama-server"
          ]
          ++ (
            if isPromoted then
              [
                "-m"
                "/models/${gguf.file}"
              ]
            else
              [
                "-hf"
                modelCfg.hf
              ]
          )
          ++ [
            "--host"
            "0.0.0.0"
            "--port"
            "8080"
            "-ngl"
            (toString modelCfg.ngl)
          ]
          ++ [
            "-c"
            (toString modelCfg.ctxSize)
          ]
          ++ (modelCfg.extraFlags or [ ])
          ++ baseFlags;
        }
        // extraConfig;
    in
    {
      config = lib.mkIf cfg.llm {
        # Model storage (used as HF cache for unpromoted models)
        # hfCacheDir must be owned by the podman user so rootless containers can write to it
        systemd.tmpfiles.rules = [
          "d ${modelsDir} 0775 root root -"
          "d ${hfCacheDir} 0775 ${cfg.baseUsername} ${cfg.baseUsername} -"
          "d /etc/litellm 0755 root root -"
          "L+ /etc/litellm/compose.yml - - - - ${../../compose/llm/compose.yml}"
          "L+ /etc/litellm/litellm-config.yaml - - - - ${../../compose/llm/litellm-config.yaml}"
        ];

        # Declarative podman containers
        virtualisation.oci-containers = {
          backend = "podman";
          containers = {
            # Qwen 3.6 35B-A3B UD-Q8_K_XL MTP — coding assistant (128K ctx, ~2x faster via MTP)
            qwen-35b-a3b = mkContainer "qwen-35b-a3b" modelsLib.models.qwen-35b-a3b { };

            # ———— INACTIVE ———— Gemma 3 27B Q5_K_XL — creative / multimodal
            # Left here for when we return to a dual-model setup.
            # Issue: draft model resolution hits 401 on HF API (no token configured).
            #gemma-27b = mkContainer "gemma-27b" modelsLib.models.gemma-27b { autoStart = false; };
          };
        };

        # Tailscale Serve — publish each model on the node's own hostname.
        # Each model is accessible at https://lumquat.fluffy-walleye.ts.net/<name>
        # (e.g. /qwen-35b-a3b, /gemma-27b).  TLS certs are issued automatically
        # by Tailscale.  No admin approval needed — direct serve works on the
        # Free plan and with tagged nodes.
        #
        # We use direct serve (without --service=svc:) because the svc: service
        # proxy feature requires the tailscale.com/cap/services tailnet capability
        # which is not available on the Personal/Free plan.
        #
        # NOTE: llama-server serves plain HTTP, so the proxy target uses
        # http:// (Tailscale terminates TLS at the edge and forwards to
        # the HTTP backend).
        # LiteLLM proxy with Tailscale sidecar (podman-compose).
        # Serves at https://litellm.fluffy-walleye.ts.net.
        # Routes model names → local llama.cpp backends (and remote APIs).
        # Secrets are fed from SOPS at /run/secrets/ at boot — no .env on disk.
        # Compose + config are symlinked to /etc/litellm via tmpfiles above.
        systemd.services.litellm-compose = lib.mkIf config.my.llmServe (
          let
            tsAuthKeyPath = config.sops.secrets."litellm-tailscale-auth-key".path;
            litellmMasterKeyPath = config.sops.secrets."litellm-master-key".path;
            litellmDbPasswordPath = config.sops.secrets."litellm-db-password".path;
            deepseekKeyPath = config.sops.secrets."deepseek-api-key".path;
            anthropicKeyPath = config.sops.secrets."anthropic-api-key".path;
            minimaxKeyPath = config.sops.secrets."minimax-api-key".path;
            exaKeyPath = config.sops.secrets."exa-api-key".path;
          in
          {
            description = "LiteLLM proxy compose stack";
            after = [ "network.target" ];
            wants = [ "network.target" ];
            wantedBy = [ "multi-user.target" ];
            path = [ pkgs.podman-compose ];
            serviceConfig = {
              Type = "oneshot";
              RemainAfterExit = "yes";
              User = config.my.baseUsername;
              Environment = [
                "PATH=${pkgs.podman-compose}/bin:/run/current-system/sw/bin"
              ];
              LoadCredential = [
                "ts-auth-key:${tsAuthKeyPath}"
                "litellm-master-key:${litellmMasterKeyPath}"
                "litellm-db-password:${litellmDbPasswordPath}"
                "deepseek-api-key:${deepseekKeyPath}"
                "anthropic-api-key:${anthropicKeyPath}"
                "minimax-api-key:${minimaxKeyPath}"
                "exa-api-key:${exaKeyPath}"
              ];
              ExecStart = pkgs.writeShellScript "litellm-compose-start" ''
                set -e
                export XDG_RUNTIME_DIR="/run/user/$(id -u)"
                export TS_AUTHKEY="$(cat $CREDENTIALS_DIRECTORY/ts-auth-key)"
                export LITELLM_MASTER_KEY="$(cat $CREDENTIALS_DIRECTORY/litellm-master-key)"
                export LITELLM_DB_PASSWORD="$(cat $CREDENTIALS_DIRECTORY/litellm-db-password)"
                export DEEPSEEK_API_KEY="$(cat $CREDENTIALS_DIRECTORY/deepseek-api-key)"
                export ANTHROPIC_API_KEY="$(cat $CREDENTIALS_DIRECTORY/anthropic-api-key)"
                export MINIMAX_API_KEY="$(cat $CREDENTIALS_DIRECTORY/minimax-api-key)"
                export EXA_API_KEY="$(cat $CREDENTIALS_DIRECTORY/exa-api-key)"
                exec podman-compose -f /etc/litellm/compose.yml up -d
              '';
              ExecStop = "${pkgs.podman-compose}/bin/podman-compose -f /etc/litellm/compose.yml down";
            };
          }
        );

        systemd.services.tailscale-llm-serve = lib.mkIf config.my.llmServe {
          description = "Tailscale Serve for LLM services";
          after = [
            "tailscaled.service"
            "tailscaled-autoconnect.service"
          ];
          wants = [ "tailscaled.service" ];
          wantedBy = [ "multi-user.target" ];
          serviceConfig = {
            Type = "oneshot";
            RemainAfterExit = true;
          };
          path = [ config.services.tailscale.package ];
          script = lib.concatMapStringsSep "\n" (
            name:
            let
              model = modelsLib.models.${name};
            in
            ''
              echo "Configuring Tailscale Serve for ${name} -> http://localhost:${toString model.port}"
              tailscale serve --bg --set-path=/${name} http://localhost:${toString model.port}
            ''
          ) (builtins.attrNames modelsLib.models);
        };
      };
    };
}
