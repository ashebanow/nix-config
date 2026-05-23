# CLI tools module — modern command-line utilities via Home Manager.
# Self-contained Home Manager module following dendritic pattern principles.
{
  lib,
  pkgs,
  config,
  ...
}: {
  config = lib.mkIf config.my.cliTools {
    home.packages = with pkgs; [
      pkgs.eza
      pkgs.bat
      pkgs.git-delta
      pkgs.fd
      pkgs.ripgrep
      pkgs.fzf
      pkgs.zoxide
      pkgs.bottom
    ];
  };
}
