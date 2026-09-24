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
    # Use the latest Nix for all features (default only — may be overridden
    # by Determinate Nix's module at higher priority when enabled)
    package = lib.mkDefault pkgs.nixVersions.latest;

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

      # Hardlink identical files in the store to save space. Declared here so
      # it is a *daemon* setting: store operations run as the daemon, and a
      # client-side copy only works for trusted users and never governs other
      # users' or root's builds. (This was previously set in the chezmoi
      # user-level ~/.config/nix/nix.conf, where it also tripped the
      # "restricted setting ... not a trusted user" warning on hosts whose
      # trusted-users lacked @wheel.)
      #
      # Not a mkDefault: the nixpkgs default is `false`, and we want `true`.
      auto-optimise-store = true;

      # Enable flakes and nix-command for the daemon and all users
      experimental-features = [
        "nix-command"
        "flakes"
        "auto-allocate-uids"
        "cgroups"
      ];
      # Nullify the global registry for purity — use flake refs instead
      flake-registry = builtins.toFile "empty-flake-registry.json" ''{"flakes":[],"version":2}'';
      # Must be normal (or higher) priority, not mkDefault: nixpkgs sets this
      # at *normal* priority (nixos/modules/config/nix.nix:
      # `trusted-users = [ "root" ]`), and mkDefault ranks below it — so the
      # value was silently discarded and "@wheel" never took effect. Without
      # wheel members being trusted, their client-side nix.conf settings (e.g.
      # auto-optimise-store) are rejected with "ignoring the client-specified
      # setting ... not a trusted user".
      #
      # Deliberately not mkForce: remote-builder.nix adds "remotebuild" to this
      # same list at normal priority, and both definitions merge.
      trusted-users = ["root" "@wheel"];
    };
  };

  # Allow unfree packages globally
  nixpkgs.config.allowUnfree = true;
}
