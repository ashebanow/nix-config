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

## Colmena Host Config (Thin)

```nix
# modules/hosts/lumquat.nix
{inputs, ...}: {
  configurations.nixos.lumquat = {
    system = "x86_64-linux";
    modules = [
      inputs.self.nixosModules.nixos-infra
      inputs.self.nixosModules.nixos-base
      inputs.self.nixosModules.podman-base
      inputs.self.nixosModules.llm-serve
      inputs.self.nixosModules.tailscale
      inputs.self.nixosModules.cockpit
      ./hardware-configuration.nix
    ];
  };

  config.my = {
    hostName = "lumquat";
    hasMonitoring = true;
  };
}
```
