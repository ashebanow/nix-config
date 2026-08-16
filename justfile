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
        nh os build {{ FILES }} .#lumquat
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

# ===== SECRETS (BWS + secretspec) =====

# One-time bootstrap: install the BWS access token on a host as a root-only
# file. The token is from the "chezmoi" machine account in the BW Secrets
# Manager Homelab project (see SECRET_SYNC.md). Never committed anywhere.
# Usage: just bootstrap-bws [HOST]   (default: lumquat)
# Works from a dev machine (SSH to root@HOST) or on the host itself (local
# passwordless sudo for the podman user).
bootstrap-bws HOST="lumquat":
    #!/usr/bin/env bash
    set -euo pipefail
    read -rsp "BWS access token (chezmoi machine account): " token; echo
    [[ -n "$token" ]] || { echo "error: empty token" >&2; exit 1; }
    # BWS access tokens look like: 0.<base64url-key>.<base64url-mac> (~90 chars).
    # Validate before writing so a wrong paste fails here, not at boot.
    [[ "$token" =~ ^0\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+$ ]] || {
        echo "error: that does not look like a BWS access token (expected 0.<key>.<mac>)" >&2
        echo "       get it from: BW console → Secrets Manager → Homelab → Machine Accounts → chezmoi → Access Tokens" >&2
        exit 1
    }
    if [[ "$(hostname)" == "{{HOST}}" || "$(hostname -s)" == "{{HOST}}" ]]; then
        # Running ON the target host — install locally with sudo. Never SSH
        # back to ourselves: root SSH is disabled and podman's key isn't in
        # root's authorizedKeys (only the dev machine's key is).
        echo "Installing locally on $(hostname) ..."
        sudo install -d -m 0700 /var/lib/secrets
        # No trailing newline: bws rejects the token if one is present.
        printf '%s' "$token" | sudo sh -c 'umask 077 && cat > /var/lib/secrets/bws-access-token'
    else
        # Running on a dev machine — pipe the token over SSH to root@HOST.
        echo "Installing on {{HOST}} over SSH ..."
        printf '%s' "$token" | ssh "root@{{HOST}}" 'install -d -m 0700 /var/lib/secrets && umask 077 && cat > /var/lib/secrets/bws-access-token'
    fi
    echo "Bootstrap token installed at {{HOST}}:/var/lib/secrets/bws-access-token"

# Verify every secret in the shared manifest resolves against BWS.
# Requires BWS_ACCESS_TOKEN in the environment.
secrets-check:
    secretspec check -f secretspec.toml -P production --no-prompt

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

# ===== WINDSHIFT =====

# Windshift admin shell: resolve the production postgres secrets from BWS and
# run a command against the windshift-db container (psql, migrations, ad-hoc
# queries). Needs BWS_ACCESS_TOKEN in the shell (e.g. from a `bws`/Bitwarden
# login). Uses the [profiles.production] route in the repo-root
# secretspec.toml — the operator's token, deliberately NOT a file on disk.
# The command runs via `bash -c`: $POSTGRES_* references expand in the child
# AFTER secretspec injects the resolved values into its environment, so the
# secret values never appear in argv or in this recipe's own environment.
# Custom cmds: use double quotes for SQL literals (a single quote would end
# the wrapper's quoting).
windshift-admin cmd='podman exec -i windshift-db env PGPASSWORD=$POSTGRES_PASSWORD psql -U $POSTGRES_USER -d $POSTGRES_DB':
    #!/usr/bin/env bash
    set -euo pipefail
    if [ -z "${BWS_ACCESS_TOKEN:-}" ]; then
        echo "BWS_ACCESS_TOKEN is not set — source it first (bws login)" >&2
        exit 1
    fi
    SECRETSPEC_FILE=secretspec.toml
    SECRETSPEC_PROFILE=production
    SECRETSPEC_PROVIDER=bws
    secretspec run -- bash -c '{{cmd}}'

# Start the windshift stack (app + postgres + tailscale sidecar).
# The containers are rootless quadlet USER units under the `podman` user
# (~/.config/containers/systemd). Run as root (sudo) or as the podman user
# (e.g. `ssh lumquat`).
windshift-start:
    #!/usr/bin/env bash
    set -euo pipefail
    # Resolve `systemctl --user` for root (sudo -u podman + XDG_RUNTIME_DIR)
    # vs. the podman user itself (e.g. an ssh session as podman@lumquat).
    if [[ "$(id -u)" -eq 0 ]]; then
        SYSTEMCTL=(sudo -u podman env XDG_RUNTIME_DIR="/run/user/$(id -u podman)" systemctl --user)
    elif [[ "$(id -un)" == "podman" ]]; then
        SYSTEMCTL=(systemctl --user)
    else
        echo "error: run as root or as the podman user (ssh lumquat)" >&2
        exit 1
    fi
    "${SYSTEMCTL[@]}" start windshift.service windshift-db.service windshift-tailscale.service

# Stop the windshift stack (app + postgres + tailscale sidecar).
windshift-stop:
    #!/usr/bin/env bash
    set -euo pipefail
    if [[ "$(id -u)" -eq 0 ]]; then
        SYSTEMCTL=(sudo -u podman env XDG_RUNTIME_DIR="/run/user/$(id -u podman)" systemctl --user)
    elif [[ "$(id -un)" == "podman" ]]; then
        SYSTEMCTL=(systemctl --user)
    else
        echo "error: run as root or as the podman user (ssh lumquat)" >&2
        exit 1
    fi
    "${SYSTEMCTL[@]}" stop windshift.service windshift-db.service windshift-tailscale.service

# Restart the windshift stack (app + postgres + tailscale sidecar).
windshift-restart:
    #!/usr/bin/env bash
    set -euo pipefail
    if [[ "$(id -u)" -eq 0 ]]; then
        SYSTEMCTL=(sudo -u podman env XDG_RUNTIME_DIR="/run/user/$(id -u podman)" systemctl --user)
    elif [[ "$(id -un)" == "podman" ]]; then
        SYSTEMCTL=(systemctl --user)
    else
        echo "error: run as root or as the podman user (ssh lumquat)" >&2
        exit 1
    fi
    "${SYSTEMCTL[@]}" restart windshift.service windshift-db.service windshift-tailscale.service

# ===== MISC =====

# Build the zmx binary (standalone, from the zmx repo)
build-zmx:
    nix build ~/Development/nix/zmx#zmx

# Show available recipes
help:
    @just --list
