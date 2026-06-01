# Dev shell with alejandra for formatting
_: {
  perSystem = {pkgs, ...}: {
    devShells.default = pkgs.mkShell {
      name = "lumquat-dev";

      packages = with pkgs; [
        alejandra # Nix formatter
      ];

      shellHook = ''
        echo "Lumquat dev shell"
        echo "Run 'just fmt' to format Nix files"
      '';
    };
  };
}
