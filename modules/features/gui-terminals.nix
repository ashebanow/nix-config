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
        # `ghostty-bin` is upstream's macOS binary; Linux packages the source
        # build under the plain `ghostty` attribute.
        (
          if stdenv.hostPlatform.isDarwin
          then ghostty-bin
          else ghostty
        )
        kitty
        warp-terminal
        tmux
        zmx
      ];
    };
  };
}
