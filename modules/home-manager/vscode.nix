{ pkgs, ... }:
{
  home.packages = with pkgs; [
    nixd
    vscode
  ];

  # eventually we may want to move some config here, but for now
  # we rely on VSCode's own settings sync support.
  # programs.vscode = {
  #   enable = true;
  # };
}
