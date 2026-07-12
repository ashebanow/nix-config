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
        };

        # Data directory and backup directory
        systemd.tmpfiles.rules = [
          "d ${dataDir} 0755 ${cfg.baseUsername} ${cfg.baseUsername} -"
          "d ${backupDir} 0755 ${cfg.baseUsername} ${cfg.baseUsername} -"
          "d /etc/memory 0755 root root -"
          "L+ /etc/memory/compose.yml - - - - ${../../compose/memory/compose.yml}"
          "L+ /etc/memory/Dockerfile - - - - ${../../containers/mnemosyne/Dockerfile}"
        ];

        # ── Mnemosyne compose stack ──────────────────────────────
        systemd.services.memory-compose =
          let
            tsAuthKeyPath = config.sops.secrets."mnemo-tailscale-auth-key".path;
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
              ];
              ExecStartPre = pkgs.writeShellScript "memory-build-image" ''
                set -e
                # Build Mnemosyne image if not already present
                if ! podman image exists mnemosyne-memory:latest 2>/dev/null; then
                  echo "Building mnemosyne-memory image..."
                  podman build -t mnemosyne-memory:latest -f /etc/memory/Dockerfile /etc/memory
                fi
              '';
              ExecStart = pkgs.writeShellScript "memory-compose-start" ''
                set -e
                export XDG_RUNTIME_DIR="/run/user/$(id -u)"
                export MEMORY_TS_AUTHKEY="$(cat $CREDENTIALS_DIRECTORY/ts-auth-key)"
                exec podman-compose -f /etc/memory/compose.yml up -d
              '';
              ExecStop = "${pkgs.podman-compose}/bin/podman-compose -f /etc/memory/compose.yml down";
            };
          };

        # ── Health check (systemd timer, every 30 min) ────────────
        systemd.services.memory-health-check = {
          description = "Mnemosyne end-to-end health check";
          after = [ "memory-compose.service" ];
          requires = [ "memory-compose.service" ];
          path = [ pkgs.curl pkgs.sqlite ];
          serviceConfig = {
            Type = "oneshot";
            User = cfg.baseUsername;
          };
          script = ''
            set -euo pipefail
            DB="${dataDir}/mnemosyne.db"
            BASE="https://memory.fluffy-walleye.ts.net"
            TIMESTAMP=$(date -u +%s)
            HEALTH_LOG="${dataDir}/health.log"
            FAILURES_FILE="${dataDir}/consecutive_failures"

            log() { echo "[$(date -u +%Y-%m-%dT%H:%M:%SZ)] $*" | tee -a "$HEALTH_LOG"; }

            # 1. SQLite integrity
            if ! sqlite3 "$DB" "PRAGMA integrity_check;" 2>/dev/null | grep -q "ok"; then
              log "FAIL: SQLite integrity check failed"
              exit 1
            fi

            # 2. MCP endpoint health
            if ! curl -sf "$BASE/health" >/dev/null 2>&1; then
              log "FAIL: MCP health endpoint unreachable"
              exit 1
            fi

            # 3. Write + recall test
            # Mnemosyne MCP uses JSON-RPC over Streamable HTTP
            SESSION=$(curl -sf -X POST "$BASE/mcp" \
              -H "Content-Type: application/json" \
              -d "{\"jsonrpc\":\"2.0\",\"method\":\"initialize\",\"params\":{\"protocolVersion\":\"2024-11-05\",\"capabilities\":{},\"clientInfo\":{\"name\":\"health-check\",\"version\":\"1.0\"}},\"id\":1}" \
              | grep -o '"sessionId":"[^"]*"' | cut -d'"' -f4)

            if [ -z "$SESSION" ]; then
              log "FAIL: Could not establish MCP session"
              exit 1
            fi
            MCP="curl -sf -X POST $BASE/mcp -H 'Content-Type: application/json' -H 'Mcp-Session-Id: $SESSION'"

            # Store a test memory
            TEST_CONTENT="health-check-ping-$TIMESTAMP"
            eval "$MCP -d '{\"jsonrpc\":\"2.0\",\"method\":\"tools/call\",\"params\":{\"name\":\"remember\",\"arguments\":{\"content\":\"$TEST_CONTENT\",\"source\":\"health-check\"}},\"id\":2}'" >/dev/null 2>&1

            # Recall it (give it a moment to index)
            sleep 2
            RESULT=$(eval "$MCP -d '{\"jsonrpc\":\"2.0\",\"method\":\"tools/call\",\"params\":{\"name\":\"recall\",\"arguments\":{\"query\":\"health-check-ping\"}},\"id\":3}'" 2>/dev/null)

            if ! echo "$RESULT" | grep -q "$TEST_CONTENT"; then
              log "FAIL: Write/recall test failed — stored content not found"
              exit 1
            fi

            log "PASS: integrity OK, MCP healthy, write/recall verified"

            # Reset consecutive failures
            echo 0 > "$FAILURES_FILE"

            # Rotate log
            tail -n 500 "$HEALTH_LOG" > "${HEALTH_LOG}.tmp" 2>/dev/null
            mv "${HEALTH_LOG}.tmp" "$HEALTH_LOG" 2>/dev/null || true
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
