# Productivity/utility GUI apps — Home Manager package list.
_: {
  my.modules.home-manager.gui-productivity-apps = {
    lib,
    pkgs,
    config,
    ...
  }: {
    config = lib.mkIf config.my.guiProductivityApps {
      home.packages = with pkgs; [
        betterdisplay
        mist
        monitorcontrol
        postman
        raycast
        soundsource
        stats
        temurin-bin
        utm
      ];
    };
  };
}
