
{ pkgs, ... }:

{
  home = {
    shellAliases = {
      cat="bat --paging=never";
      cd="z";
      cdi="zi";
      cls="clear";
      code="code-insiders";
      codi = "code-insiders .";
      diff="delta";
      diskspace="df -hl";
      flake-checker="nix run github:DeterminateSystems/flake-checker";
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
      nps = "nix search nixpkgs";
      nsh = "nix-shell -p";
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
      oh-my-zsh = {
        enable = true;
        plugins = [
          "git"
          "sudo"
        ];
      };
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
