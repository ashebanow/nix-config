{
  description = "ashebanow's way-too-complicated nix configuration";

  nixConfig = {
    experimental-features = ["nix-command" "flakes"];
    substituters = [
      "https://cache.nixos.org/"
    ];

    extra-substituters = [
      "https://cattivi-public.cachix.org"
      "https://hyprland.cachix.org"
    ];
    extra-trusted-public-keys = [
      "cattivi-public.cachix.org-1:qQQ8FHPoEibPtL1FTZTmVbUL78KW2zCRk+LZPsRiwQ4="
      "hyprland.cachix.org-1:a7pgxzMz7+chwVL3/pzj6jIBMioiJM7ypFP8PwtkuGc="
    ];
  };

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
      inputs.nixpkgs.follows = "nixpkgs";
    };

    hyprland-plugins = {
      url = "github:hyprwm/hyprland-plugins";
      inputs.hyprland.follows = "hyprland";
    };

    nixos-hardware.url = "github:NixOS/nixos-hardware";
  };

  outputs = inputs @ {
    nixpkgs,
    home-manager,
    darwin,
    # agenix,
    ragenix,
    hyprland,
    hyprland-plugins,
    hyprwm-contrib,
    nixos-hardware,
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
          home-manager.nixosModules.home-manager
          {
            home-manager.verbose = true;
            home-manager.useGlobalPkgs = true;
            home-manager.useUserPackages = true;
            home-manager.users.ashebanow = import ./hosts/yuzu/home.nix;
          }
        ];
      };
      limon = nixpkgs.lib.nixosSystem {
        system = linuxSystem;
        specialArgs = {inherit inputs;}; # forward inputs to modules
        modules = [
          ./hosts/limon/configuration.nix
          home-manager.nixosModules.home-manager
          {
            home-manager.verbose = true;
            home-manager.useGlobalPkgs = true;
            home-manager.useUserPackages = true;
            home-manager.users.ashebanow = import ./hosts/limon/home.nix;
          }
        ];
      };
      liquid-nixos = nixpkgs.lib.nixosSystem {
        system = linuxSystem;
        specialArgs = {inherit inputs;}; # forward inputs to modules
        modules = [
          ./hosts/liquid-nixos/configuration.nix
          home-manager.nixosModules.home-manager
          {
            home-manager.verbose = true;
            home-manager.useGlobalPkgs = true;
            home-manager.useUserPackages = true;
            home-manager.users.ashebanow = import ./hosts/liquid-nixos/home.nix;
          }
        ];
      };
      nixos-mac-aarch64 = nixpkgs.lib.nixosSystem {
        system = linuxSystem;
        specialArgs = {inherit inputs;}; # forward inputs to modules
        modules = [
          ./hosts/nixos-mac-aarch64/configuration.nix
          home-manager.nixosModules.home-manager
          {
            home-manager.verbose = true;
            home-manager.useGlobalPkgs = true;
            home-manager.useUserPackages = true;
            home-manager.users.ashebanow = import ./os/linux/home.nix;
          }
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
