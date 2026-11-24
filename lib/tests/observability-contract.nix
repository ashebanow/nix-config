# Contract test for the `my.observability` option set (BOX-326).
#
# The seam this ticket establishes is "a feature module declares a source and
# the machine's machinery picks it up". That is exactly what BOX-327 (lumquat's
# agent), BOX-331 (containers/llama.cpp) and BOX-338 (dashboards) will do, so
# this exercises their future call shape rather than the option set in
# isolation.
#
# Run: nix eval --impure --file lib/tests/observability-contract.nix
#
# A plain eval, not a NixOS test: there is no host to boot (calamansi is not
# installed until BOX-324), and a broken contract shows up in rendered
# configuration values long before it shows up as a running system.
#
# Two seams are covered, because they gather differently:
#
#   scrapeTargets -> this host's agent       extended in-process
#   dashboards    -> the observability host  gathered from `inputs.self`
#
# The second reads the *committed* flake's host configurations, so it cannot be
# exercised by `extendModules` (an extended config is not in `inputs.self`). It
# is asserted on the committed hosts instead: whatever dashboards calamansi
# declares must appear in the provider's directory alongside the prebuilts.
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

  scrapeConfigs = cfg.services.vmagent.prometheusConfig.scrape_configs;
  jobNamed = name: builtins.head (builtins.filter (j: j.job_name == name) scrapeConfigs);

  # The dashboard provider's directory, as it will actually exist on the host.
  dashboardProvider = builtins.elemAt flake.nixosConfigurations.calamansi.config.services.grafana.provision.dashboards.settings.providers 0;
  dashboardFiles = builtins.attrNames (builtins.readDir dashboardProvider.options.path);

  declaredDashboardKeys = builtins.attrNames (
    flake.nixosConfigurations.calamansi.config.my.observability.dashboards
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
}
