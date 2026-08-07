# Core GUI apps common to every host — Home Manager package list.
# bitwarden-desktop deliberately excluded — nixpkgs' current build
# pulls in an EOL/insecure Electron version (same tradeoff as logseq,
# see homebrew.casks in the host configs). Kept as a Homebrew cask.
_: {
  my.modules.home-manager.gui-core-apps = {
    lib,
    pkgs,
    config,
    ...
  }: {
    config = lib.mkIf config.my.guiCoreApps {
      home.packages = with pkgs; [
        google-chrome
      ];
    };
  };
}
