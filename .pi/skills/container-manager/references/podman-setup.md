# Podman Setup on NixOS

## Base Configuration

Podman is enabled in `modules/features/base.nix`:

```nix
virtualisation.podman = {
  enable = true;
  defaultNetwork.settings.dns_enabled = true;
};
```

Additional packages (podman-tui, dive, etc.) can be added to the podman
user's home-manager config or system packages as needed.

## OCI Containers (Recommended)

LLM containers use the NixOS `virtualisation.oci-containers` module with
`backend = "podman"`. This generates systemd services automatically:

```nix
# modules/features/llm.nix
virtualisation.oci-containers = {
  backend = "podman";
  containers.qwen3-27b = {
    image = "ghcr.io/ggml-org/llama.cpp:server-rocm";
    autoStart = true;
    ports = ["8080:8080"];
    # ...
  };
};
```

The module creates `podman-qwen3-27b.service` automatically.

> **Note:** We do NOT use the deprecated `virtualisation.podman.containers`
> option. The `oci-containers` module is the current supported API.

## GPU Access in Containers

For AMD RDNA 3.5 (Strix Halo), containers need:

```nix
extraOptions = [
  "--device" "/dev/dri"     # Rendering
  "--device" "/dev/kfd"     # ROCm compute
  "--group-add" "keep-groups"
  "--security-opt" "label=disable"
];
```

## Useful Commands

```bash
# List containers
podman ps -a

# View logs
podman logs qwen3-27b

# Restart container
systemctl restart podman-qwen3-27b

# Check service status
systemctl status podman-qwen3-27b

# Follow logs
journalctl -fu podman-qwen3-27b
```
