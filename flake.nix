{
  description = "main flake for my nix configuration";

  inputs = {
    # Package sets
    nixpkgs.url = "github:nixos/nixpkgs/nixos-23.05";
    nixpkgs-unstable.url = "github:nixos/nixpkgs/nixos-unstable";
    nixpkgs-stable-darwin.url = "github:nixos/nixpkgs/nixpkgs-23.05-darwin";
    nixos-stable.url = "github:nixos/nixpkgs/nixos-23.05";

    # Environment/system management
    darwin.url = "github:lnl7/nix-darwin";
    darwin.inputs.nixpkgs.follows = "nixpkgs";
    home-manager.url = "github:nix-community/home-manager/release-23.05";
    home-manager.inputs.nixpkgs.follows = "nixpkgs";

    # sops-nix = {
    #   url = "github:Mic92/sops-nix";
    #   inputs.nixpkgs.follows = "nixpkgs";
    # };
  };

  outputs = inputs@{ nixpkgs, home-manager, darwin, ... }:
    substituters = [
      https://cache.nixos.org
      https://cache.nixos.org/
      https://cattivi-public.cachix.org
    ];
    trusted-public-keys = [
      cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY=
      cattivi-public.cachix.org-1:qQQ8FHPoEibPtL1FTZTmVbUL78KW2zCRk+LZPsRiwQ4=
    ];

    nix = {
      package = pkgs.nixFlakes;
      settings = {
        experimental-features = "nix-command flakes";
        auto-optimise-store = true;
        trusted-users = [ "root" "ashebanow" ];
        warn-dirty = false;
      };
      gc.automatic = true;
    };

    let
      darwinSystem = "aarch64-darwin";
      linuxSystem = "x86_64-linux";

      darwinPkgs = nixpkgs.legacyPackages.${darwinSystem};
      linuxPkgs = nixpkgs.legacyPackages.${linuxSystem};
    in
    {
      nixosConfigurations = {
        virt1 = nixpkgs.lib.nixosSystem {
          system = linuxSystem;
          specialArgs = inputs; # forward inputs to modules
          modules = [
            ./system/nixos/virt1-configuration.nix
            home-manager.nixosModules.home-manager
            {
              home-manager.verbose = true;
              home-manager.useGlobalPkgs = true;
              home-manager.useUserPackages = true;
              home-manager.users.ashebanow = import ./home/home.nix;

              # Optionally, use home-manager.extraSpecialArgs to pass
              # arguments to home.nix
            }
          ];
        };
        virt2 = nixpkgs.lib.nixosSystem {
          system = linuxSystem;
          specialArgs = inputs; # forward inputs to modules
          modules = [
            ./system/nixos/virt2-configuration.nix
            home-manager.nixosModules.home-manager
            {
              home-manager.verbose = true;
              home-manager.useGlobalPkgs = true;
              home-manager.useUserPackages = true;
              home-manager.users.ashebanow = import ./home/home.nix;
            }
          ];
        };
      };

      darwinConfigurations = {
        miraclemax = darwin.lib.darwinSystem {
          system = darwinSystem;
          modules = [
            ./system/darwin/configuration.nix
            home-manager.darwinModules.home-manager {
              home-manager.verbose = true;
              home-manager.useGlobalPkgs = true;
              home-manager.useUserPackages = true;
              home-manager.users.ashebanow = import ./home/home.nix;
            }
            # sops-nix.nixosModules.sops
          ];
        };
      };

      homeConfigurations = {
        home-manager.verbose = true;
        home-manager.useGlobalPkgs = true;
        home-manager.useUserPackages = true;

        ashebanow = home-manager.lib.homeManagerConfiguration {
          pkgs = linuxPkgs;
          modules = [
            ./home/home.nix
          ];
        };
      };
    };
}
