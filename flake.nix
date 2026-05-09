{
  description = "ashebanow's way-too-complicated nix configuration";

  inputs = {
    nixpkgs-stable.url = "github:nixos/nixpkgs/nixos-24.11";
    nixpkgs-unstable.url = "github:nixos/nixpkgs/nixos-unstable";
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";

    agenix = {
      url = "github:ryantm/agenix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    catppuccin.url = "github:catppuccin/nix";

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

    # nix-inspect.url = "github:bluskript/nix-inspect";

    nixos-wsl.url = "github:nix-community/NixOS-WSL/main";

    nur-packages = {
      url = "github:nix-community/NUR";
      # inputs.nixpkgs.follows = "nixpkgs";
    };

    vscode-extensions = {
      url = "github:nix-community/nix-vscode-extensions";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = {
    self,
    agenix,
    catppuccin,
    darwin,
    home-manager,
    hyprland,
    hyprland-plugins,
    hyprwm-contrib,
    # nix-inspect,
    nur-packages,
    nixpkgs,
    nixos-wsl,
    vscode-extensions,
    ...
  } @ inputs: let
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
        specialArgs = {inherit inputs;};
        modules = [
          ./hosts/yuzu/configuration.nix
          agenix.nixosModules.default
          catppuccin.nixosModules.catppuccin
          nur-packages.nixosModules.nur
          home-manager.nixosModules.home-manager
          {
            home-manager.verbose = true;
            home-manager.useGlobalPkgs = true;
            home-manager.useUserPackages = true;
            home-manager.extraSpecialArgs = {inherit inputs;};

            home-manager.users.ashebanow = {
              imports = [
                ./hosts/yuzu/home.nix
                catppuccin.homeManagerModules.catppuccin
                nur-packages.hmModules.nur
              ];
            };
          }
        ];
      };

      limon = nixpkgs.lib.nixosSystem {
        system = linuxSystem;
        specialArgs = {inherit inputs;}; # forward inputs to modules
        modules = [
          ./hosts/limon/configuration.nix
          agenix.nixosModules.default
          catppuccin.nixosModules.catppuccin
          nur-packages.nixosModules.nur
          home-manager.nixosModules.home-manager
          {
            home-manager.verbose = true;
            home-manager.useGlobalPkgs = true;
            home-manager.useUserPackages = true;
            home-manager.extraSpecialArgs = {inherit inputs;};

            home-manager.users.ashebanow = {
              imports = [
                ./hosts/limon/home.nix
                catppuccin.homeManagerModules.catppuccin
                nur-packages.hmModules.nur
              ];
            };
          }
        ];
      };


      NixOS-WSL = nixpkgs.lib.nixosSystem {
        system = linuxSystem;
        specialArgs = {inherit inputs;}; # forward inputs to modules
        modules = [
          ./hosts/nixos-wsl/configuration.nix
          agenix.nixosModules.default
          catppuccin.nixosModules.catppuccin
          nur-packages.nixosModules.nur
          nixos-wsl.nixosModules.default
          {
            system.stateVersion = "24.05";
            wsl.enable = true;
            wsl.defaultUser = "ashebanow";
            wsl.interop.register = true;
            wsl.docker-desktop.enable = true;
          }
          home-manager.nixosModules.home-manager
          {
            home-manager.verbose = true;
            home-manager.useGlobalPkgs = true;
            home-manager.useUserPackages = true;
            home-manager.extraSpecialArgs = {inherit inputs;};

            home-manager.users.ashebanow = {
              imports = [
                ./hosts/nixos-wsl/home.nix
                catppuccin.homeManagerModules.catppuccin
                nur-packages.hmModules.nur
              ];
            };
          }
        ];
      };

      installerIso = nixpkgs.lib.nixosSystem {
        system = linuxSystem;
        specialArgs = {inherit inputs;};
        modules = [
          ./os/linux/iso-configuration.nix
          agenix.nixosModules.default
          nur-packages.nixosModules.nur
        ];
      };
    };

    darwinConfigurations = {
      miraclemax = darwin.lib.darwinSystem {
        system = darwinSystem;
        specialArgs = {inherit inputs;}; # forward inputs to modules
        modules = [
          ./os/darwin/configuration.nix
          agenix.darwinModules.default
          home-manager.darwinModules.home-manager
          {
            home-manager.verbose = true;
            home-manager.useGlobalPkgs = true;
            home-manager.useUserPackages = true;
            home-manager.extraSpecialArgs = {inherit inputs;};

            home-manager.users.ashebanow = {
              imports = [
                ./os/darwin/home.nix
                catppuccin.homeManagerModules.catppuccin
              ];
            };
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
          catppuccin.homeManagerModules.catppuccin
        ];
      };
    };
  };
}
