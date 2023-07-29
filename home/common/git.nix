{ config, pkgs, ... }: {
  # home.file.".ssh/allowed_signers".text =
  #   "* ${builtins.readFile /home/ashebanow/.ssh/id_ed25519.pub}";

  programs = {
    git = {
      enable = true;
      userName = "Andrew Shebanow";
      userEmail = "ashebanow@gmail.com";

      aliases = {
        a = "add";
        amend = "commit -a --amend";
        ap = "add * --patch";
        br = "!git co $(git branch --list --sort=-authordate |fzf --height 15)";
        c = "commit -m";
        co = "checkout";

        cp = "cherry-pick";
        cpa = "cherry-pick --abort";
        cpc = "cherry-pick --continue";

        d = "diff";
        dfm = "diff origin/main";
        dfmast = "diff origin/master";
        de = "!git diff --name-only | uniq | xargs vim";
        da = "!git diff --name-only | uniq | xargs git add";
        dap = "!git diff --name-only | uniq | xargs git add --patch";

        ps = "push";
        psf = "push --force-with-lease";

        rb = "rebase --interactive origin/main";
        rbm = "rebase --interactive origin/master";
        rba = "rebase --abort";
        rbc = "rebase --continue";
        rbh = "rebase --interactive HEAD~9";

        rl = "reflog";
        s = "status";
        some = "!git fetch -a && git pull";

        st = "stash";
        stc = "stash clear";
        stp = "stash pop";

        undo = "reset HEAD~1 --mixed";

        w = "worktree";
        wa = "worktree add";
        wl = "worktree list";
        wp = "worktree prune";
        wr = "worktree remove";
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

      extraConfig = {
        color = {
          ui = "auto";
        };
        # diff = {
        #   tool = "vimdiff";
        #   mnemonicprefix = true;
        # };
        # merge = {
        #   tool = "splice";
        # };
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

        # Sign all commits using ssh key
        # commit.gpgsign = true;
        # gpg.format = "ssh";
        # gpg.ssh.allowedSignersFile = "~/.ssh/allowed_signers";
        # user.signingkey = "~/.ssh/id_ed25519.pub";
      };

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
        ".envrc"
      ];

      # signing = {
        # key = "";   # TODO: Use SECRETS MANAGEMENT
        # signByDefault = true;
      # };
    };
  };
}