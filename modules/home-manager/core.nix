{ pkgs, ... }: {

  # Home Manager is pretty good at managing dotfiles. The primary way to manage
  # plain files is through 'home.file'.
  home.file = {
    ".vimrc".source = ../../dotfiles/vimrc;

    ".config/glances/glances.conf".source = ../../dotfiles/glances.conf;
    ".config/neofetch/config".source = ../../dotfiles/neofetch-config;
    ".config/starship.toml".source = ../../dotfiles/starship.toml;
    ".config/tmux/tmux.conf".source = ../../dotfiles/tmux.conf;
    ".config/wezterm/wezterm.lua".source = ../../dotfiles/wezterm.lua;
    ".config/zellij".source = ../../dotfiles/zellij-config.kdl;

    ".local/bin/copy-ssh-keys".source = ../../scripts/copy-ssh-keys;
    ".local/bin/find-dirty-gits".source = ../../scripts/find-dirty-gits;
    ".local/bin/list-cloudflare-ips".source = ../../scripts/list-cloudflare-ips;
    ".local/bin/make-dev-shell".source = ../../scripts/make-dev-shell;
    ".local/bin/test-starship".source = ../../scripts/test-starship;

    ".local/share/backgrounds/nixos-wp-1.png".source = ../../dotfiles/backgrounds/nixos-wp-1.png;
    ".local/share/backgrounds/nixos-wp-2.png".source = ../../dotfiles/backgrounds/nixos-wp-2.png;
    ".local/share/backgrounds/nixos-wp-3.png".source = ../../dotfiles/backgrounds/nixos-wp-3.png;
    ".local/share/backgrounds/nixos-wp-4.png".source = ../../dotfiles/backgrounds/nixos-wp-4.png;
    ".local/share/backgrounds/nixos-wp-5.png".source = ../../dotfiles/backgrounds/nixos-wp-5.png;
    ".local/share/backgrounds/nixos-wp-6.png".source = ../../dotfiles/backgrounds/nixos-wp-6.png;

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
    _1password
    _1password-gui
    # sops
    # sops-nix
    age
    atuin
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
    gnupg
    gum
    hyperfine
    jq
    just
    kitty
    lego
    less
    magic-wormhole-rs
    neofetch
    (nerdfonts.override { fonts = [ "SourceCodePro" "Hack" ]; })
    nil         # nix LSP
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
