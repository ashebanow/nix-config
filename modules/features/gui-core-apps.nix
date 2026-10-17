# Core GUI apps common to every host — Home Manager package list.
# bitwarden-desktop deliberately excluded — nixpkgs' current build
# pulls in an EOL/insecure Electron version (same tradeoff as logseq,
# see homebrew.casks in the host configs). Kept as a Homebrew cask.
_: {
  my.modules.home-manager.gui-core-apps =
    {
      lib,
      pkgs,
      config,
      ...
    }:
    {
      config = lib.mkIf config.my.guiCoreApps {
        home.packages = with pkgs; [
          firefox
          google-chrome
        ];
      };
    };

  # 1Password desktop app — a NixOS system option, not Home Manager: it needs
  # a setgid browser-support helper and a polkit policy for system auth.
  # Darwin hosts don't get it from here (the darwin builder's scope rule
  # forbids programs.*.enable); 1Password there is installed outside nix.
  my.modules.nixos.gui-core-apps =
    {
      lib,
      config,
      ...
    }:
    {
      config = lib.mkIf config.my.guiCoreApps {
        programs._1password-gui = {
          enable = true;
          # Lets this user unlock 1Password with system auth (polkit).
          polkitPolicyOwners = [ "ashebanow" ];
        };
      };
    };
}
