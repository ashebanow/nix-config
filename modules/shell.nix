
{ pkgs, ... }:

{
  home = {
    sessionVariables = {
      NIXPKGS_ALLOW_UNFREE = 1;
      # here so 1password doesn't ping:
      OP_PLUGIN_ALIASES_SOURCED = 1;
    };

    sessionPath = [ 
        "$HOME/bin"
        "$HOME/.local/bin"
    ];

    shellAliases = {
      gh="op plugin run -- gh";
      brew="op plugin run -- brew";
      cachix="op plugin run -- cachix";
      start1p = "daemonize -e ~/.1password/stderr.log -o ~/.1password/stdout.log ${pkgs._1password-gui}/bin/1password --silent";

      ack = "rg";
      cat = "bat --paging=never --style=plain";
      cls = "clear";
      cpuwatts = "sudo turbostat --Summary --quiet --show PkgWatt --interval 1";
      diff = "delta";
      diskspace = "df -hl";
      flake-checker = "nix run github:DeterminateSystems/flake-checker";
      gst = "git status -sb";
      gl = "git pull --prune";
      gp = "git push origin HEAD";
      gc = "git commit";
      gca = "git commit -a";
      gco = "git checkout";
      gcb = "git copy-branch-name";
      gb = "git branch";
      gac = "git add -A && git commit -m";
      grep = "rg";
      less = "bat";
      la = "eza -a";
      ll = "eza -al";
      llt = "eza -al --sort modified -r";
      ls = "eza";
      ltree = "eza -lDT --sort modified";
      more = "bat";
      nps = "nix search nixpkgs";
      nsh = "nix-shell -p";
      wezssh = "wezterm ssh";
    };
  };

  programs = {
    zsh = {
      enable = true;
      autocd = true;
      enableCompletion = true;
      enableAutosuggestions = true;
      syntaxHighlighting = {
        enable = true;
      };
      # oh-my-zsh = {
      #   enable = true;
      #   plugins = [
      #     "docker"
      #     "git"
      #     "sudo"
      #   ];
      # };
    };

    starship = {
      enable = true;
      enableZshIntegration = true;
      # settings = {
      #   add_newline = true;
      #   container = {
      #     disabled = true;
      #   };
      # };
    };
  };
}
