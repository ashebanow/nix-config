# Capability Flags Reference

Capability flags control which features activate on which hosts.

## Standard Flags

| Flag | Type | Default | Purpose |
|------|------|---------|---------|
| `my.hostName` | string | — | Hostname |
| `my.hasDesktop` | bool | false | Graphical desktop |
| `my.hasNvidia` | bool | false | NVIDIA GPU |
| `my.hasMonitoring` | bool | false | Monitoring enabled |

## Defining Flags

```nix
# lib/my-options-module.nix
{lib, ...}: {
  options.my = {
    hostName = lib.mkOption {
      type = lib.types.str;
      description = "Hostname of this system";
    };

    hasDesktop = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Whether this host has a desktop environment";
    };
  };
}
```

## Setting Flags

```nix
# modules/hosts/lumquat.nix
{...}: {
  config = {
    my.hostName = "lumquat";
    my.hasMonitoring = true;
  };
}
```

## Using Flags

```nix
# In feature modules
config = lib.mkIf config.my.hasMonitoring {
  # Only applies when monitoring is enabled
  services.prometheus.exporters.node.enable = true;
};
```

## Flag Naming Conventions

- Prefix with `has` for booleans: `hasDesktop`, `hasNvidia`
- Use singular nouns: `hasMonitoring`, not `hasMonitorings`
- Be specific: `hasAmdGpu` > `hasGpu`
