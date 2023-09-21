{ pkgs, ... }:

{
  nix = {
    package = pkgs.nixFlakes;
    settings = {
      experimental-features = "nix-command flakes";
      auto-optimise-store = true;
      trusted-users = [ "root" "ashebanow" ];
      warn-dirty = false;
    };
    gc = {
      automatic = true;
    };
  };

  services.nix-daemon.enable = true;

  users.users.ashebanow = {
    description = "Andrew Shebanow";
    home = "/Users/ashebanow";
    openssh.authorizedKeys.keys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIJhsuxHH4J5rPM5XNosTiTdHOX+NnZzHmePfEFTyaAs1 ashebanow@gmail.com"
    ];
    shell = pkgs.zsh;
  };

  # Allow unfree packages
  nixpkgs.config.allowUnfree = true;

  # set up zsh as default shell
  programs.zsh.enable = true;

    # List packages installed in system profile. To search, run:
  # $ nix search wget
  environment.systemPackages = with pkgs; [
    age
    bat
    curl
    delta
    dig
    direnv
    exa
    git
    glances
    gnupg
    htop
    jq
    kitty
    less
    neofetch
    nixpkgs-fmt
    openssh
    ripgrep
    unzip
    vim
    wget
    zoxide
    zsh
  ];

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
      "1password-cli"
      "ableton-live-suite"
      "android-studio"
      "app-cleaner"
      # "arc"
      "discord"
      "disk-diet"
      # "docker"
      # "firefox"
      "font-droid-sans-mono-nerd-font"
      "font-jetbrains-mono-nerd-font"
      "font-profont-nerd-font"
      "font-roboto-mono-nerd-font"
      "font-sauce-code-pro-nerd-font"
      # "google-chrome"
      # "google-drive"
      # "intellij-idea"
      # "karabiner-elements"
      # "microsoft-auto-update"
      # "microsoft-office"
      "monitorcontrol"
      # "native-access"
      "parsec"
      "postico"
      "postman"
      "raycast"
      "sf-symbols"
      # "slack"
      # "soundsource"
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
