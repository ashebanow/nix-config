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
      # gh = "op plugin run -- gh";
      # brew = "op plugin run -- brew";
      # cachix = "op plugin run -- cachix";

      # start1p = "1password --ozone-platform=wayland";
      # start1p = "daemonize -e ~/.1password/stderr.log -o ~/.1password/stdout.log ${pkgs._1password-gui}/bin/1password --silent";

      ack = "rg";
      cat = "bat --paging=never --style=plain";
      cls = "clear";
      cpuwatts = "sudo turbostat --Summary --quiet --show PkgWatt --interval 1";
      diff = "delta";
      diskspace = "df -hl";
      flake-checker = "nix run github:DeterminateSystems/flake-checker";
      gst = "git status -sb";
      grep = "rg";
      less = "bat";
      la = "eza -a";
      ll = "eza -al";
      llt = "eza -al --sort modified -r";
      ls = "eza";
      ltree = "eza -lDT --sort modified";
      mkdir = "mkdir -pv";
      more = "bat";
      nix-autoupdate-log = "systemctl status nixos-upgrade.service";
      nix-autoupdate-status = "systemctl status nixos-upgrade.timer";
      nix-search = "nix search nixpkgs";
      nsh = "nix-shell -p";
      vi = "nvim";
      vim = "nvim";
      nano = "nvim";
      wezssh = "wezterm ssh";

      # vc = "code --disable-gpu --ozone-platform=wayland"; # gui code editor    };
      vc = "code";

      # # these work on Arch Linux only:
      # un = "yay -Rns"; # uninstall package
      # up = "yay -Syu"; # update system/package/aur
      # pl = "yay -Qs"; # list installed package
      # pa = "yay -Ss"; # list availabe package
      # pc = "yay -Sc"; # remove unused cache
      # po = "yay -Qtdq | yay -Rns -"; # remove unused packages, also try > yay -Qqd | yay -Rsu --print -
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
        if [[ -f /opt/homebrew/bin/brew ]]; then
          eval "$(/opt/homebrew/bin/brew shellenv)"
        fi
        '';
      syntaxHighlighting = {
        enable = true;
      };
    };

    nushell = {
      enable = true;
      # The config.nu can be anywhere you want if you like to edit your Nushell with Nu
      configFile.source = ../../dotfiles/config.nu;
      shellAliases = {
        vi = "nvim";
        vim = "nvim";
        nano = "nvim";
      };
    };

    carapace = {
      enable = true;
      enableFishIntegration = true;
      enableNushellIntegration = true;
      enableZshIntegration = true;
    };

    fish = {
      enable = true;
    };

    starship = {
      enable = true;
      enableZshIntegration = true;
      enableFishIntegration = true;
    };
  };
  
}
