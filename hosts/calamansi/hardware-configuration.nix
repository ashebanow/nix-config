# ============================================================================
# PLACEHOLDER — NOT THIS MACHINE'S REAL HARDWARE CONFIGURATION.
#
# This file exists so that `nixosConfigurations.calamansi` evaluates and builds
# before calamansi is reinstalled. It is REPLACED, not maintained: at install
# time (BOX-324) `nixos-generate-config` writes the real file from the machine's
# detected disks, filesystems and CPU, and that output is committed over this
# one. Nothing here is verified against the physical machine.
#
# Assumptions baked into the placeholder (change them with the real file, not
# by editing this one):
#   * x86_64-linux.
#   * A single disk, GPT-partitioned.
#   * An EFI system partition at /boot (vfat) and one ext4 root.
#   * No LUKS and no TPM2 enrollment — the real install decides both.
#   * The UUIDs below are placeholders. They do NOT refer to real filesystems,
#     so a system built from this file cannot boot.
#
# Machine facts this file does *not* record (they are properties of the
# hardware, not the config): 2 TB SSD (~1.8 TB usable after a bare NixOS
# install) and 64 GB RAM. See BOX-311.
# ============================================================================
{
  lib,
  modulesPath,
  ...
}:
{
  imports = [
    (modulesPath + "/installer/scan/not-detected.nix")
  ];

  boot.initrd.availableKernelModules = [
    "nvme"
    "xhci_pci"
    "usbhid"
    "usb_storage"
    "sd_mod"
  ];
  boot.initrd.kernelModules = [ ];
  boot.kernelModules = [ ];
  boot.extraModulePackages = [ ];

  # Boot loader, not hardware: systemd-boot on the EFI system partition at
  # /boot, matching the assumed layout. Declared here rather than in
  # configuration.nix because it follows from the partition scheme above — the
  # real generated file brings its own `boot.loader` section, and keeping the
  # two together means this placeholder never disagrees with itself.
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  # Placeholder partitions on the single disk: /boot is the EFI system
  # partition, / the ext4 root. Replace with the real by-uuid devices.
  fileSystems."/" = {
    device = "/dev/disk/by-uuid/00000000-0000-0000-0000-000000000001";
    fsType = "ext4";
  };

  fileSystems."/boot" = {
    device = "/dev/disk/by-uuid/0000-0001";
    fsType = "vfat";
    options = [
      "fmask=0077"
      "dmask=0077"
    ];
  };

  # No swap device: a plain file or zram choice belongs to the real install.
  swapDevices = [ ];

  nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";
}
