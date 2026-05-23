# Lumquat host configuration — capability flags.
# Host-specific: every host gets its own configuration.nix.
{
  lib,
  ...
}: {
  # Host identity
  my.hostName = "lumquat";

  # Capability flags — enables feature modules via mkIf guards
  my.base = true;
  my.baseUsername = "podman";
  my.baseTimezone = "America/Los_Angeles";
  my.llm = true;
  my.llmModelStorage = "/var/lib/llm-models";
  my.access = true;
  my.accessTailnetName = "lumquat";
  my.accessEnableSSH = true;
  my.accessEnableExitNode = false;
  my.accessEnableFallbackSSH = true;
  my.accessFallbackPort = 2222;
  my.monitoring = true;
  my.monitoringPort = 9090;

  # Non-hardware defaults
  networking.useDHCP = lib.mkDefault true;
  powerManagement.cpuFreqGovernor = lib.mkDefault "powersave";
  nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";
}
