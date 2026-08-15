# Lumquat host configuration — capability flags.
# Host-specific: every host gets its own configuration.nix.
{lib, ...}: {
  # Host identity
  my.hostName = "lumquat";

  # NixOS version this host was first installed with (for state migrations)
  system.stateVersion = "26.05";

  # Capability flags — enables feature modules via mkIf guards
  my.base = true;
  my.baseUsername = "podman";
  my.baseTimezone = "America/Los_Angeles";
  my.llm = true;
  my.llmServe = true;
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
  my.windshift = true;  # quadlet units + secretspec/BWS secrets (compose/windshift)

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
