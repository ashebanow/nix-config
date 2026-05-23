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

    # Import all feature modules
    baseFeature = import ./modules/features/base.nix;
    accessFeature = import ./modules/features/access.nix;
    llmFeature = import ./modules/features/llm.nix;
    monitoringFeature = import ./modules/features/monitoring.nix;
    secretsFeature = import ./modules/features/secrets.nix;
    cliToolsFeature = import ./modules/features/cli-tools.nix;
  in
  {
    # NixOS host configurations
    nixosConfigurations.lumquat = nixpkgs.lib.nixosSystem {
      inherit system;
      specialArgs = {inherit inputs;};
      modules = [
        # Base infrastructure
        ./lib/my-options-module.nix
        inputs.sops-nix.nixosModules.sops
        inputs.nixos-hardware.nixosModules.common-cpu-amd

        # Feature modules
        baseFeature
        accessFeature
        llmFeature
        monitoringFeature
        secretsFeature

        # Host configuration
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
        cliToolsFeature
        ./hosts/lumquat/hm-configuration.nix
      ];
    };
  };
}
