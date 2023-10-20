# Edit this configuration file to define what should be installed on
# your system.  Help is available in the configuration.nix(5) man page
# and in the NixOS manual (accessible by running ‘nixos-help’).

{ config, pkgs, ... }:

{
  nix.settings.experimental-features = [ "nix-command" "flakes" ];

  imports =
    [ # Include the results of the hardware scan.
      ./virt2-hardware-configuration.nix
    ];

  # Bootloader.
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  networking = {
    networkmanager.enable = true;
    # wireless.enable = true;  # Enables wireless support via wpa_supplicant.
    hostName = "virt2"; # Define your hostname.
    firewall = {
      enable = true;
      # Open ports in the firewall.
      allowedTCPPorts = [ 22 2049 ];
      # allowedUDPPorts = [ ... ];
    };
  };

  services.openssh = {
    enable = true;
    # require public key authentication for better security
    # settings.PasswordAuthentication = false;
    # settings.KbdInteractiveAuthentication = false;
    # settings.PermitRootLogin = "yes";
  };

  virtualisation.docker = {
    enable = true;
    enableOnBoot = true;
    # storageDriver can be null or one of "aufs", "btrfs", "devicemapper",
    # "overlay", "overlay2", "zfs". Default is null, which is "autodetect"
    # storageDriver = "zfs";
  };
  users.extraGroups.docker.members = [ "ashebanow" ];

  # Mount nfs shares from storage machine. All of these are set to automount
  # on first use, and unmount after 10 minutes
  #
  # NOTE THAT YOU MUST CREATE/COPY the '/etc/nixos/smb-secrets' file to the
  # machine, with USERNAME, DOMAIN and PASSWORD defined on separate lines.
  # FIXME: replace with vault secrets
  services.rpcbind.enable = true;
  services.nfs.server.enable = true;
  boot.initrd = {
    supportedFilesystems = [ "nfs" ];
    kernelModules = [ "nfs" ];
  };
  fileSystems = {
    "/mnt/users/appdata" = {
      device = "storage:/mnt/users/appdata";
      fsType = "cifs";
      options = let
        # this line prevents hanging on network split
        automount_opts = "x-systemd.automount,noauto,x-systemd.idle-timeout=60,x-systemd.device-timeout=5s,x-systemd.mount-timeout=5s";

      in ["${automount_opts},credentials=/etc/nixos/smb-secrets"];

      # fsType = "nfs";
      # options = [ "x-systemd.automount" "noauto" ];
    };
    # "/mnt/users/backups" = {
    #   device = "storage.local:/mnt/users/backups";
    #   fsType = "nfs";
    #   options = [ "x-systemd.automount" "noauto" "x-systemd.idle-timeout=600" ];
    # };
    # "/mnt/users/isos" = {
    #   device = "storage.local:/mnt/users/isos";
    #   fsType = "nfs";
    #   options = [ "x-systemd.automount" "noauto" "x-systemd.idle-timeout=600" ];
    # };
    # "/mnt/users/media" = {
    #   device = "storage.local:/mnt/users/media";
    #   fsType = "nfs";
    #   options = [ "x-systemd.automount" "noauto" "x-systemd.idle-timeout=600" ];
    # };
  }

  # Set your time zone.
  time.timeZone = "America/Los_Angeles";

  # Select internationalisation properties.
  i18n.defaultLocale = "en_US.UTF-8";

  i18n.extraLocaleSettings = {
    LC_ADDRESS = "en_US.UTF-8";
    LC_IDENTIFICATION = "en_US.UTF-8";
    LC_MEASUREMENT = "en_US.UTF-8";
    LC_MONETARY = "en_US.UTF-8";
    LC_NAME = "en_US.UTF-8";
    LC_NUMERIC = "en_US.UTF-8";
    LC_PAPER = "en_US.UTF-8";
    LC_TELEPHONE = "en_US.UTF-8";
    LC_TIME = "en_US.UTF-8";
  };

  # Enable the X11 windowing system.
  services.xserver.enable = true;

  # Enable the GNOME Desktop Environment.
  services.xserver.displayManager.gdm.enable = true;
  services.xserver.desktopManager.gnome.enable = true;

  # make sure we turn off suspending power
  powerManagement.enable = false;
  services.xserver.displayManager.gdm.autoSuspend = false;
  security.polkit.extraConfig = ''
    polkit.addRule(function(action, subject) {
      if (action.id == "org.freedesktop.login1.suspend" ||
          action.id == "org.freedesktop.login1.suspend-multiple-sessions" ||
          action.id == "org.freedesktop.login1.hibernate" ||
          action.id == "org.freedesktop.login1.hibernate-multiple-sessions")
      {
        return polkit.Result.NO;
      }
    });
  '';
    # Disable the GNOME3/GDM auto-suspend feature that cannot be disabled in GUI!
  # If no user is logged in, the machine will power down after 20 minutes.
  systemd.targets.sleep.enable = false;
  systemd.targets.suspend.enable = false;
  systemd.targets.hibernate.enable = false;
  systemd.targets.hybrid-sleep.enable = false;

  # Configure keymap in X11
  services.xserver = {
    layout = "us";
    xkbVariant = "";
  };

  # Enable CUPS to print documents.
  services.printing.enable = true;

  # Enable sound with pipewire.
  sound.enable = true;
  hardware.pulseaudio.enable = false;
  security.rtkit.enable = true;
  services.pipewire = {
    enable = true;
    alsa.enable = true;
    alsa.support32Bit = true;
    pulse.enable = true;
    # If you want to use JACK applications, uncomment this
    #jack.enable = true;

    # use the example session manager (no others are packaged yet so this is enabled by default,
    # no need to redefine it in your config for now)
    #media-session.enable = true;
  };

  # Enable touchpad support (enabled default in most desktopManager).
  # services.xserver.libinput.enable = true;

  # Define a user account. Don't forget to set a password with ‘passwd’.
  users.users.ashebanow = {
    shell = pkgs.zsh;
    isNormalUser = true;
    description = "Andrew Shebanow";
    extraGroups = [ "networkmanager" "wheel" "storage" ];
  };

  # Allow unfree packages
  nixpkgs.config.allowUnfree = true;

  # List packages installed in system profile. To search, run:
  # $ nix search wget
  environment.systemPackages = with pkgs; [
    docker-compose  
    git
    gnupg
    kitty
    nfs-utils
    ripgrep
    unzip
    vim
    wget
    zsh
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
  environment.shells = with pkgs; [ zsh ];

  fonts.fontDir.enable = true;

  # List services that you want to enable:

  # This value determines the NixOS release from which the default
  # settings for stateful data, like file locations and database versions
  # on your system were taken. It‘s perfectly fine and recommended to leave
  # this value at the release version of the first install of this system.
  # Before changing this value read the documentation for this option
  # (e.g. man configuration.nix or on https://nixos.org/nixos/options.html).
  system.stateVersion = "23.05"; # Did you read the comment?
}
