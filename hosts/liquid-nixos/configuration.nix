# Edit this configuration file to define what should be installed on
# your system. Help is available in the configuration.nix(5) man page, on
# https://search.nixos.org/options and in the NixOS manual (`nixos-help`).

# NixOS-WSL specific options are documented on the NixOS-WSL repository:
# https://github.com/nix-community/NixOS-WSL

{ config, lib, pkgs, ... }:

{
  nix = {
    settings = {
      auto-optimise-store = true;
      experimental-features = [ "nix-command" "flakes" ];
      warn-dirty = false;
    };
    gc = {
      automatic = true;
      dates = "weekly";
      options = "--delete-older-than 30d";
    };
  };

  # Allow unfree packages
  nixpkgs.config.allowUnfree = true;

  nixpkgs.config.permittedInsecurePackages = [
    "openssl-1.1.1u"
    "python-2.7.18.6"
  ];

  imports = [
    # include NixOS-WSL modules
    <nixos-wsl/modules>
  ];

  wsl.enable = true;
  wsl.defaultUser = "ashebanow";
  wsl.wslConf.network.generateHosts = false;

  programs.zsh.enable = true;
  users.defaultUserShell = pkgs.zsh;

  networking.hostName = "liquid-nixos";

  # Auto Upgrade
  system.autoUpgrade = {
    enable = true;
    allowReboot = true;
    flake = "github:ashebanow/nix-config#default";

    dates = "03:00";
    randomizedDelaySec = "45min";

    flags = [
      "--commit-lock-file"
      "--update-input"
      "nixpkgs"
      "-L" # print build logs
    ];
  };

  # make sure we update our nix config at least once a day, and
  # before we run autoupgrade
  systemd.services."update-nix-config" = {
    script = ''
      set -eu
      cd /home/ashebanow/nix-config
      "${pkgs.git}/bin/git" pull
    '';
    serviceConfig = {
      OnCalendar="*-*-* 2:55:00";
      Persistent = true; 
    };
    wantedBy = [ "timers.target" ];
  };

  environment.systemPackages = with pkgs; [
    cifs-utils
    cockpit
    docker
    docker-compose
    firefox
    git
    just
    kitty
    linuxKernel.packages.linux_6_1.turbostat
    msrtool
    neovim
    nfs-utils
    samba
    virt-manager
    zsh
  ];

  services.openssh = {
    enable = true;
    # require public key authentication for better security
    settings.PasswordAuthentication = false;
    settings.KbdInteractiveAuthentication = false;
    settings.PermitRootLogin = "no";
  };

  # This value determines the NixOS release from which the default
  # settings for stateful data, like file locations and database versions
  # on your system were taken. It's perfectly fine and recommended to leave
  # this value at the release version of the first install of this system.
  # Before changing this value read the documentation for this option
  # (e.g. man configuration.nix or on https://nixos.org/nixos/options.html).
  system.stateVersion = "23.11"; # Did you read the comment?
}
