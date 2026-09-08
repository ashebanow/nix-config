# LLM module — declarative podman containers for llama.cpp inference.
#
# Image: kyuz0/amd-strix-halo-toolboxes:rocm-10.0
#   - ROCm 10.0 (Fedora 44, AMD-supported gfx1151 SDK) — stable toolbox
#   - MTP (Multi-Token Prediction) merged into llama.cpp mainline (no -mtp fork)
#   - https://github.com/kyuz0/amd-strix-halo-toolboxes
#
# Model catalog: lib/models.nix (adapted from Doug Campos)
#   https://random.qmx.me/posts/2026/01/08/nixifying-local-llms/
#
# Critical Strix Halo flags (from toolboxes README):
#   -fa on       Flash attention (required to avoid crashes; newer llama-server expects on|off|auto)
#   --no-mmap    Disable mmap (required for stability)
_: {
  my.modules.nixos.llm = {
    lib,
    pkgs,
    config,
    ...
  }: let
    cfg = config.my;
    modelsDir = cfg.llmModelStorage;
    hfCacheDir = "${modelsDir}/huggingface-cache";
    modelsLib = import ../../lib/models.nix {inherit lib;};

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
      "--timeout"
      "0" # Disable HTTP read timeout (default 600s causes connection teardown on long idle)
      "--cache-ram"
      "0" # Unified KV cache in VRAM — never save/clear to disk on idle (prevents forced re-processing)
    ];

    # Resolve model: Nix store path if promoted, null otherwise
    resolveModel = hfRef:
      modelsLib.fetchModel {
        inherit pkgs;
        inherit hfRef;
      };

    # Build container config for a single model
    mkContainer = name: modelCfg: extraConfig: let
      modelPath = resolveModel modelCfg.hf;
      isPromoted = modelPath != null;
      gguf = modelsLib.ggufs.${modelCfg.hf} or {};
      portStr = toString modelCfg.port;
    in
      {
        image = "docker.io/kyuz0/amd-strix-halo-toolboxes:rocm-10.0";
        ports = ["${portStr}:8080"];
        autoStart = true;
        extraOptions = baseOptions;
        podman.user = cfg.baseUsername; # Run rootless as the podman user
        volumes =
          [
            "${hfCacheDir}:/root/.cache/huggingface"
          ]
          ++ (
            if isPromoted
            then ["${modelPath}:/models/${gguf.file}:ro"]
            else ["${modelsDir}:/root/.cache/llama.cpp"]
          );
        cmd =
          [
            "llama-server"
          ]
          ++ (
            if isPromoted
            then [
              "-m"
              "/models/${gguf.file}"
            ]
            else [
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
          ++ (modelCfg.extraFlags or [])
          ++ baseFlags;
      }
      // extraConfig;
  in {
    config = lib.mkIf cfg.llm {
      # Model storage (used as HF cache for unpromoted models)
      # hfCacheDir must be owned by the podman user so rootless containers can write to it
      systemd.tmpfiles.rules = [
        "d ${modelsDir} 0775 root root -"
        "d ${hfCacheDir} 0775 ${cfg.baseUsername} ${cfg.baseUsername} -"
        "d /etc/litellm 0755 root root -"
        "L+ /etc/litellm/compose.yml - - - - ${../../compose/llm/compose.yml}"
        "L+ /etc/litellm/litellm-config.yaml - - - - ${../../compose/llm/litellm-config.yaml}"
        "d /etc/openwebui 0755 root root -"
        "L+ /etc/openwebui/compose.yml - - - - ${../../compose/llm/openwebui-compose.yml}"
      ];

      # Shared host-local podman bridge for container→container traffic on this
      # box (bifrost → llama-server, later openwebui → bifrost). Same-host
      # sidecar↔sidecar / sidecar↔host hops over the tailnet get relayed via
      # DERP (two nodes on one host can't hole-punch), and DERP mangles request
      # bodies over ~5 KB — see BOX-140. This bridge keeps that traffic on the
      # box; Tailscale still fronts every external door.
      #
      # Created out of band (rootless podman, user ${cfg.baseUsername}) so its
      # lifecycle isn't tied to any one compose stack; consumers order after it.
      systemd.services.podman-network-llm-internal = {
        description = "Create the llm-internal podman network";
        after = ["network-online.target" "linger-users.service"];
        wants = ["network-online.target"];
        wantedBy = ["multi-user.target"];
        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = "yes";
          User = cfg.baseUsername;
          Environment = ["HOME=/home/${cfg.baseUsername}"];
        };
        script = ''
          export XDG_RUNTIME_DIR="/run/user/$(id -u)"
          ${pkgs.podman}/bin/podman network exists llm-internal \
            || ${pkgs.podman}/bin/podman network create llm-internal
        '';
      };

      # qwen also needs the network to exist before it starts.
      systemd.services.podman-qwen-35b-a3b = {
        after = ["podman-network-llm-internal.service"];
        requires = ["podman-network-llm-internal.service"];
      };

      # Declarative podman containers
      virtualisation.oci-containers = {
        backend = "podman";
        containers = {
          # Qwen 3.6 35B-A3B UD-Q8_K_XL MTP — coding assistant (256K ctx, ~2x faster via MTP)
          qwen-35b-a3b = mkContainer "qwen-35b-a3b" modelsLib.models.qwen-35b-a3b {
            # Warm-up: send a dummy request on start so model is preloaded before first real query.
            # Without this, the very first user request triggers prompt cache init which adds latency.
            #
            # --network llm-internal: reachable as `qwen-35b-a3b:8080` from other
            # containers on that bridge (bifrost). The host `8080:8080` publish
            # is kept for the legacy paths (litellm, tailscale-llm-serve) until
            # BOX-138 retires them.
            extraOptions =
              baseOptions
              ++ [
                "--network"
                "llm-internal"
                "--health-cmd"
                "curl -sf http://127.0.0.1:8080/health"
                "--health-interval"
                "30s"
                "--health-retries"
                "60"
                "--health-start-period"
                "120s"
              ];
          };
        };
      };

      # Tailscale Serve — publish each model on the node's own hostname.
      # Each model is accessible at https://lumquat.fluffy-walleye.ts.net/<name>
      # (e.g. /qwen-35b-a3b).  TLS certs are issued automatically
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
      # Secrets are resolved from BWS via secretspec (litellm scope) at start —
      # no .env or podman-secret readback; values live only in the process env.
      # Compose + config are symlinked to /etc/litellm via tmpfiles above.
      systemd.services.litellm-compose = lib.mkIf config.my.llmServe {
        description = "LiteLLM proxy compose stack";
        after = ["network-online.target"];
        wants = ["network-online.target"];
        wantedBy = ["multi-user.target"];
        path = [
          pkgs.podman
          pkgs.podman-compose
          pkgs.secretspec
          pkgs.bws
        ];
        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = "yes";
          User = config.my.baseUsername;
          Environment = [
            "SECRETSPEC_FILE=${config.my.secretspecManifest}"
            "SECRETSPEC_PROVIDER=bws-service"
          ];
          LoadCredential = [
            "access_token:${config.my.bwsAccessTokenFile}"
          ];
          ExecStart = pkgs.writeShellScript "litellm-compose-start" ''
            set -e
            export XDG_RUNTIME_DIR="/run/user/$(id -u)"
            # secretspec injects the litellm scope (TS_AUTHKEY,
            # LITELLM_MASTER_KEY, LITELLM_DB_PASSWORD, DEEPSEEK_API_KEY,
            # ANTHROPIC_API_KEY, MINIMAX_API_KEY) into this environment;
            # podman-compose substitutes them in compose.yml.
            exec ${pkgs.secretspec}/bin/secretspec run -P production -S litellm -- \
              ${pkgs.podman-compose}/bin/podman-compose -f /etc/litellm/compose.yml up -d
          '';
          ExecStop = "${pkgs.podman-compose}/bin/podman-compose -f /etc/litellm/compose.yml down";
        };
      };

      systemd.services.openwebui-compose = lib.mkIf config.my.llmServe {
        description = "Open WebUI compose stack";
        after = ["network-online.target"];
        wants = ["network-online.target"];
        wantedBy = ["multi-user.target"];
        # Without this a rebuild that only changes the symlinked compose content
        # (e.g. the gateway cutover, BOX-136) leaves the old stack running — the
        # unit text is unchanged. webui-data is a named volume; a restart is
        # down/up and does not touch it, so logins survive. (BOX-139.)
        restartTriggers = ["${../../compose/llm/openwebui-compose.yml}"];
        path = [
          pkgs.podman
          pkgs.podman-compose
          pkgs.secretspec
          pkgs.bws
        ];
        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = "yes";
          User = config.my.baseUsername;
          Environment = [
            "SECRETSPEC_FILE=${config.my.secretspecManifest}"
            "SECRETSPEC_PROVIDER=bws-service"
          ];
          LoadCredential = [
            "access_token:${config.my.bwsAccessTokenFile}"
          ];
          ExecStart = pkgs.writeShellScript "openwebui-compose-start" ''
            set -e
            export XDG_RUNTIME_DIR="/run/user/$(id -u)"
            exec ${pkgs.secretspec}/bin/secretspec run -P production -S openwebui -- \
              ${pkgs.podman-compose}/bin/podman-compose -f /etc/openwebui/compose.yml up -d
          '';
          ExecStop = "${pkgs.podman-compose}/bin/podman-compose -f /etc/openwebui/compose.yml down";
        };
      };

      systemd.services.tailscale-llm-serve = lib.mkIf config.my.llmServe {
        description = "Tailscale Serve for LLM services";
        after = [
          "tailscaled.service"
          "tailscaled-autoconnect.service"
        ];
        wants = ["tailscaled.service"];
        wantedBy = ["multi-user.target"];
        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
        };
        path = [config.services.tailscale.package];
        script = let
          modelNames = builtins.attrNames modelsLib.models;
          # /llm is the generic alias for whatever model is currently primary.
          primaryModel =
            lib.findFirst (n: modelsLib.models.${n}.primary or false) null modelNames;
          servePath = path: port: ''
            echo "Configuring Tailscale Serve for ${path} -> http://localhost:${toString port}"
            tailscale serve --bg --set-path=${path} http://localhost:${toString port}
          '';
        in
          # `tailscale serve --set-path` is additive and nothing ever removes a
          # path, so the live table accumulates entries for models that no longer
          # exist. Reset first, then re-add, so the serve table equals this
          # declaration rather than the history of every config we ever applied.
          ''
            tailscale serve reset
          ''
          + lib.concatMapStringsSep "\n" (n: servePath "/${n}" modelsLib.models.${n}.port) modelNames
          + lib.optionalString (primaryModel != null) (
            servePath "/llm" modelsLib.models.${primaryModel}.port
          );
      };
    };
  };
}
