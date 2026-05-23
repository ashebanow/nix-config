# Claude Code Agent Context — Lumquat NixOS Configuration

## Project Overview

Lumquat is an AI server running NixOS on a GMKTec Evo X2 (Strix Halo mini PC) with:
- AMD Ryzen AI Max (Strix Halo), 128GB unified memory
- AMD RDNA 3.5 integrated GPU
- LUKS-encrypted root with systemd-boot

## Architecture

This configuration follows the **dendritic pattern** with auto-discovery:

```
flake.nix
  └── flake-parts + import-tree
        ├── modules/infra/
        │   ├── module-containers.nix   # Deferred module containers
        │   └── nixos-infra.nix        # NixOS + HM configuration
        └── modules/features/
              ├── base.nix
              ├── access.nix
              ├── llm.nix
              ├── monitoring.nix
              ├── secrets.nix
              └── cli-tools.nix
```

### Key Files

| File | Purpose |
|------|---------|
| `flake.nix` | Entry point with flake-parts + import-tree |
| `lib/my-options-module.nix` | Centralized capability flags (`my.*`) |
| `modules/infra/module-containers.nix` | Defines `my.modules.nixos.*` containers |
| `modules/infra/nixos-infra.nix` | Host configuration + NixOS/HM builders |
| `modules/features/*.nix` | Self-contained feature modules |

## Dendritic Pattern

1. **Auto-discovery** via `import-tree` in flake.nix
2. **Feature modules** register into `my.modules.nixos.*` or `my.modules.home-manager.*`
3. **Capability flags** gate features: `lib.mkIf config.my.<feature>`
4. **Deferred modules** collected and composed in nixos-infra.nix

## Feature Modules

| Module | Container | Capability Flag |
|--------|----------|-----------------|
| `base.nix` | `my.modules.nixos.base` | `my.base` |
| `access.nix` | `my.modules.nixos.access` | `my.access` |
| `llm.nix` | `my.modules.nixos.llm` | `my.llm` |
| `monitoring.nix` | `my.modules.nixos.monitoring` | `my.monitoring` |
| `secrets.nix` | `my.modules.nixos.secrets` | *(auto)* |
| `cli-tools.nix` | `my.modules.home-manager.cli-tools` | `my.cliTools` |

## Building

```bash
# Evaluate configuration
nix flake check

# Build system (needs Linux)
nix build .#nixosConfigurations.lumquat

# Deploy (needs Linux + SSH access)
nixos-rebuild switch --flake .#lumquat
```

## Strix Halo Kernel Parameters

Required kernel params (defined in nixos-infra.nix):
```nix
boot.kernelParams = [
  "amd_iommu=off"           # Strix Halo stability
  "amdgpu.gttsize=126976"  # ~124GB VRAM
  "ttm.pages_limit=32505856" # Full memory pool
];
```

## Known Issues

- Home Manager configuration requires running on Linux
- Hardware UUIDs (`YOUR-LUKS-UUID-HERE`, etc.) must be filled in before deployment
