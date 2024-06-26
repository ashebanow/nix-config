{
  nixpkgs,
  catppuccin,
  config,
  pkgs,
  ...
}: {
  imports = [
    ../../modules/home-manager/core.nix
    ../../modules/home-manager/git.nix
    # ../../modules/home-manager/hashi.nix
    ../../modules/home-manager/neovim.nix
    ../../modules/home-manager/obsidian.nix
    ../../modules/home-manager/shell.nix
    ../../modules/home-manager/vscode.nix
  ];

  # Home Manager needs a bit of information about you and the paths it should
  # manage.
  home.username = "ashebanow";

  home.homeDirectory = "/Users/ashebanow";

  manual = {
    html.enable = false;
    manpages.enable = false;
    json.enable = false;
  };

  # This value determines the Home Manager release that your configuration is
  # compatible with. This helps avoid breakage when a new Home Manager release
  # introduces backwards incompatible changes.
  #
  # You should not change this value, even if you update Home Manager. If you do
  # want to update the value, then make sure to first check the Home Manager
  # release notes.
  home.stateVersion = "23.05"; # Please read the comment before changing.

  programs.home-manager.enable = true;
}
