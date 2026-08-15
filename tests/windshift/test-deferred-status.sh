#!/usr/bin/env bash
# Acceptance test (spec A4/A6): a non-terminal "Deferred" status exists and
# the suwiki deferred issues are represented as open + Deferred.
#
# Post-deploy check via the Windshift API/MCP. The exact query depends on the
# deployed API surface (search_items / list_items + status filter). This stub
# is intentionally RED until T6 wires the real check.
set -euo pipefail

BASE_URL="${WINDSHIFT_BASE_URL:-https://windshift.fluffy-walleye.ts.net}"
TOKEN="${WINDSHIFT_API_TOKEN:-}"

if [[ -z "$TOKEN" ]]; then
  echo "SKIP: WINDSHIFT_API_TOKEN not set (T5 creates it) — treat as pending" >&2
  exit 2
fi

echo "NOT-IMPLEMENTED: replace this stub with a real search_items status=Deferred check (T6)" >&2
exit 1
