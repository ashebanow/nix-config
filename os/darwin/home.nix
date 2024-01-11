{ nixpkgs, config, ... }

 @ inputs : {
  nixpkgs.config.allowUnfree = true;
  programs.home-manager.enable = true;

  imports = [
    ../../modules/core.nix
    ../../modules/git.nix
    ../../modules/hashi.nix
    # ../../modules/lorri.nix
    ../../modules/neovim
    # ../../modules/neovim.nix
    ../../modules/shell.nix
    ../../modules/vscode.nix

    # <sops-nix/modules/home-manager/sops.nix>
  ];

  home = {
    # Home Manager needs a bit of information about you and the paths it should
    # manage.
    username = "ashebanow";
    homeDirectory = "/Users/ashebanow";

    modules = [
      inputs.nixvim.homeManagerModules.nixvim
    ];

    # This value determines the Home Manager release that your configuration is
    # compatible with. This helps avoid breakage when a new Home Manager release
    # introduces backwards incompatible changes.
    #
    # You should not change this value, even if you update Home Manager. If you do
    # want to update the value, then make sure to first check the Home Manager
    # release notes.
    stateVersion = "23.05"; # Please read the comment before changing.
  };
}
