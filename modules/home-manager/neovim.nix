# NeoVim for daily work and daily notes
{
  config,
  pkgs,
  ...
}: {
  home.packages = with pkgs; [
    gnused
    neovim
  ];
}
