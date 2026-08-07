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
        cava
        vlc-bin
        # dolphin-emu (GameCube/Wii emulator, matches the "dolphin" cask
        # token) and pinta both dropped — both need to build a GTK4/
        # native library from source with no cached aarch64-darwin
        # binary (sfml, libadwaita respectively), and both crash the
        # same linker on real hardware ("Trace/BPT trap: 5" in
        # cctools-binutils-darwin). Looks like a systemic issue with
        # complex from-source GTK builds on this toolchain, not
        # specific to either package — worth watching for if other
        # GTK-heavy packages get added later. Kept on homebrew.casks.
      ];
    };
  };
}
