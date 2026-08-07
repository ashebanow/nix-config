# Terminal emulator GUI apps — Home Manager package list.
# -bin variants used where the source build is Linux-only in nixpkgs
# even though the app itself supports macOS.
_: {
  my.modules.home-manager.gui-terminals = {
    lib,
    pkgs,
    config,
    ...
  }: {
    config = lib.mkIf config.my.guiTerminals {
      home.packages = with pkgs; [
        ghostty-bin
        kitty
        warp-terminal
      ];
    };
  };
}
