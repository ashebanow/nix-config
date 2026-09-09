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
            # Not published on the host — reachable only as `qwen-35b-a3b:8080`
            # on the llm-internal bridge, i.e. only through the bifrost gateway.
            # (The host :8080 publish and the direct `lumquat.ts.net/<model>`
            # serve paths were retired with LiteLLM in BOX-138.)
            ports = [];
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

      # Open WebUI — the one browser client, served at
      # https://openwebui.fluffy-walleye.ts.net via its Tailscale sidecar.
      # Talks to the bifrost gateway (my.bifrostServe, modules/features/
      # bifrost.nix) for every model. Secrets come from BWS via secretspec
      # (openwebui scope) at start; no .env or podman-secret readback.
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
    };
  };
}
