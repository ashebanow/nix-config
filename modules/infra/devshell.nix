# Dev shell with nixfmt, jq, etc.:w
#
{inputs, ...}: {
  perSystem = {
    pkgs,
    system,
    ...
  }: let
    unfreePkgs = import pkgs.path {
      inherit system;
      config.allowUnfree = true;
    };

    # Apply pi.nix's overlay to this dev shell's package set only — pi is a
    # dev tool, not something we want resolvable (or installable by accident)
    # in a production host's pkgs. `pi-coding-agent` here is pi.nix's build,
    # which unlike nixpkgs' works in NixOS's read-only store.
    piPkgs = pkgs.extend inputs.pi-nix.overlays.default;

    # pi.nix's callPackage argument follows the nixpkgs attr rename: it used to
    # be `typescript-go`, which nixpkgs renamed to `typescript`. pi.nix HEAD
    # (rev b9009565) now takes `typescript`, so the old
    # `.override {typescript-go = pkgs.typescript;}` shim is gone — passing the
    # retired name is itself an error (`called with unexpected argument
    # 'typescript-go'`) and aborts `nix develop`.
    pi = piPkgs.pi-coding-agent;

    # Same treatment for worktrunk: nixpkgs' `worktrunk` is 0.74.0 and lacks
    # `wt config plugins pi`, which the agent workflow in this shell needs.
    # The overlay wraps upstream's own build of the pinned release (see
    # lib/overlays/worktrunk.nix).
    worktrunkPkgs = pkgs.extend (import ../../lib/overlays/worktrunk.nix {inherit (inputs) worktrunk;});

    # linear-cli (the Linear.app CLI that replaces the Linear MCP, BOX-176)
    # is not in nixpkgs; the overlay fetches upstream's release binary. Same
    # dev-tool policy as pi/worktrunk: in the shell on every host, in a
    # host closure only on the Darwin workstations.
    linearPkgs = pkgs.extend (import ../../lib/overlays/linear-cli.nix);
  in {
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
        export PI_OFFLINE="''${PI_OFFLINE:-1}"
      '';

      packages = with pkgs; [
        unfreePkgs.bws
        unfreePkgs.claude-code
        dig
        gh
        git
        home-manager
        linearPkgs.linear-cli
        mcp-nixos
        nil
        nixd
        nixfmt
        # pi shells out to `npm`/`node` for extension installs; the pi.nix
        # wrapper adds them to pi's own PATH, but keep them in the shell too
        # so a stale/odd invocation can't hit `spawn npm ENOENT`.
        nodejs
        pi
        secretspec
        uv
        worktrunkPkgs.worktrunk
      ];
    };
  };
}
