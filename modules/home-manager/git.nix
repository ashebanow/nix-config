{pkgs, ...}: {
  # we use the local path here because the installed path fails on
  # first run.
  home.file.".ssh/allowed_signers".text = "* ${builtins.readFile ../../dotfiles/ssh/github_ed25519.pub}";
  # "* ${builtins.readFile ~/.ssh/github_ed25519.pub}";

  programs = {
    gh = {
      enable = true;
      # extensions = [
      #   "github/gh-copilot"
      # ];
    };
    git = {
      enable = true;
      userName = "Andrew Shebanow";
      userEmail = "ashebanow@gmail.com";

      delta = {
        enable = true;
        catppuccin.enable = true;
      };

      # Sign all commits using ssh key via 1password
      signing = {
        key = "~/.ssh/github_ed25519.pub";
        signByDefault = true;
      };

      # this is the way to point to 1password correctly, not by setting git's
      # signing.gpgPath setting. See:
      # https://discourse.nixos.org/t/cant-commit-with-git-after-installing-1password/34021
      extraConfig = {
        gpg.ssh.program =
          if pkgs.stdenv.isDarwin
          then "/Applications/1Password.app/Contents/MacOS/op-ssh-sign"
          else "op-ssh-sign";
        # else "${pkgs._1password-gui}/bin/op-ssh-sign";
        # FIXME: need to handle wsl2 as well: /mnt/c/Users/A Shebanow/AppData/Local/1Password/app/8/op-ssh-sign-wsl
        gpg.ssh.allowedSignersFile = "~/.ssh/allowed_signers";
        gpg.format = "ssh";

        # core.editor = "${vscode}/bin/code --wait";

        # on WSL ONLY, we want to use native ssh for git
        # core.sshCommand = "ssh.exe";

        # this is here because on WSL we get intermiitent warnings about
        # safety during systemd updates. Ugh.
        safe.directory = "~/nix-config";

        init = {
          defaultBranch = "main";
        };
        color = {
          ui = "auto";
        };
        diff = {
          tool = "delta";
          mnemonicprefix = true;
        };
        merge = {
          tool = "delta";
          # conflictstyle = "diff3";
        };
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
      };

      aliases = {
        a = "add";
        co = "checkout";
        rb = "rebase --interactive origin/main";
        rbm = "rebase --interactive origin/master";
        rba = "rebase --abort";
        rbc = "rebase --continue";
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

        # Other development files #
        "nbproject"
        ".~lock.*"
        ".buildpath"
        ".idea"
        ".project"
        ".settings"
        "composer.lock"
      ];
    };
  };
}
