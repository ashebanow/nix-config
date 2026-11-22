# worktrunk — the `wt` git-worktree CLI, pinned ahead of nixpkgs.
#
# Why this exists: nixpkgs carries worktrunk 0.80.0 while upstream is on
# 0.82.0, and the agent integrations the dev workflow uses — `wt config
# plugins pi`, `.codex`, `.opencode` — only exist from 0.77.0 on. Upstream
# publishes no `overlays` output, so this wraps the package its own flake
# builds with crane (input pinned to upstream's `v0.82.0` tag in flake.nix)
# under the nixpkgs attribute name.
#
# Applied to:
#   * this repo's dev shell package set (modules/infra/devshell.nix) — the
#     only copy on lumquat, where worktrunk is a dev tool like pi;
#   * the Darwin workstations' package sets (modules/infra/darwin-builder.nix)
#     — dev workstations get `wt` globally.
#
# Bumping: run `just update-worktrunk`. It moves the tag in flake.nix and
# re-locks, and the new source/build inputs follow. Nothing to hash by hand
# here — upstream's flake owns the crane recipe and the crate hashes. The
# recipe does not touch prose, so update the version numbers in this header,
# flake.nix, modules/features/cli-vcs-tools.nix and
# modules/infra/darwin-builder.nix in the same commit.
#
# Retiring: nixpkgs has already passed the 0.78.0 floor (it sits on 0.80.0,
# which carries the full `wt config plugins` set), so the only reason left to
# keep this overlay is running ahead of nixpkgs. Drop it when that stops
# mattering (BOX-190).
{ worktrunk }: final: _prev: {
  worktrunk = worktrunk.packages.${final.stdenv.hostPlatform.system}.worktrunk;
}
