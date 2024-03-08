{
  config,
  lib,
  pkgs,
  inputs,
  ...
}: {
  users.users.ashebanow = {
    shell = pkgs.zsh;
    isNormalUser = true;
    description = "Andrew Shebanow";
    extraGroups = ["networkmanager" "wheel" "video" "storage" "libvirtd"];
    openssh.authorizedKeys.keys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIJhsuxHH4J5rPM5XNosTiTdHOX+NnZzHmePfEFTyaAs1 ashebanow@gmail.com"
    ];
  };
}
