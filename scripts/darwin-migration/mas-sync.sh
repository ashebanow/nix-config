#!/usr/bin/env bash
# Install Mac App Store apps declared in hosts/<host>/mas-apps.txt.
# Run directly by you, NOT via sudo/darwin-rebuild — mas/installd
# needs your logged-in user session, which is exactly why masApps
# isn't declared in nix-darwin's homebrew module for these hosts (it
# fails under the root session darwin-rebuild switch runs as).
#
# Install-only. Never uninstalls anything — see check.sh's report for
# MAS apps that are installed but not declared; removing those (if you
# want to) is a manual, deliberate action, not something this script
# does for you.
#
# Usage: ./mas-sync.sh [hostname] [--dry-run|--execute]
#   Defaults to --dry-run. Pass --execute to actually install.

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "${SCRIPT_DIR}/lib.sh"

HOST_ARG=""
for a in "$@"; do
    [[ "$a" != --* ]] && HOST_ARG="$a"
done
HOST="$(resolve_host "$HOST_ARG")"
parse_dry_run_flag "$@"

MAS_FILE="${REPO_ROOT}/hosts/${HOST}/mas-apps.txt"
log_header "MAS sync for ${HOST}"

if ! command -v mas >/dev/null 2>&1; then
    log_error "mas not found. Install it first (it's declared as a nix package"
    log_error "under cli-* modules if you added it, or: brew install mas)."
    exit 1
fi

if [[ ! -f "$MAS_FILE" ]]; then
    log_warn "No ${MAS_FILE} — nothing to do."
    exit 0
fi

installed_mas="$(mas list 2>/dev/null | awk '{print $1}')"
any=false
while IFS= read -r line; do
    [[ -z "$line" || "$line" == \#* ]] && continue
    id="$(awk '{print $1}' <<< "$line")"
    name="$(cut -d' ' -f2- <<< "$line")"
    any=true
    if echo "$installed_mas" | grep -qxF "$id"; then
        log_ok "$name ($id) already installed."
        continue
    fi
    if [[ "$DRY_RUN" == "true" ]]; then
        log_action "mas install $id  # $name"
    else
        log_info "Installing $name ($id)..."
        mas install "$id" || log_warn "Failed to install $name ($id) (continuing)"
    fi
done < "$MAS_FILE"

[[ "$any" == "false" ]] && log_warn "No entries in ${MAS_FILE}."

echo
if [[ "$DRY_RUN" == "true" ]]; then
    log_warn "Dry run only — nothing was installed. Re-run with --execute to apply."
else
    log_ok "MAS sync complete."
fi
