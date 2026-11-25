# Bifrost LLM gateway — replaces the LiteLLM proxy.
#
# Bifrost is a Go gateway; LiteLLM is Python. The switch is specifically to
# escape the streaming-body truncation that forced clients to disable
# streaming, and the occasional hangs the relay workaround never fixed.
#
# Runs as a podman-compose stack (compose/llm/bifrost-compose.yml) whose
# gateway container shares a Tailscale sidecar's network namespace, so nothing
# is published on the host. Served at https://ai.fluffy-walleye.ts.net —
# named for its function, so a future gateway swap does not move the endpoint.
#
# Secrets (bifrost scope: BIFROST_TS_AUTHKEY for the sidecar; DEEPSEEK_API_KEY,
# ANTHROPIC_API_KEY, MINIMAX_API_KEY, SUBQ_API_KEY for the remote providers) are
# resolved from BWS via secretspec at start. Values live only in the process
# environment; config.json references the provider keys by name (env.<VAR>),
# never by value. Compose + config are symlinked to /etc/bifrost via tmpfiles
# below.
#
# SubQ (https://docs.subq.ai) is reached over its OpenAI-compatible Chat
# Completions API as the `subq` custom provider. Only subq-savant-1.4 is wired:
# SubQ Snap's Decisions API (/v1/systemone) returns typed probabilities in a
# shape that is not OpenAI-compatible, so bifrost cannot proxy it — call it
# directly, reading the same SUBQ_API_KEY from BWS.
#
# Gated behind my.bifrostServe, separate from my.llmServe, so bifrost and
# LiteLLM can run side by side until the cutover completes.
#
# The sidecar joins the `llm-internal` bridge (podman-network-llm-internal
# .service, in llm.nix) and bifrost reaches llama-server at `qwen-35b-a3b:8080`
# on it — not over the tailnet. Two tailnet nodes on one host can't hole-punch,
# so that hop is DERP-relayed and truncates request bodies over ~5 KB
# (BOX-140). host.containers.internal isn't an option: bifrost's SSRF guard
# hard-blocks link-local (169.254.x). RFC1918 over the bridge + the provider's
# allow_private_network flag is the fix.
_: {
  my.modules.nixos.bifrost =
    {
      lib,
      pkgs,
      config,
      ...
    }:
    let
      obs = import ../../lib/observability.nix { inherit lib; };

      # ── Where bifrost's request log lives ────────────────────────────
      #
      # The compose stack mounts the named volume `bifrost-data` at
      # `/app/data` (compose/llm/bifrost-compose.yml), and this is the same
      # path the vacuum timer in this module already uses. Rootless podman puts
      # a named volume under the *owning user's* data dir, volume name prefixed
      # with the compose project name (`bifrost`), which is why the directory is
      # `bifrost_bifrost-data`.
      bifrostDataDir = "/home/${config.my.baseUsername}/.local/share/containers/storage/volumes/bifrost_bifrost-data/_data";
      bifrostLogsDb = "${bifrostDataDir}/logs.db";

      # The table the request-log rows live in, and the column carrying their
      # time.
      #
      # **This is bifrost's internal schema and upstream may rename it.** It was
      # read from source rather than guessed: `framework/logstore/tables.go` in
      # maximhq/bifrost defines `type Log struct` with `func (Log) TableName()
      # string { return "logs" }` and a `Timestamp time.Time` field (GORM's
      # default column name, so the column is `timestamp`). There is no
      # `created_at` on that struct — `agent_logs` and `mcp_tool_logs` have one,
      # `logs` does not, so using it would have produced a permanently broken
      # check.
      #
      # The check is nevertheless written so a wrong name is a *visible* failure
      # rather than a silent zero: a sqlite error (no such column) makes
      # `sqliteCheck` emit `_success 0` and exit non-zero, so the unit goes
      # failed, the generic `SystemdUnitFailed` rule fires, and the cause is one
      # `journalctl` away.
      #
      # `iso` is the right time format: the driver opens with
      # `_journal_mode=WAL` and no `_time_format` override, so GORM stores
      # `time.Time` as a text timestamp that `strftime('%s', …)` parses.
      bifrostLogTable = "logs";
      bifrostLogTimeColumn = "timestamp";
    in
    {
      config = lib.mkIf config.my.bifrostServe {
        systemd.tmpfiles.rules = [
          "d /etc/bifrost 0755 root root -"
          "L+ /etc/bifrost/compose.yml - - - - ${../../compose/llm/bifrost-compose.yml}"
          "L+ /etc/bifrost/config.json - - - - ${../../compose/llm/bifrost-config.json}"
        ];

        systemd.services.bifrost-compose = {
          description = "Bifrost LLM gateway compose stack";
          after = [
            "network-online.target"
            "podman-network-llm-internal.service"
          ];
          wants = [ "network-online.target" ];
          requires = [ "podman-network-llm-internal.service" ];
          wantedBy = [ "multi-user.target" ];
          # The unit text never changes when only the symlinked compose/config
          # content does, so without this a rebuild leaves the old stack running.
          # A change here re-runs ExecStop (`down`, no -v) + ExecStart; the named
          # data volume — and the request logs in it — survive (BOX-133).
          #
          # The manifest is watched too: adding or rotating a bifrost-scope
          # secret that neither compose.yml nor config.json names (a value only
          # read via `env.` at runtime) would otherwise leave the old env in the
          # running container until something else happened to cycle the stack.
          restartTriggers = [
            "${../../compose/llm/bifrost-compose.yml}"
            "${../../compose/llm/bifrost-config.json}"
            config.my.secretspecManifest
            # A runtime bump must cycle the gateway stack: its containers were
            # created by the podman in `path` above. Bifrost recovers in seconds
            # (no model to load), so this is the cheapest of the four.
            config.virtualisation.podman.package
          ];
          path = [
            config.virtualisation.podman.package
            pkgs.podman-compose
            pkgs.secretspec
            pkgs.bws
          ];
          serviceConfig = {
            Type = "oneshot";
            RemainAfterExit = "yes";
            User = config.my.baseUsername;
            Environment = [
              "SECRETSPEC_FILE=${config.my.secretspecManifest}"
              "SECRETSPEC_PROVIDER=bws-service"
            ];
            LoadCredential = [
              "access_token:${config.my.bwsAccessTokenFile}"
            ];
            ExecStart = pkgs.writeShellScript "bifrost-compose-start" ''
              set -e
              export XDG_RUNTIME_DIR="/run/user/$(id -u)"
              # secretspec injects the bifrost scope (BIFROST_TS_AUTHKEY,
              # DEEPSEEK_API_KEY, ANTHROPIC_API_KEY, MINIMAX_API_KEY,
              # SUBQ_API_KEY) into this environment; podman-compose substitutes
              # them in compose.yml.
              exec ${pkgs.secretspec}/bin/secretspec run -P production -S bifrost -- \
                ${pkgs.podman-compose}/bin/podman-compose -f /etc/bifrost/compose.yml up -d
            '';
            ExecStop = "${pkgs.podman-compose}/bin/podman-compose -f /etc/bifrost/compose.yml down";
          };
        };

        # Bifrost's log cleaner deletes expired rows in batches and never
        # VACUUMs (framework/logstore/cleaner.go), so the pages it frees land in
        # SQLite's freelist rather than back on the filesystem. logs.db only
        # ratchets upward no matter what log_retention_days says: dropping
        # retention 30 -> 7 deleted 93 rows and moved the file 1,627,226,112 ->
        # 1,627,258,880 bytes, i.e. up. This timer is what actually reclaims the
        # space; retention alone does not (BOX-202).
        #
        # VACUUM rewrites the whole database and wants exclusive access, so the
        # stack goes down for the duration. The trap fires on any exit path, so
        # a sqlite failure costs the space, never the gateway.
        systemd.services.bifrost-vacuum = {
          description = "Reclaim freelist space in the bifrost sqlite databases";
          path = [
            pkgs.sqlite
            pkgs.coreutils
            pkgs.systemd
          ];
          serviceConfig = {
            Type = "oneshot";
            # A 1.6 GB rewrite is seconds on NVMe, but the stack is down for it.
            TimeoutStartSec = "30m";
            ExecStart = pkgs.writeShellScript "bifrost-vacuum" ''
              set -euo pipefail
              data=/home/podman/.local/share/containers/storage/volumes/bifrost_bifrost-data/_data

              trap 'systemctl start bifrost-compose.service || true' EXIT
              systemctl stop bifrost-compose.service

              for db in logs.db config.db; do
                f="$data/$db"
                [ -f "$f" ] || continue

                # These files belong to the container's uid (999, mapped into
                # podman's subuid range), not to root. sqlite recreates the
                # database and its -wal/-shm sidecars as whoever ran it, and a
                # sidecar the container cannot write makes bifrost crash-loop on
                # "attempt to write a readonly database" at the next start — so
                # capture ownership first and put it back afterwards rather than
                # hardcoding the mapped uid.
                owner="$(stat -c '%u:%g' "$f")"
                before="$(stat -c %s "$f")"

                sqlite3 "$f" 'VACUUM;'

                for p in "$f" "$f-wal" "$f-shm"; do
                  if [ -e "$p" ]; then chown "$owner" "$p"; fi
                done

                echo "$db: $before -> $(stat -c %s "$f") bytes"
              done
            '';
          };
        };

        systemd.timers.bifrost-vacuum = {
          description = "Weekly bifrost sqlite vacuum";
          wantedBy = [ "timers.target" ];
          timerConfig = {
            # The cleaner prunes daily, so freelist pages accumulate daily too;
            # weekly keeps the file near its steady state without paying the
            # downtime every night. Persistent so a box that was off over the
            # window still catches up.
            OnCalendar = "Sun 04:00";
            RandomizedDelaySec = "30m";
            Persistent = true;
          };
        };

        # ── Observability: what the request log is doing (BOX-332) ───────
        #
        # BOX-207: the log grew to 1.63 GB in eight days and nothing noticed,
        # because the only way to see it was to SSH in and run `stat` by hand.
        # This publishes its size, row count and newest-row age as metrics so
        # the growth is a graph and an alert instead of a diagnosis.
        #
        # The query is read-only by construction — `obs.sqliteCheck` opens
        # `file:…?mode=ro&immutable=1` and passes `-readonly` — so it cannot take
        # the write lock that leaves `-wal`/`-shm` sidecars owned by the reader
        # and crash-loops bifrost on "attempt to write a readonly database"
        # (BOX-202). That is the whole reason the builder exists rather than a
        # shell one-liner in this module.
        #
        # `user = podman` is the owning account, as the contract asks. It is not
        # quite enough on its own: rootless podman stores the volume's files as
        # a uid mapped into `podman`'s *subuid* range, so `podman` cannot read
        # its own container's data. `unreadableAs` is the documented escape
        # hatch for exactly that — the check probes the file as `podman` and
        # re-execs as root when it cannot. Root is safe here only because the
        # query cannot write, which the builder guarantees. This is also why it
        # is right to state it in the option rather than discovering it as a
        # permanently red unit on the host.
        my.observability.textfileChecks.bifrost-logs-db = obs.sqliteCheck {
          name = "bifrost-logs-db";
          database = bifrostLogsDb;
          table = bifrostLogTable;
          timeColumn = bifrostLogTimeColumn;
          user = config.my.baseUsername;
          unreadableAs = bifrostLogsDb;
        };

        # The rules live beside this module, per the rules contract: they are
        # native vmalert YAML and are gathered by the observability host at
        # build time, which means adding or changing one is a `just switch` on
        # calamansi.
        my.observability.rules.bifrost = {
          files = [ ./bifrost.rules.yaml ];
          type = "metrics";
        };

        # The dashboard is BBOX-331's LLM dashboard territory, so this ticket
        # ships its own instead of editing a file another ticket owns. See
        # BOX-332.md for what BOX-331/BOX-338 need to link to it.
        my.observability.dashboards.bifrost = {
          path = ./bifrost.dashboard.json;
        };
      };
    };
}
