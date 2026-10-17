# Dev shell with nixfmt, jq, etc.:w
#
{ inputs, ... }: {
  perSystem =
    {
      pkgs,
      system,
      ...
    }:
    let
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
      worktrunkPkgs = pkgs.extend (
        import ../../lib/overlays/worktrunk.nix { inherit (inputs) worktrunk; }
      );

      # linear-cli (the Linear.app CLI that replaces the Linear MCP, BOX-176)
      # is not in nixpkgs; the overlay fetches upstream's release binary. Same
      # dev-tool policy as pi/worktrunk: in the shell on every host, in a
      # host closure only on the Darwin workstations.
      linearPkgs = pkgs.extend (import ../../lib/overlays/linear-cli.nix);

      # claude-code is pinned to Anthropic's release channel and shimmed by
      # lib/overlays/claude-code.nix, but `unfreePkgs` above is a fresh
      # `import pkgs.path` and so carries NO overlays. Without this extend the
      # shell's `claude` is stock nixpkgs (2.1.272 against the pin's 2.1.296)
      # and unshimmed — and because the shell's PATH sits ahead of
      # /etc/profiles/per-user, it *shadows* the pinned one the host actually
      # installs. That is a worse failure than a stale shell tool: `just
      # update-claude-code && just switch` then reports success while every
      # shell session keeps running the old binary. Extend the unfree set rather
      # than `pkgs`, because claude-code is unfree and that is where the
      # allowUnfree config lives.
      claudePkgs = unfreePkgs.extend (import ../../lib/overlays/claude-code.nix);
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
          export PI_OFFLINE="''${PI_OFFLINE:-1}"
        '';

        packages = with pkgs; [
          unfreePkgs.bws
          claudePkgs.claude-code
          dig
          gh
          git
          home-manager
          jq
          linearPkgs.linear-cli
          mcp-nixos
          nil
          nixd
          nixfmt
          nixfmt-tree
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
