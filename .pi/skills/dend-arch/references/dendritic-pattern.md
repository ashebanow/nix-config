# Dendritic Pattern Deep Dive

## Concept

The dendritic pattern names branches that connect back to a central structure:

```
         Top-Level Configuration
              (flake-parts)
                    │
    ┌───────────────┼───────────────┐
    │               │               │
┌───┴───┐     ┌─────┴─────┐   ┌─────┴─────┐
│meta   │     │ nixos-    │   │  hm-      │
│module │     │ base      │   │  shells   │
└───────┘     └───────────┘   └───────────┘
```

## Key Mechanism: deferredModule

The `deferredModule` type allows module definitions to be composed and merged
before they're evaluated in their target context.

```nix
# modules/infra/module-containers.nix
{lib, ...}: {
  options.my.modules = {
    nixos = lib.mkOption {
      type = lib.types.lazyAttrsOf lib.types.deferredModule;
      default = {};
    };
    home-manager = lib.mkOption {
      type = lib.types.lazyAttrsOf lib.types.deferredModule;
      default = {};
    };
  };
}
```

## Feature Registration

```nix
# modules/features/nixos-base.nix
_: {
  my.modules.nixos.base = _: {
    # This is a deferred module fragment
    # It will be composed into host NixOS configurations
    time.timeZone = lib.mkDefault "America/New_York";
    environment.systemPackages = with pkgs; [btop];
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
      # Infrastructure
      inputs.self.nixosModules.nixos-infra
      # Feature modules (collected and composed)
      inputs.self.nixosModules.base
      inputs.self.nixosModules.llm-serve
      # Host-specific
      ./hardware-configuration.nix
    ];
  };
}
```

## Anti-Pattern: specialArgs Chains

The dendritic pattern eliminates threading values through `specialArgs` chains:

```
Traditional: flake → specialArgs → nixos → specialArgs → home-manager
Dendritic:   all files are top-level modules, read config directly
```
