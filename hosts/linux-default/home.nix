{ nixpkgs, config, ... }:

{
  nixpkgs.config.allowUnfree = true;

  imports = [
    ../../modules/core.nix
    ../../modules/git.nix
    ../../modules/hashi.nix
    ../../modules/iputils.nix
    # ../../modules/lorri.nix
    ../../modules/neovim.nix
    ../../modules/shell.nix
    ../../modules/warp.nix

    # "${fetchTarball "https://github.com/msteen/nixos-vscode-server/tarball/master"}/modules/vscode-server/home.nix"
    # ../../modules/vscode.nix

    # <sops-nix/modules/home-manager/sops.nix>
  ];

  # Home Manager needs a bit of information about you and the paths it should
  # manage.
  home.username = "ashebanow";

  home.homeDirectory = "/home/ashebanow";

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
