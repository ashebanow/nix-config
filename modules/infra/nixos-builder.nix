# NixOS builder — collects deferred modules from feature modules
# (populated via import-tree) and builds flake.nixosConfigurations.
{
  inputs,
  config,
  lib,
  ...
}: let
  inherit (inputs) sops-nix nixos-hardware home-manager determinate;
  system = "x86_64-linux";

  # Collect deferred modules registered by feature modules
  deferredNixosModules = builtins.attrValues config.my.modules.nixos;
  deferredHmModules = builtins.attrValues config.my.modules.home-manager;

  # Base NixOS modules included in every host
  baseModules = [
    ../../lib/my-options-module.nix
    sops-nix.nixosModules.sops
    nixos-hardware.nixosModules.common-cpu-amd
    home-manager.nixosModules.home-manager
    determinate.nixosModules.default
    ../../hosts/lumquat/configuration.nix
    ../../hosts/lumquat/hardware-configuration.nix
    ./remote-builder.nix
    # Wire home-manager into NixOS activation so
    # nixos-rebuild switch applies it for the podman user.
    {
      home-manager.users.podman = {
        imports =
          [
            {
              home.username = "podman";
              home.homeDirectory = "/home/podman";
              home.stateVersion = "26.05";
            }
            ../../lib/my-options-module.nix
            ./hm-infra.nix
          ]
          ++ deferredHmModules;
      };
    }
  ];

  # Build the NixOS config, then override `type` to a string.
  # flake-parts expects nixosConfigurations.<name>.type to be a string (the system),
  # but nixosSystem in newer nixpkgs returns type as an attrset.
  nixosConfig = inputs.nixpkgs.lib.nixosSystem {
    inherit system;
    specialArgs = {inherit inputs;};
    modules = baseModules ++ deferredNixosModules;
  };

  # Same treatment for Home Manager — newer nixpkgs returns type as an attrset.
  homeConfig = home-manager.lib.homeManagerConfiguration {
    pkgs = import inputs.nixpkgs {
      inherit system;
      config.allowUnfree = true;
    };
    modules =
      [
        {
          home.username = "podman";
          home.homeDirectory = "/home/podman";
          home.stateVersion = "26.05";
        }
        ../../lib/my-options-module.nix
        ./hm-infra.nix
      ]
      ++ deferredHmModules;
  };
in {
  flake = {
    nixosConfigurations.lumquat = nixosConfig // {type = system;};
    homeConfigurations.podman = homeConfig // {type = system;};
  };
}
