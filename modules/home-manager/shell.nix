{pkgs, ...}: {
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

      opapp = "wrapped-1password";
      ack = "rg";
      cat = "bat --paging=never --style=plain";
      chrome = "wrapped-chrome";
      cls = "clear";
      code = "NIXOS_OZONE_WL=1 code";
      cpuwatts = "sudo turbostat --Summary --quiet --show PkgWatt --interval 1";
      df = "duf";
      diff = "delta";
      diskspace = "df -hl";
      flake-checker = "nix run github:DeterminateSystems/flake-checker";
      gst = "git status -sb";
      grep = "rg";
      hl = "wrapped-hyperland";
      less = "bat";
      la = "eza -a";
      ll = "eza -al";
      llt = "eza -al --sort modified -r";
      ls = "eza";
      ltree = "eza -lDT --sort modified";
      mkdir = "mkdir -pv";
      more = "bat";
      neofetch = "fastfetch";
      nix-autoupdate-log = "systemctl status nixos-upgrade.service";
      nix-autoupdate-status = "systemctl status nixos-upgrade.timer";
      nb = "nix build";
      nd = "nix develop";
      nf = "nix flake";
      nr = "nix run";
      ns = "nix search";
      nsh = "nix-shell -p";
      obsidian = "wrapped-obsidian";
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
      dotDir = ".config/zsh";
      initExtra = ''
        eval "$(atuin init zsh)"
        if [[ -f ~/.config/zsh/catppuccin_mocha-zsh-syntax-highlighting.zsh ]]; then
          source ~/.config/zsh/catppuccin_mocha-zsh-syntax-highlighting.zsh
        fi
        if [[ -f ~/.p10k.zsh ]]; then
          source ~/.p10k.zsh
        fi
        if [[ -f /opt/homebrew/bin/brew ]]; then
          eval "$(/opt/homebrew/bin/brew shellenv)"
        fi
      '';

      antidote = {
        enable = true;
        package = pkgs.antidote;
        plugins = [
          # ZSH utility plugins
          "zsh-users/zsh-autosuggestions"
          "zsh-users/zsh-syntax-highlighting"
          "zsh-users/zsh-completions"
          "zsh-users/zsh-history-substring-search"
          # ZSH prompt
          "romkatv/powerlevel10k"
          # Extra
          # "MichaelAquilina/zsh-you-should-use"
          "nix-community/nix-zsh-completions"
          "z-shell/zsh-eza"
        ];
        useFriendlyNames = true;
      };
    };

    # starship = {
    #   enable = true;
    #   enableZshIntegration = true;
    # };
  };
}
