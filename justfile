#!/usr/bin/env just --justfile

# Maintenance recipes for the nix-config flake.
#
# The machine-agnostic nix recipes — clean, dry-run, switch, test,
# build-hm, nix-flake-check, nix-mas-sync — are imported from the global
# justfile
# that chezmoi installs as ~/.justfile (source: home/dot_justfile.tmpl in
# the dotfiles repo). That file dispatches on the host kind (nix-darwin
# vs NixOS) using the current hostname, so the same `just switch` works
# from anywhere on any machine, and both sets of recipes show up in
# `just --list` here.
#
# Everything below the import is scoped to this repo: flake inspection /
# formatting (show, update, fmt), and lumquat-targeted operations that
# you run from a dev machine or from a checkout (vm, secrets).
# These live here rather than in ~/.justfile because they make no sense
# on non-lumquat machines.

import "~/.justfile"

# ===== FLAKE =====

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

# Run the lumquat configuration in a VM (build first, then boot it) —
# only NixOS config in this flake, so no need to derive the hostname.
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

# Note: secretspec's `require_reason` policy (secretspec.toml [project], left at
# its default of "agents") makes it refuse to resolve secrets when it detects an
# AI agent unless a reason is supplied. The reason is the audit trail, so agents
# must pass a real ticket id and purpose, not a placeholder. Just's recipe
# arguments bind positionally, so the reason is the first (and only) argument:
#
#     just secrets-check "BOX-184: verify new declaration"
#
# Humans need no argument — the default is empty, and secretspec treats an empty
# SECRETSPEC_REASON as absent, so the policy simply doesn't apply.

# Verify every secret in the shared manifest resolves against BWS.
# Requires BWS_ACCESS_TOKEN in the environment.
[group('secrets')]
secrets-check reason="":
    SECRETSPEC_REASON="{{reason}}" secretspec check -f secretspec.toml -P production --no-prompt

# ===== LLM GATEWAY =====

# Run the bifrost reliability gate — the size/duration conditions that made
# LiteLLM unusable, plus tool-calling round trips. Pass a base URL to gate a
# different deployment (default: the served gateway hostname).
[group('llm')]
reliability-gate base_url="https://ai.fluffy-walleye.ts.net":
    python3 scripts/bifrost-reliability-gate.py {{base_url}}

# ===== TOOL PINS =====

# Rewrites `version` and both per-system hashes in lib/overlays/linear-cli.nix
# from the release assets, then re-vendors the agent skill in the dotfiles
# repo from the same tag so binary and skill never drift apart (BOX-176).
# Re-running with the current tag is a no-op. Follow up with a devshell
# `nix build` and commit BOTH repos.
# Bump the linear CLI to an upstream release tag, e.g. `just linear-bump v2.7.0`
[group('tools')]
linear-bump tag:
    #!/usr/bin/env bash
    set -euo pipefail
    tag="{{tag}}"; ver="${tag#v}"
    overlay="lib/overlays/linear-cli.nix"
    base="https://github.com/schpet/linear-cli/releases/download/v${ver}"
    grep -q 'version = "' "$overlay" || { echo "no version line in $overlay" >&2; exit 1; }

    echo "linear-bump: v${ver}"
    tmp="$(mktemp)"; trap 'rm -f "$tmp"' EXIT
    awk -v ver="$ver" '/^  version = "/ { sub(/"[^"]*"/, "\"" ver "\"") } { print }' "$overlay" > "$tmp" && mv "$tmp" "$overlay"

    # One hash per target; the hash line directly follows its target line.
    for target in $(awk -F'"' '/^ +target = "/ { print $2 }' "$overlay"); do
      hash="$(nix store prefetch-file --json --name "linear-${target}.tar.xz" "${base}/linear-${target}.tar.xz" | sed -E 's/.*"hash":"([^"]+)".*/\1/')"
      [[ "$hash" == sha256-* ]] || { echo "prefetch of ${target} returned no hash" >&2; exit 1; }
      echo "  ${target}: ${hash}"
      tmp="$(mktemp)"
      awk -v t="$target" -v h="$hash" '
        $0 ~ "^ +target = \"" t "\"" { armed = 1 }
        armed && /hash = "/ { sub(/"[^"]*"/, "\"" h "\""); armed = 0 }
        { print }' "$overlay" > "$tmp" && mv "$tmp" "$overlay"
    done

    # The vendored skill lives in the dotfiles repo and is pinned to the same tag.
    dotfiles="$(chezmoi execute-template '{{{{ .chezmoi.workingTree }}' 2>/dev/null || echo "$HOME/.local/share/chezmoi")"
    if [[ -f "$dotfiles/justfile" ]]; then
      just -f "$dotfiles/justfile" linear-vendor-skill "v${ver}"
    else
      echo "dotfiles repo not found at $dotfiles — run there: just linear-vendor-skill v${ver}" >&2
    fi

    echo
    echo "Next: nix build the devshell, then commit nix-config ($overlay) and dotfiles (home/dot_agents/skills/linear-cli)."
    git --no-pager diff --stat -- "$overlay"

# ===== MISC =====

# Build the zmx binary (standalone, from the zmx repo)
[group('misc')]
build-zmx:
    nix build ~/Development/nix/zmx#zmx

# Show available recipes
[group('misc')]
help:
    @just --list
