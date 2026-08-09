# Register nix daemon settings as deferred NixOS modules.
# These are picked up by nixos-builder.nix and merged into every host's config.
_: {
  my.modules.nixos.nix-settings = import ./nix.nix;
  my.modules.nixos.nix-caches = import ./caches.nix;
  my.modules.nixos.flakehub-auth = import ./flakehub.nix;
}
