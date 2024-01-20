{ config, pkgs, ... }:

{
  # Enable dconf (System Management Tool)
  programs.dconf.enable = true;

  services.qemuGuest.enable = true;

  # Install necessary packages
  environment.systemPackages = with pkgs; [
    virt-manager
    virt-viewer
    spice spice-gtk
    spice-protocol
    win-virtio
    win-spice
    gnome.adwaita-icon-theme
  ];

  # Manage the virtualisation services
  virtualisation = {
    libvirtd = {
      enable = true;
      qemu = {
        swtpm.enable = true;
        ovmf.enable = true;
        ovmf.packages = [ pkgs.OVMFFull.fd ];
      };
    };
    spiceUSBRedirection.enable = true;
    # Enable docker
    docker = {
      enable = true;
      enableOnBoot = true;
      # storageDriver can be null or one of "aufs", "btrfs", "devicemapper",
      # "overlay", "overlay2", "zfs". Default is null, which is "autodetect"
      # storageDriver = "zfs";
    };
  };
  services.spice-vdagentd.enable = true;
}