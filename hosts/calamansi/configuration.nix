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

  # storage2 (the UniFi UNAS Pro archive) health over SNMPv3 (BOX-334). Set
  # here and nowhere else: the poller is a loopback service on this host, and
  # the module asserts that only the observability host sets it. What this
  # device does *not* expose (capacity, SMART, pool state) is recorded in
  # modules/features/storage2.nix and is UniFi's own notification's job.
  my.storage2 = true;

  # Ingest is the one listener opened beyond loopback: other machines' agents
  # remote-write their metrics here. The port is VictoriaMetrics' default.
  my.observabilityIngestPort = 8428;

  # The agent hosts allowed to reach the ingest port.
  #
  # lumquat is the only such host, and its address is 10.40.0.87. Both machines
  # are on the 10.40.0.0/24 side (calamansi is 10.40.0.61), so this rule and the
  # source agree — but keep it pinned to the /32 rather than to a CIDR: the port
  # should open to one machine, not to whatever else shares its subnet. A rule
  # written for an address the packet never had fails closed and silently, which
  # is why it names the host exactly.
  #
  # The house runs two subnets: 10.40.0.0/24 carries lumquat (10.40.0.87),
  # calamansi (10.40.0.61), storage2 (10.40.0.59) and miraclemax's secondary
  # (10.40.0.240); 10.40.60.0/24 carries bergamot (.74), miracle_max (.97), the
  # printer (.111) and the gateway (.1).
  #
  # BOX-324 must also add the UniFi gateway and storage2 here when the syslog
  # path lands (BOX-335): those are 10.40.60.1 and 10.40.0.59 respectively.
  my.observabilityHostAllowedSources = [ "10.40.0.87" ];

  # Nothing else is decided yet. my.cockpit only if the observability work
  # wants it (BOX-325 renamed my.monitoring to my.cockpit; lumquat keeps it).
  #
  # Deliberately not carried over from lumquat either, because each is specific
  # to what lumquat does rather than to being a server: my.llm* and
  # my.bifrostServe (AI serving), my.memory, my.zmx.

  # Rex — a server for the `podman` account, published through Rex's own tailnet
  # node (BOX-292), reachable as calamansi-rex.fluffy-walleye.ts.net.
  #
  # Previously excluded here on the theory that Rex was specific to lumquat.
  # It is not: the point of a Rex server on a headless host is attaching to
  # persistent sessions for debugging, which is at least as useful on the
  # observability host as on the AI host — and it is how the operator reaches
  # this machine when SSH is inconvenient.
  #
  # The tsnet node needs its own one-time key, REX_CALAMANSI_TS_AUTHKEY, which
  # modules/features/secrets.nix passes only when this flag is on. It is a
  # non-reusable key: re-enrolling after wiping /var/lib/rex needs a freshly
  # minted one (see docs/rex.md).
  my.rexServer = true;
  my.rexServerUser = "podman";

  # Boot loader. Belongs here rather than in hardware-configuration.nix:
  # `nixos-generate-config` deliberately does not write `boot.loader`, and the
  # real generated file on this branch has no stanza. Without this the host
  # fails the `boot.loader.grub.devices` / `mirroredBoots` assertion and does
  # not evaluate at all.
  #
  # systemd-boot, not GRUB: calamansi is EFI and installs its ESP at /boot
  # (hardware-configuration.nix, vfat on 1618-901C). Unlike lumquat there is
  # no LUKS on this host, so no initrd/TPM2 pieces belong here.
  boot.loader = {
    systemd-boot.enable = true;
    efi.canTouchEfiVariables = true;
    efi.efiSysMountPoint = "/boot";
  };

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
