{
  description = "Lumquat NixOS Configuration - AI Server";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";

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

  outputs = inputs @ {nixpkgs, ...}: let
    system = "x86_64-linux";
    lib = nixpkgs.lib;

    # Import and evaluate feature modules
    baseFeature = (import ./modules/features/base.nix) (_: {});
    accessFeature = (import ./modules/features/access.nix) (_: {});
    llmFeature = (import ./modules/features/llm.nix) (_: {});
    monitoringFeature = (import ./modules/features/monitoring.nix) (_: {});
    secretsFeature = (import ./modules/features/secrets.nix) (_: {});
    cliToolsFeature = (import ./modules/features/cli-tools.nix) (_: {});

    # Collect NixOS deferred modules from feature registrations
    deferredNixosModules = lib.attrValues (
      baseFeature.my.modules.nixos
      // accessFeature.my.modules.nixos
      // llmFeature.my.modules.nixos
      // monitoringFeature.my.modules.nixos
      // secretsFeature.my.modules.nixos
    );

    # Collect Home Manager deferred modules
    deferredHmModules = lib.attrValues (
      cliToolsFeature.my.modules.home-manager or {}
    );

    # Base infrastructure modules
    baseModules = [
      ./lib/my-options-module.nix
      inputs.sops-nix.nixosModules.sops
      inputs.nixos-hardware.nixosModules.common-cpu-amd
    ];
  in
  {
    # NixOS host configurations
    nixosConfigurations.lumquat = nixpkgs.lib.nixosSystem {
      inherit system;
      specialArgs = {inherit inputs;};
      modules = baseModules
        ++ deferredNixosModules
        ++ [
          ./hosts/lumquat.nix
          ./hosts/lumquat/hardware-configuration.nix
        ];
    };

    # Home Manager for podman user
    home-managerConfigurations.podman = inputs.home-manager.lib.homeManagerConfiguration {
      pkgs = import nixpkgs {inherit system;};
      modules = [
        inputs.home-manager.nixosModules.home-manager
        {
          home-manager = {
            backupFileExtension = "backup";
            useGlobalPkgs = true;
            useUserPackages = true;
          };
        }
        ./lib/my-options-module.nix
        ./hosts/lumquat/hm-configuration.nix
      ] ++ deferredHmModules;
    };
  };
}
