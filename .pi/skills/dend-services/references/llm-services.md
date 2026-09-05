# LLM Service Architecture

## Container Strategy

LLM containers are declared declaratively in `modules/features/llm.nix` using
the NixOS `virtualisation.oci-containers` module with podman backend. Containers
run **rootless** under the `podman` user (`podman.user = cfg.baseUsername`).

Image: `docker.io/kyuz0/amd-strix-halo-toolboxes:rocm-10.0`
- ROCm 10.0 (Fedora 44, AMD-supported gfx1151 SDK) — stable toolbox
- MTP (Multi-Token Prediction) merged into llama.cpp mainline (the legacy
  `-mtp` fork toolboxes are deprecated)
- https://github.com/kyuz0/amd-strix-halo-toolboxes

## Current LLM Containers

| Container | Model | Quant | Port | Context pool | Systemd Service |
|-----------|-------|-------|------|--------------|-----------------|
| qwen-35b-a3b | Qwen 3.8 27B (dense, hybrid thinking) | UD-Q8_K_XL | 8080 | 4 slots × 256K (1M total) | `podman-qwen-35b-a3b.service` |

Model catalog lives in `lib/models.nix` (adapted from Doug Campos'
[nixifying-local-llms](https://random.qmx.me/posts/2026/01/08/nixifying-local-llms/)):

- **`ggufs`**: SHA256-verified models fetched via Nix (`pkgs.fetchurl`) and
  mounted read-only into the container at `/models/<file>.gguf`. The qwen model
  is currently promoted.
- **`models`**: metadata-only entries; unpromoted models are downloaded on
  demand by llama.cpp via the `-hf` flag into `${modelsDir}` (the HF cache).

Promotion workflow: add to `models` → experiment via `-hf` → compute the SHA256
(`nix-hash --flat --type sha256 <file> | nix-to-sri`) → fill in `ggufs.sha256` →
the model becomes a Nix derivation shared via the cache.

## Container Options (llm.nix)

Shared container options (`baseOptions`) — required for the ROCm stack:

```nix
--device /dev/dri          # rendering
--device /dev/kfd          # ROCm compute
--group-add video
--group-add render
--security-opt seccomp=unconfined
```

Shared llama-server flags (`baseFlags`) — critical for Strix Halo:

```nix
-fa on         # Flash attention (on|off|auto in newer llama-server)
--no-mmap      # required for stability
--metrics      # Prometheus endpoint on :8080/metrics
--timeout 0    # disable HTTP read timeout (long idle)
--cache-ram 0  # no unified KV LRU cache — KV stays in VRAM
```

Per-model flags (qwen-35b-a3b, `models.nix`):

```nix
-np 4                      # 4 parallel slots (256K each, 1M total pool)
--jinja                    # Jinja template engine
--spec-type draft-mtp      # MTP speculative decoding (built-in MTP heads)
--spec-draft-n-max 2       # draft 2 tokens per step
--cache-type-k q4_0        # Q4 KV cache (~4x reduction vs F16)
--cache-type-v q4_0
--temp 1.0                 # Qwen3.8 thinking-mode sampling (unsloth docs)
--top-p 0.95
--top-k 20
--min-p 0.0
--presence-penalty 0.0
--reasoning-effort medium  # balance accuracy vs speed (unsloth example)
```

Sampling follows the [Qwen3.8 recommended thinking-mode settings](https://unsloth.ai/docs/models/qwen3.8)
(`temperature=1.0, top_p=0.95, top_k=20, min_p=0.0, presence_penalty=0.0,
repetition_penalty=1.0` — the last is llama.cpp's default). The instruct/
non-thinking set (`temp=0.7, top_p=0.80, presence_penalty=1.5`) is available
per-request if needed.

The container has a health check (`curl :8080/health`, 30s interval, 60 retries,
120s start period) so the model is preloaded before first real query.

## GPU Memory

Strix Halo has 128 GB unified memory:
- ~124 GB exposed to GPU via `amdgpu.gttsize=126976` (see
  `hosts/lumquat/hardware-configuration.nix`)
- Qwen3.8-27B UD-Q8_K_XL ≈ 31 GB weights (unsloth hardware table: 8-bit ≈ 31 GB)
- 1M total context at q4_0 KV fits alongside the weights in VRAM
- Strix Halo stability params: `amd_iommu=off`, `amdgpu.gttsize`, `ttm.pages_limit`
- kyuz0 recommends kernel ≥ 6.18.9 (lumquat runs 6.18.46) and warns against
  `linux-firmware-20251125` (breaks ROCm on gfx1151)

## Access / Serving

- Containers bind `0.0.0.0` inside the container (mapped to host port 8080)
- Firewall control via `modules/features/access.nix`; external access via Tailscale
- `tailscale-llm-serve.service` publishes each model:
  `https://lumquat.fluffy-walleye.ts.net/qwen-35b-a3b` → `http://localhost:8080`

## LiteLLM Proxy

`litellm-compose.service` (compose file: `compose/llm/compose.yml`, symlinked to
`/etc/litellm/`) runs a pinned `ghcr.io/berriai/litellm:v1.97.0` image with a
Tailscale sidecar, served at `https://litellm.fluffy-walleye.ts.net`. It routes
model names → local llama.cpp backends and remote providers (deepseek-*,
minimax-*, claude-*). Two aliases point at the same llama-server:
`qwen-35b-a3b` (legacy, back compat) and `qwen-latest` (generic). Secrets are
injected from BWS via secretspec (`litellm` scope) at start; no `.env` files.

## Adding a Second Model

1. Add the model to the `models` attrset in `lib/models.nix` (unique `port`)
2. Add a container entry in `modules/features/llm.nix` via `mkContainer`
   (health-check extraOptions if you want preloading)
3. Optionally promote it into `ggufs` with a SHA256
4. Add a litellm model route in `compose/llm/litellm-config.yaml`
5. `just dry-run` to validate the config on lumquat, then `just switch`
