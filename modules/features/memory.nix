# Mnemosyne memory module — single-binary SQLite memory for AI agents.
#
# Image: custom (Python 3.12 + mnemosyne-memory[embeddings])
#   - Local-first, zero external dependencies
#   - SQLite-backed with vector search (sqlite-vec)
#   - MCP server over Streamable HTTP
#   - https://mnemosyne.site
#
# Access: https://memory.fluffy-walleye.ts.net (Tailscale-only)
#
# Database: /var/lib/mnemosyne/mnemosyne.db (WAL mode)
# Backups:  /var/lib/mnemosyne/backups/ (daily, 7-day retention)
_: {
  my.modules.nixos.memory =
    {
      lib,
      pkgs,
      config,
      ...
    }:
    let
      cfg = config.my;
      dataDir = "/var/lib/mnemosyne";
      backupDir = "${dataDir}/backups";
    in
    {
      config = lib.mkIf cfg.memory {
        # SOPS secrets for Mnemosyne
        sops.secrets = {
          "mnemo-tailscale-auth-key" = {
            mode = "0640";
            group = "root";
          };
          "mnemosyne-mcp-token" = {
            mode = "0640";
            group = "root";
          };
        };

        # Data directory and backup directory
        systemd.tmpfiles.rules = [
          "d ${dataDir} 0777 ${cfg.baseUsername} ${cfg.baseUsername} -"
          "d ${backupDir} 0777 ${cfg.baseUsername} ${cfg.baseUsername} -"
          "d /etc/memory 0777 root root -"
          "L+ /etc/memory/compose.yml - - - - ${../../compose/memory/compose.yml}"
          "L+ /etc/memory/Dockerfile - - - - ${../../containers/mnemosyne/Dockerfile}"
        ];

        # ── Mnemosyne compose stack ──────────────────────────────
        systemd.services.memory-compose =
          let
            tsAuthKeyPath = config.sops.secrets."mnemo-tailscale-auth-key".path;
            mcpTokenPath = config.sops.secrets."mnemosyne-mcp-token".path;
          in
          {
            description = "Mnemosyne memory layer compose stack";
            after = [ "network.target" ];
            wants = [ "network.target" ];
            wantedBy = [ "multi-user.target" ];
            path = [ pkgs.podman-compose pkgs.podman ];
            serviceConfig = {
              Type = "oneshot";
              RemainAfterExit = "yes";
              User = cfg.baseUsername;
              Environment = [
                "PATH=${pkgs.podman-compose}/bin:/run/current-system/sw/bin"
              ];
              LoadCredential = [
                "ts-auth-key:${tsAuthKeyPath}"
                "mcp-token:${mcpTokenPath}"
              ];
              ExecStartPre = pkgs.writeShellScript "memory-build-image" ''
                set -e
                # Always rebuild to pick up Dockerfile changes
                echo "Building mnemosyne-memory image..."
                podman build -t mnemosyne-memory:latest -f /etc/memory/Dockerfile /etc/memory
              '';
              ExecStart = pkgs.writeShellScript "memory-compose-start" ''
                set -e
                export XDG_RUNTIME_DIR="/run/user/$(id -u)"
                export MEMORY_TS_AUTHKEY="$(cat $CREDENTIALS_DIRECTORY/ts-auth-key)"
                export MNEMOSYNE_MCP_TOKEN="$(cat $CREDENTIALS_DIRECTORY/mcp-token)"
                # podman-compose reads env vars from .env file
                cat > /etc/memory/.env << EOF
MEMORY_TS_AUTHKEY=$MEMORY_TS_AUTHKEY
MNEMOSYNE_MCP_TOKEN=$MNEMOSYNE_MCP_TOKEN
EOF
                exec podman-compose -f /etc/memory/compose.yml up -d
              '';
              ExecStop = "${pkgs.podman-compose}/bin/podman-compose -f /etc/memory/compose.yml down";
            };
          };

        # ── Health check (systemd timer, every 30 min) ────────────
        systemd.services.memory-health-check =
          let
            mcpTokenPath = config.sops.secrets."mnemosyne-mcp-token".path;
          in
          {
          description = "Mnemosyne end-to-end health check";
          after = [ "memory-compose.service" ];
          requires = [ "memory-compose.service" ];
          path = [ pkgs.curl pkgs.sqlite ];
          serviceConfig = {
            Type = "oneshot";
            User = cfg.baseUsername;
            LoadCredential = [
              "mcp-token:${mcpTokenPath}"
            ];
          };
          script = ''
            set -euo pipefail
            DB="${dataDir}/mnemosyne.db"
            BASE="https://memory.fluffy-walleye.ts.net"
            TIMESTAMP=$(date -u +%s)
            HEALTH_LOG="${dataDir}/health.log"
            FAILURES_FILE="${dataDir}/consecutive_failures"
            MCP_TOKEN="$(cat $CREDENTIALS_DIRECTORY/mcp-token)"

            log() { echo "[$(date -u +%Y-%m-%dT%H:%M:%SZ)] $*" | tee -a "$HEALTH_LOG"; }

            # 1. SQLite integrity
            if [ ! -f "$DB" ] || ! sqlite3 "$DB" "PRAGMA integrity_check;" 2>/dev/null | grep -q "ok"; then
              log "FAIL: SQLite integrity check failed"
              exit 1
            fi

            # 2. SSE endpoint reachable (MCP over SSE transport)
            if ! curl -sf --max-time 5 -o /dev/null "$BASE/sse" 2>/dev/null; then
              log "FAIL: SSE endpoint unreachable"
              exit 1
            fi

            # 3. Full MCP round-trip: initialize, write, recall
            # SSE session must stay alive during POST requests
            SSE_OUT=$(mktemp)
            curl -sfN "$BASE/sse" -H "Authorization: Bearer $MCP_TOKEN" > "$SSE_OUT" 2>/dev/null &
            SSE_PID=$!
            sleep 2

            SESSION_ID=$(grep -o 'session_id=[^&[:space:]]*' "$SSE_OUT" 2>/dev/null | head -1 | cut -d= -f2)
            if [ -z "$SESSION_ID" ]; then
              kill $SSE_PID 2>/dev/null || true
              rm -f "$SSE_OUT"
              log "FAIL: Could not obtain SSE session ID"
              exit 1
            fi
            AUTH="-H 'Authorization: Bearer $MCP_TOKEN'"
            MCP="curl -sf -X POST \"$BASE/messages/?session_id=$SESSION_ID\" -H 'Content-Type: application/json' $AUTH"

            # Initialize
            eval "$MCP -d '{\"jsonrpc\":\"2.0\",\"method\":\"initialize\",\"params\":{\"protocolVersion\":\"2024-11-05\",\"capabilities\":{},\"clientInfo\":{\"name\":\"health-check\",\"version\":\"1.0\"}},\"id\":1}'" >/dev/null 2>&1 || {
              kill $SSE_PID 2>/dev/null || true; rm -f "$SSE_OUT"
              log "FAIL: MCP initialize failed"
              exit 1
            }

            # Write test memory
            TEST_CONTENT="health-check-ping-$TIMESTAMP"
            eval "$MCP -d '{\"jsonrpc\":\"2.0\",\"method\":\"tools/call\",\"params\":{\"name\":\"remember\",\"arguments\":{\"content\":\"$TEST_CONTENT\",\"source\":\"health-check\"}},\"id\":2}'" >/dev/null 2>&1 || {
              kill $SSE_PID 2>/dev/null || true; rm -f "$SSE_OUT"
              log "FAIL: MCP remember tool failed"
              exit 1
            }

            # Recall and verify
            sleep 2
            RESULT=$(eval "$MCP -d '{\"jsonrpc\":\"2.0\",\"method\":\"tools/call\",\"params\":{\"name\":\"recall\",\"arguments\":{\"query\":\"$TEST_CONTENT\"}},\"id\":3}'" 2>/dev/null) || true

            kill $SSE_PID 2>/dev/null || true
            rm -f "$SSE_OUT"

            if ! echo "$RESULT" | grep -q "$TEST_CONTENT"; then
              log "FAIL: Write/recall test failed — result: $(echo "$RESULT" | head -c 200)"
              exit 1
            fi

            log "PASS: integrity OK, MCP functional, write/recall verified"

            # Reset consecutive failures
            echo 0 > "$FAILURES_FILE"

            # Rotate log
            tail -n 500 "$HEALTH_LOG" > "$HEALTH_LOG.tmp" 2>/dev/null
            mv "$HEALTH_LOG.tmp" "$HEALTH_LOG" 2>/dev/null || true
          '';
        };

        systemd.timers.memory-health-check = {
          description = "Mnemosyne health check timer";
          wantedBy = [ "timers.target" ];
          timerConfig = {
            OnCalendar = "*:0/30";
            RandomizedDelaySec = 60;
            Persistent = true;
          };
        };

        # ── Daily SQLite backup ───────────────────────────────────
        systemd.services.memory-backup = {
          description = "Daily Mnemosyne database backup";
          after = [ "memory-compose.service" ];
          path = [ pkgs.sqlite ];
          serviceConfig = {
            Type = "oneshot";
            User = cfg.baseUsername;
          };
          script = ''
            set -euo pipefail
            DB="${dataDir}/mnemosyne.db"
            BACKUP="${backupDir}/mnemosyne-$(date +%Y%m%d).db"
            RETENTION_DAYS=7

            if [ -f "$DB" ]; then
              sqlite3 "$DB" ".backup '$BACKUP'"
              echo "Backup created: $BACKUP ($(stat -c%s "$BACKUP") bytes)"

              # Rotate old backups
              find "${backupDir}" -name "mnemosyne-*.db" -mtime +$RETENTION_DAYS -delete 2>/dev/null || true
            else
              echo "No database to back up (not yet created)"
            fi
          '';
        };

        systemd.timers.memory-backup = {
          description = "Daily Mnemosyne database backup";
          wantedBy = [ "timers.target" ];
          timerConfig = {
            OnCalendar = "daily";
            RandomizedDelaySec = 1800;
            Persistent = true;
          };
        };
      };
    };
}
