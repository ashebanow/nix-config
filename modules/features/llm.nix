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
#   -fa 1        Flash attention (required to avoid crashes)
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
    modelsLib = import ../../lib/models.nix {inherit lib;};

    # Shared container options for all LLM containers
    baseOptions = [
      "--device" "/dev/dri"
      "--device" "/dev/kfd"
      "--group-add" "video"
      "--group-add" "render"
      "--security-opt" "seccomp=unconfined"
    ];

    # Base llama-server flags shared by all models
    baseFlags = [
      "-fa" "1" # Flash attention (required on Strix Halo)
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
    mkContainer = name: modelCfg: let
      modelPath = resolveModel modelCfg.hf;
      isPromoted = modelPath != null;
      gguf = modelsLib.ggufs.${modelCfg.hf} or {};
      portStr = toString modelCfg.port;
    in {
      image = "docker.io/kyuz0/amd-strix-halo-toolboxes:rocm-7.2.3-mtp";
      ports = ["${portStr}:8080"];
      autoStart = true;
      extraOptions = baseOptions;
      volumes =
        (if isPromoted
        then ["${modelPath}:/models/${gguf.file}:ro"]
        else ["${modelsDir}:/root/.cache/llama.cpp"]);
      cmd =
        ["llama-server"]
        ++ (
          if isPromoted
          then ["-m" "${modelPath}"]
          else ["-hf" modelCfg.hf]
        )
        ++ [
          "--host" "0.0.0.0"
          "--port" "8080"
          "-ngl" (toString modelCfg.ngl)
        ]
        ++ (lib.optional modelCfg.flashAttn "-fa")
        ++ ["-c" (toString modelCfg.ctxSize)]
        ++ (modelCfg.extraFlags or [])
        ++ baseFlags;
    };
  in {
    config = lib.mkIf cfg.llm {
      # Model storage (used as HF cache for unpromoted models)
      systemd.tmpfiles.rules = [
        "d ${modelsDir} 0775 root root -"
      ];

      # Declarative podman containers
      virtualisation.oci-containers = {
        backend = "podman";
        containers = {
          # Qwen 3.6 35B-A3B Q8 MTP — coding assistant (128K ctx, ~2x faster via MTP)
          qwen-35b-a3b = mkContainer "qwen-35b-a3b" modelsLib.models.qwen-35b-a3b;

          # Gemma 3 27B Q8 — creative / multimodal (256K ctx, no MTP support)
          gemma-27b = mkContainer "gemma-27b" modelsLib.models.gemma-27b;
        };
      };
    };
  };
}
