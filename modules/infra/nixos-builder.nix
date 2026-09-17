# NixOS builder — collects deferred modules from feature modules
# (populated via import-tree) and builds flake.nixosConfigurations.
{
  inputs,
  config,
  lib,
  ...
}: let
  inherit (inputs) nixos-hardware home-manager determinate;
  system = "x86_64-linux";

  # Collect deferred modules registered by feature modules
  deferredNixosModules = builtins.attrValues config.my.modules.nixos;
  deferredHmModules = builtins.attrValues config.my.modules.home-manager;

  # Base NixOS modules included in every host
  baseModules = [
    ../../lib/my-options-module.nix
    nixos-hardware.nixosModules.common-cpu-amd
    home-manager.nixosModules.home-manager
    determinate.nixosModules.default
    ../../hosts/lumquat/configuration.nix
    ../../hosts/lumquat/hardware-configuration.nix
    ./remote-builder.nix
    # Wire home-manager into NixOS activation so
    # nixos-rebuild switch applies it for the podman user.
    #
    # Written as a function rather than a bare attrset so that `config` and
    # `lib` below refer to the *NixOS* module arguments; the outer `config` in
    # this file is flake-parts' config.
    (
      {
        config,
        lib,
        pkgs,
        ...
      }: {
        # Deliver the out-of-band BWS bootstrap token to the HM activation as a
        # systemd credential (BOX-174). The activation script cannot read
        # /var/lib/secrets/bws-access-token itself: the unit's PATH is nix-store
        # paths only, so `sudo` (NixOS puts it in /run/wrappers/bin) was never
        # found and the old read silently yielded an empty token.
        # LoadCredential is performed by PID 1 as root, so the root-only 0600
        # file is readable and the resulting credential dir is handed to the
        # service's `podman` user. The name `access_token` mirrors the one the
        # service consumers use (see secretspec.toml [providers]).
        #
        # Gated on the same condition as modules/features/secrets.nix: the token
        # only exists once that module provisions /var/lib/secrets. A host
        # without it keeps a plain, token-less home-manager activation.
        #
        # Not `:`-prefixed: the file is expected to exist on any host that has
        # this module enabled, and a missing one should surface in the unit's
        # log rather than be silently skipped.
        systemd.services.home-manager-podman.serviceConfig.LoadCredential =
          lib.mkIf (config.my.access || config.my.llm)
          ["access_token:${config.my.bwsAccessTokenFile}"];

        # The chezmoi gh template shells out to `bws`, which the activation's
        # nix-store-only PATH does not include (BOX-174). Resolve the store
        # path here, where `pkgs.bws` is available (the same package
        # modules/features/base.nix puts in environment.systemPackages):
        # hm-infra.nix's own `pkgs` argument refuses the unfree package, so the
        # value is set on the Home Manager side below.
        home-manager.users.podman = {
          my.bwsBinDir = lib.mkIf (config.my.access || config.my.llm) "${pkgs.bws}/bin";
          imports =
            [
              {
                home.username = "podman";
                home.homeDirectory = "/home/podman";
                home.stateVersion = "26.05";
              }
              ../../lib/my-options-module.nix
              ./hm-infra.nix
            ]
            ++ deferredHmModules;
        };
      }
    )
  ];

  # Build the NixOS config, then override `type` to a string.
  # flake-parts expects nixosConfigurations.<name>.type to be a string (the system),
  # but nixosSystem in newer nixpkgs returns type as an attrset.
  nixosConfig = inputs.nixpkgs.lib.nixosSystem {
    inherit system;
    specialArgs = {inherit inputs;};
    modules = baseModules ++ deferredNixosModules;
  };

  # Same treatment for Home Manager — newer nixpkgs returns type as an attrset.
  homeConfig = home-manager.lib.homeManagerConfiguration {
    pkgs = import inputs.nixpkgs {
      inherit system;
      config.allowUnfree = true;
    };
    modules =
      [
        {
          home.username = "podman";
          home.homeDirectory = "/home/podman";
          home.stateVersion = "26.05";
        }
        ../../lib/my-options-module.nix
        ./hm-infra.nix
      ]
      ++ deferredHmModules;
  };
in {
  flake = {
    nixosConfigurations.lumquat = nixosConfig // {type = system;};
    homeConfigurations.podman = homeConfig // {type = system;};
  };
}
