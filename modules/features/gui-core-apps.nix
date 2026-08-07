# Core GUI apps common to every host — Home Manager package list.
_: {
  my.modules.home-manager.gui-core-apps = {
    lib,
    pkgs,
    config,
    ...
  }: {
    config = lib.mkIf config.my.guiCoreApps {
      home.packages = with pkgs; [
        bitwarden-desktop
        google-chrome
      ];
    };
  };
}
