#!/usr/bin/env bash
# Report what a pre-switch cleanup would touch, for a given host.
# Read-only — makes no changes. Run this before cleanup.sh/mas-sync.sh
# so you know what to expect.
#
# Usage: ./check.sh [hostname]
#   hostname defaults to the current machine's hostname if it matches
#   a known host (bergamot, miraclemax).

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "${SCRIPT_DIR}/lib.sh"

HOST="$(resolve_host "${1:-}")"
log_header "Pre-switch check for ${HOST}"

declared_casks=""

if ! command -v jq >/dev/null 2>&1; then
    log_error "jq is required (brew install jq, or nix shell nixpkgs#jq)"
    exit 1
fi

# ---------------------------------------------------------------
# Homebrew formulae: currently installed vs now nix-provided
# ---------------------------------------------------------------
log_header "Homebrew formulae"

if command -v brew >/dev/null 2>&1; then
    installed_formulae="$(brew list --formula 2>/dev/null | sort)"
    declared_brews="$(eval_darwin_list "$HOST" "homebrew.brews" | sort)"

    echo "Currently installed via brew, now provided by nix (candidates for cleanup.sh):"
    redundant_count=0
    while IFS= read -r formula; do
        [[ -z "$formula" ]] && continue
        nix_attr="$(awk -v f="$formula" '$1 == f {print $2; exit}' "${SCRIPT_DIR}/nix-provided-formulae.txt")"
        if [[ -n "$nix_attr" ]]; then
            echo "  - $formula (-> nixpkgs#$nix_attr)"
            redundant_count=$((redundant_count + 1))
        fi
    done <<< "$installed_formulae"
    [[ $redundant_count -eq 0 ]] && echo "  (none)"

    echo
    echo "Declared in homebrew.brews (kept as brew formulae, no nix equivalent):"
    while IFS= read -r b; do
        [[ -z "$b" ]] && continue
        if echo "$installed_formulae" | grep -qxF "$b"; then
            echo "  - $b (already installed, OK)"
        else
            echo "  - $b (not yet installed — darwin-rebuild switch will install it)"
        fi
    done <<< "$declared_brews"

    echo
    echo "Installed via brew, NOT nix-provided and NOT in homebrew.brews (unaccounted for — review manually):"
    unaccounted_count=0
    while IFS= read -r formula; do
        [[ -z "$formula" ]] && continue
        nix_attr="$(awk -v f="$formula" '$1 == f {print $2; exit}' "${SCRIPT_DIR}/nix-provided-formulae.txt")"
        if [[ -z "$nix_attr" ]] && ! echo "$declared_brews" | grep -qxF "$formula"; then
            echo "  - $formula"
            unaccounted_count=$((unaccounted_count + 1))
        fi
    done <<< "$installed_formulae"
    [[ $unaccounted_count -eq 0 ]] && echo "  (none)"
else
    log_warn "brew not found on this machine — skipping formula check"
fi

# ---------------------------------------------------------------
# Homebrew casks
# ---------------------------------------------------------------
log_header "Homebrew casks"

if command -v brew >/dev/null 2>&1; then
    installed_casks="$(brew list --cask 2>/dev/null | sort)"
    declared_casks="$(eval_darwin_list "$HOST" "homebrew.casks" | sort)"

    echo "Installed but NOT declared (darwin-rebuild switch will remove these — cleanup = uninstall):"
    while IFS= read -r cask; do
        [[ -z "$cask" ]] && continue
        if ! echo "$declared_casks" | grep -qxF "$cask"; then
            echo "  - $cask"
        fi
    done <<< "$installed_casks"

    echo
    echo "Declared but not yet installed (darwin-rebuild switch will install these):"
    while IFS= read -r cask; do
        [[ -z "$cask" ]] && continue
        if ! echo "$installed_casks" | grep -qxF "$cask"; then
            echo "  - $cask"
        fi
    done <<< "$declared_casks"
else
    log_warn "brew not found on this machine — skipping cask check"
fi

# ---------------------------------------------------------------
# Mac App Store apps — install-only via mas-sync.sh, never auto-removed
# ---------------------------------------------------------------
log_header "Mac App Store apps"

MAS_FILE="${REPO_ROOT}/hosts/${HOST}/mas-apps.txt"
if command -v mas >/dev/null 2>&1; then
    installed_mas="$(mas list 2>/dev/null | awk '{print $1}')"

    if [[ -f "$MAS_FILE" ]]; then
        echo "Declared in hosts/${HOST}/mas-apps.txt:"
        while IFS= read -r line; do
            [[ -z "$line" || "$line" == \#* ]] && continue
            id="$(awk '{print $1}' <<< "$line")"
            name="$(cut -d' ' -f2- <<< "$line")"
            if echo "$installed_mas" | grep -qxF "$id"; then
                echo "  - $name ($id) — already installed, OK"
            else
                echo "  - $name ($id) — NOT installed. Run mas-sync.sh to install."
            fi
        done < "$MAS_FILE"
    else
        log_warn "No hosts/${HOST}/mas-apps.txt found."
    fi

    echo
    echo "Installed but NOT declared (never auto-removed — mas has no reliable"
    echo "unattended uninstall path under sudo; decide manually whether to keep"
    echo "or remove via Finder/Launchpad, or 'sudo mas uninstall <id>' yourself):"
    declared_ids=""
    [[ -f "$MAS_FILE" ]] && declared_ids="$(awk '!/^#/ && NF {print $1}' "$MAS_FILE")"
    while IFS=$'\t' read -r id name; do
        [[ -z "$id" ]] && continue
        if ! echo "$declared_ids" | grep -qxF "$id"; then
            echo "  - $name ($id)"
            # Flag apps that are also declared as a cask under a similar
            # name — these need the MAS copy removed before the cask can
            # install cleanly to the same /Applications path.
            lc_name="$(tr '[:upper:]' '[:lower:]' <<< "$name" | tr -d ' ')"
            if echo "$declared_casks" | tr -d ' ' | grep -qiF "$lc_name"; then
                echo "      ^ also declared as a cask — likely migration candidate," \
                     "but remove the MAS copy manually before switching, not automated here."
            fi
        fi
    done < <(mas list 2>/dev/null | awk '{id=$1; $1=""; print id"\t"substr($0,2)}')
else
    log_warn "mas not found on this machine — skipping MAS check"
fi

# ---------------------------------------------------------------
# mise
# ---------------------------------------------------------------
log_header "mise"

if command -v mise >/dev/null 2>&1 || [[ -d "$HOME/.local/share/mise" ]]; then
    echo "mise is still present on this machine (retired in chezmoi — safe to remove via cleanup.sh):"
    command -v mise >/dev/null 2>&1 && mise list 2>/dev/null | sed 's/^/  - /' || true
    [[ -d "$HOME/.local/share/mise" ]] && echo "  - data dir: $HOME/.local/share/mise"
else
    echo "mise not found — nothing to clean up."
fi

echo
log_ok "Check complete. Nothing was changed."
