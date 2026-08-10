#!/usr/bin/env just --justfile

# Build commands for the lumquat NixOS configuration.
# Build/switch recipes use `nh` when available, falling back to
# nixos-rebuild, then raw nix — matching the chezmoi justfile's
# behavior for the darwin hosts.

# Default recipe to show available commands
default: help

# ===== BUILD / SWITCH =====

# Build the lumquat configuration (nh os build when available)
build:
    #!/usr/bin/env bash
    set -euo pipefail
    if command -v nh >/dev/null 2>&1; then
        nh os build .#lumquat
    elif command -v nixos-rebuild >/dev/null 2>&1; then
        nixos-rebuild build --flake .#lumquat
    else
        nix build .#nixosConfigurations.lumquat.config.system.build.toplevel
    fi

# Build from a machine that uses lumquat as a remote builder
# (configured in /etc/nix/nix.conf). Same recipe as build — nix/nh
# pick up the remote builder from the daemon config.
build-remote: build

# Build Home Manager for the podman user
build-hm:
    #!/usr/bin/env bash
    set -euo pipefail
    if command -v nh >/dev/null 2>&1; then
        nh home build . --configuration podman
    else
        nix build .#homeConfigurations.podman.activationPackage
    fi

# Preview what a switch would change, without applying it. Builds the
# config (no sudo needed) and diffs the closure against the active
# generation — only meaningful when run on lumquat itself.
dry-run *FILES:
    #!/usr/bin/env bash
    set -euo pipefail
    if command -v nh >/dev/null 2>&1; then
        nh os build {{ FLAGS }} .#lumquat
    elif command -v nixos-rebuild >/dev/null 2>&1; then
        nixos-rebuild build --flake .#lumquat
    else
        nix build .#nixosConfigurations.lumquat.config.system.build.toplevel
    fi
    echo
    if [[ -e /run/current-system ]] && [[ "$(hostname -s)" == "lumquat" ]]; then
        echo "=== Changes vs. the currently active generation ==="
        nix store diff-closures /run/current-system ./result
    else
        echo "=== No active generation to diff against (not run on lumquat, or never switched) ==="
    fi

# Build and activate on the current system, and make it the boot default.
# Must run on lumquat itself; from another machine use `deploy` instead.
switch *FLAGS:
    #!/usr/bin/env bash
    set -euo pipefail
    if [[ "$(hostname -s)" != "lumquat" ]]; then
        echo "error: switch must run on lumquat (this is $(hostname -s)); from another machine use 'just deploy' instead" >&2
        exit 1
    fi
    if command -v nh >/dev/null 2>&1; then
        nh os switch {{ FLAGS }} .#lumquat
    elif command -v nixos-rebuild >/dev/null 2>&1; then
        sudo nixos-rebuild switch --flake .#lumquat
    else
        nix run nixpkgs#nixos-rebuild -- switch --flake .#lumquat
    fi

# Build and activate on the current system WITHOUT making it the boot
# default — a true test of a new generation. Must run on lumquat.
test:
    #!/usr/bin/env bash
    set -euo pipefail
    if [[ "$(hostname -s)" != "lumquat" ]]; then
        echo "error: test must run on lumquat (this is $(hostname -s))" >&2
        exit 1
    fi
    if command -v nh >/dev/null 2>&1; then
        nh os test .#lumquat
    elif command -v nixos-rebuild >/dev/null 2>&1; then
        sudo nixos-rebuild test --flake .#lumquat
    else
        nix run nixpkgs#nixos-rebuild -- test --flake .#lumquat
    fi

show:
    nix flake show

update:
    nix flake update

clean:
    #!/usr/bin/env bash
    if command -v nh >/dev/null 2>&1; then
        nh clean all
    elif command -v nixos-rebuild >/dev/null 2>&1; then
        sudo nix-env --delete-generations 14d
        nix store gc
    else
        sudo nix run nixpkgs#nix-env -- delete-generations 14d
        nix store gc
    fi

# Format all Nix files
fmt:
    nix develop .# -c alejandra .

# Run the configuration in a VM (build first, then boot it)
vm:
    #!/usr/bin/env bash
    set -euo pipefail
    nix build .#nixosConfigurations.lumquat.config.system.build.vm
    ./result/bin/run-lumquat-vm

# ===== SECRETS (SOPS) =====

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

# ===== DEPLOY (from a dev machine, via colmena) =====

# Deploy to lumquat (requires colmena setup)
deploy HOST="lumquat":
    colmena deploy --on {{HOST}}

# Deploy to all hosts (requires colmena setup)
deploy-all:
    colmena deploy

# Health check on lumquat
health HOST="lumquat":
    colmena exec --on {{HOST}} -- sudo systemctl status tailscaled podman cockpit

# ===== MISC =====

# Build the zmx binary (standalone, from the zmx repo)
build-zmx:
    nix build ~/Development/nix/zmx#zmx

# Show available recipes
help:
    @just --list
