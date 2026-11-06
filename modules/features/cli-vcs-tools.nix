# Git and git-adjacent CLI tools — Home Manager package list.
#
# These are not project-specific: `git`, `gh` and `wt` are needed in every
# repo, so they belong on PATH globally rather than only inside a dev shell.
_: {
  my.modules.home-manager.cli-vcs-tools =
    {
      lib,
      pkgs,
      config,
      ...
    }:
    {
      config = lib.mkIf config.my.cliVcsTools {
        home.packages = with pkgs; [
          difftastic
          gh
          ghgrab
          git
          git-lfs
          gitnr
          github-cli
          lazygit
          # The Linear.app CLI — tracker-of-record tool beside `gh`. Not in
          # nixpkgs; `pkgs.linear-cli` exists only where the linear-cli overlay
          # (lib/overlays/linear-cli.nix) is applied: every host's pkgs and the
          # dev shell. A host with this flag off never evaluates the attribute.
          linear-cli
          mergiraf
          svu
          # nixpkgs' worktrunk is 0.74.0 and lacks `wt config plugins pi`.
          # The worktrunk overlay (lib/overlays/worktrunk.nix) makes this
          # 0.78.0 on every host; the dev shell applies the same overlay.
          worktrunk
        ];
      };
    };
}
