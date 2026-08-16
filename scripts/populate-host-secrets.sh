#!/usr/bin/env bash
# Populates the root-level host secrets consumed by file-based system services.
#
# Invoked as:  secretspec run -P production -S host -- populate-host-secrets.sh
# (from host-secrets-populate.service). secretspec injects TAILSCALE_AUTH_KEY and
# FLAKEHUB_TOKEN; this script materializes them at the paths the consumers
# already read:
#
#   /run/secrets/tailscale-auth-key  -> services.tailscale.authKeyFile
#   /run/secrets/flakehub-token      -> determinate-nixd auth login --token-file
#
# These are the ONLY secrets written to disk on the host: tailscale and
# determinate-nixd both demand a file interface, so a plain file is unavoidable.
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

write TAILSCALE_AUTH_KEY /run/secrets/tailscale-auth-key
write FLAKEHUB_TOKEN /run/secrets/flakehub-token
