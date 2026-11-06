# Dev shell for developing *this* repo.
#
# Scope rule: this shell carries only what a project-specific shell should —
# Nix-language tooling for editing this flake, plus the packages whose overlays
# exist because nixpkgs is behind (pi, worktrunk, linear-cli, claude-code).
#
# Everything genuinely project-agnostic now lives in Home Manager feature
# modules instead, because a dev shell made those tools reachable only from
# this directory: git, gh, ghgrab, github-cli, lazygit, worktrunk, linear-cli
# (modules/features/cli-vcs-tools.nix); claude-code and pi
# (modules/features/cli-ai-tools.nix); jq, dig, curl, fzf, ripgrep, fd, eza, bat
# (modules/features/cli-tools.nix + cli-productivity-tools.nix); bws and
# secretspec (modules/features/cli-security-tools.nix); uv, direnv, gcc, llvm,
# mcp-nixos (modules/features/cli-build-essentials.nix).
#
# Deliberately still project-local, and why:
#   * nil / nixd          — LSPs for the Nix language, useless in a repo with
#                           no .nix files, and each needs per-project nixd
#                           config to resolve the right nixpkgs.
#   * nixfmt / nixfmt-tree — the Nix formatter. Also the flake `formatter`
#                           output, so `nix fmt` works without them on PATH.
#   * home-manager        — used to build this flake's HM output, nothing else.
#   * nodejs              — a pinned Node version globally shadows a project's
#                           own node. pi shells out to `npm`/`node` for
#                           extension installs and the pi.nix wrapper adds them
#                           to pi's own PATH, so this is belt-and-braces for a
#                           stale invocation, not a general need.
#
{ inputs, ... }:
{
  perSystem =
    {
      pkgs,
      system,
      ...
    }:
    let
      # claude-code is unfree, so the shell's package set needs allowUnfree.
      # `perSystem`'s `pkgs` does not carry it, and the host-side feature module
      # satisfies the same requirement through nixpkgs.config.allowUnfree.
      unfreePkgs = import pkgs.path {
        inherit system;
        config.allowUnfree = true;
      };

      # pi, worktrunk and linear-cli are all pinned ahead of nixpkgs; the
      # overlays are shared with the host builders (modules/infra/*-builder.nix)
      # so the shell and the host cannot disagree about which build a name
      # means. Before, the shell built its own copies here and a stale shell
      # could silently shadow the pinned binaries the host installs.
      #
      # Extend `unfreePkgs` rather than `pkgs`, because that is where the
      # allowUnfree config lives — the pi, worktrunk and linear-cli overlays
      # only define attributes, so they compose onto either without loss.
      devPkgs = unfreePkgs.extend (
        pkgs.lib.composeManyExtensions [
          (import ../../lib/overlays/pi.nix { inherit (inputs) pi-nix; })
          (import ../../lib/overlays/worktrunk.nix { inherit (inputs) worktrunk; })
          (import ../../lib/overlays/linear-cli.nix)
        ]
      );
    in
    {
      # Standard flake formatter output (`nix fmt`) using `nixfmt-tree`, which
      # wraps `treefmt` + `nixfmt` and walks git-tracked `*.nix` files rather than
      # passing `.` to `nixfmt` (avoiding both the directory-arg deprecation
      # warning and `./result` symlink traversal into root-owned store paths).
      formatter = pkgs.nixfmt-tree;

      devShells.default = pkgs.mkShell {
        name = "lumquat-dev";

        shellHook = ''
          # Marks the nix develop subshell for the dotfiles prompt marker
          # (bashrc.d/020-prompt.sh shows "(nix-dev)"). BOX-129 ride-along.
          export IS_NIX_DEVELOP=1

          # pi runs its package manager (npm install + git clone of every
          # entry in .pi/settings.json) on *every* launch, so a flaky network
          # or a broken upstream extension bricks startup. Default it to
          # offline — extensions in .pi/npm/ keep working. To (re)sync them,
          # e.g. on a fresh clone: `PI_OFFLINE= pi` once.
          #
          # It also suppresses pi's own version check, so `pi update`'s
          # SELF-update half fails with "Could not determine latest pi
          # version." — that message is this variable, not a network or
          # permissions problem. (In 1.5.0 the check is additionally gated on
          # PI_CODING_AGENT being set, so a bare shell shows the same message
          # even online.) `pi update` is not how pi moves here anyway: this
          # shell's pi comes from the pi-nix overlay below and lives in the
          # read-only store, so it updates with `just update-pi` — which bumps
          # only the pi-nix input — never in place.
          #
          # Extensions are a separate path and do work offline: `pi update
          # --extensions` re-resolves .pi/npm/ from the local lockfile without
          # the release check. Use it (with PI_OFFLINE as-is) to bump
          # extension pins; `pi update --all` would drag in the blocked
          # self-update half and fail.
          export PI_OFFLINE="''${PI_OFFLINE:-1}"
        '';

        packages = with devPkgs; [
          # Pinned-ahead-of-nixpkgs dev tools. The hosts install these too
          # (feature modules); they stay in the shell so a shell session works
          # on a host where the relevant feature flag is off.
          claude-code
          linear-cli
          pi-coding-agent
          worktrunk
          # Nix-language tooling — see the scope rule at the top of this file.
          home-manager
          nil
          nixd
          nixfmt
          nixfmt-tree
          # pi shells out to `npm`/`node` for extension installs; the pi.nix
          # wrapper adds them to pi's own PATH, but keep them in the shell too
          # so a stale/odd invocation can't hit `spawn npm ENOENT`.
          nodejs
        ];
      };
    };
}
