{ pkgs, ... }:

{
  nix = {
    # package = pkgs.nixFlakes;
    settings = {
      auto-optimise-store = true;
      experimental-features = [ "nix-command" "flakes" ];
      warn-dirty = false;
    };
    gc = {
      automatic = true;
      interval = { Weekday = 0; Hour = 2; Minute = 0; };
      options = "--delete-older-than 30d";
    };
  };

  services.nix-daemon.enable = true;

  users.users.ashebanow = {
    description = "Andrew Shebanow";
    home = "/Users/ashebanow";
    shell = pkgs.zsh;
    openssh.authorizedKeys.keys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIJhsuxHH4J5rPM5XNosTiTdHOX+NnZzHmePfEFTyaAs1 ashebanow@gmail.com"
    ];
  };

  # Allow unfree packages
  nixpkgs.config.allowUnfree = true;

  # set up zsh as default shell
  programs.zsh.enable = true;

  # List packages installed in system profile. To search, run:
  # $ nix search wget. We generally want to keep these system-specific
  # configurations as small as possible and use home manager or shell.nix
  # to install whats needed locally. Because nix uses symbolic links to point
  # to things, no disk space is wasted.
  environment.systemPackages = with pkgs; [
    git
    vim
    wget
    zsh
    # sops
    # sops-nix
  ];

  fonts.fontDir.enable = true;

  homebrew = {
    enable = true;
    onActivation = {
      autoUpdate = true;
      upgrade = true;
    };
    # Note that the mac apps which auto-update themselves are commented out
    # here. You'll need to uncomment them to get them installed initially on
    # a new mac.
    casks = [
      # "1password-cli"
      "ableton-live-suite"
      "android-studio"
      "app-cleaner"
      # "arc"
      "betterdisplay"
      "devtoys"
      "discord"
      "disk-diet"
      "docker"
      # "google-drive"
      # "intellij-idea"
      # "karabiner-elements"
      # "microsoft-auto-update"
      # "microsoft-office"
      # "monitorcontrol"
      # "native-access"
      "parsec"
      "postico"
      "postman"
      "raycast"
      # "retrobatch"
      "sf-symbols"
      # "slack"
      # "soundsource"
      "steam"
      "temurin"
      # "tg-pro"
      # "visual-studio-code"
      # "warp"
    ];
  };

  system.defaults = {
    dock = {
      autohide = true;
      show-recents = true;
      mru-spaces = false;
      showhidden = true;
    };
    finder = {
      AppleShowAllExtensions = true;
      AppleShowAllFiles = true;
      QuitMenuItem = true;
    };
    loginwindow = {
      GuestEnabled = false;
      # autoLoginUser = "Andrew Shebanow";
    };
  };

  # Used for backwards compatibility, please read the changelog before changing.
  # $ darwin-rebuild changelog
  system.stateVersion = 4;
}
