# CLI tools module — modern command-line utilities via Home Manager.
_: {
  my.modules.home-manager.cli-tools = {
    lib,
    pkgs,
    config,
    ...
  }: {
    config = lib.mkIf config.my.cliTools {
      home.packages = with pkgs; [
        bat
        bottom
        # GNU coreutils with all features enabled — provides `timeout`
        # (and full-featured ls/cp/etc.) on the podman user's PATH.
        coreutils-full
        curl
        dig
        direnv
        eza
        fastfetch
        fd
        fzf
        gh
        just
        neovim
        nix-direnv
        ripgrep
        wget
        zoxide
      ];
    };
  };
}
