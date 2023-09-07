{ pkgs, ... }:

{
  services.nix-daemon.enable = true;

  users.users.ashebanow.home = "/Users/ashebanow";

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

  programs.zsh.enable = true;

  # homebrew = {
  #   enable = true;
  #   onActivation = {
  #     autoUpdate = true;
  #     upgrade = true;
  #   };
  #   casks = [
  #     "discord"
  #     "warp"
  #     "epic-games"
  #     "zed"
  #     "rectangle"
  #     "livebook"
  #     "rio"
  #     "visual-studio-code"
  #   ];
  # };

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
