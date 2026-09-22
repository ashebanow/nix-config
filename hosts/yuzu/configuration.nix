# Yuzu host configuration.
# Host-specific: every host gets its own configuration.nix.
{lib, ...}: {
  imports = [./capabilities.nix];

  # Host identity
  my.hostName = "yuzu";

  # NixOS version this host was first installed with (for state migrations)
  system.stateVersion = "26.11";

  # Capability flags — enables feature modules via mkIf guards
  my.base = true;
  my.baseUsername = "ashebanow";
  my.baseTimezone = "America/Los_Angeles";
  my.access = true;
  my.accessTailnetName = "yuzu";
  my.accessEnableSSH = true;
  my.accessEnableExitNode = false;
  my.accessEnableFallbackSSH = true;
  my.accessFallbackPort = 2222;
  my.zmx = true;

  # Desktop workstation: switches base.nix to desktop power/user defaults and
  # enables the desktop environment picked below (see modules/features/desktop.nix
  # for the session plumbing, gnome.nix for GNOME-specific configuration).
  my.desktop = true;
  my.desktopEnvironment = "gnome";

  # Boot loader. The EFI system partition is mounted at /boot (see
  # hardware-configuration.nix), so systemd-boot is the natural choice —
  # same as lumquat. Confirm this matches the live install if it was set up
  # with GRUB instead.
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  # Non-hardware defaults
  networking.useDHCP = lib.mkDefault true;

  # CPU governor is set centrally in base.nix (schedutil).
  # Override here only if yuzu needs a different governor:
  nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";
}
