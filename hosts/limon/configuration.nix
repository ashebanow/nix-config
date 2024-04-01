{
  config,
  pkgs,
  inputs,
  ...
}: {
  nix = {
    settings = {
      trusted-users = ["ashebanow"];
      auto-optimise-store = true;
      experimental-features = ["nix-command" "flakes"];
      warn-dirty = false;
    };
    gc = {
      automatic = true;
      dates = "weekly";
      options = "--delete-older-than 14d";
    };
  };
  # Allow unfree packages
  nixpkgs.config.allowUnfree = true;

  imports = [
    ./hardware-configuration.nix

    ../../modules/nixos/_1password.nix
    ../../modules/nixos/basics.nix
    ../../modules/nixos/bluetooth.nix
    ../../modules/nixos/boot.nix
    ../../modules/nixos/chrome.nix
    ../../modules/nixos/fonts.nix
    ../../modules/nixos/i18n.nix
    ../../modules/nixos/network.nix
    ../../modules/nixos/nvidia.nix
    ../../modules/nixos/openssh.nix
    ../../modules/nixos/printer.nix
    ../../modules/nixos/raid-mounts.nix
    # ../../modules/nixos/rancher-k3s.nix
    ../../modules/nixos/sound.nix
    ../../modules/nixos/tailscale.nix
    ../../modules/nixos/virtualisation.nix

    # ../../modules/nixos/desktops/gnome.nix
    ../../modules/nixos/desktops/hyprland.nix
    # ../../modules/nixos/desktops/plasma.nix

    ../../modules/nixos/gaming/steam.nix

    ../../users/ashebanow.nix
  ];

  networking.hostName = "limon";
  # interfaces."enp4s0".ipv4.addresses = [ {
  #   address = "10.40.60.6";
  #   prefixLength = 24;
  # } ];

  powerManagement = {
    enable = true;
    cpuFreqGovernor = "performance";
  };

  # This value determines the NixOS release from which the default
  # settings for stateful data, like file locations and database versions
  # on your system were taken. It‘s perfectly fine and recommended to leave
  # this value at the release version of the first install of this system.
  # Before changing this value read the documentation for this option
  # (e.g. man configuration.nix or on https://nixos.org/nixos/options.html).
  system.stateVersion = "23.11"; # Did you read the comment?
}
