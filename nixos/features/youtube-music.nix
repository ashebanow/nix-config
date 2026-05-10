{
  flake.nixosModules.youtube-music = {pkgs, ...}: {
    environment.systemPackages = [
      pkgs.youtube-music
    ];
  };
}
