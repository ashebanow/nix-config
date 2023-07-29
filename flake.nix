{
  description = "main flake for my nix configuration";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    darwin = {
      url = "github:lnl7/nix-darwin";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = inputs@{ nixpkgs, home-manager, darwin, ... }:
    let
      darwinSystem = "aarch64-darwin";
      wslSystem = "x86_64-linux";

      darwinPkgs = nixpkgs.legacyPackages.${darwinSystem};
      wslPkgs = nixpkgs.legacyPackages.${wslSystem};
    in
    {
      darwinConfigurations = {
        MiracleMax = darwin.lib.darwinSystem {
          system = darwinSystem;
          modules = [
            ./system/darwin/configuration.nix
          ];
        };
      };

      homeConfigurations = {
        ashebanow = home-manager.lib.homeManagerConfiguration {
          pkgs = wslPkgs;
          modules = [
            ./home/home.nix
          ];
        };
      };
    };
}