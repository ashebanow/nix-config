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

  # Rex — the login server, with the tailnet as its only door (BOX-292).
  # modules/features/rex.nix explains the three roles; this host plays the
  # login server, so it needs no my.rexClient: the Rex NixOS module already
  # installs the client into environment.systemPackages for every user
  # (installClient), which is the same binary programs.rex would add.
  #
  # `podman` is this host's owner account, `ashebanow` the same person's
  # account on the desktops. Both are reachable only by that person's Tailscale
  # login — the tailnet's only human identity.
  my.rexLoginServer = true;
  my.rexAccounts = {
    podman = [ "tailscale:ashebanow@gmail.com" ];
    ashebanow = [ "tailscale:ashebanow@gmail.com" ];
  };

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
