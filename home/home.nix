{ config, nixpkgs, ... }:

{
  nixpkgs.config.allowUnfree = true;
  # home-manager.useUserPackages = true;


  imports = [
    "${fetchTarball "https://github.com/msteen/nixos-vscode-server/tarball/master"}/modules/vscode-server/home.nix"
    # <sops-nix/modules/home-manager/sops.nix>
    ./common/core.nix
    # ./common/neovim.nix
    ./common/git.nix
    ./common/shell.nix
    # ./common/vscode.nix
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

  programs = {
    # Let Home Manager install and manage itself.
    home-manager.enable = true;
  };

}
