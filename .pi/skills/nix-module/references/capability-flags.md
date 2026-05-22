# Capability Flags Reference

Capability flags are defined in `lib/my-options-module.nix` and used by feature modules to conditionally activate.

## Standard Flags

| Flag | Purpose |
|------|---------|
| `my.hasDesktop` | Host has a graphical desktop environment |
| `my.hasNvidia` | Host has NVIDIA GPU |
| `my.hasMonitoring` | Host should have monitoring enabled |
| `my.hostName` | The hostname of the current host |

## Usage in Feature Modules

```nix
# Enable a feature only on desktops
config = lib.mkIf config.my.hasDesktop {
  services.some-desktop-app.enable = true;
};

# Check hostname for host-specific logic
config = lib.mkIf (config.my.hostName == "lumquat") {
  # Only applies to lumquat
};
```

## Adding New Flags

Flags are defined in `lib/my-options-module.nix`:

```nix
{lib, ...}: {
  options.my = {
    hasCustomFlag = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Whether this host has custom capability";
    };
  };
}
```

Then set in host definition:

```nix
# modules/hosts/lumquat.nix
config.my.hasCustomFlag = true;
```
