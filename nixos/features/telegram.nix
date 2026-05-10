{
  flake.nixosModules.telegram = {pkgs, ...}: {
    environment.systemPackages = [
      pkgs.telegram-desktop
    ];
  };
}
