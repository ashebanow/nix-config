{
  description = "ashebanow's way-too-complicated nix configuration";

  nixConfig = {
    experimental-features = [ "nix-command" "flakes" ];
    substituters = [
      "https://cache.nixos.org/"
    ];

    extra-substituters = [
      "https://cattivi-public.cachix.org"
    ];
    extra-trusted-public-keys = [
      "cattivi-public.cachix.org-1:qQQ8FHPoEibPtL1FTZTmVbUL78KW2zCRk+LZPsRiwQ4="
    ];
  };

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-23.11";

    darwin = {
      url = "github:lnl7/nix-darwin/master";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    home-manager = {
      url = "github:nix-community/home-manager/release-23.11";
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

    sops-nix = {
      url = "github:Mic92/sops-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = inputs@{ nixpkgs, home-manager, darwin, ... }:
    let
      linuxArmSystem = "aarch64-linux";
      darwinSystem = "aarch64-darwin";
      linuxSystem = "x86_64-linux";

      lib = nixpkgs.lib // home-manager.lib;

      darwinPkgs = nixpkgs.legacyPackages.${darwinSystem};
      linuxPkgs = nixpkgs.legacyPackages.${linuxSystem};
    in
    {
      inherit lib;
      nix.registry.nixpkgs.flake = inputs.nixpkgs;

      nixosConfigurations = {
        loquat = nixpkgs.lib.nixosSystem {
          system = linuxSystem;
          specialArgs = { inherit inputs; }; # forward inputs to modules
          modules = [
            ./hosts/loquat/configuration.nix
            home-manager.nixosModules.home-manager {
              home-manager.verbose = true;
              home-manager.useGlobalPkgs = true;
              home-manager.useUserPackages = true;
              home-manager.users.ashebanow = import ./hosts/loquat/home.nix;
            }
          ];
        };
        yuzu = nixpkgs.lib.nixosSystem {
          system = linuxSystem;
          specialArgs = { inherit inputs; }; # forward inputs to modules
          modules = [
            ./hosts/yuzu/configuration.nix
            home-manager.nixosModules.home-manager {
              home-manager.verbose = true;
              home-manager.useGlobalPkgs = true;
              home-manager.useUserPackages = true;
              home-manager.users.ashebanow = import ./hosts/yuzu/home.nix;
            }
          ];
        };
        liquid-nixos = nixpkgs.lib.nixosSystem {
          system = linuxSystem;
          specialArgs = { inherit inputs; }; # forward inputs to modules
          modules = [
            ./hosts/liquid-nixos/configuration.nix
            home-manager.nixosModules.home-manager {
              home-manager.verbose = true;
              home-manager.useGlobalPkgs = true;
              home-manager.useUserPackages = true;
              home-manager.users.ashebanow = import ./hosts/liquid-nixos/home.nix;
            }
          ];
        };
        nixos-mac-aarch64 = nixpkgs.lib.nixosSystem {
          system = linuxSystem;
          specialArgs = { inherit inputs; }; # forward inputs to modules
          modules = [
            ./hosts/nixos-mac-aarch64/configuration.nix
            home-manager.nixosModules.home-manager {
              home-manager.verbose = true;
              home-manager.useGlobalPkgs = true;
              home-manager.useUserPackages = true;
              home-manager.users.ashebanow = import ./os/linux/home.nix;
            }
          ];
        };
        virt1 = nixpkgs.lib.nixosSystem {
          system = linuxSystem;
          specialArgs = { inherit inputs; }; # forward inputs to modules
          modules = [
            ./hosts/virt1/configuration.nix
            home-manager.nixosModules.home-manager
            {
              home-manager.verbose = true;
              home-manager.useGlobalPkgs = true;
              home-manager.useUserPackages = true;
              home-manager.users.ashebanow = import ./os/linux/home.nix;

              # Optionally, use home-manager.extraSpecialArgs to pass
              # arguments to home.nix
            }
          ];
        };
        virt2 = nixpkgs.lib.nixosSystem {
          system = linuxSystem;
          specialArgs = { inherit inputs; }; # forward inputs to modules
          modules = [
            ./hosts/virt2/configuration.nix
            home-manager.nixosModules.home-manager {
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
          specialArgs = { inherit inputs; }; # forward inputs to modules
          modules = [
            ./os/darwin/configuration.nix
            home-manager.darwinModules.home-manager {
              home-manager.verbose = true;
              home-manager.useGlobalPkgs = true;
              home-manager.useUserPackages = true;
              home-manager.users.ashebanow = import ./os/darwin/home.nix;
            }
            # sops-nix.nixosModules.sops
          ];
        };
      };

      # this is currently used only for the WSL2 install on Liquidity,
      # but we could end up using it on other non-nixOS linux systems
      # later. (e.g. harvester nodes)
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
