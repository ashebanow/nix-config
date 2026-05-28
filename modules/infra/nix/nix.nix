# Nix daemon settings — registered as a deferred NixOS module.
# `inputs` is passed via specialArgs from nixos-builder.nix.
{
  lib,
  config,
  pkgs,
  inputs,
  ...
}: {
  nix = {
    # Use the latest Nix for all features
    package = lib.mkForce pkgs.nixVersions.latest;

    gc = {
      automatic = true;
      options = "--delete-older-than 30d";
    };

    # Make <nixpkgs> references resolve to flake-pinned inputs
    nixPath = [
      "nixpkgs=${inputs.nixpkgs}"
      # Uncomment when nixpkgs-stable input is added:
      # "nixpkgs-stable=${inputs.nixpkgs-stable}"
    ];

    registry = {
      nixpkgs.flake = inputs.nixpkgs;
      # Uncomment when nixpkgs-stable input is added:
      # nixpkgs-stable.flake = inputs.nixpkgs-stable;
    };

    settings = {
      warn-dirty = false;
      # Enable flakes and nix-command for the daemon and all users
      experimental-features = [
        "nix-command"
        "flakes"
        "auto-allocate-uids"
        "cgroups"
      ];
      # Nullify the global registry for purity — use flake refs instead
      flake-registry = builtins.toFile "empty-flake-registry.json" ''{"flakes":[],"version":2}'';
      trusted-users = lib.mkDefault [ "root" "@wheel" ];
    };
  };

  # Allow unfree packages globally
  nixpkgs.config.allowUnfree = true;
}
