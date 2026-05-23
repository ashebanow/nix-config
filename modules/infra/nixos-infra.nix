# NixOS infrastructure — host capability flags and base config.
{
  config,
  lib,
  ...
}: {
  # Host capability flags
  my.hostName = "lumquat";
  my.base = true;
  my.baseUsername = "podman";
  my.baseTimezone = "America/Los_Angeles";
  my.llm = true;
  my.llmModelStorage = "/var/lib/llm-models";
  my.access = true;
  my.accessTailnetName = "lumquat";
  my.accessEnableSSH = true;
  my.accessEnableExitNode = false;
  my.accessEnableFallbackSSH = true;
  my.accessFallbackPort = 2222;
  my.monitoring = true;
  my.monitoringPort = 9090;

  # Strix Halo hardware configuration
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
  boot.kernelParams = [
    "amd_iommu=off"
    "amdgpu.gttsize=126976"
    "ttm.pages_limit=32505856"
  ];

  boot.loader = {
    systemd-boot.enable = true;
    efi.canTouchEfiVariables = true;
    efi.efiSysMountPoint = "/boot";
  };

  boot.initrd.luks.devices = {
    luks-root = {
      device = "/dev/disk/by-uuid/YOUR-LUKS-UUID-HERE";
      preLVM = true;
    };
  };

  fileSystems = {
    "/" = {
      device = "/dev/mapper/luks-root";
      fsType = "ext4";
    };
    "/boot" = {
      device = "/dev/disk/by-uuid/YOUR-EFI-UUID-HERE";
      fsType = "vfat";
    };
    "/var/lib/llm-models" = {
      device = "/dev/disk/by-uuid/YOUR-MODELS-UUID-HERE";
      fsType = "ext4";
      options = ["noatime"];
    };
  };

  networking.useDHCP = lib.mkDefault true;
  hardware.graphics.enable = lib.mkDefault true;
  hardware.graphics.enable32Bit = lib.mkDefault true;
  powerManagement.cpuFreqGovernor = lib.mkDefault "powersave";
  nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";
}
