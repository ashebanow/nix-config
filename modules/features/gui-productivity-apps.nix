# Productivity/utility GUI apps — Home Manager package list.
_: {
  my.modules.home-manager.gui-productivity-apps = {
    lib,
    pkgs,
    config,
    ...
  }: {
    # raycast is macOS-only, so the flag is also gated on the platform:
    # enabling it on a Linux host is a no-op instead of a build failure.
    # Add Linux productivity/utility GUI apps here as they come up.
    config = lib.mkIf (config.my.guiProductivityApps && pkgs.stdenv.hostPlatform.isDarwin) {
      home.packages = with pkgs; [
        raycast
      ];
    };
  };
}
