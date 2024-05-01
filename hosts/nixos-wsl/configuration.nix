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
  };
  # Allow unfree packages
  nixpkgs.config.allowUnfree = true;

  imports = [
    ../../modules/nixos/_1password.nix
    ../../modules/nixos/basics.nix
    # ../../modules/nixos/bluetooth.nix
    # ../../modules/nixos/boot.nix
    # ../../modules/nixos/chrome.nix
    ../../modules/nixos/fonts.nix
    ../../modules/nixos/i18n.nix
    ../../modules/nixos/network.nix
    # ../../modules/nixos/nvidia.nix
    ../../modules/nixos/openssh.nix
    # ../../modules/nixos/printer.nix
    ../../modules/nixos/raid-mounts.nix
    ../../modules/nixos/sound.nix
    ../../modules/nixos/syncthing.nix
    ../../modules/nixos/tailscale.nix
    ../../modules/nixos/virtualisation.nix

    # ../../modules/nixos/desktops/gnome.nix
    # ../../modules/nixos/desktops/hyprland.nix
    # ../../modules/nixos/desktops/plasma.nix

    ../../users/ashebanow.nix
  ];

  networking.hostName = "NixOS-WSL";

  # enable relevant modules from my configuration:
  my.modules._1password.enable = true;
  my.modules._1password.enableGUI = true;
  my.modules.fonts.enable = true;
  my.modules.syncthing.enable = false;
}
