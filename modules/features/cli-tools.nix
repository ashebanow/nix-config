# CLI tools module — modern command-line utilities via Home Manager.
# Note: direnv + nix-direnv live in cli-build-essentials.nix;
# gh lives in cli-vcs-tools.nix.
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
        eza
        fastfetch
        fd
        fzf
        just
        neovim
        ripgrep
        wget
        zoxide
      ];
    };
  };
}
