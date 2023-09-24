{ pkgs, ... }: {

  # Home Manager is pretty good at managing dotfiles. The primary way to manage
  # plain files is through 'home.file'.
  home.file = {
    ".config/starship.toml".source = ../../dotfiles/starship.toml;
    ".config/tmux/tmux.conf".source = ../../dotfiles/tmux.conf;
    ".config/neofetch/config".source = ../../dotfiles/neofetch-config;
    ".config/nix/nix.conf".source = ../../dotfiles/nix.conf;
    ".vimrc".source = ../../dotfiles/vimrc;
  };

  home.sessionVariables = {
    EDITOR = "vim";
    ACKRC = "~/.config/ackrc";
  };

  home.packages = with pkgs; [
    # sops
    # sops-nix
    age
    bat
    curl
    delta
    dig
    direnv
    exa
    gh
    git
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
    vim
    wget
    wishlist
    zoxide
    zsh
  ];

  fonts = {
    fontDir.enable = true;
    fontconfig = {
      enable = true;
      defaultFonts = {
        monospace = [
          "SauceCodePro Nerd Font"
        ];
      };
    };
    fonts = with pkgs; [
      (nerdfonts.override { fonts = [ "JetBrainsMono", "RobotoMono", "SourceCodePro" ]; })
      corefonts # Microsoft free fonts
      noto-fonts
    ];
  };

  programs = {
    bat = {
      enable = true;
      extraPackages = with pkgs.bat-extras; [ batdiff batman batgrep batwatch prettybat batpipe ];
      config = {
        pager = "less -FR";
        theme = "Solarized (dark)";
      };
    };

    # direnv configuration.
    direnv = {
      enable = true;
      enableZshIntegration = true;
      nix-direnv = {
        enable = true;
      };
    };

    exa = {
      enable = true;
      icons = true;
    };

    zoxide = {
      enable = true;
      enableZshIntegration = true;
    };
  };
}
