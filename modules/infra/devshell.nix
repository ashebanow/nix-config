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
        mcp-nixos
        nixd
        nixfmt
        # pi shells out to `npm`/`node` for extension installs; the pi.nix
        # wrapper adds them to pi's own PATH, but keep them in the shell too
        # so a stale/odd invocation can't hit `spawn npm ENOENT`.
        nodejs
        piPkgs.pi-coding-agent
        secretspec
        uv
        worktrunk
      ];
    };
  };
}
