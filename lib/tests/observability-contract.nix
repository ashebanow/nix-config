# Contract test for the `my.observability` option set (BOX-326), extended by
# BOX-327 (a remote agent, GPU telemetry, the Host detail dashboard), BOX-330
# (journal shipping and the log store), BOX-329 (rules and the alerting path)
# and BOX-332 (textfile checks and the bifrost dashboard).
#
# The seam this ticket establishes is "a feature module declares a source and
# the machine's machinery picks it up". That is exactly what BOX-331
# (containers/llama.cpp) and BOX-338 (dashboards) will do, so this exercises
# their future call shape rather than the option set in isolation.
#
# Run: nix eval --impure --file lib/tests/observability-contract.nix --json
#
# A plain eval, not a NixOS test: there is no host to boot (calamansi is not
# installed until BOX-324), and a broken contract shows up in rendered
# configuration values long before it shows up as a running system.
#
# Nine seams are covered, because they gather differently:
#
#   scrapeTargets -> this host's agent       extended in-process
#   dashboards    -> the observability host  gathered from `inputs.self`
#   a remote agent -> where it remote-writes extended in-process
#   journald      -> every agent host        extended in-process (BOX-330)
#   retention/UID -> the observability host  extended in-process (BOX-330)
#   the committed agent host                 read from `inputs.self`
#   GPU telemetry -> per-host collector flag extended in-process
#   rules         -> the observability host  gathered, via the documented
#                                            `my.observabilityGatheredHosts` hook
#   alerting      -> Alertmanager's config   rendered, asserted as data
#   textfileChecks -> this host's agent      extended in-process (BOX-332)
#   the bifrost check + dashboard             read from the committed lumquat
#
# The dashboard seam reads the *committed* flake's host configurations, so it
# cannot be exercised by `extendModules` (an extended config is not in
# `inputs.self`). It is asserted on the committed hosts instead: whatever
# dashboards calamansi declares must appear in the provider's directory
# alongside the prebuilts.
#
# The rules seam has the same problem and a documented answer:
# `my.observabilityGatheredHosts`, empty on every real host, lets a test supply
# the set of hosts to gather. Without it there is no way to demonstrate "a rule
# declared on lumquat reaches calamansi" before the rule itself is committed.
#
# ## How this fails
#
# `nix eval` exits 0 whatever the output JSON says, so printing a `false` is
# not a gate. `assertions` below is the gate: every broken assertion's message
# is thrown together, so the eval fails with the whole list of what broke. The
# returned attribute set is the readable output that makes a failure
# diagnosable without re-deriving the values by hand.
let
  flake = builtins.getFlake (toString ../../.);

  lib = flake.nixosConfigurations.calamansi.pkgs.lib;

  # What a consuming feature module will look like. Deliberately uses the
  # public option paths only — no internals of the rendering helpers — so this
  # test breaks if the contract breaks, not merely if the implementation moves.
  featureModule = {
    config.my.observability = {
      # The BOX-331 shape: a container's metrics, published on loopback, with
      # the model name as a label and a slower interval.
      scrapeTargets.llama-qwen = {
        address = "127.0.0.1:8080";
        labels.model = "qwen-27b";
        interval = "30s";
      };
      # Defaults-only shape: address is the only required field.
      scrapeTargets.plain = {
        address = "127.0.0.1:9101";
      };
    };
  };

  # The direction that has to work in production: an *agent host that is not
  # the observability host* — BOX-327's lumquat. Simulated here by moving the
  # remote-write address off loopback, so the simulation does not depend on any
  # committed host's LAN address.
  remoteAgentModule = {
    # Deliberately a documentation-range address (TEST-NET-3), not any host's
    # real one: this asserts the *mechanism* (remote-write follows the option),
    # and must not start failing because the house LAN was re-addressed.
    config.my.observabilityHostAddress = "203.0.113.10";
  };

  # A host with a GPU whose telemetry node_exporter can read.
  gpuModule = {
    config.my.observabilityGpuMetrics = true;
  };

  cfg =
    (flake.nixosConfigurations.calamansi.extendModules {
      modules = [ featureModule ];
    }).config;

  remoteCfg =
    (flake.nixosConfigurations.calamansi.extendModules {
      modules = [
        featureModule
        remoteAgentModule
      ];
    }).config;

  gpuCfg =
    (flake.nixosConfigurations.calamansi.extendModules {
      modules = [ gpuModule ];
    }).config;

  scrapeConfigs = cfg.services.vmagent.prometheusConfig.scrape_configs;
  jobNamed = name: builtins.head (builtins.filter (j: j.job_name == name) scrapeConfigs);
  jobNames = map (j: j.job_name) scrapeConfigs;

  # ── The real agent host (BOX-327's lumquat) ─────────────────────────
  #
  # `extendModules` above simulates a remote agent; this is the committed one,
  # and it is the host the dashboard's target names must match. Node Exporter
  # Full selects its series with `job="node"`, and that job is named in the
  # agent module, not in the dashboard: asserting the name here is what stops
  # the two drifting apart without anything in between noticing.
  lumquat = flake.nixosConfigurations.lumquat.config;

  # BOX-334's two jobs, read from calamansi's *rendered* agent config so a
  # module that stops declaring them fails here rather than on the host.
  storage2Job = jobNamed "storage2";
  storage2ExporterJob = jobNamed "storage2-exporter";
  storage2Address = flake.nixosConfigurations.calamansi.config.my.storage2Address;
  snmpAuth = flake.nixosConfigurations.calamansi.config.services.prometheus.exporters.snmp.configuration.auths.storage2;

  lumquatJobNames = map (j: j.job_name) lumquat.services.vmagent.prometheusConfig.scrape_configs;
  lumquatNodeJob = builtins.head (
    builtins.filter (j: j.job_name == "node") lumquat.services.vmagent.prometheusConfig.scrape_configs
  );
  lumquatNodeExporterTarget = "127.0.0.1:${toString lumquat.services.prometheus.exporters.node.port}";
  lumquatCollectors = lumquat.services.prometheus.exporters.node.enabledCollectors;

  # The remote-write URL a host that is not the observability host must *not*
  # have: its own loopback. Computed rather than written out so the assertion
  # does not go stale if the default port changes.
  loopbackRemoteWrite = "http://127.0.0.1:${toString lumquat.my.observabilityIngestPort}/api/v1/write";

  # ── The dashboard seam ──────────────────────────────────────────────
  #
  # The provider directory as it will exist on the host, and the prebuilts as
  # fetched — both are derivations, so this also proves each pinned hash still
  # resolves to the JSON it claims to.
  dashboardProvider = builtins.elemAt flake.nixosConfigurations.calamansi.config.services.grafana.provision.dashboards.settings.providers 0;
  dashboardFiles = builtins.attrNames (builtins.readDir dashboardProvider.options.path);

  declaredDashboardKeys = builtins.attrNames (
    flake.nixosConfigurations.calamansi.config.my.observability.dashboards
  );

  # The dashboard as Grafana will actually serve it — read **through** the
  # provider directory, not from the module's source file. `readFile` does
  # follow the farm's symlinks (an earlier comment here claimed otherwise and a
  # reviewer disproved it), and going through the farm is strictly stronger: it
  # proves the bytes Grafana loads are the ones asserted, rather than proving
  # something about a file the farm might in principle not point at. Same shape
  # as `nodeExporterFullJson` below.
  storage2DashboardJson = builtins.fromJSON (
    builtins.readFile (dashboardProvider.options.path + "/storage2.json")
  );

  # ── BOX-330: the agent's always-on collectors ──────────────────────
  #
  # The observability host is also an agent, so its own config proves the shared
  # module wires journal shipping. The remote case — an agent host that is not
  # the observability host — is `remoteCfg` below, which is BOX-327's call shape.
  hostCfg = flake.nixosConfigurations.calamansi.config;
  hostJournal = hostCfg.services.journald.upload;

  nodeExporterFullJson = builtins.fromJSON (
    builtins.readFile (dashboardProvider.options.path + "/prebuilt-node-exporter-full.json")
  );

  # Enough of Node Exporter Full to prove the pinned bytes are the dashboard
  # and not an error page: its uid, its title, and the datasource variable
  # Grafana binds to whatever Prometheus datasource exists. A hardcoded UID
  # here would mean the dashboard needed vendoring before it could render.
  nodeExporterFullFacts = {
    inherit (nodeExporterFullJson) uid title schemaVersion;
    panelCount = builtins.length nodeExporterFullJson.panels;
    datasourceVariables = map (v: v.name) (
      builtins.filter (v: v.type == "datasource") nodeExporterFullJson.templating.list
    );
  };

  # ── BOX-330: the log store's retention and its datasource UID ───────
  #
  # ExecStart is where nixpkgs' VictoriaLogs module puts the binary's flags, and
  # `services.victorialogs` has no retention option — so this is the only place
  # to prove BOX-319's "90 days, 80% disk cap" actually reaches the process.
  victorialogsExecStart = hostCfg.systemd.services.victorialogs.serviceConfig.ExecStart;

  # The UID was reserved by BOX-326 before the datasource existed; this asserts
  # the provisioned datasource uses that exact value, because every dashboard
  # written in between already points at it. The literal is deliberate: it is
  # the contract, so a test that read it from the same place the implementation
  # does could not catch a typo in it.
  logDatasource = builtins.head (
    builtins.filter (
      d: d.uid == "victorialogs"
    ) hostCfg.services.grafana.provision.datasources.settings.datasources
  );

  # ── BOX-329: alert rules, gathered and rendered ─────────────────────
  #
  # The gather reads `inputs.self`, so the lumquat side of the acceptance
  # criterion is simulated the one way it can be: an extended lumquat (carrying
  # the fixture ruleset and the agent flag BOX-327 sets) handed to calamansi
  # through `my.observabilityGatheredHosts`.
  obsHelper = import ../../lib/observability.nix { inherit lib; };

  lumquatWithRules = flake.nixosConfigurations.lumquat.extendModules {
    modules = [
      {
        config.my.observability.rules.llama-queue.files = [
          ./fixtures/box329-sample-lumquat.rules.yaml
        ];
      }
    ];
  };

  gatherHosts = {
    calamansi = flake.nixosConfigurations.calamansi;
    lumquat = lumquatWithRules;
  };

  gatherCfg =
    (flake.nixosConfigurations.calamansi.extendModules {
      modules = [ { config.my.observabilityGatheredHosts = gatherHosts; } ];
    }).config;

  # The rule farm's file names, computed with the *same* helper the host module
  # uses. Reading the rendered directory instead would make this eval depend on
  # a build (the farm is a derivation), and the farm contains exactly one
  # symlink per entry here, so the two cannot differ without this changing too.
  defaultRulesets = {
    generic = {
      type = "metrics";
      files = [
        (builtins.path {
          path = ../../modules/features/observability-default.rules.yaml;
          name = "observability-default.rules.yaml";
        })
        (builtins.path {
          path = ../../modules/features/observability-watchdog.rules.yaml;
          name = "observability-watchdog.rules.yaml";
        })
      ];
    };
  };

  committedRuleEntries = obsHelper.mkRuleFiles (
    obsHelper.rulesetsOfType "metrics" (
      defaultRulesets
      // lib.concatMapAttrs (
        hostName: host:
        lib.mapAttrs' (
          name: ruleset: lib.nameValuePair "${hostName}-${name}" ruleset
        ) host.config.my.observability.rules
      ) (lib.filterAttrs (_: host: host.config.my.observabilityAgent or false) flake.nixosConfigurations)
    )
  );

  gatheredRuleEntries = obsHelper.mkRuleFiles (
    obsHelper.rulesetsOfType "metrics" (
      defaultRulesets
      // lib.concatMapAttrs (
        hostName: host:
        lib.mapAttrs' (
          name: ruleset: lib.nameValuePair "${hostName}-${name}" ruleset
        ) host.config.my.observability.rules
      ) (lib.filterAttrs (_: host: host.config.my.observabilityAgent or false) gatherHosts)
    )
  );

  # BOX-334 makes calamansi declare a feature ruleset, so "a new agent host gets
  # the generic defaults for free" can no longer be read off the committed host:
  # it is asserted on the same host with the feature switched off.
  genericOnlyFlake = {
    calamansi = flake.nixosConfigurations.calamansi.extendModules {
      modules = [
        { config.my.storage2 = lib.mkForce false; }
        { config.my.observabilityGatheredHosts = { }; }
      ];
    };
    lumquat = flake.nixosConfigurations.lumquat;
  };

  genericOnlyRuleFiles = map (f: f.name) (obsHelper.mkRuleFiles (
    obsHelper.rulesetsOfType "metrics" (
      defaultRulesets
      // lib.concatMapAttrs (
        hostName: host:
        lib.mapAttrs' (
          name: ruleset: lib.nameValuePair "${hostName}-${name}" ruleset
        ) host.config.my.observability.rules
      ) (lib.filterAttrs (_: host: host.config.my.observabilityAgent or false) genericOnlyFlake)
    )
  ));

  committedRuleFiles = map (f: f.name) committedRuleEntries;
  gatheredRuleFiles = map (f: f.name) gatheredRuleEntries;

  # The directory each vmalert unit actually loads, from its own `-rule=` flag.
  ruleDirOf =
    unit: builtins.head (builtins.match ".*-rule=(/[^ ']+)/\\*\\.yaml.*" unit.serviceConfig.ExecStart);

  committedRuleDir = ruleDirOf hostCfg.systemd.services.vmalert;
  gatheredRuleDir = ruleDirOf gatherCfg.systemd.services.vmalert;

  # Every `alert:` name in a rule file, so a reader sees which rules ship
  # without opening the YAML.
  alertNamesIn =
    file:
    let
      text =
        builtins.readFile
          (builtins.head (builtins.filter (f: f.name == file) committedRuleEntries)).path;
      lines = builtins.filter builtins.isString (builtins.split "\n" text);
      matched = map (line: builtins.match "[ ]*- alert: (.*)" line) lines;
    in
    map builtins.head (builtins.filter (m: builtins.isList m && m != [ ]) matched);

  # Only the generic files: `committedRuleFiles` now also contains BOX-334's
  # storage2 ruleset, and this list is the *stack's* default alert set.
  defaultRuleNames = builtins.concatMap alertNamesIn [
    "generic.0.yaml"
    "generic.1.yaml"
  ];
  storage2RuleNames = alertNamesIn "calamansi-storage2.0.yaml";

  # The stack's own rules, i.e. those in the two `generic.*` files. BOX-332 adds
  # a feature's rules to the same committed farm, and "the defaults are the
  # stack's" is a statement about `generic.*`, not about everything loaded.
  genericRuleFiles = builtins.filter (n: lib.hasPrefix "generic." n) committedRuleFiles;
  genericRuleNames = builtins.concatMap alertNamesIn genericRuleFiles;

  alertmanagerConfig = hostCfg.services.prometheus.alertmanager.configuration;
  alertmanagerRoute = alertmanagerConfig.route;
  alertmanagerReceivers = alertmanagerConfig.receivers;
  receiverNamed = name: builtins.head (builtins.filter (r: r.name == name) alertmanagerReceivers);

  pushoverConfig = builtins.head (receiverNamed "pushover").pushover_configs;

  # ── BOX-332: textfile checks ──────────────────────────────���──────────
  #
  # The acceptance criterion is "the helper is generic: another feature could add
  # a sqlite check in a few lines", so the test declares **two** checks that it
  # did not have to write: one from `obs.sqliteCheck`, against a database that
  # does not exist on any host (the point is the rendering, not the file), and
  # one hand-written `textfileScript`. Between them they prove the shape a future
  # feature copies.

  # A trivial second consumer: a plain textfile check with no helper at all,
  # which is what "not every check is a sqlite check" looks like.
  secondConsumerModule = {
    config.my.observability.textfileChecks.disk-snapshot = {
      user = "podman";
      interval = "1h";
      script = obsHelper.textfileScript "disk-snapshot" ''
        printf '# TYPE sample_gauge gauge\nsample_gauge 1\n' | emit_textfile
      '';
    };
  };

  # A sqlite check, in the shape a feature module writes it.
  sqliteConsumerModule = {
    config.my.observability.textfileChecks.demo-db = obsHelper.sqliteCheck {
      name = "demo-db";
      database = "/var/lib/demo/demo.db";
      table = "events";
      user = "podman";
    };
  };

  checkCfg =
    (flake.nixosConfigurations.calamansi.extendModules {
      modules = [
        sqliteConsumerModule
        secondConsumerModule
      ];
    }).config;

  checkNames = builtins.filter (n: lib.hasPrefix "textfile-check-" n) (builtins.attrNames checkCfg.systemd.services);
  checkTimers = builtins.filter (n: lib.hasPrefix "textfile-check-" n) (builtins.attrNames checkCfg.systemd.timers);

  demoService = checkCfg.systemd.services."textfile-check-demo-db";
  demoScript = demoService.script;
  diskService = checkCfg.systemd.services."textfile-check-disk-snapshot";
  demoTimer = checkCfg.systemd.timers."textfile-check-demo-db".timerConfig;
  diskTimer = checkCfg.systemd.timers."textfile-check-disk-snapshot".timerConfig;

  # The directory node_exporter is told to read, from its own flag. This is the
  # assertion that matters most: the checks write into the directory the
  # collector actually scans, and both sides get it from
  # `obs.textfileDirectory` so a rename cannot half-apply.
  textfileDirFlag =
    builtins.head (
      builtins.filter (f: lib.hasPrefix "--collector.textfile.directory=" f) (
        checkCfg.services.prometheus.exporters.node.extraFlags
      )
    );
  textfileDir = builtins.substring (builtins.stringLength "--collector.textfile.directory=") 1000 textfileDirFlag;

  # ── BOX-332: the committed bifrost check and its dashboard ───────────
  #
  # Read from the committed lumquat, because the host that matters is the one
  # that will run it. The assertions below are what stops the rendered script
  # drifting away from the read-only contract BOX-202 established.
  bifrostService = lumquat.systemd.services."textfile-check-bifrost-logs-db";
  bifrostScript = bifrostService.script;
  bifrostTimer = lumquat.systemd.timers."textfile-check-bifrost-logs-db".timerConfig;

  # The bifrost dashboard's identity, read out of the provider directory. A
  # dashboard whose datasource UID is wrong renders empty, which looks exactly
  # like "no data yet" — so the UID is asserted, not eyeballed.
  bifrostDashboard =
    if builtins.elem "bifrost.json" dashboardFiles then
      builtins.fromJSON (builtins.readFile (dashboardProvider.options.path + "/bifrost.json"))
    else
      { };

  # A panel and each of its targets must both name the datasource: Grafana
  # resolves the panel-level one for display, and a target with no `datasource`
  # of its own inherits it — but an *explicitly wrong* one on either renders the
  # panel empty, so both are collected. `uid` may be a bare string in older
  # schema versions, so both spellings are accepted rather than reported as
  # missing.
  uidOf =
    ds:
    if builtins.isAttrs ds then
      ds.uid or ""
    else if builtins.isString ds then
      ds
    else
      "";
  bifrostDashboardDatasources_raw = builtins.concatMap (
    panel: [ (uidOf (panel.datasource or "")) ] ++ map (t: uidOf (t.datasource or "")) (panel.targets or [ ])
  ) bifrostDashboard.panels or [ ];

  bifrostDashboardDatasources = builtins.filter (d: d != "") bifrostDashboardDatasources_raw;

  bifrostAlertsInGathered = builtins.filter (n: n == "lumquat-bifrost.0.yaml") gatheredRuleFiles;

  # ── Assertions ──────────────────────────────────────────────────────
  #
  # Each entry says what broke and what is affected. They are collected in one
  # list so the gate can report every failure at once rather than the first.
  assertions = [
    # Seam 1 — a feature declares a source, the agent scrapes it.
    {
      assertion = builtins.elem "node" jobNames;
      message = "The agent no longer scrapes its own node_exporter under job_name \"node\". A feature declaring a target must not displace it, and Node Exporter Full filters on that name.";
    }
    {
      assertion = builtins.elem "llama-qwen" jobNames;
      message = "A declared scrapeTargets entry did not reach vmagent's rendered config.";
    }

    # Seam 2 — dashboards reach the provider's directory.
    {
      assertion = builtins.elem "prebuilt-node-exporter-full.json" dashboardFiles;
      message = "Node Exporter Full is not in Grafana's dashboard provider directory, so the Host detail dashboard is missing on calamansi.";
    }
    {
      assertion =
        nodeExporterFullFacts.uid == "rYdddlPWk" && nodeExporterFullFacts.title == "Node Exporter Full";
      message = "The pinned Node Exporter Full JSON is not dashboard 1860 (uid rYdddlPWk / title \"Node Exporter Full\"). The URL or the hash is wrong.";
    }
    {
      assertion = builtins.elem "ds_prometheus" nodeExporterFullFacts.datasourceVariables;
      message = "Node Exporter Full has no `ds_prometheus` datasource variable, so it would need a datasource UID baked in and vendoring before it renders.";
    }
    {
      # BOX-334 is the first feature to declare a dashboard, so this is also the
      # first proof that the seam reaches Grafana and not only the option set.
      # The file name is derived from the key by the provider renderer, so a
      # declared-but-not-rendered dashboard passes the key check and fails here.
      assertion = builtins.elem "storage2.json" dashboardFiles;
      message = "my.observability.dashboards.storage2 did not reach Grafana's dashboard provider directory, so the storage2 dashboard is missing on calamansi.";
    }
    {
      assertion = storage2DashboardJson.uid == "storage2-nas";
      message = "The storage2 dashboard's uid is not `storage2-nas`. The uid is what a bookmark or a runbook link points at.";
    }
    {
      # The panels must select the job the module declares, or every panel is
      # empty against a successful scrape — the failure a file check misses.
      assertion = lib.any (
        p: builtins.any (t: lib.hasInfix "job=\"storage2\"" (t.expr or "")) (p.targets or [ ])
      ) storage2DashboardJson.panels;
      message = "No storage2 dashboard panel selects job=\"storage2\", so the dashboard would render empty while the scrape succeeds.";
    }

    # Seam 1 again, for the SNMP path (BOX-334): the device's metrics come
    # through snmp_exporter's query API, and the exporter is scraped a second
    # time for its own `snmp_scrape_*`. Losing the second job silently removes
    # the only series that distinguishes "device unreachable" from "poll
    # returning nothing", which is what Storage2PollDead is for.
    {
      assertion = storage2Job.metrics_path == "/snmp?target=${storage2Address}&module=storage2&auth=storage2";
      message = "The storage2 scrape job does not poll my.storage2Address through snmp_exporter's query API with the storage2 module and auth, so it is either scraping nothing or the wrong device.";
    }
    {
      assertion = storage2ExporterJob.metrics_path == "/metrics";
      message = "The storage2 exporter's self-metrics job does not scrape /metrics, so snmp_scrape_* series are never collected and Storage2PollDead can never fire.";
    }
    {
      # BOX-332: this reminder is now satisfied for real — `bifrost.json` is
      # asserted to reach the provider directory above, and its UID and
      # datasource bindings are asserted with it. The reminder is replaced rather
      # than deleted so the *property* (a declared dashboard key must be in the
      # directory) stays asserted for whatever BOX-331/BOX-338 declares next.
      assertion = lib.all (key: builtins.elem "${key}.json" dashboardFiles) declaredDashboardKeys;
      message = "A my.observability.dashboards key is declared on an agent host but is not in Grafana's provider directory. Either the gather dropped it or the key collides.";
    }

    # Seam 3 — a remote agent ships to the host, not to its own loopback.
    {
      assertion = cfg.services.vmagent.remoteWrite.url == "http://127.0.0.1:8428/api/v1/write";
      message = "The observability host's own agent must remote-write to loopback; anything else sends its metrics off-box.";
    }
    {
      assertion = remoteCfg.services.vmagent.remoteWrite.url != cfg.services.vmagent.remoteWrite.url;
      message = "my.observabilityHostAddress did not change the remote-write URL. A remote agent would buffer forever writing to its own localhost.";
    }

    # Seam 4 (BOX-330) — journal shipping arrives with the agent flag, and its
    # destination follows the same option vmagent uses.
    {
      assertion = hostJournal.enable;
      message = "The observability host's own agent does not upload its journal, so calamansi's logs are never stored even though it runs VictoriaLogs.";
    }
    {
      assertion = remoteCfg.services.journald.upload.enable;
      message = "A remote agent host does not upload its journal. Journal shipping must arrive from the agent flag alone, with no per-host wiring.";
    }
    {
      assertion = hostJournal.settings.Upload.URL == "http://127.0.0.1:9428/insert/journald";
      message = "The observability host's journal upload does not target its local VictoriaLogs. It must go over loopback, and it must use VictoriaLogs' native journald endpoint (/insert/journald) rather than a JSON bridge.";
    }
    {
      assertion =
        remoteCfg.services.journald.upload.settings.Upload.URL != hostJournal.settings.Upload.URL;
      message = "my.observabilityHostAddress did not change the journal upload URL. A remote agent would ship its journal to nothing.";
    }

    # Seam 5 (BOX-330) — the log store's retention and the datasource's UID.
    {
      assertion = lib.hasInfix "-retentionPeriod=90d" victorialogsExecStart;
      message = "VictoriaLogs does not run with a 90-day retention. BOX-319 decided 90 days of logs on calamansi.";
    }
    {
      assertion = lib.hasInfix "-retention.maxDiskUsagePercent=80" victorialogsExecStart;
      message = "VictoriaLogs does not cap itself at 80% disk usage. BOX-319 decided an 80% cap, and without it the log store fills the disk that the metrics store shares.";
    }
    {
      assertion = logDatasource.uid == "victorialogs";
      message = "The VictoriaLogs datasource does not use the reserved `victorialogs` UID. Every dashboard written between BOX-326 and now points at that literal.";
    }

    # Seam 4 — the committed lumquat agent.
    {
      assertion = lumquat.my.observabilityAgent;
      message = "lumquat is not an observability agent (my.observabilityAgent = true). It runs no collectors and contributes nothing to calamansi.";
    }
    {
      assertion = !lumquat.my.observabilityHost;
      message = "lumquat is flagged as the observability host. Exactly one host stores metrics; a second VictoriaMetrics and Grafana on lumquat contradicts BOX-311's design.";
    }
    {
      assertion = builtins.elem "node" lumquatJobNames;
      message = "lumquat's agent does not declare job_name \"node\". Node Exporter Full selects its series with job=\"node\", so the Host detail dashboard would be empty.";
    }
    {
      assertion = builtins.any (
        sc: builtins.elem lumquatNodeExporterTarget (sc.targets or [ ])
      ) lumquatNodeJob.static_configs;
      message = "lumquat's node job does not target its own node_exporter (${lumquatNodeExporterTarget}).";
    }
    {
      assertion = lumquat.services.vmagent.remoteWrite.url != loopbackRemoteWrite;
      message = "lumquat's vmagent remote-writes to loopback. On a host that is not the observability host that means samples buffer forever against a VictoriaMetrics that does not exist here: set my.observabilityHostAddress.";
    }
    {
      assertion = lumquat.services.prometheus.exporters.node.listenAddress == "127.0.0.1";
      message = "lumquat's node_exporter is not loopback-bound. A metrics endpoint on the LAN is an information leak with no upside.";
    }

    # Seam 4 — lumquat's collectors (BOX-315's decision, BOX-332's contract).
    {
      assertion = builtins.elem "drm" lumquatCollectors;
      message = "lumquat's node_exporter does not enable the drm collector, so it exposes no GPU metrics (BOX-315). Set my.observabilityGpuMetrics.";
    }
    {
      assertion = builtins.elem "hwmon" lumquatCollectors;
      message = "lumquat's node_exporter does not enable hwmon, so GPU temperature and package power are missing (BOX-315).";
    }
    {
      assertion = builtins.any (
        f: lib.hasInfix "collector.textfile.directory" f
      ) lumquat.services.prometheus.exporters.node.extraFlags;
      message = "lumquat's node_exporter has no textfile directory. BOX-332's checks write <name>.prom into /var/lib/node_exporter/textfile and nothing would read them.";
    }

    # Seam 5 — GPU telemetry is a per-host flag, not a global.
    {
      assertion = builtins.elem "drm" gpuCfg.services.prometheus.exporters.node.enabledCollectors;
      message = "my.observabilityGpuMetrics = true did not enable the drm collector.";
    }
    {
      assertion = !builtins.elem "drm" cfg.services.prometheus.exporters.node.enabledCollectors;
      message = "A host without my.observabilityGpuMetrics enabled the drm collector. It is AMD-specific and walks /sys/class/drm on every scrape for nothing.";
    }
    {
      assertion = builtins.elem "hwmon" cfg.services.prometheus.exporters.node.enabledCollectors;
      message = "hwmon is not on for a host without a GPU. Temperatures are host health, not GPU telemetry, and are needed everywhere.";
    }

    # ── BOX-334: device credentials never reach the Nix store ────────
    #
    # The rendered `snmp.yml` carries the *variable names*; secretspec expands
    # them into the exporter's environment at start-up. Anything else would put a
    # NAS credential in the world-readable store and in every generation.
    {
      assertion = snmpAuth.username == "\${UNIFI_SNMP_USER}";
      message = "The SNMPv3 username is not a \${UNIFI_SNMP_USER} reference. Anything else would put a device credential in the Nix store.";
    }
    {
      assertion = snmpAuth.password == "\${UNIFI_SNMP_PASSWORD}";
      message = "The SNMPv3 auth password is not a \${UNIFI_SNMP_PASSWORD} reference. Anything else would put a device credential in the Nix store.";
    }
    {
      assertion = snmpAuth.priv_password == "\${UNIFI_SNMP_PASSWORD}";
      message = "The SNMPv3 privacy password is not a \${UNIFI_SNMP_PASSWORD} reference. Anything else would put a device credential in the Nix store.";
    }
    {
      assertion = lib.hasInfix "-S unifi-snmp" hostCfg.systemd.services.prometheus-snmp-exporter.serviceConfig.ExecStart;
      message = "The snmp_exporter unit does not resolve the `unifi-snmp` scope, so the \${VAR} references in snmp.yml would never be substituted and every poll would fail authentication.";
    }
    {
      # The exporter only expands ${VAR} when told to; without this flag the
      # literal reference is sent to the device as the username.
      assertion = lib.hasInfix "--config.expand-environment-variables" hostCfg.systemd.services.prometheus-snmp-exporter.serviceConfig.ExecStart;
      message = "snmp_exporter runs without --config.expand-environment-variables, so \${UNIFI_SNMP_USER} would be sent to storage2 verbatim.";
    }
    {
      # The poller is a native host service (ADR 0006), and it is only ever
      # loopback: the device's internals have no business on the LAN.
      assertion = hostCfg.services.prometheus.exporters.snmp.listenAddress == "127.0.0.1";
      message = "The SNMP exporter is not loopback-bound. It re-serves a NAS's internals and only this host's own agent scrapes it.";
    }

    # ── BOX-329: rules and the alerting path ──────────────────────────

    # The generic defaults are the stack's, not a feature's: they must be there
    # with no feature declaring anything, which is the "a new host gets them for
    # free" property.
    {
      assertion =
        genericOnlyRuleFiles == [
          "generic.0.yaml"
          "generic.1.yaml"
          # BOX-332: bifrost's rules are declared on lumquat and gathered, so the
          # committed farm now holds them too. The "for free" property is what
          # this asserts, not an empty farm: the two generic files are still
          # first, still unqualified and still unreplaced by any feature.
          "lumquat-bifrost.0.yaml"
        ];
      message = "A host with no feature rulesets of its own does not load exactly the two generic rule files. A new agent host is supposed to get the default rules with no declaration of its own.";
    }
    {
      # `generic.*` explicitly, not the whole committed farm: BOX-332 adds
      # bifrost's rules to the farm, and they are a feature's, not the stack's.
      assertion =
        genericRuleNames == [
          "HostDown"
          "DiskFilling"
          "DiskNearlyFull"
          "DiskFillingFast"
          "OutOfMemory"
          "SystemdUnitFailed"
          "SourceDown"
          "HotHardware"
          "Watchdog"
        ];
      message = "The generic rule set no longer matches BOX-320's decided v1 list (host down, disk filling, disk nearly full, OOM, unit failed, source down, hot hardware, watchdog).";
    }

    # The acceptance criterion: a rule declared by a lumquat feature appears in
    # calamansi's vmalert rule directory.
    {
      assertion = builtins.elem "lumquat-llama-queue.0.yaml" gatheredRuleFiles;
      message = "A ruleset declared on lumquat did not reach calamansi's vmalert rule directory. my.observability.rules is not being gathered across agent hosts.";
    }
    {
      assertion = lib.hasInfix "vmalert-rules-metrics" gatheredRuleDir;
      message = "calamansi's vmalert unit does not load its rules from the rendered rule farm.";
    }

    # BOX-334's rules. `Storage2PollDead` is the whole point: the device cannot
    # run an agent, so a dead SNMP poll is the only storage2 failure visible from
    # outside it, and it is silent without this rule.
    {
      assertion = builtins.elem "calamansi-storage2.0.yaml" committedRuleFiles;
      message = "The storage2 ruleset did not reach calamansi's vmalert rule directory, so a dead SNMP poll on storage2 raises nothing.";
    }
    {
      assertion = builtins.elem "Storage2PollDead" storage2RuleNames;
      message = "No Storage2PollDead rule exists. Nothing would notice storage2's SNMP agent going away.";
    }
    {
      # A reviewer's finding: once the per-file assertions became `elem` checks,
      # nothing pinned the committed host's rule set *exactly*, so a fourth
      # ruleset arriving unannounced would have passed. Re-pin it. This fails
      # when a feature adds rules — which is the point: the fix is to name the
      # new file here, so the gathered set stays a reviewed fact rather than an
      # accumulation.
      assertion =
        committedRuleFiles == [
          "calamansi-storage2.0.yaml"
          "generic.0.yaml"
          "generic.1.yaml"
          "lumquat-bifrost.0.yaml"
        ];
      message = "calamansi's gathered rule file set changed. If a feature just added rules, name its file here so the set stays deliberate; if not, something is being gathered that should not be.";
    }

    # The delivery path, as BOX-320 decided it.
    {
      assertion =
        alertmanagerRoute.group_by == [
          "alertname"
          "host"
        ];
      message = "Alertmanager no longer groups by rule and host. BOX-320 decided grouping by (alertname, host).";
    }
    {
      assertion = alertmanagerRoute.group_wait == "30s";
      message = "Alertmanager's group_wait is not 30 s (BOX-320).";
    }
    {
      assertion = alertmanagerRoute.repeat_interval == "1h";
      message = "Alertmanager does not repeat a critical alert hourly (BOX-320).";
    }
    {
      assertion = builtins.elem "pushover" (map (r: r.name) alertmanagerReceivers);
      message = "Alertmanager has no Pushover receiver, so no alert reaches the phone.";
    }
    {
      assertion = builtins.elem "healthchecks" (map (r: r.name) alertmanagerReceivers);
      message = "Alertmanager has no healthchecks.io receiver, so the dead-man's switch is not wired.";
    }
    {
      assertion =
        (builtins.head alertmanagerRoute.routes).matchers == [ "severity=\"none\"" ]
        && (builtins.head alertmanagerRoute.routes).receiver == "healthchecks";
      message = "The Watchdog (severity=\"none\") is not routed to healthchecks.io. It must not reach the phone, and it must not go anywhere else.";
    }
    {
      assertion = (builtins.head alertmanagerRoute.routes).repeat_interval == "1m";
      message = "The Watchdog's route does not repeat every minute. healthchecks.io expects a ping a minute and alerts after its own grace period.";
    }
    {
      assertion = lib.hasInfix "severity" pushoverConfig.priority;
      message = "Pushover's priority is no longer a template over the alert's severity, so critical and warning cannot differ (BOX-320: critical = 1, warning = 0).";
    }

    # The Watchdog rule itself, which is what the bridge above pings for.
    {
      assertion = builtins.elem "Watchdog" defaultRuleNames;
      message = "No always-firing Watchdog alert exists. Without it nothing pings healthchecks.io, and the house going dark is silent.";
    }

    # Secrets: the rendered config carries the *variable name*, never a value.
    {
      assertion = pushoverConfig.token == "\${PUSHOVER_APP_TOKEN}";
      message = "Alertmanager's Pushover token is not a \${PUSHOVER_APP_TOKEN} reference. Anything else would put a credential in the Nix store.";
    }
    {
      assertion = pushoverConfig.user_key == "\${PUSHOVER_USER_KEY}";
      message = "Alertmanager's Pushover user key is not a \${PUSHOVER_USER_KEY} reference. Anything else would put a credential in the Nix store.";
    }
    {
      assertion = lib.hasInfix "-S alerting" hostCfg.systemd.services.alertmanager.serviceConfig.ExecStart;
      message = "Alertmanager's unit does not resolve the `alerting` scope, so the \${VAR} references in its config would never be substituted at start-up.";
    }

    # ── BOX-332: textfile checks ─────────────────────────────────────────

    # The collection is inert until a feature declares something: calamansi
    # declares no checks, so it must get no check units at all. Otherwise a
    # `mkIf`-guarded empty attrset would leave dead units on every host.
    {
      assertion = builtins.filter (n: lib.hasPrefix "textfile-check-" n) (builtins.attrNames hostCfg.systemd.services) == [ ];
      message = "The observability host has textfile-check units even though it declares no checks. The check units must appear only with the entries that need them.";
    }

    # A declared check becomes a service *and* a timer, named after the entry.
    {
      assertion =
        checkNames == [
          "textfile-check-demo-db"
          "textfile-check-disk-snapshot"
        ];
      message = "A declared my.observability.textfileChecks entry did not become a systemd service named textfile-check-<name>. Two checks were declared (one from obs.sqliteCheck, one hand-written) and both must be rendered.";
    }
    {
      assertion = checkTimers == checkNames;
      message = "A textfile check has a service but no timer, or a timer with no service. Each check needs both: the timer schedules, the service runs.";
    }
    {
      assertion = demoTimer.Unit == "textfile-check-demo-db.service";
      message = "A textfile check's timer does not point at its own service.";
    }
    {
      assertion = demoTimer.OnUnitInactiveSec == "15m" && diskTimer.OnUnitInactiveSec == "1h";
      message = "A textfile check's timer does not use the declared `interval` (default 15m, or the value the entry set).";
    }

    # The user contract: a check runs as the account that owns what it reads.
    # A check with no escape hatch runs directly as that user, so `User=` names
    # it — this is the option the whole shape exists for (BOX-202).
    {
      assertion = diskService.serviceConfig.User == "podman";
      message = "A textfile check without an escape hatch does not run as its declared `user`. That is the BOX-202 lesson: a check runs as the owner of what it reads, not as root.";
    }

    # The documentation's "another feature adds a check in a few lines" claim,
    # asserted rather than asserted-in-prose: two consumers, two shapes, no
    # per-check wiring anywhere.
    {
      assertion = lib.hasInfix "sample_gauge" diskService.script;
      message = "A hand-written textfile check's body did not reach its service script.";
    }

    # ── BOX-202: the bifrost check must be read-only ─────────────────
    #
    # This is the assertion that would have caught the crash-loop. Every query
    # the check runs has to open the database `mode=ro` **and** `immutable=1`:
    # ro refuses a write, immutable means sqlite takes no lock and reads no
    # -wal, so it can neither create a `-shm` sidecar nor leave one owned by the
    # wrong uid. `-readonly` is the second refusal at the CLI layer.
    {
      assertion = lib.hasInfix "mode=ro&immutable=1" bifrostScript;
      message = "The bifrost logs.db check does not open the database `mode=ro&immutable=1`. Without `immutable=1` sqlite takes a lock and may create a -shm sidecar owned by the check's user, which makes bifrost crash-loop on \"attempt to write a readonly database\" (BOX-202).";
    }
    {
      assertion = lib.hasInfix "-readonly" bifrostScript;
      message = "The bifrost logs.db check does not pass sqlite3's `-readonly` flag, so the read-only guarantee rests on the URI alone.";
    }
    {
      # A write anywhere in the script is the failure this ticket exists to
      # avoid. The only writes the script performs are its own .prom temp file
      # and the rename onto the target.
      assertion =
        !(lib.hasInfix "VACUUM" bifrostScript)
        && !(lib.hasInfix "INSERT" bifrostScript)
        && !(lib.hasInfix "DELETE" bifrostScript)
        && !(lib.hasInfix "UPDATE " bifrostScript)
        && !(lib.hasInfix "PRAGMA" bifrostScript);
      message = "The bifrost logs.db check's script contains a database write (VACUUM/INSERT/DELETE/UPDATE/PRAGMA). A check must never open bifrost's database for writing (BOX-202).";
    }
    {
      # The read-only query must actually query the table bifrost writes, and
      # with the column that table has. `logs`/`timestamp` was read from
      # bifrost's source (framework/logstore/tables.go), not guessed.
      assertion = lib.hasInfix "FROM logs" bifrostScript && lib.hasInfix "timestamp" bifrostScript;
      message = "The bifrost check does not query the `logs` table's `timestamp` column. That is bifrost's own schema (framework/logstore/tables.go), and a guessed name would make the check emit _success 0 forever.";
    }
    {
      assertion = lib.hasInfix "bifrost_logs_db_size_bytes" bifrostScript
        && lib.hasInfix "bifrost_logs_db_rows" bifrostScript
        && lib.hasInfix "bifrost_logs_db_oldest_row_age_seconds" bifrostScript;
      message = "The bifrost check does not publish all three of BOX-207's numbers: size, row count and oldest-row age.";
    }

    # The atomic write: a temp file in the same directory, then a rename. In
    # place would let a scrape read a half-written file.
    {
      assertion = lib.hasInfix "mv -f" bifrostScript && lib.hasInfix ".prom.$$" bifrostScript;
      message = "The bifrost check does not write atomically (temp file + rename in the textfile directory), so a scrape can read a half-written .prom file.";
    }
    {
      assertion = lib.hasInfix "chmod 0644" bifrostScript;
      message = "The bifrost check does not chmod its .prom file 0644, so the file's readability depends on the check user's umask and node_exporter may not be able to read it.";
    }

    # The writer and the reader must agree on the directory. Both come from
    # `obs.textfileDirectory`, and this asserts the check writes where
    # node_exporter is told to look.
    {
      assertion = lib.hasInfix textfileDir bifrostScript;
      message = "The bifrost check writes its .prom file somewhere other than node_exporter's textfile directory (${textfileDir}). Nothing would read it.";
    }
    {
      assertion = lib.hasInfix "ReadWritePaths" (builtins.toJSON bifrostService.serviceConfig);
      message = "The bifrost check's unit is not granted write access to the textfile directory, so it cannot publish its file under `ProtectSystem = strict`.";
    }

    # The bifrost timer is on a multi-minute clock, not a scrape interval.
    {
      assertion = bifrostTimer.OnUnitInactiveSec == "15m";
      message = "The bifrost check does not run on the default 15-minute interval.";
    }

    # ── BOX-332: the rule and the dashboard ──────────────────────

    # The recording rule and the alerts must be gathered by the observability
    # host — a rule file that stays on lumquat alerts on nothing.
    {
      assertion = bifrostAlertsInGathered != [ ];
      message = "lumquat's bifrost rules did not reach calamansi's vmalert rule directory. The ruleset is declared on lumquat and gathered across agent hosts.";
    }
    {
      assertion =
        let
          entry = builtins.head (
            builtins.filter (f: f.name == "lumquat-bifrost.0.yaml") (
              committedRuleEntries ++ gatheredRuleEntries
            )
          );
          text = builtins.readFile entry.path;
        in
        lib.hasInfix "bifrost:logs_db_growth_mib_per_day" text
        && lib.hasInfix "BifrostLogGrowth" text
        && lib.hasInfix "> 200" text
        && lib.hasInfix "1024^3" text;
      message = "The bifrost rule file no longer carries BOX-320's decided thresholds: a `bifrost:logs_db_growth_mib_per_day` recording rule, a `BifrostLogGrowth` alert at 200 MB/day and a 1 GB total.";
    }

    # The dashboard reaches Grafana's provider directory, and its panels query
    # the datasource UID that is actually provisioned.
    {
      assertion = builtins.elem "bifrost.json" dashboardFiles;
      message = "BOX-332's bifrost dashboard is not in Grafana's provider directory. Declared on lumquat in my.observability.dashboards.bifrost, gathered by calamansi.";
    }
    {
      assertion = bifrostDashboard.uid == "bifrost-logs-db";
      message = "The bifrost dashboard's uid is not `bifrost-logs-db`. BOX-331/BOX-338 link to that literal, so changing it breaks their links.";
    }
    {
      assertion = lib.unique bifrostDashboardDatasources == [ "victoriametrics" ];
      message = "The bifrost dashboard does not bind every panel to the provisioned `victoriametrics` datasource UID. A wrong UID renders empty, which looks exactly like \"no data yet\".";
    }
    {
      assertion = builtins.length (bifrostDashboard.panels or [ ]) >= 5;
      message = "The bifrost dashboard has fewer than five panels, so it cannot show size, rows, oldest-row age and growth together (BOX-207's list).";
    }
  ];

  failures = map (a: a.message) (builtins.filter (a: !a.assertion) assertions);

  result = {
    # ── Seam 1 output ──
    # The host's own exporter is still there (a feature does not displace it)
    # and both declared targets arrived, in declaration-independent order.
    jobNames = jobNames;
    # Optional fields survive the trip. `job_name` comes from the attrset key,
    # which is what a Grafana query filters on.
    llamaJob = jobNamed "llama-qwen";
    plainJob = jobNamed "plain";

    # ── Seam 2 output ──
    dashboardFiles = dashboardFiles;
    declaredDashboardKeys = declaredDashboardKeys;
    nodeExporterFullFacts = nodeExporterFullFacts;
    storage2DashboardUid = storage2DashboardJson.uid;
    storage2DashboardTitle = storage2DashboardJson.title;
    storage2Job = storage2Job;
    storage2ExporterJob = storage2ExporterJob;

    # ── Seam 3 output ──
    localRemoteWrite = cfg.services.vmagent.remoteWrite.url;
    remoteRemoteWrite = remoteCfg.services.vmagent.remoteWrite.url;

    # ── Seam 4 output ──
    lumquatIsAgent = lumquat.my.observabilityAgent;
    lumquatIsNotHost = !lumquat.my.observabilityHost;
    lumquatJobNames = lumquatJobNames;
    lumquatNodeTargets = lumquatNodeJob.static_configs;
    lumquatNodeExporterCollectors = lumquatCollectors;
    lumquatNodeExporterFlags = lumquat.services.prometheus.exporters.node.extraFlags;
    lumquatRemoteWrite = lumquat.services.vmagent.remoteWrite.url;

    # ── Seam 4 (BOX-330) output: journal shipping is part of the agent ──
    journalEnabledOnHost = hostJournal.enable;
    journalEnabledOnRemoteAgent = remoteCfg.services.journald.upload.enable;
    journalUrlOnHost = hostJournal.settings.Upload.URL;
    journalUrlOnRemoteAgent = remoteCfg.services.journald.upload.settings.Upload.URL;

    # ── Seam 5 (BOX-330) output: the log store ──
    victorialogsExecStart = victorialogsExecStart;
    logDatasourceUid = logDatasource.uid;

    # ── Seam 6 output ──
    gpuHostCollectors = gpuCfg.services.prometheus.exporters.node.enabledCollectors;
    nonGpuHostCollectors = cfg.services.prometheus.exporters.node.enabledCollectors;

    # ── Seam 8 output (BOX-329): rules ──
    committedRuleFiles = committedRuleFiles;
    committedRuleDir = committedRuleDir;
    gatheredRuleFiles = gatheredRuleFiles;
    gatheredRuleDir = gatheredRuleDir;
    defaultRuleNames = defaultRuleNames;
    storage2RuleNames = storage2RuleNames;
    snmpAuthIsReferences = {
      inherit (snmpAuth) username password priv_password;
    };
    genericOnlyRuleFiles = genericOnlyRuleFiles;

    # ── Seam 9 output (BOX-329): the delivery path ──
    alertmanagerGroupBy = alertmanagerRoute.group_by;
    alertmanagerGroupWait = alertmanagerRoute.group_wait;
    alertmanagerRepeatInterval = alertmanagerRoute.repeat_interval;
    alertmanagerReceiverNames = map (r: r.name) alertmanagerReceivers;
    watchdogRoute = builtins.head alertmanagerRoute.routes;
    pushoverPriority = pushoverConfig.priority;
    pushoverTokenIsReference = pushoverConfig.token;
    pushoverUserKeyIsReference = pushoverConfig.user_key;

    # ── Seam 10 output (BOX-332): textfile checks ──
    textfileDirectory = textfileDir;
    checkServices = checkNames;
    checkTimers = checkTimers;
    demoCheckUser = demoService.serviceConfig.User;
    demoCheckTimerInterval = demoTimer.OnUnitInactiveSec;
    bifrostCheckUser = bifrostService.serviceConfig.User;
    bifrostCheckInterval = bifrostTimer.OnUnitInactiveSec;
    bifrostCheckWritesTo = textfileDir;
    bifrostDashboardUid = bifrostDashboard.uid or null;
    bifrostDashboardPanels = builtins.length (bifrostDashboard.panels or [ ]);
    bifrostRuleFile = bifrostAlertsInGathered;

    # ── The gate ──
    # Printed too, so a reader of the JSON sees the result without checking the
    # exit code; the throw below is what actually fails the eval.
    assertions = assertions;
  };
in
if failures == [ ] then
  result
else
  throw ''
    observability contract violated:
      - ${lib.concatStringsSep "\n  - " failures}''
