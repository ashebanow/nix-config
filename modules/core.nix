{ pkgs, ... }: {

  # Home Manager is pretty good at managing dotfiles. The primary way to manage
  # plain files is through 'home.file'.
  home.file = {
    ".local/bin/copy-ssh-keys".source = ../scripts/copy-ssh-keys;
    ".local/bin/find-dirty-gits".source = ../scripts/find-dirty-gits;
    ".local/bin/list-cloudflare-ips".source = ../scripts/list-cloudflare-ips;
    ".local/bin/make-dev-shell".source = ../scripts/make-dev-shell;
    ".config/glances/glances.conf".source = ../dotfiles/glances.conf;
    ".config/neofetch/config".source = ../dotfiles/neofetch-config;
    ".config/starship.toml".source = ../dotfiles/starship.toml;
    ".config/tmux/tmux.conf".source = ../dotfiles/tmux.conf;
    ".vimrc".source = ../dotfiles/vimrc;
    ".ssh/config".source = ../dotfiles/ssh/config;
    ".ssh/github_ed25519.pub".source = ../dotfiles/ssh/github_ed25519.pub;
    ".ssh/id_ed25519.pub".source = ../dotfiles/ssh/id_ed25519.pub;
  };

  home.sessionVariables = {
    EDITOR = "vim";
  };

  fonts.fontconfig.enable = true;

  home.packages = with pkgs; [
    _1password
    _1password-gui
    # sops
    # sops-nix
    age
    bat
    btop
    cachix
    curl
    daemonize
    delta
    dig
    direnv
    diskus
    eza
    foreman
    gh
    git
    glances
    glow
    google-chrome
    gnupg
    gum
    hyperfine
    jq
    just
    kitty
    lego
    less
    # lorri
    neofetch
    (nerdfonts.override { fonts = [ "SourceCodePro" ]; })
    nil # nix LSP
    nix-direnv
    nixpkgs-fmt
    overmind
    ripgrep
    starship
    tldr
    tmux
    unzip
    vim
    wget
    wishlist
    yarn
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

    eza = {
      enable = true;
      icons = true;
    };

    zoxide = {
      enable = true;
      enableZshIntegration = true;
    };
  };
}
