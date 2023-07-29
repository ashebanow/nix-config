
{ pkgs, ... }:

0{
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
      enableSyntaxHighlighting = true;
      oh-my-zsh = {
        enable = true;
        plugins = [
          "git"
          "sudo"
        ];
      };

      initExtra = ''
        source ${pkgs.zsh-vi-mode}/share/zsh-vi-mode/zsh-vi-mode.plugin.zsh
        if [[ "$(uname)" != "Darwin" ]]; then
          # hacky pyenv
          export PYENV_ROOT="$HOME/.pyenv"
          command -v pyenv >/dev/null || export PATH="$PYENV_ROOT/bin:$PATH"
          eval "$(pyenv init -)"
          eval "$(pyenv virtualenv-init -)"
          export PATH="/home/g/.local/bin:$PATH"
        fi
        nu
      '';
    };

    nushell = {
      enable = true;
      shellAliases = aliases;
      extraConfig = ''
<<<<<<< Updated upstream
          let-env config = {
            edit_mode: vi
            float_precision: 4
            show_banner: false
          }
        let-env PROMPT_INDICATOR_VI_INSERT = ""
        let-env PROMPT_INDICATOR_VI_NORMAL = ": "
        let-env PROMPT_MULTILINE_INDICATOR = "::: "
=======
        let-env config = {
          edit_mode: vi
          float_precision: 4
          show_banner: false
        }
        let-env PROMPT_INDICATOR_VI_INSERT = ""
        let-env PROMPT_INDICATOR_VI_NORMAL = ": "
        let-env PROMPT_MULTILINE_INDICATOR = "::: "

        source ~/nix/scripts/nu/quan_util.nu
>>>>>>> Stashed changes
      '';
    };

    starship = {
      enable = true;
      settings = {
        add_newline = true;
        container = {
          disabled = true;
        };
      };
    };
  };
}
