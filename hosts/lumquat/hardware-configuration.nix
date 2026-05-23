# Lumquat hardware configuration — GMKTec Evo X2 (Strix Halo).
# AMD Ryzen AI Max with 128GB unified memory, RDNA 3.5 GPU.
# LUKS-encrypted root with systemd-boot.
{
  config,
  lib,
  pkgs,
  modulesPath,
  ...
}: {
  imports = [
    (modulesPath + "/profiles/base.nix")
  ];

  boot.initrd.availableKernelModules = [
    "ahci" "xhci_pci" "usb_storage" "usbhid" "sd_mod"
    "amdgpu" "radeon" "nouveau"
  ];
  boot.initrd.kernelModules = ["amdgpu"];
  boot.kernelModules = [];
  boot.kernelParams = [
    # Required for Strix Halo stability
    "amd_iommu=off"
    # Expose ~124 GB VRAM to GPU
    "amdgpu.gttsize=126976"
    # Allow TTM to use full memory pool
    "ttm.pages_limit=32505856"
  ];

  boot.loader = {
    systemd-boot.enable = true;
    efi.canTouchEfiVariables = true;
    efi.efiSysMountPoint = "/boot";
  };

  # LUKS-encrypted root
  boot.initrd.luks.devices = {
    luks-root = {
      device = "/dev/disk/by-uuid/YOUR-LUKS-UUID-HERE";
      preLVM = true;
    };
  };

  # Root file system (on LUKS)
  fileSystems."/" = {
    device = "/dev/mapper/luks-root";
    fsType = "ext4";
  };

  # EFI partitions
  fileSystems."/boot" = {
    device = "/dev/disk/by-uuid/YOUR-EFI-UUID-HERE";
    fsType = "vfat";
  };

  # Model storage
  fileSystems."/var/lib/llm-models" = {
    device = "/dev/disk/by-uuid/YOUR-MODELS-UUID-HERE";
    fsType = "ext4";
    options = ["noatime"];
  };

  # Networking
  networking.useDHCP = lib.mkDefault true;

  # AMD GPU
  hardware.graphics.enable = lib.mkDefault true;
  hardware.graphics.enable32Bit = lib.mkDefault true;

  # AMD CPU/Power
  powerManagement.cpuFreqGovernor = lib.mkDefault "powersave";

  # Nixpkgs system configuration
  nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";
}
