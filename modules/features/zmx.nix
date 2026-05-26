# zmx — session persistence and workflow tool for terminal sessions.
# Registered as a NixOS module gated by my.zmx capability flag.
# inputs is passed via specialArgs from nixos-builder.nix.
_: {
  my.modules.nixos.zmx = {
    lib,
    config,
    pkgs,
    inputs,
    ...
  }: {
    config = lib.mkIf config.my.zmx {
      environment.systemPackages = [
        inputs.zmx.packages.${pkgs.stdenv.hostPlatform.system}.zmx
      ];
    };
  };
}
