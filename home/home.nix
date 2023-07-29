{ config, pkgs, ... }:

{
  nixpkgs.config.allowUnfree = true;

  imports = [
    "${fetchTarball "https://github.com/msteen/nixos-vscode-server/tarball/master"}/modules/vscode-server/home.nix"
    ./git.nix
    # ./neovim.nix
  ];

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
    pkgs.git
    pkgs.gnupg
    pkgs.htop
    pkgs.less
    pkgs.neofetch
    # pkgs.neovim
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
    ".config/ackrc".source = ../dotfiles/ackrc;
    ".config/starship.toml".source = ../dotfiles/starship.toml;
    ".config/tmux/tmux.conf".source = ../dotfiles/tmux.conf;
    ".vimrc".source = ../dotfiles/vimrc;

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
    EDITOR = "nvim";
    ACKRC = "~/.config/ackrc";
  };

  home.shellAliases = {
    cat="bat --paging=never";
    cd="z";
    cdi="zi";
    cls="clear";
    code="code-insiders";
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
    # Let Home Manager install and manage itself.
    home-manager.enable = true;

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

    starship = {
      enable = true;
      enableZshIntegration = true;
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
    
    zoxide.enable = true;
    zoxide.enableZshIntegration = true;

    zsh.enable = true;
  };

  services = {
    # TODO: this should really only be done on non-interactive hosts
    # (WSL, servers, etc).
    vscode-server.enable = true;
  };
}
