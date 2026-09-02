# Dev shell with alejandra for formatting
_: {
  perSystem = {
    pkgs,
    system,
    ...
  }: let
    unfreePkgs = import pkgs.path {
      inherit system;
      config.allowUnfree = true;
    };
  in {
    devShells.default = pkgs.mkShell {
      name = "lumquat-dev";

      shellHook = ''
        # Marks the nix develop subshell for the dotfiles prompt marker
        # (bashrc.d/020-prompt.sh shows "(nix-dev)"). BOX-129 ride-along.
        export IS_NIX_DEVELOP=1
      '';

      packages = with pkgs; [
        alejandra
        unfreePkgs.bws
        colmena
        dig
        gh
        git
        home-manager
        mcp-nixos
        nixd
        nixfmt
        pi-coding-agent
        secretspec
        uv
      ];
    };
  };
}
