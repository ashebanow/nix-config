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

  # Dial the peers directly instead of discovering them. Resilio's own
  # tracker/relay machinery is still up, but this daemon never dials out at all
  # (see docs/research/resilio-sync-nixos.md), and LAN discovery cannot bridge
  # these hosts anyway: yuzu is 10.40.0.240/24 while the macs are 10.40.60.0/24,
  # so the multicast never crosses. known_hosts sidesteps all of it.
  #
  # LAN addresses deliberately, not hostnames: `bergamot` resolves to its
  # Tailscale address on this host, and Resilio does not traverse Tailscale.
  # These are DHCP leases, so they move if the router reassigns them.
  #
  # Every port here is 4444, the same fixed port yuzu listens on -- a peer left
  # on Resilio's default random port has no stable address to name, which is why
  # pinning it in each mac's Resilio preferences is a prerequisite for this
  # list to do anything.
  my.resilioKnownHosts = [
    "10.40.60.74:4444" # bergamot
    "10.40.60.97:4444" # miracle_max
  ];

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
