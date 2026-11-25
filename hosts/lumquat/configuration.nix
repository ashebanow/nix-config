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
  my.monitoring = true;
  my.monitoringPort = 9090;
  my.zmx = true;
  my.memory = true;

  # Rex — the login server on this host (BOX-292). modules/features/rex.nix
  # explains the three roles; /etc/rex/accounts.jsonc, installed from
  # modules/features/rex/accounts.jsonc, is the whole allowlist.
  #
  # The login server rather than the shared server, because this is the box the
  # operator attaches to for a specific account: it maps each Tailscale caller
  # to an operating system account (named explicitly, or any regular UID >= 1000
  # through the wildcard) instead of admitting every caller as one account.
  #
  # It publishes through this host's tailscaled plus Tailscale Serve on 443 (the
  # login server cannot use tsnet), so the address is lumquat's own tailnet name
  # with no port and no `-rex` node:
  #
  #   rex --server lumquat.fluffy-walleye.ts.net ls
  #   rex --server https://podman@lumquat.fluffy-walleye.ts.net ls
  #
  # Consequently this host runs no `my.rexServer` (the two are mutually
  # exclusive). This host also runs no `my.rexClient`: the Rex NixOS module
  # installs the client into environment.systemPackages for every user
  # (installClient), which is the same binary programs.rex would add.
  my.rexLoginServer = true;
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
