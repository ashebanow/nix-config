# Yuzu hardware configuration.
# Started from ‘nixos-generate-config’ output, then hand-maintained: the r8169
# suspend/resume workaround at the bottom is ours and must be preserved if the
# generated parts are ever refreshed.
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

  boot.initrd.availableKernelModules = ["xhci_pci" "nvme" "thunderbolt" "usbhid" "usb_storage" "sd_mod"];
  boot.initrd.kernelModules = [];
  boot.kernelModules = ["kvm-amd"];
  boot.extraModulePackages = [];

  fileSystems."/" = {
    device = "/dev/disk/by-uuid/dd71e1c7-d100-48cc-862f-5dc99048cad5";
    fsType = "ext4";
  };

  fileSystems."/boot" = {
    device = "/dev/disk/by-uuid/E491-595B";
    fsType = "vfat";
    options = ["fmask=0077" "dmask=0077"];
  };

  swapDevices = [
    {device = "/dev/disk/by-uuid/01fd054b-c305-475a-ae98-6d910a31f531";}
  ];

  nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";
  # Redistributable firmware — linux-firmware (incl. the RTL8125 blobs, which
  # r8169 needs) and amd-microcode. The not-detected.nix import above already
  # sets this to mkDefault true, but this file is hand-maintained: if that
  # generated import is ever dropped, firmware — and therefore microcode — would
  # silently turn off. State it explicitly so it cannot.
  hardware.enableRedistributableFirmware = true;
  hardware.cpu.amd.updateMicrocode = lib.mkDefault config.hardware.enableRedistributableFirmware;

  # ── r8169 (Realtek RTL8125) suspend/resume workaround ───────────────
  # The 2.5GbE NIC does not re-establish its link after a suspend/resume cycle
  # (kernel.org bug 204079): the device comes back wedged, NetworkManager never
  # gets a DHCP lease, and Tailscale loses its path until the module is
  # reloaded. Runs on resume via NixOS's sleep-actions.service — this nixpkgs
  # has no post-resume.target. Stopping NetworkManager first is what lets
  # `modprobe -r` release the still-up device.
  powerManagement.resumeCommands = ''
    ${pkgs.systemd}/bin/systemctl stop NetworkManager.service || true
    ${pkgs.kmod}/bin/modprobe -r r8169 || true
    ${pkgs.kmod}/bin/modprobe r8169 || true
    ${pkgs.systemd}/bin/systemctl start NetworkManager.service || true
    ${pkgs.systemd}/bin/systemctl try-restart tailscaled.service || true
  '';
}
