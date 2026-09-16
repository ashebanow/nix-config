# Dev shell with alejandra for formatting
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

    # pi.nix's package still takes `typescript-go` as a callPackage argument,
    # but nixpkgs renamed that attr to `typescript`. As of nixpkgs ef34387
    # (2026-09-13) the old name is a `throw`, not a deprecation warning:
    #
    #   typescript-go = throw "'typescript-go' has been renamed to/replaced by 'typescript'";
    #
    # Because `inputs.nixpkgs.follows = "nixpkgs"` puts pi.nix on our nixpkgs,
    # merely evaluating pi-coding-agent aborts `nix develop` — which is why a
    # `nix flake update` appears to break a dev shell nothing changed in.
    # `pkgs.typescript` is the same derivation the old name used to resolve to.
    # Drop this once pi.nix renames the argument (its HEAD still does not).
    pi = piPkgs.pi-coding-agent.override {typescript-go = pkgs.typescript;};

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
        alejandra
        unfreePkgs.bws
        unfreePkgs.claude-code
        dig
        gh
        git
        home-manager
        linearPkgs.linear-cli
        mcp-nixos
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
