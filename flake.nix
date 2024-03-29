{
  description = "ashebanow's way-too-complicated nix configuration";

  inputs = {
    # nixpkgs.url = "github:nixos/nixpkgs/nixos-23.11";
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";

    # agenix = {
    #   url = "github:ryantm/agenix";
    #   inputs.nixpkgs.follows = "nixpkgs";
    # };

    ragenix = {
      url = "github:yaxitech/ragenix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    darwin = {
      url = "github:lnl7/nix-darwin/master";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    home-manager = {
      # url = "github:nix-community/home-manager/release-23.11";
      url = "github:nix-community/home-manager/master";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    hyprland = {
      url = "github:hyprwm/hyprland";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    hyprwm-contrib = {
      url = "github:hyprwm/contrib";
      inputs.nixpkgs.follows = "hyprland";
    };

    hyprland-plugins = {
      url = "github:hyprwm/hyprland-plugins";
      inputs.hyprland.follows = "hyprland";
    };

    vscode-extensions.url = "github:nix-community/nix-vscode-extensions";

  };

  outputs = inputs @ {
    nixpkgs,
    darwin,
    home-manager,
    hyprland-plugins,
    hyprland,
    hyprwm-contrib,
    ragenix,
    vscode-extensions,
    ...
  }: let
    linuxArmSystem = "aarch64-linux";
    darwinSystem = "aarch64-darwin";
    linuxSystem = "x86_64-linux";

    lib = nixpkgs.lib // home-manager.lib;

    darwinPkgs = nixpkgs.legacyPackages.${darwinSystem};
    linuxPkgs = nixpkgs.legacyPackages.${linuxSystem};
    linuxArmPkgs = nixpkgs.legacyPackages.${linuxArmSystem};
  in {
    inherit lib;
    nix.registry.nixpkgs.flake = inputs.nixpkgs;

    formatter.x86_64-linux = (import nixpkgs {system = "x86_64-linux";}).alejandra;
    formatter.aarch64-linux = (import nixpkgs {system = "aarch64-linux";}).alejandra;
    formatter.aarch64-darwin = (import nixpkgs {system = "aarch64-darwin";}).alejandra;

    nixosConfigurations = {
      yuzu = nixpkgs.lib.nixosSystem {
        system = linuxSystem;
        specialArgs = {inherit inputs;}; # forward inputs to modules
        modules = [
          ./hosts/yuzu/configuration.nix
          ragenix.nixosModules.default
          home-manager.nixosModules.home-manager
          {
            home-manager.verbose = true;
            home-manager.useGlobalPkgs = true;
            home-manager.useUserPackages = true;
            home-manager.extraSpecialArgs = {inherit inputs;};
            home-manager.users.ashebanow = import ./hosts/yuzu/home.nix;
          }
        ];
      };

      limon = nixpkgs.lib.nixosSystem {
        system = linuxSystem;
        specialArgs = {inherit inputs;}; # forward inputs to modules
        modules = [
          ./hosts/limon/configuration.nix
          ragenix.nixosModules.default
          home-manager.nixosModules.home-manager
          {
            home-manager.verbose = true;
            home-manager.useGlobalPkgs = true;
            home-manager.useUserPackages = true;
            home-manager.extraSpecialArgs = {inherit inputs;};
            home-manager.users.ashebanow = import ./hosts/limon/home.nix;
          }
        ];
      };

      installerIso = nixpkgs.lib.nixosSystem {
        system = linuxSystem;
        specialArgs = {inherit inputs;};
        modules = [
          ./os/linux/iso-configuration.nix
          ragenix.nixosModules.default
        ];
      };
    };

    darwinConfigurations = {
      miraclemax = darwin.lib.darwinSystem {
        system = darwinSystem;
        specialArgs = {inherit inputs;}; # forward inputs to modules
        modules = [
          ./os/darwin/configuration.nix
          home-manager.darwinModules.home-manager
          {
            home-manager.verbose = true;
            home-manager.useGlobalPkgs = true;
            home-manager.useUserPackages = true;
            home-manager.extraSpecialArgs = {inherit inputs;};
            home-manager.users.ashebanow = import ./os/darwin/home.nix;
          }
        ];
      };
    };

    # this is currently used for the WSL2 install on Liquidity,
    # and for instaling on non-nixOS systems like loquat.
    homeConfigurations = {
      home-manager.verbose = true;
      home-manager.useGlobalPkgs = true;
      home-manager.useUserPackages = true;

      ashebanow = home-manager.lib.homeManagerConfiguration {
        pkgs = linuxPkgs;
        modules = [
          ./os/linux/home.nix
        ];
      };
    };
  };
}
