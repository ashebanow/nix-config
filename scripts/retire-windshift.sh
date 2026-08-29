#!/usr/bin/env bash
# Throwaway cleanup: retire the windshift stack from lumquat (one-time).
#
# Why this exists: nix-config removed the windshift feature module
# (windshift -> Linear). A bare `nixos-rebuild switch` stops the systemd
# SYSTEM services (windshift-secrets-populate, windshift-quadlet-reload),
# but the rootless quadlet USER units keep running: their .container /
# .network / .volume files were installed as tmpfiles L+ symlinks into the
# podman user's ~/.config/containers/systemd/, and tmpfiles never removes
# symlinks when the rule disappears — so podman's generator keeps emitting
# the units and Restart=always keeps the containers alive, even across
# reboots (linger). The data (/etc/windshift, podman volumes/secrets/
# network) is never touched by a switch either.
#
# What it does (one-time):
#   1. stop the windshift systemd services (system + quadlet user units)
#   2. remove the stale quadlet definition symlinks and daemon-reload
#   3. remove windshift containers, volumes, secrets, and the network
#   4. remove /etc/windshift (tailscale-serve config + directory)
#
# Run it on the target host, as root (sudo) or as the 'podman' user:
#   sudo ./scripts/retire-windshift.sh -y     # execute
#   ./scripts/retire-windshift.sh             # dry run (prints what it would do)
#
# Safe to re-run; tolerates already-missing pieces. THROWAWAY: delete this
# script (and this commit) once the stack is retired.
set -euo pipefail

PODMAN_USER="podman"
DO_IT=0

usage() {
  cat <<'EOF'
Retire the windshift stack (one-time cleanup for the windshift -> Linear
migration). Removes:
  1. windshift systemd services + rootless quadlet user units & symlinks
  2. windshift containers, volumes, secrets, and the podman network
  3. /etc/windshift (tailscale-serve config + directory)

Usage:
  sudo ./scripts/retire-windshift.sh -y     # execute (as root or podman user)
  ./scripts/retire-windshift.sh             # dry run: print what it would do
  ./scripts/retire-windshift.sh -h          # this help

Safe to re-run; tolerates already-missing pieces. Throwaway script.
EOF
}

if [[ $# -gt 1 ]]; then
  echo "error: too many arguments" >&2
  usage >&2
  exit 2
fi
case "${1:-}" in
  "") : ;;
  -y|--yes) DO_IT=1 ;;
  -h|--help) usage; exit 0 ;;
  *)
    echo "error: unknown argument '$1'" >&2
    usage >&2
    exit 2
    ;;
esac

# Privilege handling: the stack is owned by the rootless 'podman' user.
if [[ "$(id -u)" -eq 0 ]]; then
  PRIV=() # already root: no sudo prefix
  as_podman() {
    sudo -u "$PODMAN_USER" env XDG_RUNTIME_DIR="/run/user/$(id -u "$PODMAN_USER")" "$@"
  }
else
  if [[ "$(id -un)" != "$PODMAN_USER" ]]; then
    echo "error: run as root (sudo) or as the '$PODMAN_USER' user — this cleans the rootless stack owned by '$PODMAN_USER'" >&2
    exit 1
  fi
  PRIV=(sudo) # podman user: passwordless sudo for the system-level bits
  as_podman() {
    "$@"
  }
fi

PODMAN_HOME="$(getent passwd "$PODMAN_USER" | cut -d: -f6)"
if [[ -z "$PODMAN_HOME" ]]; then
  echo "error: no '$PODMAN_USER' user on this host" >&2
  exit 1
fi

say() { printf '== %s\n' "$*"; }

do_or_dry() {
  if [[ "$DO_IT" -eq 1 ]]; then
    "$@" || true # tolerate already-missing pieces
  else
    printf '   [dry-run] would run: %s\n' "$*"
  fi
}

if [[ "$DO_IT" -eq 0 ]]; then
  echo "(dry run — pass -y/--yes to execute)"
  echo
fi

say "Stopping windshift systemd services (system + quadlet user units)"
do_or_dry "${PRIV[@]}" systemctl stop windshift-secrets-populate.service windshift-quadlet-reload.service
do_or_dry as_podman systemctl --user stop windshift.service windshift-db.service windshift-tailscale.service

say "Removing stale windshift quadlet symlinks from $PODMAN_USER's systemd dirs"
do_or_dry rm -f "$PODMAN_HOME/.config/systemd/user/windshift.network.service"
do_or_dry find "$PODMAN_HOME/.config/containers/systemd" -maxdepth 1 -name 'windshift*' -delete

say "Reloading the podman user manager (drops generated windshift units)"
do_or_dry as_podman systemctl --user daemon-reload

say "Removing windshift containers/pod"
do_or_dry as_podman podman pod rm -f windshift
do_or_dry as_podman podman rm -f windshift windshift-db windshift-tailscale

say "Removing windshift volumes, secrets, and network"
do_or_dry as_podman bash -c 'podman volume ls -q | grep "^windshift" | xargs -r podman volume rm -f'
do_or_dry as_podman bash -c 'podman secret ls -q | grep "^windshift" | xargs -r podman secret rm'
do_or_dry as_podman bash -c 'podman network ls -q | grep "^windshift" | xargs -r podman network rm -f'

say "Removing /etc/windshift (tailscale-serve config + directory)"
do_or_dry "${PRIV[@]}" rm -rf /etc/windshift

if [[ "$DO_IT" -eq 1 ]]; then
  say "Verifying"
  if as_podman podman ps -a --format '{{.Names}}' | grep -q '^windshift'; then
    echo "  WARNING: windshift containers still present:"
    as_podman podman ps -a --format '{{.Names}}' | grep '^windshift' | sed 's/^/    /'
  else
    echo "  no windshift containers remain"
  fi
  if [[ -e /etc/windshift ]]; then
    echo "  /etc/windshift still exists"
  else
    echo "  /etc/windshift removed"
  fi
  echo
  echo "Done. This script is throwaway — remove it from the repo once the stack is retired."
fi
