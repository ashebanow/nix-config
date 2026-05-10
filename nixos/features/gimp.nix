{
  flake.nixosModules.gimp = {pkgs, ...}: {
    environment.systemPackages = [
      pkgs.gimp3
    ];
  };
}
