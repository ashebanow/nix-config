{
  config,
  pkgs,
  self,
  inputs,
  lib,
  ...
}: {
  # Import all your configuration modules here
  imports = [
    ./firefox.nix
  ];
}
