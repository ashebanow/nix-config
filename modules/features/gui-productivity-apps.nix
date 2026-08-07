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
        raycast
      ];
    };
  };
}
