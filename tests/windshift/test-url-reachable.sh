#!/usr/bin/env bash
# Acceptance test (spec A1): Windshift web UI reachable over the tailnet at
# https://windshift.fluffy-walleye.ts.net.
set -euo pipefail

URL="https://windshift.fluffy-walleye.ts.net"

code="$(curl -s -o /dev/null -w '%{http_code}' -m 15 "$URL" || echo '000')"
if [[ "$code" == "000" ]]; then
  echo "FAIL: $URL unreachable (curl error / DNS not up yet — deploy first)" >&2
  exit 1
fi
if [[ "$code" =~ ^(200|301|302|303|307|308)$ ]]; then
  echo "PASS: $URL responds HTTP $code"
else
  echo "FAIL: $URL responded HTTP $code (expected 2xx/3xx)" >&2
  exit 1
fi

# Expect a Windshift login/setup marker in the body.
body="$(curl -s -m 15 "$URL" || true)"
if grep -qiE "windshift|sign in|setup" <<<"$body"; then
  echo "PASS: page contains a Windshift marker"
else
  echo "WARN: page content unrecognized (marker not found) — verify manually" >&2
fi
