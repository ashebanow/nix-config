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
        caddy
        copyparty
        inetutils
        lazyssh
        mole
        tailscale
        talosctl
        wishlist
      ];
    };
  };
}
