{pkgs, ...}: {
  # Home Manager is pretty good at managing dotfiles. The primary way to manage
  # plain files is through 'home.file'.
  home.file = {
    ".vimrc".source = ../../dotfiles/vimrc;

    ".config/alacritty" = {
      source = ../../dotfiles/alacritty;
      recursive = true;
    };
    # we copy the top level files/directors separately instead of just
    # copying the whole nvim tree, because we don't want to overwrite
    # lazyvim.lock, and it needs to stay writable.
    #
    # FIXME: nix is complaining about init.lua being used for multiple
    # home.file targets, but this is the only reference to init.lua in
    # my config.
    # ".config/nvim/init.lua".source = ../../dotfiles/nvim/init.lua;
    # ".config/nvim/lazyvim.json".source = ../../dotfiles/nvim/lazyvim.json;
    # ".config/nvim/lua".source = ../../dotfiles/nvim/lua;
    # ".config/nvim/lua".recursive = true;
    ".config/nvim" = {
      source = ../../dotfiles/nvim;
      recursive = true;
    };
    ".config/glances/glances.conf".source = ../../dotfiles/glances.conf;
    ".config/neofetch/config".source = ../../dotfiles/neofetch-config;
    ".config/skhd/skhdrc".source = ../../dotfiles/skhdrc;
    ".config/starship.toml".source = ../../dotfiles/starship.toml;
    ".config/tmux/tmux.conf".source = ../../dotfiles/tmux.conf;
    ".config/wezterm/wezterm.lua".source = ../../dotfiles/wezterm.lua;
    ".config/yabai/yabairc".source = ../../dotfiles/yabairc;
    ".config/zellij".source = ../../dotfiles/zellij-config.kdl;

    ".local/bin/copy-ssh-keys".source = ../../scripts/copy-ssh-keys;
    ".local/bin/find-dirty-gits".source = ../../scripts/find-dirty-gits;
    ".local/bin/list-cloudflare-ips".source = ../../scripts/list-cloudflare-ips;
    ".local/bin/make-dev-shell".source = ../../scripts/make-dev-shell;
    ".local/bin/test-starship".source = ../../scripts/test-starship;

    ".local/share/backgrounds" = {
      source = ../../dotfiles/backgrounds;
      recursive = true;
    };

    ".ssh/config".source = ../../dotfiles/ssh/config;
    ".ssh/github_ed25519.pub".source = ../../dotfiles/ssh/github_ed25519.pub;
    ".ssh/id_ed25519.pub".source = ../../dotfiles/ssh/id_ed25519.pub;
    ".ssh/cattivi_unifi.pub".source = ../../dotfiles/ssh/cattivi_unifi.pub;
  };

  home.sessionVariables = {
    EDITOR = "vim";
  };

  fonts.fontconfig.enable = true;

  home.packages = with pkgs; [
    alejandra
    atuin
    bandwhich
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
    fastfetch
    firefox
    foreman
    gh
    git
    glances
    glow
    gnupg
    gum
    hyperfine
    jq
    just
    kitty
    lego
    less
    magic-wormhole-rs
    (nerdfonts.override {fonts = ["SourceCodePro" "Hack"];})
    nil # nix LSP
    nix-direnv
    nixpkgs-fmt
    overmind
    ripgrep
    speedtest-cli
    starship
    tldr
    tmux
    unzip
    vale
    vim
    wezterm
    wget
    wishlist
    yarn
    zellij
    zoxide
    zsh
  ];

  programs = {
    bat = {
      enable = true;
      extraPackages = with pkgs.bat-extras; [batdiff batman batgrep batwatch prettybat batpipe];
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
