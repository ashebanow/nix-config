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
        image = "docker.io/kyuz0/amd-strix-halo-toolboxes:rocm-7.2.3-mtp";
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
          ["llama-server"]
          ++ (
            if isPromoted
            then ["-m" "${modelPath}"]
            else ["-hf" modelCfg.hf]
          )
          ++ [
            "--host"
            "0.0.0.0"
            "--port"
            "8080"
            "-ngl"
            (toString modelCfg.ngl)
          ]
          ++ ["-c" (toString modelCfg.ctxSize)]
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
      ];

      # Declarative podman containers
      virtualisation.oci-containers = {
        backend = "podman";
        containers = {
          # Qwen 3.6 35B-A3B UD-Q8_K_XL MTP — coding assistant (128K ctx, ~2x faster via MTP)
          qwen-35b-a3b = mkContainer "qwen-35b-a3b" modelsLib.models.qwen-35b-a3b {};

          # ———— INACTIVE ———— Gemma 3 27B Q5_K_XL — creative / multimodal
          # Left here for when we return to a dual-model setup.
          # Issue: draft model resolution hits 401 on HF API (no token configured).
          #gemma-27b = mkContainer "gemma-27b" modelsLib.models.gemma-27b { autoStart = false; };
        };
      };
    };
  };
}
