# Lumquat hardware configuration — Strix Halo (GMKTec Evo X2).
# Carefully maintained; hardware changes must be reflected here.
{ config, lib, pkgs, modulesPath, ... }:

{
  imports =
    [ (modulesPath + "/installer/scan/not-detected.nix")
    ];

  # Initrd modules for AMD GPU and storage
  boot.initrd.availableKernelModules = [
    "nvme"
    "xhci_pci"
    "thunderbolt"
    "usbhid"
    "usb_storage"
    "sd_mod"
    "sr_mod"
    "sdhci_pci"
    "ahci"
    "amdgpu"
    "radeon"
  ];
  boot.initrd.kernelModules = ["amdgpu"];
  boot.kernelModules = [ "kvm-amd" ];
  boot.extraModulePackages = [ ];

  # Strix Halo kernel params for LLM GPU passthrough
  # See: https://github.com/hellas-ai/nix-strix-halo
  boot.kernelParams = [
    "amd_iommu=off" # Required for Strix Halo stability
    "amdgpu.gttsize=126976" # Expose ~124 GB VRAM to GPU
    "ttm.pages_limit=32505856" # Full memory pool for TTM
  ];

  # systemd-boot on EFI
  boot.loader = {
    systemd-boot.enable = true;
    efi.canTouchEfiVariables = true;
    efi.efiSysMountPoint = "/boot";
  };

  # LUKS-encrypted root
  boot.initrd.luks.devices = {
    luks-root = {
      device = "/dev/disk/by-uuid/2363ecb6-9c4e-4c6a-a948-1e5e24089470";
      preLVM = true;
    };
  };

  # Filesystems
  fileSystems = {
    "/" = {
      device = "/dev/mapper/luks-root";
      fsType = "ext4";
    };
    "/boot" = {
      device = "/dev/disk/by-uuid/179f8938-930f-4315-8c24-c8ce290d9165";
      fsType = "vfat";
    };
  };

  swapDevices = [ ];

  nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";
  hardware.cpu.amd.updateMicrocode = lib.mkDefault config.hardware.enableRedistributableFirmware;

  # AMD GPU
  hardware.graphics.enable = lib.mkDefault true;
  hardware.graphics.enable32Bit = lib.mkDefault true;
}
