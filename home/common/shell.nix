
{ pkgs, ... }:

{
  home = {
    sessionVariables = {
      NIXPKGS_ALLOW_UNFREE = 1;
    };

    sessionPath = [ 
        "$HOME/bin"
        "$HOME/.local/bin"
    ];

    shellAliases = {
      ack = "rg";
      cat = "bat --paging=never";
      cls = "clear";
      # there is no insiders package
      # code = mkIf (pkgs.installed "vscode-insiders") "code";
      code = "code-insiders";
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
      # l = "exa -FG";
      la = "exa -aFG --color=auto --icons";
      ll = "exa -alF --color=auto --icons";
      llt = "exa -alF --sort modified -r --color=auto --icons";
      ls = "exa -FG --color=auto --icons";
      ltree = "exa -lFDT --sort modified --color=auto --icons";
      more = "bat";
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
      # syntaxHighlighting = {
      #   enable = true;
      # };
      oh-my-zsh = {
        enable = true;
        plugins = [
          "docker"
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
