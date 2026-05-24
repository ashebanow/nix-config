# LLM Service Architecture

## Container Strategy

LLM containers are declared declaratively in `modules/features/llm.nix` using
the NixOS `virtualisation.oci-containers` module with podman backend.

## Current LLM Containers

| Container | Model | Port | Systemd Service |
|-----------|-------|------|-----------------|
| qwen3-27b | Qwen3-27B Q4_K_M | 8080 (configurable via `my.llmPort`) | `podman-qwen3-27b.service` |
| deepseek-v4 | DeepSeek v4 | TBD | Not yet implemented |

## Feature Module Structure

All LLM configuration lives in `modules/features/llm.nix`:

```nix
_: {
  my.modules.nixos.llm = { lib, pkgs, config, ... }: let
    cfg = config.my;
    modelsDir = cfg.llmModelStorage;
    port = toString cfg.llmPort;
  in {
    config = lib.mkIf cfg.llm {
      # Model storage directory
      systemd.tmpfiles.rules = ["d ${modelsDir} 0775 root root -"];

      # Automatic model download on first boot
      systemd.services.download-llm-models = { ... };

      # Declarative containers via oci-containers module
      virtualisation.oci-containers = {
        backend = "podman";
        containers.qwen3-27b = {
          image = "ghcr.io/ggml-org/llama.cpp:server-rocm";
          autoStart = true;
          ports = ["${port}:8080"];
          volumes = ["${modelsDir}:/models:ro"];
          extraOptions = [
            "--device" "/dev/dri"
            "--device" "/dev/kfd"
            "--group-add" "keep-groups"
            "--security-opt" "label=disable"
          ];
          cmd = [
            "--model" "/models/qwen3-27b-q4_k_m.gguf"
            "--host" "0.0.0.0"
            "--port" "8080"
            "--n-gpu-layers" "99"
            "--ctx-size" "32768"
            "--metrics"
          ];
        };
      };
    };
  };
}
```

## Model Details

| Model | Quant | Size | HuggingFace Source |
|-------|-------|------|--------------------|
| Qwen3-27B | Q4_K_M | ~16 GB | bartowski/Qwen3-27B-GGUF |

Models are downloaded automatically by `download-llm-models.service` on first
boot. The download is idempotent — existing files are skipped.

## GPU Memory

Strix Halo has 128 GB unified memory:
- ~124 GB exposed to GPU via `amdgpu.gttsize=126976`
- Qwen3-27B Q4_K_M uses ~16 GB, leaving headroom for a second model
- `--n-gpu-layers 99` offloads maximum layers to GPU

## Access Control

- Containers bind to `0.0.0.0` inside the container (mapped to host port)
- Firewall control via `modules/features/access.nix`
- All external access routed through Tailscale

## Adding a Second Model

To add DeepSeek v4 (or any additional model):

1. Add to the `models` attrset with download URL
2. Add a new container entry with a unique host port (e.g., `"8081:8080"`)
3. `nix flake check` to validate
