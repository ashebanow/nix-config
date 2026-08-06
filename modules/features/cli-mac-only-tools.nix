# macOS-specific CLI tools — Home Manager package list.
_: {
  my.modules.home-manager.cli-mac-only-tools = {
    lib,
    pkgs,
    config,
    ...
  }: {
    config = lib.mkIf config.my.cliMacOnlyTools {
      home.packages = with pkgs; [
        dockutil
        pinentry_mac
        xcodes
      ];
    };
  };
}
