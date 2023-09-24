{ pkgs, ... }: {

  # Home Manager is pretty good at managing dotfiles. The primary way to manage
  # plain files is through 'home.file'.
  home.file = {
    ".config/starship.toml".source = ../../dotfiles/starship.toml;
    ".config/tmux/tmux.conf".source = ../../dotfiles/tmux.conf;
    ".config/neofetch/config".source = ../../dotfiles/neofetch-config;
    ".config/nix/nix.conf".source = ../../dotfiles/nix.conf;
    ".vimrc".source = ../../dotfiles/vimrc;

    # # You can also set the file content immediately.
    # ".gradle/gradle.properties".text = ''
    #   org.gradle.console=verbose
    #   org.gradle.daemon.idletimeout=3600000
    # '';
  };

  # You can also manage environment variables but you will have to manually
  # source
  #
  #  ~/.nix-profile/etc/profile.d/hm-session-vars.sh
  #
  # or
  #
  #  /etc/profiles/per-user/ashebanow/etc/profile.d/hm-session-vars.sh
  #
  # if you don't want to manage your shell through Home Manager.
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
    nerdfonts
    nix-direnv
    nixpkgs-fmt
    openssh
    ripgrep
    starship
    unzip
    vim
    wget
    wishlist
    zoxide
    zsh

    # It is sometimes useful to fine-tune packages, for example, by applying
    # overrides. You can do that directly here, just don't forget the
    # parentheses. Maybe you want to install Nerd Fonts with a limited number of
    # fonts?
    # (nerdfonts.override { fonts = [ "SourceCodePro" ]; })

    # You can also create simple shell scripts directly inside your
    # configuration. For example, this adds a command 'my-hello' to your
    # environment:
    # (writeShellScriptBin "my-hello" ''
    #   echo "Hello, ${config.home.username}!"
    # '')
  ];

  fonts.fontconfig.enable = true;

  # sops = {
  #   # age.keyFile = "/home/ashebanow/.age-key.txt"; # must have no password!
  #   # It's also possible to use a ssh key, but only when it has no password:
  #   age.sshKeyPaths = [ "/home/ashebanow/.ssh/id_ed25519" ];
  #   defaultSopsFile = ./secrets.yaml;
  #   secrets.test = {
  #     # sopsFile = ./secrets.yml.enc; # optionally define per-secret files
  #
  #     # %r gets replaced with a runtime directory, use %% to specify a '%'
  #     # sign. Runtime dir is $XDG_RUNTIME_DIR on linux and $(getconf
  #     # DARWIN_USER_TEMP_DIR) on darwin.
  #     path = "%r/test.txt"; 
  #   };
  # };

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
