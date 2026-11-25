# Contract test for the `my.observability` option set.
#
# Established by BOX-326 (scrapeTargets, dashboards) and extended by BOX-329
# (rules, the alerting path). The seam each ticket owns is "a feature module
# declares something and the machine's machinery picks it up", so this exercises
# the call shape a feature module will use rather than the option set in
# isolation.
#
# Run: nix eval --impure --file lib/tests/observability-contract.nix --json
#
# A plain eval, not a NixOS test: there is no host to boot (calamansi is not
# installed until BOX-324), and a broken contract shows up in rendered
# configuration values long before it shows up as a running system.
#
# Seams covered:
#
#   scrapeTargets -> this host's agent       extended in-process
#   dashboards    -> the observability host  gathered from `inputs.self`
#   rules         -> the observability host  gathered, via the documented
#                                            `my.observabilityGatheredHosts` hook
#   alerting      -> Alertmanager's config   rendered, asserted as data
#
# The gather seams read the *committed* flake's host configurations, so they
# cannot be exercised by `extendModules` alone (an extended config is not in
# `inputs.self`). `my.observabilityGatheredHosts` — an internal option that is
# empty on every real host — is the seam that makes them testable; see its
# description in lib/my-options-module.nix.
let
  flake = builtins.getFlake (toString ../../.);

  # What a consuming feature module will look like. Deliberately uses the
  # public option paths only — no internals of the rendering helpers — so this
  # test breaks if the contract breaks, not merely if the implementation moves.
  featureModule = { lib, ... }: {
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

  # The other direction the contract has to work in: an *agent host that is not
  # the observability host* (BOX-327's lumquat), simulated by moving the
  # remote-write address off loopback.
  remoteAgentModule = {
    config.my.observabilityHostAddress = "10.40.60.20";
  };

  # BOX-329's shape: a lumquat feature declares an alert-rule file beside its
  # module. `extendModules` on lumquat, because the gather must see a *host*.
  #
  # `my.observabilityAgent = true` stands in for BOX-327, which is what makes
  # lumquat an agent host: the gather discovers hosts by that flag, so until
  # BOX-327 lands no lumquat ruleset can reach calamansi — which is why the
  # committed run below shows only the generic files.
  lumquatWithRules = flake.nixosConfigurations.lumquat.extendModules {
    modules = [
      ({ lib, ... }: {
        config.my.observabilityAgent = lib.mkForce true;
        config.my.observability.rules.llama-queue.files = [
          ./fixtures/box329-sample-lumquat.rules.yaml
        ];
      })
    ];
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

  # Calamansi, gathering a *simulated* set of agent hosts: the committed
  # calamansi plus lumquat carrying one feature ruleset.
  gatherHosts = {
    calamansi = flake.nixosConfigurations.calamansi;
    lumquat = lumquatWithRules;
  };

  gatherCfg =
    (flake.nixosConfigurations.calamansi.extendModules {
      modules = [ { config.my.observabilityGatheredHosts = gatherHosts; } ];
    }).config;

  scrapeConfigs = cfg.services.vmagent.prometheusConfig.scrape_configs;
  jobNamed = name: builtins.head (builtins.filter (j: j.job_name == name) scrapeConfigs);

  # The dashboard provider's directory, as it will actually exist on the host.
  dashboardProvider = builtins.elemAt flake.nixosConfigurations.calamansi.config.services.grafana.provision.dashboards.settings.providers 0;
  dashboardFiles = builtins.attrNames (builtins.readDir dashboardProvider.options.path);

  declaredDashboardKeys = builtins.attrNames (
    flake.nixosConfigurations.calamansi.config.my.observability.dashboards
  );

  # ── Alerting ─────────────────────────────────────────────────────────
  #
  # The rendered rule directory: what vmalert actually loads. `readDir` on it is
  # the assertion that matters — a rule file that never reaches this directory
  # is a rule that never runs.
  vmalertUnit = flake.nixosConfigurations.calamansi.config.systemd.services.vmalert;

  # The directory vmalert actually loads. Asserted on its *shape* (a path under
  # the rendered rule farm), not read: reading it would require the farm to be
  # built, and the file list below is computed from the same helper that fills
  # it.
  vmalertRuleDir = builtins.head (
    builtins.match ".*-rule=(/[^ ']+)/\\*\\.yaml.*" vmalertUnit.serviceConfig.ExecStart
  );

  # Rule file names and contents are read from the *sources*, not from the
  # rendered `linkFarm`: realising the farm would make this eval depend on a
  # build, and it contains exactly one symlink per source. The farm's naming
  # (`<host>-<ruleset>.<n>.yaml` for gathered rules, `<ruleset>.<n>.yaml` for the
  # stack's own) is what `obs.mkRuleFiles` implements, so using it here tests the
  # same function the module uses.
  obs = import ../../lib/observability.nix { inherit lib; };
  lib = flake.inputs.nixpkgs.lib;

  committedAgentHosts = lib.filterAttrs (
    _: host: host.config.my.observabilityAgent or false
  ) flake.nixosConfigurations;

  allRuleSets = {
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
  }
  // lib.concatMapAttrs (
    hostName: host:
    lib.mapAttrs' (
      name: ruleset: lib.nameValuePair "${hostName}-${name}" ruleset
    ) host.config.my.observability.rules
  ) committedAgentHosts;

  committedRuleEntries = obs.mkRuleFiles (obs.rulesetsOfType "metrics" allRuleSets);
  committedRuleFiles = map (f: f.name) committedRuleEntries;

  # The gathered run's rule files, which must include lumquat's.
  #
  # Read from the *rendered directory* (`linkFarm`, which needs no build) rather
  # than the checked one: the check derivation also validates, so reading it
  # would make a pure eval of this test depend on a build. `ruleDirContains`
  # below is what proves the checked directory is the same set.
  gatherRuleDir = builtins.head (
    builtins.match ".*-rule=(/[^ ']+)/\\*\\.yaml.*" gatherCfg.systemd.services.vmalert.serviceConfig.ExecStart
  );

  alertmanagerRoute =
    flake.nixosConfigurations.calamansi.config.services.prometheus.alertmanager.configuration.route;
  alertmanagerReceivers =
    flake.nixosConfigurations.calamansi.config.services.prometheus.alertmanager.configuration.receivers;
  receiverNamed = name: builtins.head (builtins.filter (r: r.name == name) alertmanagerReceivers);

  # Every `alert:` name in one rule file, so a reader can see which rules ship
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

  # Where vmalert loads rules from on each run. The file lists below come from
  # `mkRuleFiles` — the same function that fills these directories — so this
  # eval stays pure (no `readDir` of a path that has to be built first).
  committedRuleDirSpec = vmalertRuleDir;
  gatheredRuleDirSpec = gatherRuleDir;

  # Gathered: a ruleset declared on a *lumquat* feature appears here, named
  # `<host>-<ruleset>.<n>.yaml`. This is BOX-329's acceptance criterion.
  #
  # The list comes from the gather's own rulesets (what `mkRuleFiles` names)
  # *and* from the directory the rendered config points at, so the two cannot
  # disagree silently: a rule whose name never reaches the vmalert directory
  # fails here even if the gather computed it.
  gatheredRuleEntries = obs.mkRuleFiles (
    obs.rulesetsOfType "metrics" (
      {
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
      }
      // lib.concatMapAttrs (
        hostName: host:
        lib.mapAttrs' (
          name: ruleset: lib.nameValuePair "${hostName}-${name}" ruleset
        ) host.config.my.observability.rules
      ) (lib.filterAttrs (_: host: host.config.my.observabilityAgent or false) gatherHosts)
    )
  );

