{ config, pkgs, ... }: {
  # iputils gets its own module because it doesn't work on darwin
  home.packages = with pkgs; [
    google-chrome
  ];
}
