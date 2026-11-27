# storage2 — SNMP polling of the UniFi UNAS Pro on the observability host
# (BOX-334).
#
# ## Why this module exists at all
#
# storage2 is the house's archive: a UniFi UNAS Pro that cannot run services.
# It has no agent to install, so everything we know about its health comes from
# its own SNMP agent. BOX-320 confirmed the agent answers SNMPv3 `authPriv`
# (SHA auth, AES privacy, one password for both) and recorded what it serves.
#
# ## The boundary, stated once and prominently
#
# BOX-314 walked this device's SNMP agent and recorded what is *not* there.
# Anyone extending the dashboard or the rules must know it before concluding
# something was forgotten:
#
#   NOT AVAILABLE over SNMP
#     - capacity / free space — no `hrStorageTable` (1.3.6.1.2.1.25.2.3),
#       no UCD `dskTable` (1.3.6.1.4.1.2021.9). Both trees answer
#       "No Such Object".
#     - SMART, drive health, pool/RAID state — not exported at all. There is
#       no Ubiquiti enterprise MIB on this agent
#       (1.3.6.1.4.1.41112 / .4413 are not served).
#     - anything in the SIEM/syslog stream either: BOX-314 checked, and the
#       UNAS sends only UniFi OS *events* (system, updates, admins, backups,
#       users), with no storage or drive categories.
#
#   Capacity, drive-failure and pool alerts therefore stay with **UniFi's own
#   push/email notifications**, which are the only documented SMART-driven path
#   for this hardware. That is a hardware boundary, not a gap here. The
#   dashboard says the same thing on the panel, so the next person to look for
#   "disk filling" finds the answer instead of filing a bug.
#
# ## What is scraped, and from which OIDs
#
# The `prometheus-snmp-exporter` on this host polls storage2 and re-serves the
# result as Prometheus metrics on loopback; this host's own vmagent scrapes
# those. The module config is hand-written rather than taken from upstream's
# `snmp.yml` because upstream has **no module covering this device's trees**:
# it ships `ucd_la_table`, `ucd_memory` and `ucd_system_stats` but nothing for
# UCD diskIO or LM-SENSORS, which are the two that matter for a NAS. (Checked
# at snmp_exporter v0.30.1: `grep diskio|lmFanSensors|lmTempSensors snmp.yml`
# returns nothing.)
#
# The OIDs, each verified against its MIB rather than copied from memory:
#
#   LM-SENSORS-MIB fans       1.3.6.1.4.1.2021.13.16.3   lmFanSensorsTable
#     .1.2  lmFanSensorsDevice  (label `fan`, e.g. "fan1")
#     .1.3  lmFanSensorsValue   (RPM)
#
#   LM-SENSORS-MIB temperatures 1.3.6.1.4.1.2021.13.16.2 lmTempSensorsTable
#     .1.2  lmTempSensorsDevice (label `sensor`, e.g. "Board Temp")
#     .1.3  lmTempSensorsValue  (millidegrees C — divided by 1000 below)
#
#   UCD-DISKIO-MIB            1.3.6.1.4.1.2021.13.15.1  diskIOTable
#     .1.2  diskIODevice        (label `device`, e.g. "sda")
#     .1.12 diskIONReadX        (bytes read, Counter64)
#     .1.13 diskIONWrittenX     (bytes written, Counter64)
#     .1.14 diskIOBusyTime      (microseconds busy, Counter64)
#
#   UCD-SNMP-MIB load         1.3.6.1.4.1.2021.10.1     laTable
#     .1.5  laLoadInt           (1/5/15-minute load, x100, label `window`)
#
#   UCD-SNMP-MIB memory       1.3.6.1.4.1.2021.4        memory
#     .5    memTotalReal        (kB)
#     .6    memAvailReal        (kB)
#
#   UCD-SNMP-MIB systemStats  1.3.6.1.4.1.2021.11       systemStats
#     .9    ssCpuUser           (% of CPU in user code)
#     .10   ssCpuSystem         (% of CPU in system code)
#     .11   ssCpuIdle           (% of CPU idle)
#
# Numeric OIDs are used rather than MIB names (`UCD-SNMP-MIB::memTotalReal`)
# on purpose: snmp_exporter's generator resolves names by parsing MIBs with
# net-snmp, and net-snmp in nixpkgs ships no MIB files at all. Numeric OIDs
# need no MIB database, so this config is self-contained and reproducible
# without a MIB fetch — at the cost that a typo in an OID is not caught at
# build time. The build-time `snmp_exporter --dry-run` validates only the
# document's structure and auth sections (it accepts a bogus metric type or a
# bogus OID without complaint — see the note beside `configCheck`), so the
# promise of catching a typo is *not* met anywhere off-host. `Storage2PollDead`
# in the rule file is what catches "reachable but returning nothing" on the
# host, and it is the only thing that does.
#
# ## Credentials
#
# Values never enter the Nix store. The rendered config carries `${VAR}`
# *references* for `username`, `password` and `priv_password`, and
# snmp_exporter expands them at start-up from its own environment
# (`--config.expand-environment-variables`), which `secretspec run` fills from
# the `unifi-snmp` scope. See `systemd.services.prometheus-snmp-exporter`
# below for the full chain and for why this does **not** use the
# Alertmanager-style `envsubst`-into-a-0600-file dance.
{ lib, ... }:
{
  my.modules.nixos.storage2 =
    {
      config,
      pkgs,
      ...
    }:
    let
      cfg = config.my;

      # ── The snmp_exporter module config ──────────────────────────────
      #
      # `auths` and `modules` are snmp_exporter's own schema
      # (config/config.go at v0.30.1), not ours. Notes on the fields that are
      # easy to get wrong:
      #
      #   version: 3            SNMPv3, as BOX-320 verified on the device.
      #   security_level: authPriv   authentication *and* privacy, which is
      #                         what the device answered on.
      #   auth_protocol / priv_protocol
      #                         BOX-320 recorded SHA and AES from the device's
      #                         own successful responses, and both are
      #                         snmp_exporter's spelling of those
      #                         (`config.Auth` case statements). They are
      #                         options rather than hardcoded for the reason in
      #                         the option's description.
      #   password / priv_password
      #                         Both are the *same* BWS value: BOX-320 recorded
      #                         "same password for both", and secretspec
      #                         declares one `UNIFI_SNMP_PASSWORD` in the
      #                         `unifi-snmp` scope. Referenced twice, not
      #                         duplicated in the store.
      #   max_repetitions: 10   Below upstream's 25 default. A GETBULK of 25
      #                         is a large UDP response, and an appliance-grade
      #                         SNMP agent is the usual place where that gets
      #                         fragmented or dropped. Lower costs a few more
      #                         round trips on a LAN.
      #   timeout: 3s / retries: 2   A NAS on the same switch should answer in
      #                         milliseconds; 5s x 3 (upstream's default) makes
      #                         a dead device cost 15 s per scrape against a
      #                         15 s scrape interval, so scrapes would overlap.
      snmpConfig = {
        auths.storage2 = {
          version = 3;
          security_level = "authPriv";
          # References, expanded at start-up from the snmp_exporter process's
          # own environment. `${...}` here is written `\${...}` so Nix emits
          # the literal text and does not interpolate.
          username = "\${UNIFI_SNMP_USER}";
          password = "\${UNIFI_SNMP_PASSWORD}";
          auth_protocol = cfg.storage2AuthProtocol;
          priv_protocol = cfg.storage2PrivProtocol;
          priv_password = "\${UNIFI_SNMP_PASSWORD}";
        };

        modules.storage2 = {
          walk = [
            # LM-SENSORS: fans (13.16.3) and temperatures (13.16.2)
            "1.3.6.1.4.1.2021.13.16.2"
            "1.3.6.1.4.1.2021.13.16.3"
            # UCD diskIO: per-device read/written/busy counters
            "1.3.6.1.4.1.2021.13.15.1"
            # UCD load table
            "1.3.6.1.4.1.2021.10.1"
            # UCD memory: total/available real memory
            "1.3.6.1.4.1.2021.4"
            # UCD systemStats: CPU user/system/idle percentages
            "1.3.6.1.4.1.2021.11"
          ];
          max_repetitions = 10;
          retries = 2;
          timeout = "3s";

          metrics = [
            # ── Fans ──────────────────────────────────────────────────
            #
            # `lmFanSensorsTable` is indexed by `lmFanSensorsIndex`, which
            # carries no meaning on its own, so it is mapped to the sibling
            # `lmFanSensorsDevice` string ("fan1", "fan2", …) and then
            # dropped. That label is what `Storage2FanStopped` groups on: a
            # fan is identified by name, not by a table position that could
            # shift on a firmware update.
            {
              name = "snmp_lm_fan_rpm";
              oid = "1.3.6.1.4.1.2021.13.16.3.1.3";
              type = "gauge";
              help = "Fan speed in RPM (LM-SENSORS lmFanSensorsValue)";
              indexes = [
                {
                  labelname = "fanIndex";
                  type = "gauge";
                }
              ];
              lookups = [
                {
                  labels = [ "fanIndex" ];
                  labelname = "fan";
                  oid = "1.3.6.1.4.1.2021.13.16.3.1.2";
                  type = "DisplayString";
                }
                {
                  # Drop the numeric index once `fan` carries the identity:
                  # keeping both would make every series unique twice over,
                  # and a dashboard `by (fan)` would still work but an alert
                  # `on (fan)` would not.
                  labels = [ ];
                  labelname = "fanIndex";
                }
              ];
            }

            # ── Temperatures ──────────────────────────────────────────
            #
            # `lmTempSensorsValue` is in **millidegrees Celsius** (the MIB's
            # UNITS clause is "milliC"), so the extract divides by 1000.
            # Missing that would put every sensor at ~47000 °C and make
            # `Storage2Hot` fire on a cold NAS — which is why the divisor is
            # spelled out here rather than left implicit.
            {
              name = "snmp_lm_temp_celsius";
              oid = "1.3.6.1.4.1.2021.13.16.2.1.3";
              type = "gauge";
              # milliC -> C. `scale` is snmp_exporter's own per-metric
              # multiplier (collector.go: `if metric.Scale != 0.0 { value *=
              # metric.Scale }`), so the conversion happens in the exporter and
              # every consumer downstream sees real degrees.
              scale = 0.001;
              help = "Sensor temperature in degrees Celsius (LM-SENSORS lmTempSensorsValue)";
              indexes = [
                {
                  labelname = "sensorIndex";
                  type = "gauge";
                }
              ];
              lookups = [
                {
                  labels = [ "sensorIndex" ];
                  labelname = "sensor";
                  oid = "1.3.6.1.4.1.2021.13.16.2.1.2";
                  type = "DisplayString";
                }
                {
                  labels = [ ];
                  labelname = "sensorIndex";
                }
              ];
            }

            # ── Per-drive I/O ─────────────────────────────────────────
            #
            # The `X` variants (Counter64) rather than the 32-bit
            # `diskIONRead`/`diskIONWritten`: the 32-bit counters wrap at
            # 4 GiB, which on an archive NAS with 7 drives is minutes of
            # transfer, and a wrapped counter turns every rate() into a
            # spike. `diskIOBusyTime` is microseconds busy, which gives
            # utilisation as a ratio of two deltas.
            #
            # All three are the same table and share the `device` lookup, so
            # they are separate metrics with identical index handling.
            {
              name = "snmp_diskio_read_bytes_total";
              oid = "1.3.6.1.4.1.2021.13.15.1.1.12";
              type = "counter";
              help = "Bytes read from this device since boot (UCD-DISKIO-MIB diskIONReadX)";
              indexes = [
                {
                  labelname = "deviceIndex";
                  type = "gauge";
                }
              ];
              lookups = [
                {
                  labels = [ "deviceIndex" ];
                  labelname = "device";
                  oid = "1.3.6.1.4.1.2021.13.15.1.1.2";
                  type = "DisplayString";
                }
                {
                  labels = [ ];
                  labelname = "deviceIndex";
                }
              ];
            }
            {
              name = "snmp_diskio_written_bytes_total";
              oid = "1.3.6.1.4.1.2021.13.15.1.1.13";
              type = "counter";
              help = "Bytes written to this device since boot (UCD-DISKIO-MIB diskIONWrittenX)";
              indexes = [
                {
                  labelname = "deviceIndex";
                  type = "gauge";
                }
              ];
              lookups = [
                {
                  labels = [ "deviceIndex" ];
                  labelname = "device";
                  oid = "1.3.6.1.4.1.2021.13.15.1.1.2";
                  type = "DisplayString";
                }
                {
                  labels = [ ];
                  labelname = "deviceIndex";
                }
              ];
            }
            {
              name = "snmp_diskio_busy_seconds_total";
              oid = "1.3.6.1.4.1.2021.13.15.1.1.14";
              type = "counter";
              # microseconds -> seconds, for the same reason as the
              # temperature scale above: one conversion, in the exporter.
              scale = 0.000001;
              help = "Seconds this device has been busy since boot (UCD-DISKIO-MIB diskIOBusyTime)";
              indexes = [
                {
                  labelname = "deviceIndex";
                  type = "gauge";
                }
              ];
              lookups = [
                {
                  labels = [ "deviceIndex" ];
                  labelname = "device";
                  oid = "1.3.6.1.4.1.2021.13.15.1.1.2";
                  type = "DisplayString";
                }
                {
                  labels = [ ];
                  labelname = "deviceIndex";
                }
              ];
            }

            # ── Load ──────────────────────────────────────────────────
            #
            # `laLoadInt` is the load average multiplied by 100 (the MIB's
            # "as an integer"), so the extract divides to get a real load
            # figure. `laNames` carries "Load-1"/"Load-5"/"Load-15", which is
            # a better label than the row index.
            {
              name = "snmp_load";
              oid = "1.3.6.1.4.1.2021.10.1.5";
              type = "gauge";
              # laLoadInt is the load average x100.
              scale = 0.01;
              help = "System load average, 1/5/15 minute (UCD-SNMP-MIB laLoadInt)";
              indexes = [
                {
                  labelname = "windowIndex";
                  type = "gauge";
                }
              ];
              lookups = [
                {
                  labels = [ "windowIndex" ];
                  labelname = "window";
                  oid = "1.3.6.1.4.1.2021.10.1.2";
                  type = "DisplayString";
                }
                {
                  labels = [ ];
                  labelname = "windowIndex";
                }
              ];
            }

            # ── Memory ────────────────────────────────────────────────
            #
            # `memTotalReal`/`memAvailReal` are in kilobytes. Both are plain
            # scalars in the same table, so one `memory` label distinguishes
            # them only if they were combined; keeping them as their own
            # metrics is clearer in a query and matches how the dashboard
            # divides one by the other.
            {
              name = "snmp_mem_total_kilobytes";
              oid = "1.3.6.1.4.1.2021.4.5";
              type = "gauge";
              help = "Total real memory in kilobytes (UCD-SNMP-MIB memTotalReal)";
            }
            {
              name = "snmp_mem_avail_kilobytes";
              oid = "1.3.6.1.4.1.2021.4.6";
              type = "gauge";
              help = "Available real memory in kilobytes (UCD-SNMP-MIB memAvailReal)";
            }

            # ── CPU ───────────────────────────────────────────────────
            #
            # Three scalar percentages. Kept separate rather than as one
            # labelled metric because each is a different quantity; a
            # dashboard stack is `user + system`, and idle is its complement.
            {
              name = "snmp_cpu_user_percent";
              oid = "1.3.6.1.4.1.2021.11.9";
              type = "gauge";
              help = "Percentage of CPU time spent in user-level code (UCD-SNMP-MIB ssCpuUser)";
            }
            {
              name = "snmp_cpu_system_percent";
              oid = "1.3.6.1.4.1.2021.11.10";
              type = "gauge";
              help = "Percentage of CPU time spent in system-level code (UCD-SNMP-MIB ssCpuSystem)";
            }
            {
              name = "snmp_cpu_idle_percent";
              oid = "1.3.6.1.4.1.2021.11.11";
              type = "gauge";
              help = "Percentage of CPU time spent idle (UCD-SNMP-MIB ssCpuIdle)";
            }
          ];
        };
      };

      # The rendered config, as a file the exporter reads. JSON is valid YAML,
      # so `pkgs.formats.yaml` serialises the attrset above into exactly the
      # document snmp_exporter's `yaml.UnmarshalStrict` expects.
      #
      # The `${VAR}` references survive into the store as text: nothing here
      # expands them, and `snmp_exporter` only does so when told to, from its
      # own environment, at run time.
      snmpConfigFile = (pkgs.formats.yaml { }).generate "snmp.yml" snmpConfig;

      # ── Build-time config validation ─────────────────────────────────
      #
      # `snmp_exporter --dry-run` parses the module config and validates its
      # **structure and auth sections only**. It does not contact a device and
      # does not need credentials — the `${VAR}` references are valid strings to
      # the parser, so they check as they stand.
      #
      # What it does NOT catch, measured rather than assumed: a bogus metric
      # `type` (`NOT_A_REAL_TYPE`) and a bogus OID (`not.an.oid`, or a bogus
      # lookup OID) all print "Configuration parsed successfully" and exit 0.
      # So this gate is worth having for shape, and worthless for typo
      # detection — which is why the header says a typo in an OID is not caught
      # at build time, and why `Storage2PollDead` exists to make a wrong OID or
      # protocol visible on the host instead of silently empty.
      #
      # nixpkgs' own `enableConfigCheck` would run this too, but its result is
      # only reachable through the module's *default* ExecStart, which the
      # override below replaces (the exporter has to run under `secretspec
      # run`). Leaving it at its default would therefore produce a check
      # derivation nothing depends on — a validation that never happens and
      # looks like it does. So the check is built here instead and put in the
      # unit's `path`, the same way BOX-329 puts `vmalert -dryRun` in vmalert's
      # `path`: any system containing this unit cannot build unless the config
      # parses.
      configCheck =
        pkgs.runCommand "checked-snmp-exporter-config.yml"
          {
            nativeBuildInputs = [ pkgs.prometheus-snmp-exporter ];
          }
          ''
            set -eu
            ln -s ${snmpConfigFile} $out
            snmp_exporter --dry-run --config.file $out
          '';

      # The scrape target. `metricsPath` is snmp_exporter's query API: the
      # `/snmp` endpoint takes the target and module as parameters, so this is
      # where storage2's address is written — once, as a parameter, rather than
      # as a Prometheus `targets:` entry. That is the shape upstream documents
      # for polling many devices through one exporter, and it keeps the
      # exporter's own port loopback-only.
      #
      # `interval = "60s"` rather than the agent's 15 s: fan RPM, temperature
      # and drive byte counters move on the scale of minutes, and a GETBULK
      # walk of six subtrees every 15 s on a NAS's embedded SNMP agent is load
      # with no informational return. `scrapeTimeout` is above the module's
      # own 3 s x 2 retries so a slow poll is not cut off by the scraper.
      scrapeTarget = {
        address = "127.0.0.1:${toString config.my.storage2ExporterPort}";
        metricsPath = "/snmp?target=${cfg.storage2Address}&module=storage2&auth=storage2";
        interval = "60s";
        scrapeTimeout = "30s";
      };
    in
    {
      config = lib.mkIf (config.my.storage2 && config.my.observabilityHost) {
        # The exporter is an SNMP poller, so it only makes sense on the host
        # that does the polling. ADR 0006: native service, never a container.
        services.prometheus.exporters.snmp = {
          enable = true;

          # The exporter runs `secretspec`, which resolves its own uid at
          # startup. Under `DynamicUser` that lookup needs `libnss_systemd.so.2`,
          # which is not on the binary's library path, so it fails and
          # secretspec misreports it as a missing manifest. A static user takes
          # the uid from /etc/passwd and needs no NSS. nixpkgs creates the
          # `snmp-exporter` user and group itself when this is false (see
          # `mkExporterConf` in prometheus/exporters.nix), which is why the
          # module declares no user of its own.
          #
          # Confirmed on calamansi with strace: /etc/secretspec.toml opened
          # successfully, then four ENOENT attempts at libnss_systemd.so.2, then
          # exit 1.
          #
          # Set on the *unit*, not on this option set: the exporter module
          # declares `serviceConfig.DynamicUser = mkDefault enableDynamicUser`,
          # so the override belongs on the unit (below), and there is no
          # `serviceConfig` sub-option here.

          # The config document, exposed as a *value* too so the contract test
          # can assert on it as data (that the credentials are references and
          # not values) instead of grep-ing rendered YAML.
          configuration = snmpConfig;

          # Loopback only. The exporter re-serves a NAS's internals; nothing
          # outside this host has any reason to see them, and this host's own
          # vmagent scrapes it over loopback.
          #
          # Deliberately NOT `openFirewall`.
          listenAddress = "127.0.0.1";
          port = config.my.storage2ExporterPort;

          # Off, because the module's check is only reachable through the
          # `ExecStart` we override below. `configCheck` (above) is the check
          # that actually runs; leaving this on would silently produce a second
          # derivation nothing depends on.
          enableConfigCheck = false;
        };

        # ── Where the credentials come from ──────────────────────────────
        #
        # The chain, in order. Nothing in it puts a value in the store, and —
        # unlike the Alertmanager path — nothing in it writes a rendered copy
        # of the config to *any* filesystem either.
        #
        #   1. `snmpConfig` above renders `username`/`password`/`priv_password`
        #      as the literal text `${UNIFI_SNMP_USER}` / `${UNIFI_SNMP_PASSWORD}`
        #      into the store's `snmp.yml`. The store holds variable *names*.
        #
        #   2. `ExecStart` is overridden (mkForce) to run the exporter under
        #      `secretspec run -S unifi-snmp`, so the two variables are in the
        #      *process's* environment — visible to that process only, never
        #      to another user, never on disk, never in a unit file.
        #
        #   3. `--config.expand-environment-variables` is passed because
        #      without it snmp_exporter treats `${UNIFI_SNMP_USER}` as the
        #      literal username and every poll fails auth. With it, config.go
        #      substitutes `username`, `password` and `priv_password` through
        #      `os.Expand`/`os.Getenv` at load time — i.e. from exactly the
        #      environment `secretspec run` provided in step 2.
        #
        # ## Why there is no ExecStartPre, and why no 0400 file
        #
        # BOX-329 found nixpkgs' Alertmanager service expanding its template
        # into `/tmp` through a world-readable ExecStartPre, and the fix there
        # was to override it and write a 0400 file in the RuntimeDirectory.
        # **No module-generated pre-start writes credentials anywhere** — no
        # `/tmp`, no materialised plaintext. (The rendered unit does have an
        # `ExecStartPre`, but it is only this module's own `preStart` echo; an
        # earlier version of this comment said the unit had none, which a
        # reviewer correctly flagged as false. The conclusion held either way.)
        # That makes the runtime env
        # the better option here: the exporter never materialises the
        # credentials anywhere, so there is no file whose mode could regress.
        #
        # ## The two endpoints that *could* leak, and why they do not
        #
        # snmp_exporter serves `/config`, which marshals its loaded
        # configuration. `config.Secret.MarshalYAML` replaces any non-empty
        # password with the literal string `<secret>`, so the expanded values
        # are not readable there. The username *is* shown, as it is in the
        # rendered config — a username is not the secret, the password is.
        # Both leak surfaces are on a loopback port this host's firewall never
        # opens.
        systemd.services.prometheus-snmp-exporter = {
          wants = [ "network-online.target" ];
          after = [ "network-online.target" ];
          # Static user rather than DynamicUser — see the note on the exporter's
          # `enable` block above for the strace evidence. `mkForce`, not a plain
          # assignment: the exporter module sets `mkDefault true`, and this must
          # win regardless of module order.
          serviceConfig.DynamicUser = lib.mkForce false;
          path = [
            pkgs.secretspec
            pkgs.bws
            # The validated config, so its `snmp_exporter --dry-run` is part of
            # this unit's build closure (see `configCheck` above).
            configCheck
          ];
          # Print the checked path in preStart, so the dependency cannot be
          # optimised away as dead and an operator can see it in the journal.
          preStart = ''
            echo "validated snmp config: ${configCheck}"
          '';
          # A rotation edits no file this unit can see, so watch the manifest:
          # a `secretspec.toml` change must cycle the unit or the old password
          # stays in the running process.
          restartTriggers = [ config.my.secretspecManifest ];
          serviceConfig = {
            Environment = [
              "SECRETSPEC_FILE=${config.my.secretspecManifest}"
              "SECRETSPEC_PROVIDER=bws-service"
            ];
            # The repo's standard bootstrap (modules/features/secrets.nix): the
            # BWS access token arrives as a systemd credential, so it is not in
            # the environment either.
            LoadCredential = [ "access_token:${config.my.bwsAccessTokenFile}" ];
            ExecStart = lib.mkForce (
              lib.escapeShellArgs [
                "${pkgs.secretspec}/bin/secretspec"
                "run"
                "-P"
                "production"
                "-S"
                "unifi-snmp"
                "--"
              ]
              + " "
              + lib.escapeShellArgs [
                "${pkgs.prometheus-snmp-exporter}/bin/snmp_exporter"
                "--config.file=${snmpConfigFile}"
                "--config.expand-environment-variables"
                "--log.format=${config.services.prometheus.exporters.snmp.logFormat}"
                "--log.level=${config.services.prometheus.exporters.snmp.logLevel}"
                "--web.listen-address=127.0.0.1:${toString config.my.storage2ExporterPort}"
              ]
            );
          };
        };

        # ── Scrape it ────────────────────────────────────────────────────
        #
        # Declared through the public collection, so this is the same seam
        # every feature uses: the host's own agent picks it up with no
        # extra wiring, and `job_name` is `storage2` — the name the rules and
        # the dashboard filter on.
        my.observability.scrapeTargets.storage2 = scrapeTarget;

        # ── Rules and dashboard ──────────────────────────────────────────
        #
        # Both sit beside this module and are gathered by the observability
        # host at build time, so a change here means redeploying calamansi.
        my.observability.rules.storage2 = {
          files = [ ./storage2.rules.yaml ];
          type = "metrics";
        };

        my.observability.dashboards.storage2 = {
          path = ./storage2.dashboard.json;
        };

        # The exporter's own metrics (`snmp_scrape_*`) are what
        # `Storage2PollDead` watches, and they are served on the same
        # `/metrics` path as a normal scrape — but the target above scrapes
        # `/snmp?...`, which returns device metrics only. So the exporter is
        # scraped a second time for its self-metrics; without this there is no
        # series to distinguish "device unreachable" from "poll returning
        # nothing".
        my.observability.scrapeTargets.storage2-exporter = {
          address = "127.0.0.1:${toString config.my.storage2ExporterPort}";
          metricsPath = "/metrics";
          interval = "60s";
        };

        # The exporter can only be useful where the poller runs, and the poller
        # is the observability host (ADR 0006: native service on the host that
        # stores what it collects). On any other host the flag would start a
        # loopback exporter that nothing scrapes and that has no route to the
        # device — a silent no-op that looks configured. Fail at eval instead.
        #
        # This is only reachable when `my.storage2` is set at all, because the
        # whole block is guarded by it; the condition is spelled out anyway so
        # the message is the thing a reader finds, not the guard.
        assertions = [
          {
            assertion = config.my.storage2 && config.my.observabilityHost;
            message = "my.storage2 is set on a host that is not the observability host. The SNMP exporter polls storage2 from the observability host; set my.storage2 there and leave it off elsewhere.";
          }
        ];
      };
    };
}
