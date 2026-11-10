# Networking/remote-access/download CLI tools — Home Manager package list.
_: {
  my.modules.home-manager.cli-network-tools =
    {
      lib,
      pkgs,
      config,
      ...
    }:
    {
      config = lib.mkIf config.my.cliNetworkTools {
        home.packages = with pkgs; [
          aria2
          autossh
          # caddy
          copyparty
          inetutils
          # lazyssh — removed: it rewrites ~/.ssh/config from its own model on
          # save, dropping the rex guard Include and any comments chezmoi
          # renders there. chezmoi owns ~/.ssh/config.
          # mole excluded — nixpkgs marks it broken currently; kept on
          # homebrew.brews in the host configs instead.
          # tailscale — NOT via nix or Homebrew on the Macs: official .pkg
          # installer (MAS build is sandboxed → no Tailscale SSH; nixpkgs
          # build won't start on macOS)
          # talosctl
          wishlist
        ];
      };
    };
}
