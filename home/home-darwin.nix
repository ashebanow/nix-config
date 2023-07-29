{ ... }: {

  imports = [
    ./common/core.nix
    # ./common/neovim.nix
    ./common/git.nix
    ./common/shell.nix
  ];

  home = {
    username = "ashebanow";
    homeDirectory = "/Users/ashebanow";
    stateVersion = "23.05";
  };
  
  programs = {
    home-manager.enable = true;
  };
}
