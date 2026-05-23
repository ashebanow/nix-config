{
  description = "Lumquat NixOS Configuration - AI Server";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";

    # Flake framework
    flake-parts.url = "github:hercules-ci/flake-parts";
    import-tree.url = "github:vic/import-tree";
    import-tree.flake = false;

    # Home Manager
    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Secrets management
    sops-nix = {
      url = "github:Mic92/sops-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # NixOS hardware quirks
    nixos-hardware.url = "github:nixos/nixos-hardware";
  };

  outputs = inputs @ {flake-parts, ...}: let
    import-tree = import inputs.import-tree;
  in
    flake-parts.lib.mkFlake {inherit inputs;} {
      imports = [
        # Auto-discover all feature modules
        (import-tree ./modules/features)

        # Infrastructure modules (explicit — not auto-discovered)
        ./modules/infra/module-containers.nix
        ./modules/infra/devshell.nix
        ./modules/infra/nixos-builder.nix
      ];

      systems = ["x86_64-linux" "aarch64-darwin"];
    };
}
