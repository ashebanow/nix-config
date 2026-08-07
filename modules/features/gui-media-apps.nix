# Media GUI apps — Home Manager package list.
_: {
  my.modules.home-manager.gui-media-apps = {
    lib,
    pkgs,
    config,
    ...
  }: {
    config = lib.mkIf config.my.guiMediaApps {
      home.packages = with pkgs; [
        dolphin-emu # GameCube/Wii emulator — matches the "dolphin" cask token
        pinta
        vlc-bin
      ];
    };
  };
}
