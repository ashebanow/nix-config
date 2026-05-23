# NixOS infrastructure — composes deferred modules and defines hosts.
# Imported by flake-parts, this module sets up the NixOS configuration.
{
  inputs,
  config,
  lib,
  ...
}: let
  inherit (inputs) sops-nix nixos-hardware home-manager;

  # deferredModule fragments contributed by feature modules
  deferredNixosModules = builtins.attrValues config.my.modules.nixos;
  deferredHmModules = builtins.attrValues config.my.modules.home-manager;

  # Hardware configuration as inline module
  lumquatHardware = {
    config,
    ...
  }: {
    boot.initrd.availableKernelModules = [
      "ahci" "xhci_pci" "usb_storage" "usbhid" "sd_mod"
      "amdgpu" "radeon" "nouveau"
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
  };

  # Host capability flags
  lumquatHost = {
    config,
    ...
  }: {
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
  };

  # Home Manager config for podman user
  lumquatHm = {
    config,
    ...
  }: {
    my.cliTools = true;
  };
in {
  # Expose deferred modules
  flake.nixosModules = config.my.modules.nixos;
  flake.homeManagerModules = config.my.modules.home-manager;

  # NixOS configuration
  flake.nixosConfigurations.lumquat = inputs.nixpkgs.lib.nixosSystem {
    system = "x86_64-linux";
    specialArgs = {inherit inputs;};
    modules = [
      ./module-containers.nix
      (import ../../lib/my-options-module.nix)
      sops-nix.nixosModules.sops
      nixos-hardware.nixosModules.common-cpu-amd
      lumquatHardware
      lumquatHost
    ] ++ deferredNixosModules;
  };

  # Home Manager configuration
  flake.homeManagerConfigurations.podman = home-manager.lib.homeManagerConfiguration {
    pkgs = import inputs.nixpkgs {system = "x86_64-linux";};
    modules = [
      home-manager.nixosModules.home-manager
      {
        home-manager = {
          backupFileExtension = "backup";
          useGlobalPkgs = true;
          useUserPackages = true;
        };
      }
      (import ../../lib/my-options-module.nix)
      ./module-containers.nix
      lumquatHm
    ] ++ deferredHmModules;
  };
}
