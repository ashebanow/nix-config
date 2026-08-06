# Deferred module containers — the core dendritic mechanism.
# Any flake-parts module can write NixOS or Home Manager module
# fragments into these containers. The system builders collect them
# and include them in each host's module list.
{lib, ...}: {
  options.my.modules = {
    nixos = lib.mkOption {
      type = lib.types.lazyAttrsOf lib.types.deferredModule;
      default = {};
      description = "NixOS module fragments keyed by feature name";
    };
    darwin = lib.mkOption {
      type = lib.types.lazyAttrsOf lib.types.deferredModule;
      default = {};
      description = "nix-darwin module fragments keyed by feature name";
    };
    home-manager = lib.mkOption {
      type = lib.types.lazyAttrsOf lib.types.deferredModule;
      default = {};
      description = "Home Manager module fragments keyed by feature name";
    };
  };
}
