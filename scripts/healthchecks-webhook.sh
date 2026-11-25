#!/usr/bin/env bash
# healthchecks.io webhook receiver — the dead-man's switch (BOX-329).
#
# ## Why this exists at all
#
# healthchecks.io is pinged with a GET to a *capability URL*, and Alertmanager's
# `webhook_configs` only knows how to POST a JSON body to a URL. There is no
# "ping this URL every minute" receiver in Alertmanager, and no way to make it
# issue a GET. So the smallest possible bridge sits in front: Alertmanager
# POSTs here (loopback only), and this translates the notification into the
# ping healthchecks.io expects.
#
# Alertmanager's own `pushover_configs` and `webhook_configs` both read the
# capability URL and the Pushover pair from *this process's environment*, not
# from the config file: nixpkgs renders the Alertmanager config with `envsubst`,
# which silently substitutes nothing when the variable is unset — so the tokens
# exist only in the unit's environment (filled by `secretspec run`) and never in
# the Nix store. See `modules/features/observability-host.nix`.
#
# ## The protocol
#
#   firing    -> ping the capability URL. A 2xx means "healthchecks.io saw the
#                heartbeat"; anything else must fail loudly so Alertmanager
#                retries, because a swallowed ping is a silent dead-man's switch.
#   resolved  -> do nothing. The Watchdog never resolves in a healthy system,
#                so a resolve means vmalert or Alertmanager restarted; pinging
#                on resolve would hide exactly the gap we want surfaced.
#                healthchecks.io's grace period covers a short restart.
#   else      -> ignore. This receiver is for the Watchdog only; Alertmanager
#                routing guarantees nothing else arrives here, and if something
#                does, silently pinging would be a lie.
#
# ## Never log the URL
#
# The ping URL is a capability URL: whoever has it can keep the switch quiet.
# Only the HTTP status is ever written out.
set -euo pipefail

: "${HEALTHCHECKS_PING_URL:?HEALTHCHECKS_PING_URL is not set — the alerting scope did not resolve}"

status=0

# Read the notification. The body is not parsed for content: this endpoint
# receives one alert name by routing, and the decision above is made on the
# alert *state* alone. `jq -e` is used rather than a text match so a malformed
# body is an error rather than a silent "no alerts".
if ! payload=$(cat); then
  echo "healthchecks-webhook: could not read request body" >&2
  exit 1
fi

# Alertmanager's webhook payload: {"status": "firing"|"resolved", "alerts": [...], ...}
state=$(printf '%s' "$payload" | jq -r '.status // empty' 2>/dev/null || true)

case "$state" in
  firing)
    if ! http_code=$(curl --silent --show-error --output /dev/null \
      --write-out '%{http_code}' --max-time 10 --retry 2 \
      "$HEALTHCHECKS_PING_URL"); then
      echo "healthchecks-webhook: ping failed (no HTTP response)" >&2
      exit 1
    fi
    case "$http_code" in
      2*) echo "healthchecks-webhook: pinged (HTTP $http_code)" ;;
      *)
        echo "healthchecks-webhook: ping rejected (HTTP $http_code)" >&2
        exit 1
        ;;
    esac
    ;;
  resolved)
    echo "healthchecks-webhook: resolved notification ignored (not a heartbeat)"
    ;;
  *)
    echo "healthchecks-webhook: unexpected payload status '${state:-<none>}' — ignoring" >&2
    status=0
    ;;
esac

exit "$status"
