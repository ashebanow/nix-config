# Everyday shell/productivity CLI tools — Home Manager package list.
_: {
  my.modules.home-manager.cli-productivity-tools = {
    lib,
    pkgs,
    config,
    ...
  }: {
    config = lib.mkIf config.my.cliProductivityTools {
      home.packages = with pkgs; [
        # atuin
        bat
        bc
        curl
        eza
        fd
        findutils
        fish
        fzf
        glow
        gum
        jq
        jsongrep
        mpv
        nano
        neovim
        presenterm
        pv
        rsync
        rtk
        starship
        tlrc
        tree
        tree-sitter
        ugrep
        units
        unzip
        vim
        wget
        yq
        zennotes-desktop
        zip
        zoxide
      ];
    };
  };
}