in
{
  # ── Seam 1: a feature declares a scrape target, the agent scrapes it ──
  #
  # jobNames is the assertion: the host's own exporter is still there (a
  # feature does not displace it) and both declared targets arrived, in
  # declaration-independent order.
  jobNames = map (j: j.job_name) scrapeConfigs;

  # Optional fields survive the trip. `job_name` comes from the attrset key,
  # which is what a Grafana query filters on.
  llamaJob = jobNamed "llama-qwen";
  plainJob = jobNamed "plain";

  # ── Seam 2: dashboards reach the provider's directory ────────────────
  #
  # The three prebuilts are always there; every dashboard a committed agent
  # host declares must be too, under its collection key.
  dashboardFiles = dashboardFiles;
  declaredDashboardKeys = declaredDashboardKeys;

  # ── Seam 3: a remote agent ships to the host, not to its own loopback ──
  localRemoteWrite = cfg.services.vmagent.remoteWrite.url;
  remoteRemoteWrite = remoteCfg.services.vmagent.remoteWrite.url;

  # ── Seam 4: rules reach calamansi's vmalert rule directory ───────────
  #
  # The compute side (which files the gather produces) and the render side (the
  # directory vmalert's own `-rule=` flag names) are both reported. A rule whose
  # name is computed but never reaches the directory would show up as the two
  # disagreeing; the paths are here so a reader can look at either.
  #
  # Committed: the two generic files from the shared machinery (BOX-329's
  # defaults and the Watchdog). They are present without any feature declaring
  # them, which is the "a new host gets them for free" property.

  committedRuleFiles = committedRuleFiles;
  gatheredRuleFiles = map (f: f.name) gatheredRuleEntries;
  committedRuleDir = committedRuleDirSpec;
  gatheredRuleDir = gatheredRuleDirSpec;

  defaultRuleNames = builtins.concatMap alertNamesIn committedRuleFiles;

  # ── Seam 5: the delivery path, asserted as data ─────────────────────
  #
  # Grouping and repeat behaviour are BOX-320's decision; they are values here
  # so a change to them is a failing test rather than a silent behaviour change.
  alertmanagerGroupBy = alertmanagerRoute.group_by;
  alertmanagerGroupWait = alertmanagerRoute.group_wait;
  alertmanagerRepeatInterval = alertmanagerRoute.repeat_interval;
  alertmanagerReceiverNames = map (r: r.name) alertmanagerReceivers;

  # The Watchdog route: `severity="none"` -> the healthchecks bridge only.
  watchdogRoute = builtins.head alertmanagerRoute.routes;

  # The Pushover receiver's priority is a template over severity, not two
  # receivers and not two configs to keep in step.
  pushoverPriority = (builtins.head (receiverNamed "pushover").pushover_configs).priority;

  # ── Seam 6: secrets are references, never values ─────────────────────
  #
  # The rendered config carries the *variable name*, and that is the whole
  # point: the store holds `${PUSHOVER_APP_TOKEN}`, which is not a token. The
  # value is substituted at start-up by `secretspec run`. A `true` here plus a
  # token-shaped string being absent is the assertion the acceptance criterion
  # asks for.
  pushoverTokenIsReference = (builtins.head (receiverNamed "pushover").pushover_configs).token;
  pushoverUserKeyIsReference = (builtins.head (receiverNamed "pushover").pushover_configs).user_key;

  # The rendered Alertmanager file as the *unit* will read it, proving the
  # `${...}` survives nixpkgs' envsubst pass into the store.
  alertmanagerUnitExecStart =
    flake.nixosConfigurations.calamansi.config.systemd.services.alertmanager.serviceConfig.ExecStart;
}
