# Networking/remote-access/download CLI tools — Home Manager package list.
_: {
  my.modules.home-manager.cli-network-tools = {
    lib,
    pkgs,
    config,
    ...
  }: {
    config = lib.mkIf config.my.cliNetworkTools {
      home.packages = with pkgs; [
        aria2
        autossh
        # caddy
        copyparty
        inetutils
        lazyssh
        # mole excluded — nixpkgs marks it broken currently; kept on
        # homebrew.brews in the host configs instead.
        tailscale-gui
        # talosctl
        wishlist
      ];
    };
  };
}
