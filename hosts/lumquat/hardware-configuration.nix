# Lumquat hardware configuration — Strix Halo (GMKTec Evo X2).
# Carefully maintained; hardware changes must be reflected here.
{
  config,
  lib,
  pkgs,
  modulesPath,
  ...
}: {
  imports = [
    (modulesPath + "/installer/scan/not-detected.nix")
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
  boot.kernelModules = ["kvm-amd"];
  boot.extraModulePackages = [];

  # Strix Halo kernel params for LLM GPU passthrough
  # See: https://github.com/hellas-ai/nix-strix-halo
  #
  # Memory layout (unified CPU+GPU, ~124 GB usable of 128 GB):
  #   - vis_vramlimit: 100 GB reported to ROCm/llama.cpp
  #   - ttm.pages_limit: 106 GB TTM-managed pool
  #   - OS reserve: ~22 GB (safe for containers + system)
  #
  # Model budget: qwen Q8 256K (~89 GB). 100 GB GPU + 6 GB TTM headroom.
  # Remaining GPU headroom: ~13 GB for KV cache bursts / future growth
  #
  # vis_vramlimit overrides the incorrect 64 GB VRAM reporting.
  # 100 GB = 102,400 MiB. 106 GB = 27,787,264 pages (4 KB each).
  boot.kernelParams = [
    "amd_iommu=off" # Required for Strix Halo stability
    "ttm.pages_limit=27787264" # 106 GB / 4 KB
    "amdgpu.vis_vramlimit=102400" # 100 GB visible VRAM
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
      device = "/dev/disk/by-uuid/8A6E-4E07";
      fsType = "vfat";
    };
  };

  swapDevices = [];

  nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";
  hardware.cpu.amd.updateMicrocode = lib.mkDefault config.hardware.enableRedistributableFirmware;

  # AMD GPU
  hardware.graphics.enable = lib.mkDefault true;
  hardware.graphics.enable32Bit = lib.mkDefault true;
}
