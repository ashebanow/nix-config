{ pkgs, ... }: {

  # Home Manager is pretty good at managing dotfiles. The primary way to manage
  # plain files is through 'home.file'.
  home.file = {
    ".config/ackrc".source = ../../dotfiles/ackrc;
    ".config/starship.toml".source = ../../dotfiles/starship.toml;
    ".config/tmux/tmux.conf".source = ../../dotfiles/tmux.conf;
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
    ack
    bat
    direnv
    exa
    gh
    git
    glow
    gnupg
    htop
    hyperfine
    jq
    less
    neofetch
    # neovim
    nixpkgs-fmt
    ripgrep
    starship
    unzip
    zoxide
    zsh

    # It is sometimes useful to fine-tune packages, for example, by applying
    # overrides. You can do that directly here, just don't forget the
    # parentheses. Maybe you want to install Nerd Fonts with a limited number of
    # fonts?
    (nerdfonts.override { fonts = [ "SourceCodePro" ]; })

    # You can also create simple shell scripts directly inside your
    # configuration. For example, this adds a command 'my-hello' to your
    # environment:
    # (writeShellScriptBin "my-hello" ''
    #   echo "Hello, ${config.home.username}!"
    # '')
  ];

  fonts.fontconfig.enable = true;

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

  # vscode should be enabled on interactive machines only
  #  vscode = {
  #    enable = true;
  #    enableExtensionUpdateCheck = false;
  #    enableUpdateCheck = false;
  #    mutableExtensionsDir = true;

  #    extensions = [
  #      pkgs.vscode-extensions.bbenoist.nix
  #    ];

  #    userSettings = {
  #     "files.autoSave" = "off";
  #     "[nix]"."editor.tabSize" = 2;
  #    };
  #  };
  
    zoxide = {
      enable = true;
      enableZshIntegration = true;
    };
  };
}
