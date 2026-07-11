#!/usr/bin/env bash
# Honcho health check — verifies end-to-end: API → deriver → embedding → DB save.
# Run by systemd timer every 15 min. Fails loudly on Discord after 2 consecutive misses.
set -euo pipefail

HONCHO_BASE="https://honcho.fluffy-walleye.ts.net"
WORKSPACE="health-check"
PEER="monitor"
SESSION="pulse"
HEALTH_LOG="/var/lib/honcho/health.log"
MAX_LOG_LINES=1000
CONSECUTIVE_FAILURES_FILE="/var/lib/honcho/consecutive_failures"

# Ensure directories exist
mkdir -p "$(dirname "$HEALTH_LOG")"

# ── helpers ──────────────────────────────────────────────────
_ts() { date -u +%Y-%m-%dT%H:%M:%SZ; }
_log() { echo "[$(_ts)] $*" | tee -a "$HEALTH_LOG"; }

_discord_alert() {
  local msg="$1"
  if [[ -n "${DISCORD_WEBHOOK_URL:-}" ]]; then
    curl -sf -X POST "$DISCORD_WEBHOOK_URL" \
      -H "Content-Type: application/json" \
      -d "{\"content\":\"❌ **Honcho Health Check FAILED** on lumquat\\n$msg\"}" \
      >/dev/null 2>&1 || true
  fi
}

# ── create workspace / peer / session (idempotent) ───────────
_ensure() {
  curl -sf -X POST "$HONCHO_BASE/v3/workspaces" \
    -H "Content-Type: application/json" \
    -d "{\"name\":\"$WORKSPACE\"}" >/dev/null 2>&1 || true
  curl -sf -X POST "$HONCHO_BASE/v3/workspaces/$WORKSPACE/peers" \
    -H "Content-Type: application/json" \
    -d "{\"name\":\"$PEER\"}" >/dev/null 2>&1 || true
  curl -sf -X POST "$HONCHO_BASE/v3/workspaces/$WORKSPACE/sessions" \
    -H "Content-Type: application/json" \
    -d "{\"name\":\"$SESSION\"}" >/dev/null 2>&1 || true
}

# ── post a test message ──────────────────────────────────────
_post_message() {
  local msg_text="Health check pulse at $(_ts)"
  local resp
  resp=$(curl -sf -X POST \
    "$HONCHO_BASE/v3/workspaces/$WORKSPACE/sessions/$SESSION/messages" \
    -H "Content-Type: application/json" \
    -d "{\"messages\":[{\"role\":\"user\",\"content\":\"$msg_text\",\"peer_id\":\"$PEER\"}]}")
  echo "$resp" | sed -n 's/.*"id":"\([^"]*\)".*/\1/p' | head -1
}

# ── wait for deriver to process ──────────────────────────────
_wait_for_sync() {
  local msg_id="$1"
  local max_wait=300  # seconds (deriver jitter + model loading can be slow)
  local waited=0
  while (( waited < max_wait )); do
    local state
    state=$(podman exec honcho-db psql -U honcho -d honcho -tAc \
      "SELECT d.sync_state FROM documents d
       JOIN messages m ON d.id = m.public_id
       WHERE m.public_id = '$msg_id'
       LIMIT 1" 2>/dev/null || echo "not_found")
    case "$state" in
      synced) return 0 ;;
      failed) return 1 ;;
      not_found|pending) sleep 5; waited=$((waited + 5)) ;;
      *) sleep 5; waited=$((waited + 5)) ;;
    esac
  done
  return 1  # timeout
}

# ── rotate health log ────────────────────────────────────────
_rotate_log() {
  local lines
  lines=$(wc -l < "$HEALTH_LOG" 2>/dev/null || echo 0)
  if (( lines > MAX_LOG_LINES )); then
    tail -n "$MAX_LOG_LINES" "$HEALTH_LOG" > "${HEALTH_LOG}.tmp"
    mv "${HEALTH_LOG}.tmp" "$HEALTH_LOG"
  fi
}

# ── main ─────────────────────────────────────────────────────
_log "Starting health check..."

_ensure

MESSAGE_ID=$(_post_message)
_log "Posted message $MESSAGE_ID, waiting for deriver..."

if _wait_for_sync "$MESSAGE_ID"; then
  _log "PASS: document $MESSAGE_ID synced successfully"
  echo 0 > "$CONSECUTIVE_FAILURES_FILE"
else
  _log "FAIL: document $MESSAGE_ID did not sync within 120s"

  # Track consecutive failures
  failures=$(cat "$CONSECUTIVE_FAILURES_FILE" 2>/dev/null || echo 0)
  failures=$((failures + 1))
  echo "$failures" > "$CONSECUTIVE_FAILURES_FILE"

  if (( failures >= 2 )); then
    _discord_alert "Document $MESSAGE_ID failed to sync. $failures consecutive failures."
  fi
fi

_rotate_log
exit 0
