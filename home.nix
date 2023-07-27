{ config, pkgs, ... }:

{
  # Home Manager needs a bit of information about you and the paths it should
  # manage.
  home.username = "ashebanow";
  home.homeDirectory = "/home/ashebanow";


  # install direnv hook
  # eval "$(direnv hook zsh)"

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
    # # Building this configuration will create a copy of 'dotfiles/screenrc' in
    # # the Nix store. Activating the configuration will then make '~/.screenrc' a
    # # symlink to the Nix store copy.
    # ".screenrc".source = dotfiles/screenrc;

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
    # EDITOR = "emacs";
  };

  home.shellAliases = {
    cat="bat --paging=never";
    cd="z";
    cdi="zi";
    cls="clear";
    diff="delta";
    diskspace="df -hl";
    grep="rg";
    less="bat";
    # l="exa -FG";
    # la="exa -aFG --icons";
    # ll="exa -alF --icons";
    # ls="exa -F";
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

  exa = {
    enable = true;
    enableAliases = true;
    icons = true;
  };

  # git configuration
  git.enable = true;

  # direnv configuration.
  direnv.enable = true;
  direnv.nix-direnv.enable = true;

  starship = {
    enable = true;
    enableZshIntegration = true;
  };
  
  zoxide.enable = true;
  zoxide.enableZshIntegration = true;

  zsh.enable = true;
};

  # Let Home Manager install and manage itself.
  programs.home-manager.enable = true;
}
