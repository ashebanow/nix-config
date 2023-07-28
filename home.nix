{ config, pkgs, ... }:

{
  # Home Manager needs a bit of information about you and the paths it should
  # manage.
  home.username = "ashebanow";
  home.homeDirectory = "/home/ashebanow";

  # This value determines the Home Manager release that your configuration is
  # compatible with. This helps avoid breakage when a new Home Manager release
  # introduces backwards incompatible changes.
  #
  # You should not change this value, even if you update Home Manager. If you do
  # want to update the value, then make sure to first check the Home Manager
  # release notes.
  home.stateVersion = "23.05"; # Please read the comment before changing.

  # The home.packages option allows you to install Nix packages into your
  # environment.
  home.packages = [
    pkgs.ack
    pkgs.bat
    pkgs.direnv
    pkgs.exa
    pkgs.gh
    pkgs.htop
    pkgs.less
    pkgs.neofetch
    pkgs.ripgrep
    pkgs.starship
    pkgs.zoxide
    pkgs.zsh

    # # It is sometimes useful to fine-tune packages, for example, by applying
    # # overrides. You can do that directly here, just don't forget the
    # # parentheses. Maybe you want to install Nerd Fonts with a limited number of
    # # fonts?
    (pkgs.nerdfonts.override { fonts = [ "SourceCodePro" ]; })

    # # You can also create simple shell scripts directly inside your
    # # configuration. For example, this adds a command 'my-hello' to your
    # # environment:
    # (pkgs.writeShellScriptBin "my-hello" ''
    #   echo "Hello, ${config.home.username}!"
    # '')
  ];

  # Home Manager is pretty good at managing dotfiles. The primary way to manage
  # plain files is through 'home.file'.
  home.file = {
    ".config/ackrc".source = dotfiles/ackrc;
    ".config/git/config.local".source = dotfiles/git/config.local;
    ".config/starship.toml".source = dotfiles/starship.toml;
    ".config/tmux/tmux.conf".source = dotfiles/tmux.conf;
    ".vimrc".source = dotfiles/vimrc;

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
    SCREENRC = "~/.config/screenrc";
  };

  home.shellAliases = {
    cat="bat --paging=never";
    cd="z";
    cdi="zi";
    cls="clear";
    diff="delta";
    diskspace="df -hl";
    gst = "git status -sb";
    gl = "git pull --prune";
    gp = "git push origin HEAD";
    gc = "git commit";
    gca = "git commit -a";
    gco = "git checkout";
    gcb = "git copy-branch-name";
    gb = "git branch";
    gac = "git add -A && git commit -m";
    grep="rg";
    less="bat";
    l="exa -FG";
    la="exa -aFG --icons";
    ll="exa -alF --icons";
    ls="exa -FG --icons";
    more="bat";
  };

  programs = {
    bat = {
      enable = true;
      config = {
        pager = "less -FR";
        theme = "Solarized (dark)";
      };
    };

    # direnv configuration.
    direnv = {
      enable = true;
      enableZshIntegration = true;
      nix-direnv.enable = true;
    };

    exa = {
      enable = true;
      icons = true;
    };

    # git configuration
    git = {
      enable = true;
      # lots more to come...
      userName = "Andrew Shebanow";
      userEmail = "ashebanow@gmail.com";

      aliases = {
        undo = "reset HEAD~1 --mixed";
        amend = "commit -a --amend";
      };

      attributes = [
        "*_spec.rb diff=rspec"
        "*.c     diff=cpp"
        "*.c++   diff=cpp"
        "*.cc    diff=cpp"
        "*.cpp   diff=cpp"
        "*.cs    diff=csharp"
        "*.css   diff=css"
        "*.el    diff=lisp"
        "*.erb   diff=html"
        "*.ex    diff=elixir"
        "*.exs   diff=elixir"
        "*.go    diff=golang"
        "*.h     diff=cpp"
        "*.h++   diff=cpp"
        "*.hh    diff=cpp"
        "*.hpp   diff=cpp"
        "*.html  diff=html"
        "*.lisp  diff=lisp"
        "*.m     diff=objc"
        "*.md    diff=markdown"
        "*.mdown diff=markdown"
        "*.mm    diff=objc"
        "*.php   diff=php"
        "*.pl    diff=perl"
        "*.py    diff=python"
        "*.rake  diff=ruby"
        "*.rb    diff=ruby"
        "*.rs    diff=rust"
        "*.xhtml diff=html"
        "*.xhtml diff=html"
      ];

      extraConfig = {
        color = {
          ui = "auto";
        };
        # diff = {
        #   tool = "vimdiff";
        #   mnemonicprefix = true;
        # };
        # merge = {
        #   tool = "splice";
        # };
        push = {
          default = "simple";
        };
        pull = {
          rebase = true;
        };
        branch = {
          autosetupmerge = true;
        };
        rerere = {
          enabled = true;
        };
        include = {
          path = "~/config/gitconfig.local";
        };
      };

      ignores = [
        # General
        "*~"
        "*.swp"
        "scratchpad"

        # Compiled source #
        ###################
        "*.com"
        "*.class"
        "*.dll"
        "*.exe"
        "*.o"
        "*.so"

        # Packages #
        ############
        # it's better to unpack these files and commit the raw source
        # git has its own built in compression methods
        "*.7z"
        "*.dmg"
        "*.gz"
        "*.iso"
        "*.jar"
        "*.rar"
        "*.tar"
        "*.zip"

        # Logs and databases #
        ######################
        "*.log"
        "*.sql"
        "*.sqlite"

        # OS generated files #
        ######################
        ".DS_Store"
        ".DS_Store?"
        ".AppleDouble"
        ".LSOverride"
        "._*"
        ".Spotlight-V100"
        ".Trashes"
        "ehthumbs.db"
        "Thumbs.db"
        ".DocumentRevisions-V100"
        ".fseventsd"
        ".Spotlight-V100"
        ".TemporaryItems"
        ".Trashes"
        ".VolumeIcon.icns"
        ".com.apple.timemachine.donotpresent"

        # Directories potentially created on remote AFP share
        ".AppleDB"
        ".AppleDesktop"
        "Network Trash Folder"
        "Temporary Items"
        ".apdisk"

        # IDE files #
        #############
        "nbproject"
        ".~lock.*"
        ".buildpath"
        ".idea"
        ".project"
        ".settings"
        "composer.lock"
      ];

      # Put your encryption keys and other secret stuff in this file
      includes = [ { path = "~/.config/git/config.local"; } ];
    };

    starship = {
      enable = true;
      enableZshIntegration = true;
    };

    # vscode = {
    #   enable = true;
    # };
    
    zoxide.enable = true;
    zoxide.enableZshIntegration = true;

    zsh.enable = true;
  };

  # Let Home Manager install and manage itself.
  programs.home-manager.enable = true;
}
