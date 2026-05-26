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
        pkgs.bat
        pkgs.bottom
        pkgs.curl
        pkgs.eza
        pkgs.fastfetch
        pkgs.fd
        pkgs.fzf
        pkgs.git-delta
        pkgs.iputils
        pkgs.just
        pkgs.neovim
        pkgs.ripgrep
        pkgs.wget
        pkgs.zoxide
      ];
    };
  };
}
