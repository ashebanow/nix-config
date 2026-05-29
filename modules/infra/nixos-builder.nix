# NixOS builder — collects deferred modules from feature modules
# (populated via import-tree) and builds flake.nixosConfigurations.
{
  inputs,
  config,
  lib,
  ...
}: let
  inherit (inputs) sops-nix nixos-hardware home-manager;
  system = "x86_64-linux";

  # Collect deferred modules registered by feature modules
  deferredNixosModules = builtins.attrValues config.my.modules.nixos;
  deferredHmModules = builtins.attrValues config.my.modules.home-manager;

  # Base NixOS modules included in every host
  baseModules = [
    ../../lib/my-options-module.nix
    sops-nix.nixosModules.sops
    nixos-hardware.nixosModules.common-cpu-amd
    ../../hosts/lumquat/configuration.nix
    ../../hosts/lumquat/hardware-configuration.nix
  ];
  # Build the NixOS config, then override `type` to a string.
  # flake-parts expects nixosConfigurations.<name>.type to be a string (the system),
  # but nixosSystem in newer nixpkgs returns type as an attrset.
  nixosConfig = inputs.nixpkgs.lib.nixosSystem {
    inherit system;
    specialArgs = {inherit inputs;};
    modules = baseModules ++ deferredNixosModules;
  };
in {
  flake = {
    # NixOS host configuration
    nixosConfigurations.lumquat = nixosConfig // {type = system;};

    # Home Manager for podman user
    homeConfigurations.podman = home-manager.lib.homeManagerConfiguration {
      pkgs = import inputs.nixpkgs {
        inherit system;
        config.allowUnfree = true;
      };
      modules =
        [
          {
            home-manager = {
              backupFileExtension = "backup";
              useGlobalPkgs = true;
              useUserPackages = true;
            };
          }
          ../../lib/my-options-module.nix
          ./hm-infra.nix
        ]
        ++ deferredHmModules;
    };
  };
}
