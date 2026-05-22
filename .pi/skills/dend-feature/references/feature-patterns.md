# Feature Module Patterns

## Correct NixOS Feature Module

```nix
# modules/features/nixos-base.nix
_: {
  my.modules.nixos.base = _: {
    time.timeZone = lib.mkDefault "America/New_York";
    environment.systemPackages = with pkgs; [btop];
  };
}
```

## Correct HM Feature Module

```nix
# modules/features/hm-shells.nix
_: {
  my.modules.home-manager.shells = _: {
    programs.zsh.enable = true;
    programs.fish.enable = true;
  };
}
```

## Cross-Cutting Feature (NixOS + HM)

```nix
# modules/features/tailscale.nix
_: {
  my.modules.nixos.tailscale = _: {
    services.tailscale = {
      enable = true;
      useRoutingFeatures = "server";
    };
  };

  my.modules.home-manager.tailscale = _: {
    # HM-specific tailscale config if needed
  };
}
```

## Feature with Capability Guard

```nix
# modules/features/cockpit.nix
_: {
  my.modules.nixos.cockpit = _: {
    services.cockpit = {
      enable = true;
      port = 9090;
    };

    environment.systemPackages = with pkgs; [
      cockpit-podman
    ];
  };
}
```

## Common Mistakes

### Missing Registration

```nix
# WRONG: Module doesn't register
_: {
  # Missing: my.modules.nixos.example
  services.example.enable = true;
}

# RIGHT: Registers into container
_: {
  my.modules.nixos.example = _: {
    services.example.enable = true;
  };
}
```

### Hostname Check Instead of Flag

```nix
# WRONG: Hostname check
_: {
  my.modules.nixos.example = _: {
    config = lib.mkIf (config.my.hostName == "lumquat") {
      # ...
    };
  };
}

# RIGHT: Capability flag
_: {
  my.modules.nixos.example = lib.mkIf config.my.hasMonitoring _: {
    # ...
  };
}
```

## Testing Feature Modules

```bash
# Check eval
nix eval .#nixosModules.example

# Build config to test
nix build .#nixosConfigurations.lumquat.config.system.build.toplevel
```
