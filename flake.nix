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

  # outputs = inputs@{ nixpkgs, home-manager, darwin, sops-nix, ... }:
  outputs = inputs@{ nixpkgs, home-manager, darwin, ... }:
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
              home-manager.useGlobalPkgs = true;
              home-manager.useUserPackages = true;
              home-manager.users.ashebanow = import ./home/home.nix;

              # Optionally, use home-manager.extraSpecialArgs to pass
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
              home-manager.useGlobalPkgs = true;
              home-manager.useUserPackages = true;
              home-manager.users.ashebanow = import ./home/home.nix;

              # Optionally, use home-manager.extraSpecialArgs to pass
              # arguments to home.nix
            }
          ];
        };
      };

      darwinConfigurations = {
        miraclemax = darwin.lib.darwinSystem {
          system = darwinSystem;
          modules = [
            ./system/darwin/configuration.nix
            # sops-nix.nixosModules.sops
          ];
        };
      };

      homeConfigurations = {
        ashebanow = home-manager.lib.homeManagerConfiguration {
          pkgs = linuxPkgs;
          modules = [
            ./home/home.nix
          ];
        };
      };
    };
}
