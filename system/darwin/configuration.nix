{ pkgs, ... }:

{
  nix = {
    package = pkgs.nixFlakes;
    settings = {
      auto-optimise-store = true;
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
    shell = pkgs.zsh;
  };

  # Allow unfree packages
  nixpkgs.config.allowUnfree = true;

  # set up zsh as default shell
  programs.zsh.enable = true;

    # List packages installed in system profile. To search, run:
  # $ nix search wget
  environment.systemPackages = with pkgs; [
    git
    vim
    wget
    zsh
    # these are here temporarily until we fix home manager
    # sops
    # sops-nix
    ack
    age
    bat
    cachix
    curl
    delta
    dig
    direnv
    exa
    gh
    glances
    glow
    gnupg
    gum
    htop
    hyperfine
    jq
    kitty
    lego
    less
    neofetch
    nix-direnv
    nixpkgs-fmt
    ripgrep
    starship
    unzip
    wishlist
    zoxide
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
      "1password-cli"
      "ableton-live-suite"
      "android-studio"
      "app-cleaner"
      # "arc"
      "discord"
      "disk-diet"
      "docker"
      # "firefox"
      # "google-chrome"
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
