# Build commands for lumquat NixOS configuration

# Default recipe
default: help

# Build the lumquat configuration
build:
    nix build .#nixosConfigurations.lumquat

# Build Home Manager for podman user
build-hm:
    nix build .#home-managerConfigurations.podman

# Check the configuration
check:
    nix flake check

# Show the configuration
show:
    nix flake show

# Build and activate on current system (for testing)
test:
    sudo nixos-rebuild switch --flake .#lumquat

# Update flake inputs
update:
    nix flake update

# Format all Nix files
fmt:
    nix develop .# -c alejandra .

# Run VM with the configuration
vm:
    nix run .#nixosConfigurations.lumquat.config.system.build.vm -- eval "$(nix --print-build-logs run .#nixosConfigurations.lumquat.config.system.build.toplevel --run 'cat' 2>/dev/null || echo 'echo "Build first"')"

# Deploy to lumquat (requires colmena setup)
deploy HOST="lumquat":
    colmena deploy --on {{HOST}}

# Deploy to all hosts (requires colmena setup)
deploy-all:
    colmena deploy

# Health check on lumquat
health HOST="lumquat":
    colmena exec --on {{HOST}} -- sudo systemctl status tailscaled podman cockpit

# Show available recipes
help:
    @just --list
