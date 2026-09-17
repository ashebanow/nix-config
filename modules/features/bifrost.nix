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
# ANTHROPIC_API_KEY, MINIMAX_API_KEY for the remote providers) are resolved from
# BWS via secretspec at start. Values live only in the process environment;
# config.json references the provider keys by name (env.<VAR>), never by value.
# Compose + config are symlinked to /etc/bifrost via tmpfiles below.
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
  my.modules.nixos.bifrost = {
    lib,
    pkgs,
    config,
    ...
  }: {
    config = lib.mkIf config.my.bifrostServe {
      systemd.tmpfiles.rules = [
        "d /etc/bifrost 0755 root root -"
        "L+ /etc/bifrost/compose.yml - - - - ${../../compose/llm/bifrost-compose.yml}"
        "L+ /etc/bifrost/config.json - - - - ${../../compose/llm/bifrost-config.json}"
      ];

      systemd.services.bifrost-compose = {
        description = "Bifrost LLM gateway compose stack";
        after = ["network-online.target" "podman-network-llm-internal.service"];
        wants = ["network-online.target"];
        requires = ["podman-network-llm-internal.service"];
        wantedBy = ["multi-user.target"];
        # The unit text never changes when only the symlinked compose/config
        # content does, so without this a rebuild leaves the old stack running.
        # A change here re-runs ExecStop (`down`, no -v) + ExecStart; the named
        # data volume — and the request logs in it — survive (BOX-133).
        restartTriggers = [
          "${../../compose/llm/bifrost-compose.yml}"
          "${../../compose/llm/bifrost-config.json}"
        ];
        path = [
          pkgs.podman
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
            # DEEPSEEK_API_KEY, ANTHROPIC_API_KEY, MINIMAX_API_KEY) into this
            # environment; podman-compose substitutes them in compose.yml.
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
        path = [pkgs.sqlite pkgs.coreutils pkgs.systemd];
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
        wantedBy = ["timers.target"];
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
    };
  };
}
