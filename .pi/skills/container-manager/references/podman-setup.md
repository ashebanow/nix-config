# Podman Setup on NixOS

## Base Configuration

```nix
# modules/features/podman-base.nix
_: {
  my.modules.nixos.podman-base = _: {
    environment.systemPackages = with pkgs; [
      podman-tui      # Terminal UI for podman
      dive             # Image layer inspection
    ];

    virtualisation = {
      containers.enable = true;
      podman = {
        enable = true;
        dockerCompat = true;  # docker CLI compatibility
        defaultNetwork.settings.dns_enabled = true;
      };
    };
  };
}
```

## Quadlets vs docker-compose

This project uses NixOS quadlet options, NOT docker-compose files.
Quadlets are systemd unit files for containers, managed declaratively in Nix.

```nix
# RIGHT: Quadlet via NixOS module
virtualisation.podman.containers.myapp = {
  image = "docker.io/library/nginx";
  ports = ["8080:80"];
};

# WRONG: docker-compose approach (not used here)
```

## Rootless Podman

Podman runs rootless by default on NixOS. No daemon required.

## GPU Access in Rootless

For AMD GPUs in rootless podman:
```nix
devices = ["/dev/dri"];  # Pass through /dev/dri device
```

## Auto-Update

Enable auto-update for container images:
```nix
virtualisation.podman.enable = true;
# Container-level:
autoStart = true;
```

## Useful Commands

```bash
# List containers
podman ps -a

# View logs
podman logs <container>

# Restart container
podman restart <container>

# Inspect image layers
dive <image>
```
