# LLM Container Configuration

## Container Architecture

Lumquat runs multiple LLM containers, each serving a different model:

### Qwen-27B (Coding)

```nix
virtualisation.podman.containers.qwen-27b = {
  image = "ghcr.io/ggerganov/llama.cpp:server";
  autoStart = true;
  environment = {
    MODEL = "/models/qwen-27b-q4_k_m.gguf";
    HOST = "127.0.0.1";  # Localhost only - accessed via Tailscale
    PORT = "8080";
  };
  volumes = ["/var/lib/llm-models:/models:ro"];
  devices = ["/dev/dri"];  # AMD RDNA 3.5 GPU
};
```

### DeepSeek v4 (Planning/Multimodal)

```nix
virtualisation.podman.containers.deepseek-v4 = {
  image = "ghcr.io/ggerganov/llama.cpp:server";
  autoStart = true;
  environment = {
    MODEL = "/models/deepseek-v4-q4_k_m.gguf";
    HOST = "127.0.0.1";
    PORT = "8081";
  };
  volumes = ["/var/lib/llm-models:/models:ro"];
  devices = ["/dev/dri"];
};
```

## Access Control

- Containers bind to `127.0.0.1` — not directly accessible
- All LLM traffic routed through Tailscale Aperture
- No firewall exposure except Tailscale interface

## GPU Passthrough

The AMD RDNA 3.5 GPU in Strix Halo requires:
- Container has access to `/dev/dri`
- Kernel parameters set correctly (see host-inventory.md)
- Proper Vulkan/ROCM setup if needed

## Model Storage

Models stored at `/var/lib/llm-models/`:
- Read-only mount into containers
- Managed separately from NixOS configuration
- Could be on separate partition for disk management
