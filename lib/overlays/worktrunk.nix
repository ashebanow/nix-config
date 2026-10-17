# worktrunk — the `wt` git-worktree CLI, pinned ahead of nixpkgs.
#
# Why this exists: nixpkgs (unstable) still ships worktrunk 0.74.0, so the
# agent integrations the dev workflow uses — `wt config plugins pi`, `.codex`,
# `.opencode` — are absent from it (they exist from 0.77.0 on). Upstream
# publishes no `overlays` output, so this wraps the package its own flake
# builds with crane (input pinned to upstream's `v0.80.0` tag in flake.nix)
# under the nixpkgs attribute name.
#
# Applied to:
#   * this repo's dev shell package set (modules/infra/devshell.nix) — the
#     only copy on lumquat, where worktrunk is a dev tool like pi;
#   * the Darwin workstations' package sets (modules/infra/darwin-builder.nix)
#     — dev workstations get `wt` globally.
#
# Bumping: run `just update-worktrunk` (rewrites the tag in flake.nix to
# upstream's newest semver tag, then `nix flake lock`); the new source/build
# inputs follow. Nothing to hash by hand here — upstream's flake owns the
# crane recipe and the crate hashes.
#
# Retiring: drop this overlay and the flake input once nixpkgs unstable ships
# >= 0.78.0 (BOX-190).
{ worktrunk }: final: _prev: {
  worktrunk = worktrunk.packages.${final.stdenv.hostPlatform.system}.worktrunk;
}
