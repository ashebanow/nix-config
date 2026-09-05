#!/usr/bin/env just --justfile

# Maintenance recipes for the nix-config flake.
#
# The machine-agnostic nix recipes — clean, dry-run, switch, build-hm,
# nix-flake-check, nix-mas-sync — are imported from the global justfile
# that chezmoi installs as ~/.justfile (source: home/dot_justfile.tmpl in
# the dotfiles repo). That file dispatches on the host kind (nix-darwin
# vs NixOS) using the current hostname, so the same `just switch` works
# from anywhere on any machine, and both sets of recipes show up in
# `just --list` here.
#
# Everything below the import is scoped to this repo: flake inspection /
# formatting (show, update, fmt), and lumquat-targeted operations that
# you run from a dev machine or from a checkout (build, test, vm, deploy,
# secrets). These live here rather than in ~/.justfile because they make
# no sense on non-lumquat machines.

import "~/.justfile"

# ===== BUILD / SWITCH =====

# Build the lumquat configuration (nh os build when available)
[group('nix')]
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
[group('nix')]
build-remote: build

# Build and activate on the current system WITHOUT making it the boot
# default — a true test of a new generation. Must run on lumquat.
[group('nix')]
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

[group('nix')]
show:
    nix flake show

[group('nix')]
update:
    nix flake update

# Format all Nix files
[group('nix')]
fmt:
    nix develop .# -c alejandra .

# Run the configuration in a VM (build first, then boot it)
[group('nix')]
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
[group('secrets')]
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
[group('secrets')]
secrets-check:
    secretspec check -f secretspec.toml -P production --no-prompt

# ===== MISC =====

# Build the zmx binary (standalone, from the zmx repo)
[group('misc')]
build-zmx:
    nix build ~/Development/nix/zmx#zmx

# Show available recipes
[group('misc')]
help:
    @just --list
