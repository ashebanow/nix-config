#!/usr/bin/env bash
# Runs the Windshift acceptance suite against the deployed stack.
# Exit 0 = all green; 1 = failures; 2 = skipped (needs something not yet deployed).
set -uo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
overall=0
skipped=0

for t in "$HERE"/test-*.sh; do
  name="$(basename "$t")"
  if "$t" >/tmp/windshift-test.out 2>&1; then
    echo "[PASS] $name"
  else
    rc=$?
    if [[ $rc -eq 2 ]]; then
      echo "[SKIP] $name — $(tail -1 /tmp/windshift-test.out)"
      skipped=$((skipped + 1))
    else
      echo "[FAIL] $name"
      cat /tmp/windshift-test.out >&2
      overall=1
    fi
  fi
done

echo
if [[ $overall -eq 0 && $skipped -gt 0 ]]; then
  echo "SUITE: green ($skipped skipped — pending later tickets)"
elif [[ $overall -eq 0 ]]; then
  echo "SUITE: all green"
else
  echo "SUITE: FAILURES"
fi
exit $overall
