# Calamansi host configuration — capability flags.
#
# calamansi is the **observability host**: it stores, queries, alerts on and
# displays every server's logs and metrics (see the Observability section of
# CONTEXT.md). Nothing AI-serving runs here; that is lumquat's job.
#
# This file is deliberately the lumquat server baseline and nothing more. The
# observability stack itself arrives with BOX-326 and its followers; until then
# the host must evaluate and build so those tickets have something to target
# while the physical bring-up (BOX-324) happens in parallel.
{ lib, ... }: {
  # Host identity
  my.hostName = "calamansi";

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

  # Access — the same shape as lumquat: Tailscale SSH as the primary path, the
  # non-standard-port SSH daemon as the way back in when Tailscale is down.
  # Not an exit node and not a subnet router: calamansi is a destination, like
  # lumquat.
  #
  # Gated on one prerequisite the user must supply before the first switch
  # (BOX-324): a Tailscale auth key for this node in BWS, declared as
  # CALAMANSI_TAILSCALE_AUTH_KEY alongside a `host-calamansi` scope in
  # secretspec.toml. host-secrets-populate.service aborts without it, which is
  # why tailscaled never comes up on a host whose key is missing.
  my.access = true;
  my.accessTailnetName = "calamansi";
  my.accessEnableSSH = true;
  my.accessEnableExitNode = false;
  my.accessEnableFallbackSSH = true;
  my.accessFallbackPort = 2222;

  # Observability — both roles. calamansi is the observability host (it stores,
  # queries, alerts on and displays every server's logs and metrics) *and* an
  # observability agent for its own metrics, because there is one agent per
  # machine and this one has only itself. See the Observability section of
  # CONTEXT.md and docs/adr/0006.
  my.observabilityHost = true;
  my.observabilityAgent = true;

  # Ingest is the one listener opened beyond loopback: other machines' agents
  # remote-write their metrics here. The port is VictoriaMetrics' default.
  my.observabilityIngestPort = 8428;

  # PLACEHOLDER — the agent hosts allowed to reach the ingest port.
  #
  # lumquat is the only such host, and **its real LAN address is not recorded
  # anywhere in this repo**: `docs/lumquat-hardware.md` has the hardware, not
  # the network, and git history shows only the 10.40.60.0/24 subnet the house
  # LAN uses (bergamot 10.40.60.74, miracle_max 10.40.60.97, the printer
  # 10.40.60.111, gateway 10.40.60.1) — never lumquat itself. So this is a
  # placeholder on that subnet, not a claim about the machine.
  #
  # BOX-324 sets the real address at install (either "/32" here, or
  # "10.40.60.0/24" if calamansi's own DHCP lease should simply be pinned
  # instead). Until then the rule below matches nothing useful, which is the
  # safe direction: an ingest port that nobody can reach is a bug, an ingest
  # port the whole LAN can reach is a hole.
  my.observabilityHostAllowedSources = [ "10.40.60.20" ];

  # Nothing else is decided yet. my.cockpit only if the observability work
  # wants it (BOX-325 renamed my.monitoring to my.cockpit; lumquat keeps it).
  #
  # Deliberately not carried over from lumquat either, because each is specific
  # to what lumquat does rather than to being a server: my.llm* and
  # my.bifrostServe (AI serving), my.memory, my.rexServer, my.zmx.

  # Non-hardware defaults
  networking.useDHCP = lib.mkDefault true;

  # Headless server — no need for the HTML manual / options docs.
  # Also avoids nixpkgs' make-options-doc `options.json` derivation, which
  # triggers the "store path without a proper context" warning on every
  # build (Nix >= 2.31; tracked upstream as NixOS/nixpkgs#485682).
  documentation.enable = false;

  # CPU governor is set centrally in base.nix (schedutil).
  # Override here only if calamansi needs a different governor:
  nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";
}
