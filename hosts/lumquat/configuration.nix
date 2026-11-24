# Lumquat host configuration — capability flags.
# Host-specific: every host gets its own configuration.nix.
{ lib, ... }: {
  # Host identity
  my.hostName = "lumquat";

  # NixOS version this host was first installed with (for state migrations)
  system.stateVersion = "26.05";

  # Capability flags — enables feature modules via mkIf guards
  my.base = true;
  my.baseUsername = "podman";
  my.baseTimezone = "America/Los_Angeles";
  my.cliProductivityTools = true;
  my.cliSecurityTools = true;
  my.cliSystemTools = true;
  my.cliTools = true;
  my.llm = true;
  my.llmServe = true;
  my.bifrostServe = true;
  my.llmModelStorage = "/var/lib/llm-models";
  my.access = true;
  my.accessTailnetName = "lumquat";
  my.accessEnableSSH = true;
  my.accessEnableExitNode = false;
  my.accessEnableFallbackSSH = true;
  my.accessFallbackPort = 2222;
  my.cockpit = true;
  my.cockpitPort = 9090;
  my.zmx = true;
  my.memory = true;

  # Observability — lumquat is an observability **agent**, not a host: it
  # collects its own metrics and ships them to calamansi, and stores nothing
  # (CONTEXT.md; docs/adr/0006). The flag turns on the shared agent module
  # (modules/features/observability-agent.nix): node_exporter on loopback,
  # and vmagent scraping it and remote-writing to the observability host with
  # disk buffering. Nothing else on this host needs to know it happened.
  my.observabilityAgent = true;

  # The AMD Strix Halo GPU (gfx1151). Turns on node_exporter's `drm`
  # collector — GPU busy percentage and VRAM / visible-VRAM / GTT usage —
  # alongside the `hwmon` collector every agent runs. This is the entirety of
  # BOX-315's GPU answer: no ROCm, no amd-smi, no amdgpu_top. Which of those
  # metrics this APU actually populates is recorded in
  # `docs/lumquat-hardware.md` and still needs confirming on the box.
  my.observabilityGpuMetrics = true;

  # PLACEHOLDER — calamansi's LAN address, for vmagent's remote-write target.
  #
  # Same caveat as `my.observabilityHostAllowedSources` on calamansi, and the
  # same value, because both sides of one connection have to agree: neither
  # host's real LAN address is recorded anywhere in this repo. Git history
  # shows only the 10.40.60.0/24 subnet the house LAN uses (bergamot .74,
  # miracle_max .97, the printer .111, gateway .1); calamansi is not on it yet
  # and lumquat's address appears nowhere at all. .20 was picked as a
  # free-looking address on that subnet — it is not a claim about either
  # machine.
  #
  # The default (`127.0.0.1`) is wrong here in a way that is easy to miss:
  # vmagent would happily buffer forever writing to a VictoriaMetrics that does
  # not exist on this host, and the only symptom would be an empty Grafana.
  #
  # BOX-324 sets the real address on both hosts at install. Until then this is
  # a placeholder and the data path does not work.
  my.observabilityHostAddress = "10.40.60.20";

  # Rex — a server for the `podman` account, published through Rex's own
  # tailnet node (BOX-292). modules/features/rex.nix explains the roles.
  #
  # This host runs no `my.rexClient`: the Rex NixOS module already installs the
  # client into environment.systemPackages for every user (installClient),
  # which is the same binary programs.rex would add.
  #
  # Only `podman` is served, deliberately. The point of Rex on a headless host
  # is attaching to persistent sessions for debugging, and `podman` is the
  # operator account here; there is no /home/ashebanow on lumquat at all. The
  # restriction is Tailscale's job now (owner-only on the node), not an
  # accounts file, because the login server cannot use tsnet.
  my.rexServer = true;
  my.rexServerUser = "podman";

  # Non-hardware defaults
  networking.useDHCP = lib.mkDefault true;

  # Headless server — no need for the HTML manual / options docs.
  # Also avoids nixpkgs' make-options-doc `options.json` derivation, which
  # triggers the "store path without a proper context" warning on every
  # build (Nix >= 2.31; tracked upstream as NixOS/nixpkgs#485682).
  documentation.enable = false;

  # CPU governor is set centrally in base.nix (schedutil).
  # Override here only if lumquat needs a different governor:
  nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";
}
