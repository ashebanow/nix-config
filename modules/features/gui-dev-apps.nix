# Development GUI apps — Home Manager package list.
_: {
  my.modules.home-manager.gui-dev-apps = {
    lib,
    pkgs,
    config,
    ...
  }: {
    config = lib.mkIf config.my.guiDevApps {
      home.packages = with pkgs; [
        charm
        crush
        temurin-bin
        vscode
        zed-editor
      ];
    };
  };
}
