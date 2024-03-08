{
  config,
  pkgs,
  inputs,
  nixos-hardware,
  ...
}: {
  imports = [
    ../../modules/nixos/nix-settings.nix
    ./hardware-configuration.nix
    ../../modules/nixos/bluetooth.nix
    ../../modules/nixos/boot.nix
    ../../modules/nixos/i18n.nix
    ../../modules/nixos/network.nix
    ../../modules/nixos/openssh.nix
    ../../modules/nixos/printer.nix
    ../../modules/nixos/raid-mounts.nix
    # ../../modules/nixos/rancher-k3s.nix
    ../../modules/nixos/sound.nix
    ../../modules/nixos/virtualisation.nix

    # ../../modules/nixos/desktops/gnome.nix
    # ../../modules/nixos/desktops/hyprland.nix
    ../../modules/nixos/desktops/plasma.nix
  ];

  networking.hostName = "limon";
  # interfaces."enp4s0".ipv4.addresses = [ {
  #   address = "10.40.60.6";
  #   prefixLength = 24;
  # } ];

  # console ttys use the same keymap as X11
  console.useXkbConfig = true;

  # Enable touchpad support (enabled default in most desktopManager).
  # services.xserver.libinput.enable = true;

  # Enable CUPS to print documents.
  services.printing.enable = true;

  # Define a user account. Don't forget to set a password with ‘passwd’.
  users.users.ashebanow = {
    shell = pkgs.zsh;
    isNormalUser = true;
    description = "Andrew Shebanow";
    extraGroups = ["networkmanager" "wheel" "video" "storage" "libvirtd"];
    openssh.authorizedKeys.keys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIJhsuxHH4J5rPM5XNosTiTdHOX+NnZzHmePfEFTyaAs1 ashebanow@gmail.com"
    ];
  };

  environment.systemPackages = with pkgs; [
    # inputs.agenix.packages.x86_64-linux.default
    inputs.ragenix.packages.x86_64-linux.default
    firefox
    kitty
  ];

  # Some programs need SUID wrappers, can be configured further or are
  # started in user sessions.
  # programs.mtr.enable = true;
  programs.gnupg.agent = {
    enable = true;
    enableSSHSupport = true;
  };

  # set up zsh as default shell
  programs.zsh.enable = true;
  users.defaultUserShell = pkgs.zsh;
  environment.shells = with pkgs; [zsh];

  fonts.fontDir.enable = true;

  # Enable the 1Password CLI, this also enables a SGUID wrapper so the CLI can authorize against the GUI app
  programs._1password = {
    enable = true;
  };

  # Enable the 1Passsword GUI with myself as an authorized user for polkit
  programs._1password-gui = {
    enable = true;
    polkitPolicyOwners = ["ashebanow"];
  };

  # This value determines the NixOS release from which the default
  # settings for stateful data, like file locations and database versions
  # on your system were taken. It‘s perfectly fine and recommended to leave
  # this value at the release version of the first install of this system.
  # Before changing this value read the documentation for this option
  # (e.g. man configuration.nix or on https://nixos.org/nixos/options.html).
  system.stateVersion = "23.11"; # Did you read the comment?
}
