#!/usr/bin/env bash
# Pre-switch cleanup: removes Homebrew formulae now provided by nix,
# and removes mise (retired in chezmoi, fully replaced). Run check.sh
# first to see what this will do.
#
# Deliberately does NOT touch:
#   - Homebrew casks — darwin-rebuild switch's own
#     homebrew.onActivation.cleanup = "uninstall" handles casks not in
#     the declared list; no need to duplicate that here.
#   - Mac App Store apps — mas has no reliable unattended uninstall
#     path under sudo, and losing a configured app by accident is a
#     much bigger deal than a stale CLI formula. Handle MAS removals
#     yourself, manually, if you ever want to.
#
# Usage: ./cleanup.sh [hostname] [--dry-run|--execute]
#   Defaults to --dry-run. Pass --execute to actually uninstall/remove.

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "${SCRIPT_DIR}/lib.sh"

# First non-flag arg is the host; flags can appear anywhere.
HOST_ARG=""
for a in "$@"; do
    [[ "$a" != --* ]] && HOST_ARG="$a"
done
HOST="$(resolve_host "$HOST_ARG")"
parse_dry_run_flag "$@"

log_header "Pre-switch cleanup for ${HOST}"

if ! command -v jq >/dev/null 2>&1; then
    log_error "jq is required (brew install jq, or nix shell nixpkgs#jq)"
    exit 1
fi

# ---------------------------------------------------------------
# Homebrew formulae now provided by nix
# ---------------------------------------------------------------
log_header "Homebrew formulae"

if command -v brew >/dev/null 2>&1; then
    installed_formulae="$(brew list --formula 2>/dev/null | sort)"
    to_remove=()
    while IFS= read -r formula; do
        [[ -z "$formula" ]] && continue
        nix_attr="$(awk -v f="$formula" '$1 == f {print $2; exit}' "${SCRIPT_DIR}/nix-provided-formulae.txt")"
        [[ -n "$nix_attr" ]] && to_remove+=("$formula")
    done <<< "$installed_formulae"

    if [[ ${#to_remove[@]} -eq 0 ]]; then
        log_ok "No redundant formulae found."
    else
        for formula in "${to_remove[@]}"; do
            if [[ "$DRY_RUN" == "true" ]]; then
                log_action "brew uninstall $formula"
            else
                log_info "Uninstalling $formula..."
                brew uninstall "$formula" || log_warn "Failed to uninstall $formula (continuing)"
            fi
        done
    fi
else
    log_warn "brew not found — skipping formula cleanup"
fi

# ---------------------------------------------------------------
# mise
# ---------------------------------------------------------------
log_header "mise"

if command -v mise >/dev/null 2>&1; then
    if [[ "$DRY_RUN" == "true" ]]; then
        log_action "brew uninstall mise (or rm the mise.run-installed binary)"
    else
        log_info "Removing mise..."
        if brew list --formula 2>/dev/null | grep -qxF mise; then
            brew uninstall mise || log_warn "Failed to uninstall mise via brew (continuing)"
        elif [[ -x "$HOME/.local/bin/mise" ]]; then
            rm -f "$HOME/.local/bin/mise"
        fi
    fi
else
    log_ok "mise binary not found."
fi

for d in "$HOME/.local/share/mise" "$HOME/.cache/mise" "$HOME/.config/mise"; do
    if [[ -e "$d" ]]; then
        if [[ "$DRY_RUN" == "true" ]]; then
            log_action "rm -rf $d"
        else
            log_info "Removing $d..."
            rm -rf "$d"
        fi
    fi
done

echo
if [[ "$DRY_RUN" == "true" ]]; then
    log_warn "Dry run only — nothing was changed. Re-run with --execute to apply."
else
    log_ok "Cleanup complete."
fi
