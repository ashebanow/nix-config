# Service Patterns

## NixOS Service in Feature Module

```nix
# modules/features/tailscale.nix
_: {
  my.modules.nixos.tailscale = _: {
    services.tailscale = {
      enable = true;
      useRoutingFeatures = "server";
      authKeyFile = "/run/secrets/tailscale-auth-key"; # BWS secret (host-secrets-populate)
    };

    networking.firewall = {
      checkReversePath = "loose";
      trustedInterfaces = ["tailscale0"];
    };
  };
}
```

## Podman Container Service

```nix
# modules/features/llm-serve.nix
_: {
  my.modules.nixos.llm-serve = _: {
    virtualisation.podman = {
      enable = true;
      containers."qwen-27b" = {
        image = "ghcr.io/ggerganov/llama.cpp:server";
        autoStart = true;
        environment = {
          MODEL = "/models/qwen-27b.gguf";
          PORT = "8080";
        };
        volumes = ["/var/lib/llm-models:/models:ro"];
        devices = ["/dev/dri"];
      };
    };
  };
}
```

## Cockpit Service

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

## Monitoring (Prometheus)

```nix
# modules/features/monitoring.nix
_: {
  my.modules.nixos.monitoring = lib.mkIf config.my.hasMonitoring _: {
    services.prometheus = {
      enable = true;
      port = 9090;
    };

    services.prometheus.exporters.node = {
      enable = true;
      port = 9100;
    };
  };
}
```

## Host Config (Thin)

A host config sets capability flags and host-specific values — nothing else. Capability
flags are what turn feature modules on, through their `mkIf` guards.

```nix
# hosts/lumquat/configuration.nix
{lib, ...}: {
  my.hostName = "lumquat";

  # Capability flags — enables feature modules via mkIf guards
  my.base = true;
  my.baseUsername = "podman";
  my.llm = true;
  my.llmServe = true;
  my.monitoring = true;

  my.llmModelStorage = "/var/lib/llm-models";
  my.monitoringPort = 9090;

  # Non-hardware defaults
  networking.useDHCP = lib.mkDefault true;
}
```

Hardware facts live beside it in `hosts/<host>/hardware-configuration.nix`. Anything a
second host would also want belongs in a feature module behind a flag, not here.
