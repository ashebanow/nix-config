{ pkgs, ... }:

{
  home = {
    sessionVariables = {
      NIXPKGS_ALLOW_UNFREE = 1;
      # here so 1password doesn't ping:
      OP_PLUGIN_ALIASES_SOURCED = 1;
      DONT_PROMPT_WSL_INSTALL = 1;
    };

    sessionPath = [
      "$HOME/bin"
      "$HOME/.local/bin"
    ];

    shellAliases = {
      gh = "op plugin run -- gh";
      brew = "op plugin run -- brew";
      cachix = "op plugin run -- cachix";
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
      nix-autoupdate-log = "systemctl status nixos-upgrade.service";
      nix-autoupdate-status = "systemctl status nixos-upgrade.timer";
      nix-search = "nix search nixpkgs";
      nsh = "nix-shell -p";
      vi = "nvim";
      vim = "nvim";
      nano = "nvim";
      wezssh = "wezterm ssh";
    };
  };

  programs = {
    zsh = {
      enable = true;
      autocd = true;
      dotDir = ".config/zsh";
      enableCompletion = true;
      enableAutosuggestions = true;
      initExtra = ''
        bindkey '^ ' autosuggest-accept
        eval "$(atuin init zsh)"
        '';
      syntaxHighlighting = {
        enable = true;
      };
    };

    nushell = {
      enable = true;
      # The config.nu can be anywhere you want if you like to edit your Nushell with Nu
      configFile.source = ../dotfiles/config.nu;
      shellAliases = {
        vi = "nvim";
        vim = "nvim";
        nano = "nvim";
      };
    };
    carapace.enable = true;
    carapace.enableNushellIntegration = true;

    starship = {
      enable = true;
      enableZshIntegration = true;
    };
  };
}
