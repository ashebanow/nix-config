# Lumquat hardware configuration — Strix Halo (GMKTec Evo X2).
# Host-specific: every host gets its own hardware-configuration.nix.
{lib, ...}: {
  # Initrd modules for AMD GPU and storage
  boot.initrd.availableKernelModules = [
    "ahci"
    "xhci_pci"
    "usb_storage"
    "usbhid"
    "sd_mod"
    "amdgpu"
    "radeon"
    "nouveau"
  ];
  boot.initrd.kernelModules = ["amdgpu"];
  boot.kernelModules = [];

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

  # Filesystems (fill in UUIDs before deployment)
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

  # AMD GPU
  hardware.graphics.enable = lib.mkDefault true;
  hardware.graphics.enable32Bit = lib.mkDefault true;
}
