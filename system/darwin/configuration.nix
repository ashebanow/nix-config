{ pkgs, ... }:

{
  imports = [
    ./common/core.nix
    ./common/git.nix
    ./common/shell.nix
    # ./common/neovim.nix
    # <sops-nix/modules/home-manager/sops.nix>
    # "${fetchTarball "https://github.com/msteen/nixos-vscode-server/tarball/master"}/modules/vscode-server/home.nix"
    # ./common/vscode.nix
  ];

  nix = {
    package = pkgs.nixFlakes;
    settings = {
      experimental-features = "nix-command flakes";
      auto-optimise-store = true;
      trusted-users = [ "root" "ashebanow" ];
      warn-dirty = false;
    };
    gc = {
      automatic = true;
    };
  };

  services.nix-daemon.enable = true;
  services.openssh.enable = true;

  users.users.ashebanow = {
    description = "Andrew Shebanow";
    extraGroups = [ "networkmanager" "wheel" "storage" ];
    home = "/Users/ashebanow";
    isNormalUser = true;
    openssh.authorizedKeys.keys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIJhsuxHH4J5rPM5XNosTiTdHOX+NnZzHmePfEFTyaAs1 ashebanow@gmail.com"
    ];
    shell = pkgs.zsh;
  };

  # Allow unfree packages
  nixpkgs.config.allowUnfree = true;

  # set up zsh as default shell
  programs.zsh.enable = true;
  users.defaultUserShell = pkgs.zsh;
  environment.shells = with pkgs; [ zsh ];

  homebrew = {
    enable = true;
    onActivation = {
      autoUpdate = true;
      upgrade = true;
    };
    casks = [
      "warp"
      # "visual-studio-code"
    ];
  };

  system.defaults = {
    dock = {
      autohide = true;
      show-recents = true;
      mru-spaces = false;
      showhidden = true;
    };
    finder = {
      AppleShowAllExtensions = true;
      AppleShowAllFiles = true;
      QuitMenuItem = true;
    };
    loginwindow = {
      GuestEnabled = false;
      # autoLoginUser = "Andrew Shebanow";
    };
  };

  # Used for backwards compatibility, please read the changelog before changing.
  # $ darwin-rebuild changelog
  system.stateVersion = 4;
}
