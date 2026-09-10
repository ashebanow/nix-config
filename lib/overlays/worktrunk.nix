# worktrunk — the `wt` git-worktree CLI, pinned ahead of nixpkgs.
#
# Why this exists: nixpkgs (unstable) ships worktrunk 0.74.0, three releases
# behind, and the agent integrations the dev workflow uses — `wt config
# plugins pi`, `.codex`, `.opencode` — only exist from 0.77.0 on. Upstream
# publishes no `overlays` output, so this wraps the package its own flake
# builds with crane (input pinned to a release tag in flake.nix) under the
# nixpkgs attribute name.
#
# Applied to:
#   * this repo's dev shell package set (modules/infra/devshell.nix) — the
#     only copy on lumquat, where worktrunk is a dev tool like pi;
#   * the Darwin workstations' package sets (modules/infra/darwin-builder.nix)
#     — dev workstations get `wt` globally.
#
# Bumping: edit the tag in flake.nix, run `nix flake lock`, and the new
# source/build inputs follow. Nothing to hash by hand here — upstream's
# flake owns the crane recipe and the crate hashes.
{worktrunk}: final: _prev: {
  worktrunk = worktrunk.packages.${final.stdenv.hostPlatform.system}.worktrunk;
}
