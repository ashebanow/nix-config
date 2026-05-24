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
    port = toString cfg.llmPort;
    modelsLib = import ../../lib/models.nix {inherit lib;};

    # Resolve model: Nix store path if promoted, null otherwise
    model = modelsLib.fetchModel {
      inherit pkgs;
      hfRef = modelsLib.models.qwen3-27b.hf;
    };

    # -m <path> if promoted, -hf <ref> otherwise
    modelArg =
      if model != null
      then "-m ${model}"
      else "-hf ${modelsLib.models.qwen3-27b.hf}";

    # Volume mount for Nix store model (only when promoted)
    modelVolumes =
      if model != null
      then ["${model}:/models/${modelsLib.ggufs.${modelsLib.models.qwen3-27b.hf}.file}:ro"]
      else [];

    # When using -hf, llama.cpp needs a writable cache dir for downloads
    hfCacheDir =
      if model == null
      then ["${modelsDir}:/root/.cache/llama.cpp"]
      else [];
  in {
    config = lib.mkIf cfg.llm {
      # Model storage (used as HF cache until model is promoted)
      systemd.tmpfiles.rules = [
        "d ${modelsDir} 0775 root root -"
      ];

      # Declarative podman containers via NixOS oci-containers module
      virtualisation.oci-containers = {
        backend = "podman";
        containers = {
          # Qwen3-27B (coding assistant + general tasks)
          qwen3-27b = {
            image = "docker.io/kyuz0/amd-strix-halo-toolboxes:rocm-7.2.3-mtp";
            ports = ["${port}:8080"];
            volumes = modelVolumes ++ hfCacheDir;
            extraOptions = [
              "--device" "/dev/dri"
              "--device" "/dev/kfd"
              "--group-add" "video"
              "--group-add" "render"
              "--security-opt" "seccomp=unconfined"
            ];
            cmd = [
              "llama-server"
              modelArg
              "--host" "0.0.0.0"
              "--port" "8080"
              "-ngl" "999"
              "-fa" "1" # Flash attention (required on Strix Halo)
              "--no-mmap" # Required for Strix Halo stability
              "-c" "32768"
              "--metrics"
            ];
            autoStart = true;
          };
        };
      };
    };
  };
}
