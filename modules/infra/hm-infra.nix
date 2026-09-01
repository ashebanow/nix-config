# Home Manager infrastructure for podman user.
#
# Also installs chezmoi and applies it on every HM activation (which runs
# on every `nh os switch` via the home-manager NixOS module). Lumquat is a
# chezmoi-managed headless host: `programs.chezmoi` does not exist upstream,
# so the wiring is home.packages + a home.activation entry. The init is
# guarded by the presence of the chezmoi source repo so it is idempotent,
# and `--force` makes `apply` non-interactive (suppresses the changed-file
# TTY prompt). Apply safety is handled chezmoi-side: the headless
# .chezmoiignore excludes the personal-secret templates (hermes, git
# signingkey, gh token), so apply runs token-less — secretspec/BWS is
# untouched.
{ lib, pkgs, ... }: {
  my.cliTools = true;

  home.packages = [ pkgs.chezmoi ]; # nixpkgs chezmoi 2.72.0

  home.activation.chezmoiApply = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    run test -d "$HOME/.local/share/chezmoi/.git" \
      || run ${pkgs.chezmoi}/bin/chezmoi init https://github.com/ashebanow/dotfiles.git
    run ${pkgs.chezmoi}/bin/chezmoi apply --force
  '';
}
