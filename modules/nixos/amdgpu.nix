{
  config,
  lib,
  pkgs,
  inputs,
  ...
}: {
  boot.initrd.kernelModules = ["amdgpu"];
  services.xserver.videoDrivers = ["amdgpu"];

  hardware = {
    opengl = with pkgs; {
      # this fixes the "glXChooseVisual failed" bug, context:
      # https://github.com/NixOS/nixpkgs/issues/47932
      enable = true;
      driSupport = true;
      driSupport32Bit = true;
      extraPackages =
        if pkgs ? rocmPackages.clr
        then with pkgs.rocmPackages; [clr clr.icd amdvlk]
        else with pkgs; [rocm-opencl-icd rocm-opencl-runtime];
      # For 32 bit applications
      extraPackages32 = [
        driversi686Linux.amdvlk
      ];
    };
  };
}
