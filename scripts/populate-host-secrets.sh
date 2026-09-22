#!/usr/bin/env bash
# Populates the file-backed secrets under /run/secrets (tmpfs) from the scope
# secretspec has injected into this process's environment.
#
# Invoked twice by host-secrets-populate.service, once per scope, so each
# subprocess sees only its own secrets:
#
#   secretspec run -P production -S host-<host> -- \
#     populate-host-secrets.sh host <HOST>_TAILSCALE_AUTH_KEY
#     /run/secrets/tailscale-auth-key  -> services.tailscale.authKeyFile   (0600 root)
#     /run/secrets/flakehub-token      -> determinate-nixd auth login --token-file (0600 root)
#
#   secretspec run -P production -S dev  -- populate-host-secrets.sh dev <operator-user>
#     /run/secrets/linear-api-key      -> the `linear` CLI wrapper           (0400 <operator-user>)
#
# The tailscale key is per node, so its variable name (<HOST>_TAILSCALE_AUTH_KEY)
# is passed in by the caller rather than hardcoded.
#
# `host` secrets are root-only and mandatory: tailscale and determinate-nixd
# demand a file interface, and a host without them is misconfigured, so an
# absent value aborts. `dev` secrets are operator-tool secrets (docs/adr/0001):
# user-readable, and optional — an absent value skips the file with a notice
# rather than failing the unit, because no service depends on them.
# Every other secret is delivered straight into process environments via
# `secretspec run` (no env files, no podman-secret readback).
set -euo pipefail

fail() {
  echo "populate-host-secrets: $*" >&2
  exit 1
}

# write <env-var> <path>
write() {
  local var="$1" path="$2"
  [[ -n "${!var:-}" ]] || fail "$var is empty/absent — aborting without a partial set"
  umask 077
  printf '%s\n' "${!var}" > "$path"
  chmod 0600 "$path"
  echo "wrote $path"
}

# write_user <env-var> <path> <owner>: like write, but readable only by
# <owner> (0400) and tolerant of an absent value. Written to a temp file and
# renamed so a reader never sees a partial key.
write_user() {
  local var="$1" path="$2" owner="$3"
  if [[ -z "${!var:-}" ]]; then
    echo "$var is empty/absent — skipping $path (optional dev secret)"
    rm -f "$path"
    return 0
  fi
  umask 077
  local tmp="$path.tmp"
  printf '%s\n' "${!var}" > "$tmp"
  chown "$owner:root" "$tmp"
  chmod 0400 "$tmp"
  mv -f "$tmp" "$path"
  echo "wrote $path (owner $owner)"
}

case "${1:-host}" in
  host)
    [[ -n "${2:-}" ]] || fail "host mode needs the node's tailscale variable name as its second argument"
    write "$2" /run/secrets/tailscale-auth-key
    write FLAKEHUB_TOKEN /run/secrets/flakehub-token
    ;;
  dev)
    [[ -n "${2:-}" ]] || fail "dev mode needs the operator user as its second argument"
    write_user LINEAR_API_KEY /run/secrets/linear-api-key "$2"
    ;;
  *)
    fail "unknown mode '$1' (expected: host <HOST>_TAILSCALE_AUTH_KEY | dev <operator-user>)"
    ;;
esac
