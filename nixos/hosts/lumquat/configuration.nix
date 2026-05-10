{
  inputs,
  self,
  lib,
  ...
}: {
  flake.nixosConfigurations.lumquat = inputs.nixpkgs.lib.nixosSystem {
    modules = [
      self.nixosModules.hostLumquat
    ];
  };

  flake.nixosModules.hostLumquat = {pkgs, ...}: {
    imports = [
      self.nixosModules.base
      self.nixosModules.general
      self.nixosModules.desktop   # TODO: REMOVE once ssh is set up and secured

      self.nixosModules.tailscale

      self.nixosModules.powersave
    ];

    boot.loader.systemd-boot.enable = true;
    boot.loader.efi.canTouchEfiVariables = true;

    networking.hostName = "lumquat";

    networking.networkmanager.enable = true;

    programs.niri.enable = true;
    programs.niri.package = self.packages.${pkgs.system}.niri;

    boot.kernelPackages = pkgs.linuxPackages_latest;

    system.stateVersion = "25.11";
  };
}
