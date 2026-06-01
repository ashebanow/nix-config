{pkgs ? import <nixpkgs> {}}:
pkgs.mkShell {
  name = "lumquat-dev";

  nativeBuildInputs = with pkgs; [
    alejandra
    gh
    git
    home-manager
    pi-coding-agent
    sops
  ];

  shellHook = ''
    echo "Lumquat dev shell"
    echo "Run 'just fmt' to format Nix files"
  '';
}
