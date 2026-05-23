# Claude Code Agent Context — Lumquat NixOS Configuration

## Project Overview

Lumquat is an AI server running NixOS on a GMKTec Evo X2 (Strix Halo mini PC) with:
- AMD Ryzen AI Max (Strix Halo), 128GB unified memory
- AMD RDNA 3.5 integrated GPU
- LUKS-encrypted root with systemd-boot

## Architecture

This configuration follows a **simplified dendritic pattern**:
- **Capability flags** defined centrally in `lib/my-options-module.nix`
- **Feature modules** in `modules/features/*.nix` — self-contained with `lib.mkIf` guards
- **Host configuration** in `hosts/lumquat.nix` — sets capability flags

## Key Files

```
.
├── flake.nix                    # NixOS + Home Manager configuration
├── lib/
│   └── my-options-module.nix   # Central capability flags (my.* options)
├── modules/features/
│   ├── base.nix                # Server foundation (users, SSH, podman)
│   ├── access.nix              # Tailscale VPN + SSH
│   ├── llm.nix                 # LLM container support
│   ├── monitoring.nix          # Cockpit web UI
│   ├── secrets.nix             # SOPS-nix integration
│   └── cli-tools.nix           # Home Manager CLI tools
└── hosts/lumquat/
    ├── lumquat.nix             # Host capability flags
    └── hardware-configuration.nix  # Strix Halo kernel params
```

## Dendritic Pattern Principles

1. **Capability flags** gate features — use `lib.mkIf config.my.<feature>` in modules
2. **Self-contained modules** — each feature defines its own options and config
3. **Host-specific config** — only sets capability flags, no imperative NixOS config

## Building

```bash
# Evaluate configuration
nix flake check

# Build system (needs Linux)
nix build .#nixosConfigurations.lumquat

# Deploy (needs Linux + SSH access)
nixos-rebuild switch --flake .#lumquat
```

## Feature Modules

| Module | Capability Flag | Purpose |
|--------|-----------------|---------|
| `base.nix` | `my.base` | Users, SSH, podman, timezone |
| `access.nix` | `my.access` | Tailscale, firewall, fallback SSH |
| `llm.nix` | `my.llm` | GPU passthrough, container support |
| `monitoring.nix` | `my.monitoring` | Cockpit web UI |
| `secrets.nix` | *(auto)* | SOPS-nix for secrets |
| `cli-tools.nix` | `my.cliTools` | Home Manager CLI tools |

## Strix Halo Kernel Parameters

Required in `hardware-configuration.nix`:
```nix
boot.kernelParams = [
  "amd_iommu=off"           # Strix Halo stability
  "amdgpu.gttsize=126976"  # ~124GB VRAM
  "ttm.pages_limit=32505856" # Full memory pool
];
```

## Known Issues

- Home Manager configuration requires running on Linux (can't build on macOS)
- Hardware UUIDs (`YOUR-LUKS-UUID-HERE`, etc.) must be filled in before deployment
