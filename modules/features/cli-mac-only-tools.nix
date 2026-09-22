# macOS-specific CLI tools — Home Manager package list.
_: {
  my.modules.home-manager.cli-mac-only-tools = {
    lib,
    pkgs,
    config,
    ...
  }: {
    # Every package here is macOS-only, so the flag is also gated on the
    # platform: enabling it on a Linux host is a no-op instead of a build
    # failure.
    config = lib.mkIf (config.my.cliMacOnlyTools && pkgs.stdenv.hostPlatform.isDarwin) {
      home.packages = with pkgs; [
        dockutil
        pinentry_mac
        xcodes
      ];
    };
  };
}
