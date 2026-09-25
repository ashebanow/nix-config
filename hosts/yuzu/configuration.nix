# Yuzu host configuration.
{
  lib,
  pkgs,
  ...
}:
{
  imports = [ ./capabilities.nix ];

  # Host identity
  my.hostName = "yuzu";

  # NixOS version this host was first installed with (for state migrations)
  system.stateVersion = "25.11";

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

  # Resilio Sync — mirrors the macs' "Synced Files" folder (Books, Documents,
  # Fonts, Music, Pictures, Scans, Videos, personal_wiki, Google Photos) and
  # symlinks each into $HOME, so the data dirs are the synced ones. The folder
  # key comes from BWS via the `resilio` secretspec scope, never from here.
  # See modules/features/resilio.nix.
  my.resilio = true;
  my.resilioUser = "ashebanow";
  my.resilioDeviceName = "yuzu";
  my.resilioDirectory = "/home/ashebanow/Synced Files";
  my.resilioHomeLinks = [
    "Books"
    "Documents"
    "Fonts"
    "Google Photos"
    "Music"
    "Pictures"
    "Scans"
    "Videos"
    "personal_wiki"
  ];

  # The shared folder itself is NOT declared here. Resilio will not bind its
  # Web UI while a folder is declared in the config file, and a config-declared
  # folder cannot be put into the connecting state (that is runtime state the
  # daemon overrides), so the folder -- its key, its path and its known_hosts --
  # is added once through the UI at http://127.0.0.1:8888. Peers to name there:
  # 10.40.60.74 (bergamot) and 10.40.60.97 (miracle_max), both on port 4444.

  # CUPS, for the networked colour LaserJet. Both the service and the queue are
  # declarative (see modules/features/printing.nix).
  my.printing = true;

  # HP Color LaserJet MFP M477fdw, reached over IPP Everywhere at its LAN
  # address. The address is pinned rather than the printer's NPIAF8010.local
  # mDNS name, which CUPS cannot resolve here — systemd-resolved is not set up
  # for mDNS resolution, so only the IP works (confirmed via avahi-browse).
  # When the printer's DHCP lease changes, update the URI here and rebuild.
  my.printers = [
    {
      name = "HP_Color_LaserJet_MFP_M477fdw";
      uri = "ipp://10.40.60.111/ipp/print";
      description = "HP Color LaserJet MFP M477fdw";
      location = "Office";
      isDefault = true;
    }
  ];

  # Desktop workstation: switches base.nix to desktop power/user defaults and
  # turns on the graphical session plumbing in modules/features/desktop.nix.
  # Which sessions exist and which one starts by default is capabilities.nix's
  # business, not this file's — see CONTEXT.md under "NixOS scope".
  my.desktop = true;

  # Boot loader. The EFI system partition is mounted at /boot (see
  # hardware-configuration.nix), so systemd-boot is the natural choice.
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;
  boot.kernelPackages = pkgs.linuxPackages_latest;

  # Non-hardware defaults
  networking.useDHCP = lib.mkDefault true;

  # CPU governor is set centrally in base.nix (schedutil).
  # Override here only if yuzu needs a different governor:
  nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";
}
