# LLM module — declarative podman containers for llama.cpp inference.
#
# Image: kyuz0/amd-strix-halo-toolboxes:rocm-7.2.3-mtp
#   - ROCm 7.2.3 compiled for Strix Halo RDNA 3.5
#   - MTP (Multi-Token Prediction) support via am17an/llama.cpp mtp-clean fork
#   - https://github.com/kyuz0/amd-strix-halo-toolboxes
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

    # Model definitions — name to huggingface GGUF URL
    models = {
      "qwen3-27b-q4_k_m.gguf" = "https://huggingface.co/bartowski/Qwen3-27B-GGUF/resolve/main/Qwen3-27B-Q4_K_M.gguf";
    };

    # Generate a download script for all models
    downloadScript = pkgs.writeShellScript "download-llm-models" ''
      set -euo pipefail
      mkdir -p "${modelsDir}"

      ${lib.concatStringsSep "\n" (lib.mapAttrsToList (filename: url: ''
        if [ ! -f "${modelsDir}/${filename}" ]; then
          echo "Downloading ${filename}..."
          ${pkgs.wget}/bin/wget -q --show-progress --continue \
            -O "${modelsDir}/${filename}.tmp" "${url}"
          mv "${modelsDir}/${filename}.tmp" "${modelsDir}/${filename}"
          echo "  Done: ${filename}"
        else
          echo "  Skip: ${filename} (already present)"
        fi
      '') models)}

      chmod 644 "${modelsDir}"/*.gguf 2>/dev/null || true
    '';
  in {
    config = lib.mkIf cfg.llm {
      # Model storage
      systemd.tmpfiles.rules = [
        "d ${modelsDir} 0775 root root -"
      ];

      # Download models on first boot (before containers start)
      systemd.services.download-llm-models = {
        description = "Download LLM models";
        wantedBy = ["multi-user.target"];
        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
          ExecStart = downloadScript;
        };
      };

      # Declarative podman containers via NixOS oci-containers module
      virtualisation.oci-containers = {
        backend = "podman";
        containers = {
          # Qwen3-27B (coding assistant + general tasks)
          qwen3-27b = {
            image = "docker.io/kyuz0/amd-strix-halo-toolboxes:rocm-7.2.3-mtp";
            ports = ["${port}:8080"];
            volumes = ["${modelsDir}:/models:ro"];
            extraOptions = [
              "--device" "/dev/dri"
              "--device" "/dev/kfd"
              "--group-add" "video"
              "--group-add" "render"
              "--security-opt" "seccomp=unconfined"
            ];
            cmd = [
              "llama-server"
              "-m" "/models/qwen3-27b-q4_k_m.gguf"
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
