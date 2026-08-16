{
  description = "Lumquat NixOS Configuration - AI Server";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";

    # Determinate Nix — replaces stock nix-daemon with determinate-nixd
    determinate.url = "https://flakehub.com/f/DeterminateSystems/determinate/*";

    # Flake framework
    flake-parts.url = "github:hercules-ci/flake-parts";
    import-tree.url = "github:vic/import-tree";
    import-tree.flake = false;

    # Home Manager
    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # macOS system configuration (Darwin hosts)
    nix-darwin = {
      url = "github:nix-darwin/nix-darwin/master";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Declarative Homebrew installation management (Darwin hosts) —
    # taps pinned via flake inputs so nix-homebrew can manage the
    # Homebrew installation itself, not just run `brew bundle`.
    nix-homebrew.url = "github:zhaofengli/nix-homebrew";
    homebrew-core = {
      url = "github:homebrew/homebrew-core";
      flake = false;
    };
    homebrew-cask = {
      url = "github:homebrew/homebrew-cask";
      flake = false;
    };

    # Registers nix/home-manager-installed .app bundles with Spotlight
    # and Launchpad — without this, GUI apps installed via home.packages
    # are technically present but undiscoverable (Spotlight doesn't
    # index the symlinks Nix creates).
    mac-app-util.url = "github:hraban/mac-app-util";

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
        ./modules/infra/nix
        ./modules/infra/module-containers.nix
        ./modules/infra/devshell.nix
        ./modules/infra/nixos-builder.nix
        ./modules/infra/darwin-builder.nix
      ];

      systems = ["x86_64-linux" "aarch64-darwin"];
    };
}
