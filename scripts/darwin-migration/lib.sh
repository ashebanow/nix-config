#!/usr/bin/env bash
# Shared helpers for the darwin-migration scripts. Sourced, not run directly.

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
BOLD='\033[1m'
NC='\033[0m'

log_info()   { echo -e "${BLUE}[info]${NC} $*"; }
log_ok()     { echo -e "${GREEN}[ok]${NC} $*"; }
log_warn()   { echo -e "${YELLOW}[warn]${NC} $*"; }
log_error()  { echo -e "${RED}[error]${NC} $*" >&2; }
log_action() { echo -e "${BOLD}[would run]${NC} $*"; }
log_header() { echo; echo -e "${BOLD}== $* ==${NC}"; }

SCRIPT_DIR_LIB="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC2034  # used by check.sh and mas-sync.sh
REPO_ROOT="$(cd "${SCRIPT_DIR_LIB}/../.." && pwd)"
KNOWN_HOSTS=("bergamot" "miraclemax")

# Resolve the target host: explicit $1 if given and known, else the
# machine's own hostname if it matches a known host. Exits with an
# error otherwise rather than guessing.
resolve_host() {
    local requested="${1:-}"
    local actual
    actual="$(scutil --get LocalHostName 2>/dev/null || hostname -s)"

    if [[ -n "$requested" ]]; then
        for h in "${KNOWN_HOSTS[@]}"; do
            if [[ "$h" == "$requested" ]]; then
                echo "$requested"
                return 0
            fi
        done
        log_error "Unknown host '$requested'. Known hosts: ${KNOWN_HOSTS[*]}"
        exit 1
    fi

    for h in "${KNOWN_HOSTS[@]}"; do
        if [[ "$h" == "$actual" ]]; then
            echo "$actual"
            return 0
        fi
    done

    log_error "This machine's hostname ('$actual') doesn't match a known host (${KNOWN_HOSTS[*]})."
    log_error "Pass the host explicitly as the first argument."
    exit 1
}

# Parse --dry-run / --execute from "$@". Defaults to dry-run (safe) —
# an explicit --execute is required to actually change anything.
# Sets the global DRY_RUN variable (true/false).
parse_dry_run_flag() {
    DRY_RUN=true
    for arg in "$@"; do
        case "$arg" in
            --execute) DRY_RUN=false ;;
            --dry-run) DRY_RUN=true ;;
        esac
    done
    if [[ "$DRY_RUN" == "true" ]]; then
        log_warn "Running in --dry-run mode (default). Pass --execute to actually make changes."
    else
        log_warn "Running with --execute — this WILL make changes."
    fi
}

# Pull a JSON list attribute out of a host's darwinConfiguration and
# print it as newline-separated plain strings. Avoids maintaining a
# second copy of casks/brews lists that could drift from the flake.
eval_darwin_list() {
    local host="$1" attr="$2"
    nix eval --json ".#darwinConfigurations.${host}.config.${attr}" 2>/dev/null | jq -r '.[]'
}

# Same, but for the map-shaped homebrew.masApps-style attrset (unused
# now that masApps is out of nix-darwin, kept in case that changes).
eval_darwin_attrnames() {
    local host="$1" attr="$2"
    nix eval --json ".#darwinConfigurations.${host}.config.${attr}" 2>/dev/null | jq -r 'keys[]'
}

# The nix-managed CLI package list for a host, as pnames (best-effort —
# falls back to the derivation name, which may include a version suffix).
eval_darwin_home_packages() {
    local host="$1"
    nix eval --json \
        ".#darwinConfigurations.${host}.config.home-manager.users.ashebanow.home.packages" \
        --apply 'pkgs: map (p: p.pname or p.name) pkgs' \
        2>/dev/null | jq -r '.[]'
}
