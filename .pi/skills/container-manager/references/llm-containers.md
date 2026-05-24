# LLM Container Configuration

## Container Architecture

LLM containers are declared in `modules/features/llm.nix` using the NixOS
`virtualisation.oci-containers` module with podman backend. Each container
runs llama.cpp server with ROCm GPU passthrough for the Strix Halo's
AMD RDNA 3.5 iGPU.

### Current Containers

#### Qwen3-27B (Coding Assistant)

```nix
virtualisation.oci-containers.containers.qwen3-27b = {
  image = "docker.io/kyuz0/amd-strix-halo-toolboxes:rocm-7.2.3-mtp";
  autoStart = true;
  ports = ["8080:8080"];
  volumes = ["/var/lib/llm-models:/models:ro"];
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
```

Systemd service: `podman-qwen3-27b.service`

### Adding a New Container (e.g., DeepSeek v4)

1. Add the model URL to the `models` attrset in `modules/features/llm.nix`
2. Add a new entry under `virtualisation.oci-containers.containers`:
   - Use a unique host port (e.g., `"8081:8080"`)
   - Reference the correct model filename
3. Run `nix flake check` to validate

## GPU Passthrough

For AMD RDNA 3.5 (Strix Halo):
- `/dev/dri` — rendering device nodes (required)
- `/dev/kfd` — ROCm compute interface (required)
- `--group-add keep-groups` — preserves supplementary groups for GPU access
- `--security-opt label=disable` — disables SELinux labeling for device access

Kernel parameters (set in `hosts/lumquat/hardware-configuration.nix`):
- `amd_iommu=off`
- `amdgpu.gttsize=126976`
- `ttm.pages_limit=32505856`

## Model Storage

Models live at `/var/lib/llm-models/` and are:
- Downloaded automatically by `download-llm-models.service` on first boot
- Mounted read-only into containers
- Managed via the `models` attrset in `modules/features/llm.nix`

Model URLs are declared alongside the container definitions for full reproducibility.

## Access Control

- Containers bind to `0.0.0.0` on the container side, mapped to host port via
  the `ports` directive
- Access control is handled at the firewall level (see `modules/features/access.nix`)
- The Cockpit monitoring UI tracks container health
