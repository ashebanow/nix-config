#!/usr/bin/env bash
# Populates podman secrets for the Kaneo quadlet units.
#
# Invoked as:  secretspec run -P production -- populate-secrets.sh
# (from the kaneo-secrets.service oneshot). secretspec injects every secret
# from the production profile as an env var; this script maps them to podman
# secret names — the same names the units' `Secret=<name>` lines reference.
#
# The tailscale sidecar auth key is sops-delivered (not in BWS): it arrives
# via systemd LoadCredential as $CREDENTIALS_DIRECTORY/kaneo-tailscale-auth-key.
#
# Rules (issue #6):
#   - Pipe into stdin; never $(...) — command substitution strips trailing
#     newlines, which matters for the PEM private key.
#   - Fail loudly and non-zero on any missing/empty value — a partial
#     population that lets containers start is the dangerous case.
#   - Not periodic: --replace only affects newly created containers, so a
#     timer yields drift, not rotation. Rotation = re-run + restart the stack.
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

create kaneo-postgres-db POSTGRES_DB
create kaneo-postgres-host POSTGRES_HOST
create kaneo-postgres-password POSTGRES_PASSWORD
create kaneo-postgres-user POSTGRES_USER
create kaneo-auth-secret AUTH_SECRET
create kaneo-github-app-id GITHUB_APP_ID
create kaneo-github-app-webhook GITHUB_WEBHOOK_SECRET
create kaneo-github-app-private-key GITHUB_PRIVATE_KEY
create kaneo-github-app-client-id GITHUB_OAUTH_CLIENT_ID
create kaneo-github-app-client-secret GITHUB_OAUTH_CLIENT_SECRET
create kaneo-client-url KANEO_CLIENT_URL
create kaneo-api-url KANEO_API_URL
create kaneo-cors-origins CORS_ORIGINS
create kaneo-smtp-from SMTP_FROM
create kaneo-smtp-host SMTP_HOST
create kaneo-smtp-ignore-tls SMTP_IGNORE_TLS
create kaneo-smtp-password SMTP_PASSWORD
create kaneo-smtp-port SMTP_PORT
create kaneo-smtp-require-tls SMTP_REQUIRE_TLS
create kaneo-smtp-secure SMTP_SECURE
create kaneo-smtp-user SMTP_USER

# Sidecar tailscale auth key — from BWS via the production profile (TS_AUTHKEY).
create kaneo-tailscale-auth-key TS_AUTHKEY
