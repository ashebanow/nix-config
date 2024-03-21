let
  ashebanow_pub = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIJhsuxHH4J5rPM5XNosTiTdHOX+NnZzHmePfEFTyaAs1";
  users = [ashebanow_pub];

  calamansi_pub = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOW+de2VEfei4Ja84wZVXXozO8HWKB9VYyXax+tiPBTn root@nixos";
  limon_pub = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIIZOc8KRP0xXk6LGvL/+Zf+7+8e9a4xebZe3TPfO92Fq root@nixos";
  miraclemax_pub = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIBgnAx3aD6mU7JLSqIEuaZUF5sn2ebr4sfWT3fKOHNvb";
  yuzu_pub = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIDXAe0NETgTw3cQYz2/pnB6RsB8JxUTRpdYdr1wTnaeV root@nixos";
  systems = [calamansi_pub limon_pub miraclemax_pub yuzu_pub];
in {
  # "secret1.age".publicKeys = [ashebanow_pub yuzu_pub];
  "tailscale-authkey.age".publicKeys = users ++ systems;
  "tailscale-ashebanow-key.age".publicKeys = users ++ systems;
  "smb-secrets.age".publicKeys = users ++ systems;
}
