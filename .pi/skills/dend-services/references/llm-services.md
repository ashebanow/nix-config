# LLM Service Architecture

## Container Strategy

Lumquat uses separate containers per LLM model for:
- Independent scaling
- Isolated resource management
- Easier model updates

## Current LLM Containers

| Container | Model | Port | Purpose |
|-----------|-------|------|---------|
| qwen-27b | Qwen-27B | 8080 | Coding assistance |
| deepseek-v4 | DeepSeek v4 | 8081 | Planning, multimodal |

## Feature Module Structure

```nix
# modules/features/llm-serve.nix
_: {
  my.modules.nixos.llm-serve = _: {
    virtualisation.podman = {
      enable = true;
      containers = {
        qwen-27b = {
          image = "ghcr.io/ggerganov/llama.cpp:server";
          autoStart = true;
          environment = {
            MODEL = "/models/qwen-27b-q4_k_m.gguf";
            HOST = "127.0.0.1";  # Localhost only
            PORT = "8080";
          };
          volumes = ["/var/lib/llm-models:/models:ro"];
          devices = ["/dev/dri"];  # AMD GPU
        };

        deepseek-v4 = {
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
      };
    };
  };
}
```

## Access Control

All LLM traffic routes through Tailscale Aperture:
- Containers bind to `127.0.0.1`, not `0.0.0.0`
- Tailscale handles authentication
- No direct internet exposure

## Model Storage

```
/var/lib/llm-models/
├── qwen-27b-q4_k_m.gguf
└── deepseek-v4-q4_k_m.gguf
```

Mount as read-only into containers.

## GPU Memory

Strix Halo has 128 GB unified memory:
- ~124 GB exposed to GPU via `amdgpu.gttsize=126976`
- Sufficient for running multiple 27B+ models simultaneously
