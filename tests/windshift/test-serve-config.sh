#!/usr/bin/env bash
# Acceptance test (spec A3-adjacent): the tailscale serve config proxies
# 443 -> 127.0.0.1:8080 for windshift.fluffy-walleye.ts.net and allows funnel.
set -euo pipefail

CONFIG="${WINDSHIFT_SERVE_CONFIG:-$(dirname "$0")/../../compose/windshift/ts-serve/serve-config.json}"

fail=0
[[ -f "$CONFIG" ]] || { echo "FAIL: $CONFIG missing" >&2; exit 1; }

jq -e '.TCP["443"].HTTPS == true' "$CONFIG" >/dev/null || { echo "FAIL: TCP 443 HTTPS not enabled" >&2; fail=1; }
jq -e '.Web["${TS_CERT_DOMAIN}:443"].Handlers["/"].Proxy == "http://127.0.0.1:8080"' "$CONFIG" >/dev/null || { echo "FAIL: proxy target is not 127.0.0.1:8080" >&2; fail=1; }
jq -e '.AllowFunnel["${TS_CERT_DOMAIN}:443"] == true' "$CONFIG" >/dev/null || { echo "FAIL: AllowFunnel not set" >&2; fail=1; }

if [[ "$fail" -eq 0 ]]; then
  echo "PASS: serve-config proxies 443 -> 127.0.0.1:8080 with funnel allowed"
fi
exit $fail
