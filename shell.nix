{pkgs ? import <nixpkgs> {}}:
pkgs.mkShell {
  name = "lumquat-dev";

  packages =
    (with pkgs; [
      alejandra # Nix formatter
      git
    ])
    ++ (with pkgs; [
      # Platform-specific tools if needed
    ]);

  shellHook = ''
    echo "Lumquat dev shell"
    echo "Run 'just fmt' to format Nix files"
  '';
}
