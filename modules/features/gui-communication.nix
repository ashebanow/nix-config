# Communication GUI apps — Home Manager package list.
_: {
  my.modules.home-manager.gui-communication = {
    lib,
    pkgs,
    config,
    ...
  }: {
    config = lib.mkIf config.my.guiCommunication {
      home.packages = with pkgs; [
        discord
        signal-desktop
        slack
        zoom-us
      ];
    };
  };
}
