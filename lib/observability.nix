# Rendering helpers for the `my.observability` option set.
#
# These turn the collections declared in lib/my-options-module.nix into the
# native config formats the services actually read: Prometheus scrape config
# for vmagent, and Grafana provisioning for the host. The point of keeping them
# here rather than inline in a module is that two consumers need the same
# shape — the agent renders what it scrapes, the host renders what it gathers
# from everyone — and a single implementation cannot drift from itself.
#
# The textfile-check builders (BOX-332's `sqliteCheck` and `textfileScript`) are
# here for the same reason: the agent renders the runner, and the contract test
# and a feature module both reason about the same rendered script.
{ lib }:
rec {
  # ── Scrape targets ────────────────────────────────────────────────────
  #
  # One `scrape_configs` entry per named target. The entry's name is the
  # `job_name`, which is what a dashboard filters on, so it is deliberately
  # the key from `my.observability.scrapeTargets` and nothing else.
  #
  # `targets` is a list even for a single address because that is what
  # Prometheus' config requires; the option takes a string and may carry
  # several comma-separated addresses for a multi-instance service.
  scrapeTargetToJob =
    name: target:
    let
      hosts = map (s: lib.trim s) (lib.splitString "," target.address);
      staticConfig = {
        targets = hosts;
      }
      // lib.optionalAttrs (target.labels != { }) {
        labels = target.labels;
      };
    in
    {
      job_name = name;
      metrics_path = target.metricsPath;
      static_configs = [ staticConfig ];
    }
    // lib.optionalAttrs (target.interval != null) { scrape_interval = target.interval; }
    // lib.optionalAttrs (target.scrapeTimeout != null) { scrape_timeout = target.scrapeTimeout; };

  # `scrapeTargets` attrset -> the `scrape_configs` list vmagent reads.
  # Sorted by name so the rendered config is byte-stable: an attrset's order
  # is not defined, and a config that reorders on every eval would restart
  # vmagent for no reason and make the diff worthless.
  renderScrapeConfigs = scrapeTargets: lib.mapAttrsToList scrapeTargetToJob scrapeTargets;

  # The whole Prometheus scrape config document. Named after the file the
  # service consumes so a reader can go straight from a rendered path to this
  # function.
  mkPrometheusScrapeConfig = scrapeTargets: {
    scrape_configs = renderScrapeConfigs scrapeTargets;
  };

  # ── Dashboards ────────────────────────────────────────────────────────
  #
  # A dashboard provider watches a directory, so gathering every host's
  # dashboards is a link farm: one symlink per declared file, named after the
  # collection key. Two hosts declaring the same key is a collision, and the
  # assertion in observability-host.nix catches it — a silent overwrite would
  # look like one host's dashboard simply not existing.
  mkDashboardLinks =
    dashboards:
    lib.mapAttrs' (name: dashboard: lib.nameValuePair "${name}.json" dashboard.path) dashboards;

  # ── Alert rules ───────────────────────────────────────────────────────
  #
  # A ruleset is a named entry in `my.observability.rules` with a list of YAML
  # files; vmalert loads a *directory* of them. Two transformations are needed
  # and both are here because the host and the contract test must agree on the
  # result exactly.
  #
  # The file name is derived from the ruleset key and the position in `files`
  # (`<ruleset>.0.yaml`, `<ruleset>.1.yaml`), never from the source file's own
  # name: two features may both ship `alerts.yaml`, and a collision there would
  # silently drop one of them. Sorting by name makes the directory listing
  # byte-stable, so a rebuild that changed nothing re-uses the same derivation.
  mkRuleFiles =
    rulesets:
    lib.sort (a: b: a.name < b.name) (
      lib.concatLists (
        lib.mapAttrsToList (
          name: ruleset:
          lib.imap0 (index: path: {
            name = "${name}.${toString index}.yaml";
            inherit path;
          }) ruleset.files
        ) rulesets
      )
    );

  # The rulesets that belong to one vmalert instance. `type` is `metrics` or
  # `logs`, and it selects which datasource the files are evaluated against.
  rulesetsOfType = type: rulesets: lib.filterAttrs (_: ruleset: ruleset.type == type) rulesets;

  # ── Alertmanager configuration ────────────────────────────────────────
  #
  # Rendered as an attrset and serialised by the caller, so the route tree can
  # be read (and asserted on) as data rather than as YAML text.
  #
  # ## The secret indirection
  #
  # `token`/`user_key`/`url` below are `${VAR}` *references*, not values: the
  # Alertmanager module runs `envsubst` over the rendered file at build time, and
  # the environment it sees has none of these variables set — so they survive
  # into the store as literal `${PUSHOVER_APP_TOKEN}` text and are substituted at
  # start-up by `secretspec run`, which holds the only copy of the values. That
  # is the whole mechanism, and it is why the store never contains a token.
  #
  # The `${VAR}` text is deliberate, and `\${` is what the caller writes so
  # that Nix emits exactly it — not an interpolation of a Nix variable, and not
  # the `$${VAR}` escaping Alertmanager documents for a `$` it should keep.
  #
  # ## Grouping
  #
  # BOX-320: group by rule and host, 30 s group wait, repeat critical hourly and
  # warning every 12 h. `host` is not a label the rules have to carry: vmagent
  # attaches `instance` to every series it scrapes and vmalert copies the
  # alerting series' labels onto the alert, so the generic rules get their
  # hostname for free. The Watchdog (`vector(1)`) has no `instance`, so it
  # groups by `alertname` alone — which for a single always-firing alert is the
  # same thing.
  #
  # ## Severity → Pushover priority
  #
  # Pushover's `priority` is a per-notification value, so the receiver's is a
  # Go template over the alert's severity label rather than two receivers. The
  # `pushover_configs` field is a string so the template survives serialisation
  # unquoted.
  mkAlertmanagerConfig =
    {
      healthchecksReceiverUrl,
    }:
    {
      global = {
        resolve_timeout = "5m";
      };
      route = {
        receiver = "pushover";
        group_by = [
          "alertname"
          "host"
        ];
        group_wait = "30s";
        group_interval = "5m";
        repeat_interval = "1h";
        routes = [
          {
            # The Watchdog is not an alert for a human: it goes only to the
            # healthchecks.io bridge, at the one-minute cadence that service
            # expects, and never to the phone.
            receiver = "healthchecks";
            matchers = [ "severity=\"none\"" ];
            group_wait = "0s";
            group_interval = "1m";
            repeat_interval = "1m";
          }
          {
            # BOX-320: a warning repeats every 12 h rather than hourly, so a
            # slow-burning condition does not become a phone that buzzes all
            # day. Critical keeps the route default (hourly).
            receiver = "pushover";
            matchers = [ "severity=\"warning\"" ];
            repeat_interval = "12h";
          }
        ];
      };
      receivers = [
        {
          name = "pushover";
          pushover_configs = [
            {
              token = "\${PUSHOVER_APP_TOKEN}";
              user_key = "\${PUSHOVER_USER_KEY}";
              # 1 for critical (sounds once, bypasses quiet hours), 0 for
              # warning (respects them). No emergency priority in v1: an
              # unacknowledged repeat-until-ack at 3 a.m. is how Pushover gets
              # muted, and then nothing arrives at all.
              priority = "{{ if eq .CommonLabels.severity \"critical\" }}1{{ else }}0{{ end }}";
              # A resolve is worth knowing about; Pushover shows it at normal
              # priority because Alertmanager sends its own notification.
              send_resolved = true;
              title = "{{ .CommonLabels.alertname }}";
              message = "{{ range .Alerts }}{{ .Annotations.summary }}{{ if .Annotations.description }}\n{{ .Annotations.description }}{{ end }}{{ end }}";
            }
          ];
        }
        {
          name = "healthchecks";
          webhook_configs = [
            {
              # Loopback: the bridge is a sidecar of this host and is not
              # reachable from anywhere else.
              url = healthchecksReceiverUrl;
              send_resolved = false;
              max_alerts = 1;
            }
          ];
        }
      ];
      # No `inhibit_rules`: v1's rule list has no alert whose firing makes
      # another meaningless, and an unnecessary inhibition is an alert that
      # silently never arrives. Add one only alongside the rule that needs it.
      inhibit_rules = [ ];
    };

  # ── VictoriaLogs endpoints ────────────────────────────────────────────
  #
  # The journald ingest URL, in one place because two modules need to agree on
  # it: the host opens a firewall port for it, the agent uploads to it. A
  # mismatch there is the worst kind of bug — the firewall looks right, the
  # uploader looks right, and nothing arrives.
  #
  # `/insert/journald` is VictoriaLogs' native systemd-journal ingest endpoint:
  # it accepts the journal's own binary encoding
  # (`application/vnd.fdo.journal`), which is exactly what
  # `systemd-journal-upload` sends. It is not a JSON endpoint with a journald
  # name; VictoriaLogs' own error string is "only application/vnd.fdo.journal
  # encoding is supported for Journald". So no translation layer is needed — see
  # the module header in modules/features/observability-agent.nix for the
  # alternatives that were rejected.
  #
  # Upstream writes the same URL path (`/insert/journald`) in its setup docs;
  # `/insert/journald/upload` also exists and is what the metric name
  # `vl_http_request_duration_seconds{path="/insert/journald/upload"}` reports,
  # but the documented value is used here so a future reader comparing our
  # config to the upstream page sees the same string.
  journalUploadUrl = hostAddress: port: "http://${hostAddress}:${toString port}/insert/journald";

  # ── Textfile checks (BOX-332) ─────────────────────────────────────────
  #
  # node_exporter's textfile collector reads `*.prom` out of one directory on
  # every scrape (`--collector.textfile.directory`, set by the agent module). A
  # *check* answers a question only a command can answer — a database's size, a
  # certificate's remaining days — so the arrangement is a systemd timer that
  # runs the command and drops its output into that directory as
  # `<name>.prom`.
  #
  # Three properties this section exists to guarantee, each with its comment
  # where it is implemented:
  #
  #   the file lands whole         `emitTextfile` below (temp file + rename(2))
  #   the reader can read it       `install -m 0644`, not the writer's umask
  #   the check cannot write       `sqliteCheck` opens `mode=ro&immutable=1`
  #
  # The directory is root-owned and NOT writable by a check's user: a check that
  # could create files there could also replace another check's output.
  textfileDirectory = "/var/lib/node_exporter/textfile";

  # The shell prelude every generated check script is wrapped in.
  #
  # `emitTextfile` takes prom text on stdin, so a builder pipes its output
  # straight in. The temp file is created in the *same* directory as the target
  # so `mv` is a rename within one filesystem — atomic, so a scrape sees either
  # the previous complete file or the new complete file, never a truncated one.
  # (A half-written file is a parse error for that scrape, which looks exactly
  # like the check having failed.) `$$` keeps two invocations from colliding.
  #
  # `chmod 0644` is explicit rather than inherited because the writer's umask is
  # whatever systemd gives it and node_exporter reads as its own user.
  emitTextfile = name: ''
    emit_textfile() {
      tmp="${textfileDirectory}/.${name}.prom.$$"
      trap 'rm -f "$tmp"' EXIT
      cat > "$tmp"
      chmod 0644 "$tmp"
      mv -f "$tmp" "${textfileDirectory}/${name}.prom"
      trap - EXIT
    }
  '';

  # A complete check script: the prelude, then the caller's body, which is
  # expected to end by piping prom text into `emit_textfile`.
  #
  # `set -u` and `pipefail` but deliberately **not** `set -e`: a check that
  # fails partway should still publish what it knows (`..._success 0`) rather
  # than leaving the previous file in place looking healthy forever.
  textfileScript =
    name: body: ''
      set -uo pipefail
      umask 022
      ${emitTextfile name}
      ${body}
    '';

  # ── sqlite checks ─────────────────────────────────────────────────────
  #
  # A `sqliteCheck` reports one sqlite file's byte size, its row count and how
  # old its newest row is — BOX-207's list, and the shape that closes "the file
  # grew to 1.6 GB in eight days and nothing noticed".
  #
  # ## THE BOX-202 TRAP: this must never open the database for writing
  #
  # A sqlite connection that takes a write lock on a database another uid owns
  # can leave `-wal`/`-shm` sidecars owned by *the reader's* uid. The owning
  # service then crash-loops on "attempt to write a readonly database". That
  # happened on lumquat while diagnosing BOX-149; it is why the vacuum script
  # captures and restores ownership rather than hardcoding a uid.
  #
  # Every query here is therefore opened `mode=ro&immutable=1`:
  #
  #   mode=ro       the connection cannot write. A write is refused with
  #                 SQLITE_READONLY instead of taking a lock.
  #   immutable=1   sqlite treats the file as unchanging: it skips the whole
  #                 lock protocol and reads no `-wal`. So it creates no `-shm`
  #                 when one is missing, takes no lock, and cannot create or
  #                 chown a sidecar. This is the flag that makes "read the file
  #                 without touching the directory" literal rather than
  #                 hopeful.
  #
  # `-readonly` is passed to the CLI as well, belt and braces: it is a *second*
  # refusal at the sqlite3 layer, and it is what makes the query read-only even
  # if a future edit drops the URI.
  #
  # **The cost of immutable=1, stated plainly**: uncommitted `-wal` content is
  # invisible, so the row count can trail the live database by whatever the
  # writer has not checkpointed, and `oldest_row_age_seconds` is the age of the
  # newest *checkpointed* row. For a growth signal over hours that is a fine
  # trade — and it is the only reading guaranteed to be side-effect-free, which
  # is the property BOX-202 says must win.
  #
  # ## Other choices worth knowing
  #
  #   - **The database is opened by path, never copied.** A copy of a 1.6 GB
  #     database is a second 1.6 GB write on the disk that just ran out of
  #     space.
  #   - **`size_bytes` is `stat`, not sqlite.** It is the number that grew, it
  #     survives a failed query (so "size fine, rows unreadable" is
  #     distinguishable from "size zero"), and it is the on-disk size including
  #     the freelist — `page_count * page_size` is the *logical* size and misses
  #     exactly the gap BOX-202 hit.
  #   - **A failure is emitted, not swallowed.** The script writes
  #     `<prefix>_success 0` and exits 1, so the series says "collected and
  #     broken" (not "never collected") and the unit's failed state shows up in
  #     `node_systemd_unit_state`. One silently dead check for a month is the
  #     failure mode this whole ticket exists to remove.
  #   - **No rows means NaN, not zero.** An empty database's "oldest row" has no
  #     age; reporting 0 would read as "just wrote a row".
  #
  # ## Parameters
  #
  #   `name`        the collection key. Becomes `<name>.prom` and the metric
  #                 prefix — `bifrost-logs-db` emits
  #                 `bifrost_logs_db_size_bytes`, with `-`/`.` replaced by `_`
  #                 because a Prometheus metric name may not contain them.
  #   `database`    absolute path to the sqlite file on this host.
  #   `table`       table to count. Required, not guessed: a wrapper's own
  #                 bookkeeping tables are not a log.
  #   `timeColumn`  column whose maximum is the newest row's timestamp.
  #   `timeFormat`  `iso` (a SQLite text timestamp such as bifrost's
  #                 `2026-09-16T20:36:21Z`, compared with `strftime('%s', …)`),
  #                 `unix` (integer seconds) or `unixmilli`.
  #   `user`        the account the check runs as — the database's **owning**
  #                 user, so it needs read permission rather than privilege.
  #   `unreadableAs`  see "the escape hatch" below. `null` by default.
  #
  # ## The escape hatch (`unreadableAs`), and why it is not the default
  #
  # A rootless container's volume is owned by a uid mapped into the owning
  # user's *subuid* range. The owning user therefore cannot read its own
  # container's data, while root can — so "run as the owning user" would
  # produce a permanently failing unit on exactly the host this ticket targets.
  #
  # `unreadableAs` names the path the owning user is expected to read. Each run
  # probes it **as that user** (`runuser -u <user> -- test -r <path>`); if the
  # probe fails, the check re-execs itself as root. The unit is consequently
  # `User=root` (a unit that started as the owning user could not become root
  # for the fallback), and `sudo`/`runuser` is what drops to the owning account —
  # the direction is root → user, so this can only ever *retain* privilege, not
  # escalate it.
  #
  # Running it as root is safe here **only because the query cannot write**: the
  # BOX-202 trap is a write-lock sidecar, and `mode=ro&immutable=1` takes no
  # lock at all. A builder that writes to its data must not offer this option.
  sqliteCheck =
    {
      name,
      database,
      table,
      timeColumn ? "created_at",
      timeFormat ? "iso",
      user,
      unreadableAs ? null,
    }:
    let
      prefix = builtins.replaceStrings [ "-" "." ] [ "_" "_" ] name;

      # Epoch seconds of the newest row, per format. `iso` compares with
      # `strftime` on the same call path that wrote the value, so nothing here
      # assumes a timezone.
      newestExpr =
        {
          iso = "CAST(strftime('%s', ${timeColumn}) AS INTEGER)";
          unix = "CAST(${timeColumn} AS INTEGER)";
          unixmilli = "CAST(${timeColumn} AS INTEGER) / 1000";
        }
        .${timeFormat}
          or (throw "sqliteCheck: timeFormat must be iso, unix or unixmilli");

      # One row, two columns, space-separated: `<count> <newest-epoch>`.
      # `coalesce(…, 0)` so an empty table reports 0 rather than NULL, and the
      # caller turns 0 into NaN.
      query = "SELECT count(*) || ' ' || coalesce(max(${newestExpr}), 0) FROM ${table};";

      header = ''
        echo '# HELP ${prefix}_size_bytes On-disk size of the sqlite file in bytes (includes the freelist).'
        echo '# TYPE ${prefix}_size_bytes gauge'
        echo "${prefix}_size_bytes ''${size}"
      '';

      body = ''
        db=${lib.escapeShellArg database}

        # Always published, even if the query below fails: this is the series
        # that would have caught BOX-202.
        size=$(stat -c %s "$db" 2>/dev/null || echo 0)

        if read -r rows newest < <(
          sqlite3 "file:$db?mode=ro&immutable=1" -readonly -noheader ${lib.escapeShellArg query} 2>/dev/null
        ); then
          now=$(date +%s)
          # No rows means no age to report. NaN rather than 0 so an empty
          # database does not read as a freshly written one.
          if [ "''${newest:-0}" -gt 0 ]; then
            age=$(( now - newest ))
          else
            age=NaN
          fi
          {
            ${header}
            echo '# HELP ${prefix}_rows Rows in ${table}.'
            echo '# TYPE ${prefix}_rows gauge'
            echo "${prefix}_rows ''${rows}"
            echo '# HELP ${prefix}_oldest_row_age_seconds Age of the newest persisted row in seconds.'
            echo '# TYPE ${prefix}_oldest_row_age_seconds gauge'
            echo "${prefix}_oldest_row_age_seconds ''${age}"
            echo '# HELP ${prefix}_success 1 when the check could read the database.'
            echo '# TYPE ${prefix}_success gauge'
            echo "${prefix}_success 1"
          } | emit_textfile
        else
          {
            ${header}
            echo '# HELP ${prefix}_success 1 when the check could read the database.'
            echo '# TYPE ${prefix}_success gauge'
            echo "${prefix}_success 0"
          } | emit_textfile
          echo "sqlite check failed: could not read $db" >&2
          exit 1
        fi
      '';
    in
    {
      script = textfileScript name body;
      inherit user unreadableAs;
    };

  # The account a check's unit declares. A check with an escape hatch must be
  # able to become root, so its unit is root and the script drops to the owning
  # user itself; a check without one runs directly as the owning user.
  checkUnitUser =
    check: if check.unreadableAs == null then check.user else "root";

  # The shell that runs just before a check's own body: without an escape hatch
  # it is empty, with one it is the probe-and-maybe-re-exec.
  checkPrelude =
    check:
    lib.optionalString (check.unreadableAs != null) ''
      # The owning user may not be able to read this (a rootless volume is owned
      # by a uid in its subuid range). Prefer the owning user; fall back to root
      # when it cannot read the file, which is safe because the query is
      # read-only by construction.
      if runuser -u ${lib.escapeShellArg check.user} -- test -r ${lib.escapeShellArg check.unreadableAs} 2>/dev/null; then
        exec runuser -u ${lib.escapeShellArg check.user} -- "$0" "$@"
      fi
      echo "textfile check: ${check.user} cannot read ${check.unreadableAs}, running as root (read-only query)" >&2
    '';


  # ── Grafana datasource UIDs ───────────────────────────────────────────
  #
  # Fixed, because dashboards and the Alertmanager links inside them reference
  # a datasource by UID and a generated UID would break them on every rebuild.
  # VictoriaLogs was reserved before it existed (BOX-326) and is now provisioned
  # by BOX-330; Alertmanager is still reserved and is BOX-329's.
  datasourceUids = {
    victoriaMetrics = "victoriametrics";
    victoriaLogs = "victorialogs";
    alertmanager = "alertmanager";
  };
}
