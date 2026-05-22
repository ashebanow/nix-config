# Dendritic Pattern Overview

The dendritic pattern organizes Nix configurations by **feature**, not by configuration class.

## Core Principle

Every Nix file (except entry points like `flake.nix` and `default.nix`) is a module of a single top-level configuration. Each file implements a single feature across all configuration classes.

## Directory Layout

```
modules/
├── infra/
│   ├── module-containers.nix    # deferredModule containers
│   ├── nixos-infra.nix          # System builder
│   └── ...
├── features/                     # One file per feature
│   ├── nixos-base.nix           # Base config (all hosts)
│   ├── llm-serve.nix            # LLM serving
│   ├── tailscale.nix            # Tailscale VPN
│   └── ...
└── hosts/
    ├── lumquat.nix              # lumquat composition
    └── hardware-configuration.nix
```

## Feature Module Structure

```nix
# modules/features/llm-serve.nix
_: {
  my.modules.nixos.llm-serve = {config, pkgs, ...}: {
    virtualisation.podman.containers.qwen-27b = {
      image = "ghcr.io/ggerganov/llama.cpp:server";
      autoStart = true;
      # ...
    };
  };
}
```

## Host Composition

```nix
# modules/hosts/lumquat.nix
{inputs, ...}: {
  configurations.nixos.lumquat = {
    system = "x86_64-linux";
    modules = [
      inputs.self.nixosModules.nixos-infra
      inputs.self.nixosModules.nixos-base
      inputs.self.nixosModules.llm-serve
      # Host-specific
      ./hardware-configuration.nix
    ];
  };
}
```

## Key Benefits

1. **File type is always known** — every non-entry-point is a flake-parts module
2. **Automatic importing** — import-tree handles all imports
3. **Path independence** — paths represent features, not config types
