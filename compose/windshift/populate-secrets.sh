#!/usr/bin/env bash
# Populates podman secrets for the Windshift quadlet units.
#
# Invoked as:  secretspec run -P production -S windshift -- populate-secrets.sh
# (from the windshift-secrets.service oneshot). secretspec injects the windshift
# scope of the shared repo-root manifest as env vars; this script maps them to
# podman secret names — the same names the units' `Secret=<name>` lines reference.
#
# POSTGRES_CONNECTION_STRING is composed here from the postgres parts (the app
# expects the full URL; the host is always `windshift-db` on the podman net).
#
# Rules:
#   - Pipe into stdin; never $(...) — command substitution strips trailing
#     newlines.
#   - Fail loudly and non-zero on any missing/empty value — a partial
#     population that lets containers start is the dangerous case.
#   - Not periodic: --replace only affects newly created containers, so a
#     timer yields drift, not rotation. Rotation = re-run + restart the stack.
#   - Generated postgres passwords are hex (no URL-encoding needed in the
#     connection string). If a non-hex password is ever used, URL-encode it.
set -euo pipefail

fail() {
  echo "populate-secrets: $*" >&2
  exit 1
}

# create <podman-secret-name> <env-var-name>
create() {
  local name="$1" var="$2"
  [[ -n "${!var:-}" ]] || fail "$var is empty/absent — aborting without a partial set"
  printf '%s' "${!var}" | podman secret create --replace "$name" - >/dev/null
  echo "populated $name"
}

create windshift-sso-secret SSO_SECRET
create windshift-postgres-db POSTGRES_DB
create windshift-postgres-user POSTGRES_USER
create windshift-postgres-password POSTGRES_PASSWORD
create windshift-tailscale-auth-key WINDSHIFT_TS_AUTHKEY
create windshift-base-url BASE_URL
create windshift-allowed-hosts ALLOWED_HOSTS

# Compose the connection string secret.
[[ -n "${POSTGRES_USER:-}" && -n "${POSTGRES_PASSWORD:-}" && -n "${POSTGRES_DB:-}" ]] || fail "postgres parts missing — aborting"
printf 'postgres://%s:%s@windshift-db:5432/%s?sslmode=disable' \
  "$POSTGRES_USER" "$POSTGRES_PASSWORD" "$POSTGRES_DB" |
  podman secret create --replace windshift-postgres-connection-string - >/dev/null
echo "populated windshift-postgres-connection-string"
