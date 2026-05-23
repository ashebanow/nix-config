{
  description = "Lumquat NixOS Configuration - AI Server";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";

    # Flake framework for devShells
    flake-parts.url = "github:hercules-ci/flake-parts";

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

  outputs = inputs @ {
    flake-parts,
    nixpkgs,
    ...
  }: let
    lib = nixpkgs.lib;
    system = "x86_64-linux";

    # Import all feature modules
    baseFeature = import ./modules/features/base.nix;
    accessFeature = import ./modules/features/access.nix;
    llmFeature = import ./modules/features/llm.nix;
    monitoringFeature = import ./modules/features/monitoring.nix;
    secretsFeature = import ./modules/features/secrets.nix;
    cliToolsFeature = import ./modules/features/cli-tools.nix;

    # Collect NixOS deferred modules from feature registrations
    deferredNixosModules = lib.attrValues (
      (baseFeature.my.modules.nixos or {})
      // (accessFeature.my.modules.nixos or {})
      // (llmFeature.my.modules.nixos or {})
      // (monitoringFeature.my.modules.nixos or {})
      // (secretsFeature.my.modules.nixos or {})
    );

    # Collect Home Manager deferred modules
    deferredHmModules = lib.attrValues (cliToolsFeature.my.modules.home-manager or {});

    # Base infrastructure modules
    baseModules = [
      ./lib/my-options-module.nix
      inputs.sops-nix.nixosModules.sops
      inputs.nixos-hardware.nixosModules.common-cpu-amd
      ./modules/infra/nixos-infra.nix
    ];
  in
    flake-parts.lib.mkFlake {inherit inputs;} {
      imports = [
        ./modules/infra/devshell.nix
      ];

      systems = ["x86_64-linux" "aarch64-darwin"];

      # NixOS host configuration
      flake.nixosConfigurations.lumquat = nixpkgs.lib.nixosSystem {
        inherit system;
        specialArgs = {inherit inputs;};
        modules = baseModules ++ deferredNixosModules;
      };

      # Home Manager for podman user
      flake.homeManagerConfigurations.podman = inputs.home-manager.lib.homeManagerConfiguration {
        pkgs = import nixpkgs {inherit system;};
        modules =
          [
            inputs.home-manager.nixosModules.home-manager
            {
              home-manager = {
                backupFileExtension = "backup";
                useGlobalPkgs = true;
                useUserPackages = true;
              };
            }
            ./lib/my-options-module.nix
            ./modules/infra/hm-infra.nix
          ]
          ++ deferredHmModules;
      };
    };
}
