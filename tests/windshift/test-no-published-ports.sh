#!/usr/bin/env bash
# Acceptance test (spec A2): Windshift containers expose NO published ports.
# Only the tailscale sidecar's funnel may reach the app.
set -euo pipefail

HOST="${LUMQUAT_HOST:-lumquat}"
APP_CONTAINERS="windshift windshift-db"

fail=0
for c in $APP_CONTAINERS; do
  ports="$(ssh "$HOST" "podman inspect $c --format '{{json .HostConfig.PortBindings}}'" 2>/dev/null || echo 'CONTAINER_MISSING')"
  if [[ "$ports" == "null" || "$ports" == "{}" || "$ports" == "[]" ]]; then
    echo "PASS: $c has no published ports (PortBindings=$ports)"
  elif [[ "$ports" == "CONTAINER_MISSING" ]]; then
    echo "FAIL: $c not running on $HOST — deploy first" >&2
    fail=1
  else
    echo "FAIL: $c exposes published ports: $ports" >&2
    fail=1
  fi
done

exit $fail
