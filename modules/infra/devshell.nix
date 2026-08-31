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
