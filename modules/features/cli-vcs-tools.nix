# Git and git-adjacent CLI tools — Home Manager package list.
_: {
  my.modules.home-manager.cli-vcs-tools = {
    lib,
    pkgs,
    config,
    ...
  }: {
    config = lib.mkIf config.my.cliVcsTools {
      home.packages = with pkgs; [
        difftastic
        gh
        git
        git-lfs
        gitnr
        lazygit
        mergiraf
        svu
        # nixpkgs' worktrunk is 0.74.0 and lacks `wt config plugins pi`.
        # On the Darwin workstations the worktrunk overlay
        # (lib/overlays/worktrunk.nix) makes this 0.77.0; lumquat leaves the
        # dev shell as the only place worktrunk exists, and this flag is off
        # there.
        worktrunk
      ];
    };
  };
}
