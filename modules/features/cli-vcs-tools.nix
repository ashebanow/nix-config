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
        hunk
        lazygit
        mergiraf
        svu
        worktrunk
      ];
    };
  };
}
