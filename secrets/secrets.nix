let
  ashebanow_pub = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIJhsuxHH4J5rPM5XNosTiTdHOX+NnZzHmePfEFTyaAs1";
  users = [ashebanow_pub];

  yuzu_pub = "";
  liquid-nixos_pub = "";
  nixos-mac-aarch64_pub = "";
  miraclemax_pub = "";
  systems = [yuzu_pub liquid-nixos_pub nixos-mac-aarch64_pub miraclemax_pub];
in {
  # "secret1.age".publicKeys = [ashebanow_pub yuzu_pub];
  # "secret2.age".publicKeys = users ++ systems;
}
