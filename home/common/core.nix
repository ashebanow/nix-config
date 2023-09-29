{ pkgs, ... }: {

  # Home Manager is pretty good at managing dotfiles. The primary way to manage
  # plain files is through 'home.file'.
  home.file = {
    ".config/starship.toml".source = ../../dotfiles/starship.toml;
    ".config/tmux/tmux.conf".source = ../../dotfiles/tmux.conf;
    ".config/neofetch/config".source = ../../dotfiles/neofetch-config;
    # ".config/nix/".source = ../../dotfiles/nix.conf;
    ".vimrc".source = ../../dotfiles/vimrc;
    ".ssh/config".source = ../../dotfiles/ssh/config;
    ".ssh/id_ed25519.pub".source = ../../dotfiles/ssh/id_ed25519.pub;
    ".ssh/authorized_keys".source = ../../dotfiles/ssh/authorized_keys;

    # known_hosts files don't work well when read-only.
    # why can't ssh do config files the linux standard way? sigh...
    # ".ssh/known_hosts".source = ../../dotfiles/ssh/known_hosts;
  };

  home.sessionVariables = {
    EDITOR = "vim";
  };

  fonts.fontconfig.enable = true;

  home.packages = with pkgs; [
    # sops
    # sops-nix
    age
    bat
    cachix
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
    (nerdfonts.override { fonts = [ "JetBrainsMono" "RobotoMono" "SourceCodePro" ]; })
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
