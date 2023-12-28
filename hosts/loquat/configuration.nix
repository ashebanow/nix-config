# Edit this configuration file to define what should be installed on
# your system.  Help is available in the configuration.nix(5) man page
# and in the NixOS manual (accessible by running ‘nixos-help’).

{ config, pkgs, ... }:

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

  imports =
    [ # Include the results of the hardware scan.
      ./hardware-configuration.nix
    ];

  # Bootloader
  boot = {
    loader = {
      systemd-boot.enable = true;
      efi.canTouchEfiVariables = true;
    };

    # Warp terminal app comes as an appimage, so we need to register
    # the binary format to run using the appimage-run wrapper
    binfmt.registrations.appimage = {
      wrapInterpreterInShell = false;
      interpreter = "${pkgs.appimage-run}/bin/appimage-run";
      recognitionType = "magic";
      offset = 0;
      mask = ''\xff\xff\xff\xff\x00\x00\x00\x00\xff\xff\xff'';
      magicOrExtension = ''\x7fELF....AI\x02'';
    };
  };

  networking = {
    networkmanager.enable = true;
    # wireless.enable = true;  # Enables wireless support via wpa_supplicant.
    hostName = "loquat"; # Define your hostname.

    extraHosts = ''
      10.40.0.1   gateway gateway.lan
      10.40.0.13  storage storage.lan
      10.40.0.11  virt1 virt1.lan
      10.40.0.14  virt2 virt2.lan
      10.40.0.118 loquat loquat.lan
    '';

    firewall = {
      enable = true;
      allowedTCPPorts = [ 
        22              # ssh
        80 443          # HTTP/HTTPS
        2049            # nfs
      ];
    };
  };

  # Enable network manager applet
  programs.nm-applet.enable = true;

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

  # Mount SMB shares from storage machine. All of these are set to automount
  # on first use, and unmount after 10 minutes
  #
  # NOTE THAT YOU MUST CREATE/COPY the '/etc/nixos/smb-secrets' file to the
  # machine, with USERNAME, DOMAIN and PASSWORD defined on separate lines.
  # FIXME: replace with vault secrets
  # services.rpcbind.enable = true;
  # services.nfs.server.enable = true;
  # services.gvfs.enable = true;
  # boot.initrd = {
  #   supportedFilesystems = [ "nfs" ];
  #   kernelModules = [ "nfs" ];
  # };
  # fileSystems = {
  #   "/mnt/users/appdata" = {
  #     device = "//storage/mnt/users/appdata";
  #     fsType = "cifs";
  #     options = [
  #       "x-systemd.automount"
  #       "noauto"
  #       "credentials=/etc/nixos/smb-secrets"
  #       "x-systemd.idle-timeout=60"
  #       "x-systemd.device-timeout=5s"
  #       "x-systemd.mount-timeout=5s"
  #     ];
  #   };
    # "/mnt/users/backups" = {
    #   device = "//storage/mnt/users/backups";
    #   fsType = "cifs";
    #   options = [
    #     "x-systemd.automount"
    #     "noauto"
    #     "credentials=/etc/nixos/smb-secrets"
    #     "x-systemd.idle-timeout=60"
    #     "x-systemd.device-timeout=5s"
    #     "x-systemd.mount-timeout=5s"
    #   ];
    # };
    # "/mnt/users/isos" = {
    #   device = "//storage/mnt/users/isos";
    #   fsType = "cifs";
    #   options = [
    #     "x-systemd.automount"
    #     "noauto"
    #     "credentials=/etc/nixos/smb-secrets"
    #     "x-systemd.idle-timeout=60"
    #     "x-systemd.device-timeout=5s"
    #     "x-systemd.mount-timeout=5s"
    #   ];
    # };
    # "/mnt/users/media" = {
    #   device = "//storage/mnt/users/media";
    #   fsType = "cifs";
    #   options = [
    #     "x-systemd.automount"
    #     "noauto"
    #     "credentials=/etc/nixos/smb-secrets"
    #     "x-systemd.idle-timeout=60"
    #     "x-systemd.device-timeout=5s"
    #     "x-systemd.mount-timeout=5s"
    #   ];
    # };
  # };    

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

  # Configure the X11 windowing system.
  services.xserver = {
    enable = true;

    # Enable the MATE Desktop Environment.
    # displayManager.lightdm.enable = true;
    # desktopManager.mate.enable = true;

    # Enable the GNOME Desktop Environment.
    displayManager.gdm.enable = true;
    desktopManager.gnome.enable = true;

    modules = [ pkgs.xorg.xf86videofbdev ];
    videoDrivers = [ "hyperv_fb" ];

    # Configure keymap in X11
    layout = "us";
    xkbVariant = "";
  };

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
    extraGroups = [ "networkmanager" "wheel" "video" "storage" "libvirtd" ];
    openssh.authorizedKeys.keys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIJhsuxHH4J5rPM5XNosTiTdHOX+NnZzHmePfEFTyaAs1 ashebanow@gmail.com"
    ];
  };

  # List packages installed in system profile. To search, run:
  # $ nix search wget. We generally want to keep these system-specific
  # configurations as small as possible and use home manager or shell.nix
  # to install whats needed locally. Because nix uses symbolic links to point
  # to things, no disk space is wasted.
  environment.systemPackages = with pkgs; [
    cifs-utils
    docker
    docker-compose
    firefox
    kitty
    nfs-utils
    samba
    virt-manager
    vscode
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

  programs.chromium = {
    enable = true;
    extensions = [
      "cjpalhdlnbpafiamejdnhcphjbkeiagm" # ublock origin
      "aeblfdkhhhdcdjpifhhbdiojplfjncoa" # 1password
    ];
    extraOpts = {
      "BrowserSignin" = 1;
      "SyncDisabled" = false;
      "PasswordManagerEnabled" = false;
      "SpellcheckEnabled" = true;
      "SpellcheckLanguage" = [ "en-US" ];
    };
  };

  # Enable the 1Password CLI, this also enables a SGUID wrapper so the CLI can authorize against the GUI app
  programs._1password = {
    enable = true;
  };

  # Enable the 1Passsword GUI with myself as an authorized user for polkit
  programs._1password-gui = {
    enable = true;
    polkitPolicyOwners = [ "ashebanow" ];
  };

  # List services that you want to enable:
  services.qemuGuest.enable = true;
  virtualisation.libvirtd.enable = true;
  programs.dconf.enable = true;

  # This value determines the NixOS release from which the default
  # settings for stateful data, like file locations and database versions
  # on your system were taken. It‘s perfectly fine and recommended to leave
  # this value at the release version of the first install of this system.
  # Before changing this value read the documentation for this option
  # (e.g. man configuration.nix or on https://nixos.org/nixos/options.html).
  system.stateVersion = "23.11"; # Did you read the comment?
}
