# Contract test for the `my.observability` option set (BOX-326), extended by
# BOX-327 (a remote agent, GPU telemetry, the Host detail dashboard) and by
# BOX-330 (journal shipping and the log store).
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
# Seven seams are covered, because they gather differently:
#
#   scrapeTargets -> this host's agent       extended in-process
#   dashboards    -> the observability host  gathered from `inputs.self`
#   a remote agent -> where it remote-writes extended in-process
#   journald      -> every agent host        extended in-process (BOX-330)
#   retention/UID -> the observability host  extended in-process (BOX-330)
#   the committed agent host                 read from `inputs.self`
#   GPU telemetry -> per-host collector flag extended in-process
#
# The dashboard seam reads the *committed* flake's host configurations, so it
# cannot be exercised by `extendModules` (an extended config is not in
# `inputs.self`). It is asserted on the committed hosts instead: whatever
# dashboards calamansi declares must appear in the provider's directory
# alongside the prebuilts.
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
    config.my.observabilityHostAddress = "10.40.60.20";
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
    builtins.filter (d: d.uid == "victorialogs")
      hostCfg.services.grafana.provision.datasources.settings.datasources
  );

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
      assertion = nodeExporterFullFacts.uid == "rYdddlPWk" && nodeExporterFullFacts.title == "Node Exporter Full";
      message = "The pinned Node Exporter Full JSON is not dashboard 1860 (uid rYdddlPWk / title \"Node Exporter Full\"). The URL or the hash is wrong.";
    }
    {
      assertion = builtins.elem "ds_prometheus" nodeExporterFullFacts.datasourceVariables;
      message = "Node Exporter Full has no `ds_prometheus` datasource variable, so it would need a datasource UID baked in and vendoring before it renders.";
    }
    {
      # When the first feature dashboard is declared (BOX-331/BOX-338 shape),
      # this test must start asserting that its key reached the provider
      # directory. Failing here is the reminder, not a defect.
      assertion = declaredDashboardKeys == [ ];
      message = "An observation dashboard is now declared. Extend this test to assert its key reaches Grafana's provider directory, then remove this reminder assertion.";
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
      assertion = hostJournal.settings.Upload.URL
        == "http://127.0.0.1:9428/insert/journald";
      message = "The observability host's journal upload does not target its local VictoriaLogs. It must go over loopback, and it must use VictoriaLogs' native journald endpoint (/insert/journald) rather than a JSON bridge.";
    }
    {
      assertion = remoteCfg.services.journald.upload.settings.Upload.URL
        != hostJournal.settings.Upload.URL;
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
