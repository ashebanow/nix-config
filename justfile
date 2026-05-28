# Build commands for lumquat NixOS configuration

# Default recipe
default: help

# Build the lumquat configuration
build:
    nix build .#nixosConfigurations.lumquat.config.system.build.toplevel

# Build from bergamot using lumquat as a remote builder
# Uses raw SSH (not Tailscale SSH). Find lumquat's Tailscale IP:
#   tailscale status | grep lumquat
# Then: just build-remote 100.x.y.z
build-remote IP:
    nix build .#nixosConfigurations.lumquat.config.system.build.toplevel --builders 'ssh://{{IP}} x86_64-linux'

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

# ── Secrets (SOPS) ────────────────────────────────────────────

# One-time: generate age key from SSH identity (run on each dev machine)
setup-age:
    #!/usr/bin/env bash
    set -euo pipefail
    mkdir -p ~/.config/sops/age
    if [ ! -f ~/.config/sops/age/keys.txt ]; then
        nix run nixpkgs#ssh-to-age -- -i ~/.ssh/id_ed25519 -private-key > ~/.config/sops/age/keys.txt
        chmod 600 ~/.config/sops/age/keys.txt
        echo "Age key written to ~/.config/sops/age/keys.txt"
    else
        echo "Age key already exists at ~/.config/sops/age/keys.txt"
    fi

# Edit secrets (decrypt, edit, re-encrypt)
secrets-edit:
    sops secrets/secrets.yaml

# Show decrypted secrets (read-only)
secrets-show:
    sops -d secrets/secrets.yaml

# Re-encrypt after changing .sops.yaml recipients
secrets-rekey:
    sops updatekeys secrets/secrets.yaml

# Run VM with the configuration
vm:
    nix run .#nixosConfigurations.lumquat.config.system.build.vm -- eval "$(nix --print-build-logs run .#nixosConfigurations.lumquat.config.system.build.toplevel --run 'cat' 2>/dev/null || echo 'echo "Build first"')"

# Deploy to lumquat (requires colmena setup)
deploy HOST="lumquat":
    colmena deploy --on {{HOST}}

# Deploy to all hosts (requires colmena setup)
deploy-all:
    colmena deploy

# Build the zmx binary (standalone, from the zmx repo)
build-zmx:
    nix build ~/Development/nix/zmx#zmx

# Health check on lumquat
health HOST="lumquat":
    colmena exec --on {{HOST}} -- sudo systemctl status tailscaled podman cockpit

# Show available recipes
help:
    @just --list
