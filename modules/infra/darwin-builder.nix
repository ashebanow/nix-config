# Darwin builder — collects deferred modules (populated via import-tree)
# and builds flake.darwinConfigurations for each Mac host.
#
# Scope rule: these hosts use nix-darwin + Home Manager ONLY for
# declarative package/app lists (environment.systemPackages,
# home.packages, homebrew.{taps,brews,casks,masApps}). They must never
# use programs.*.enable, system.defaults.*, environment.etc, or HM's
# home.file/xdg.configFile — chezmoi owns all actual dotfiles/config
# files. determinateNix.enable = true keeps nix-darwin from touching
# /etc/nix/nix.conf, which chezmoi's run_onchange hook already manages.
{
  inputs,
  config,
  lib,
  ...
}: let
  inherit (inputs) nix-darwin home-manager nix-homebrew homebrew-core homebrew-cask determinate mac-app-util;
  system = "aarch64-darwin";

  deferredDarwinModules = builtins.attrValues config.my.modules.darwin;
  deferredHmModules = builtins.attrValues config.my.modules.home-manager;

  # Binary caches for the darwin hosts — same set as the NixOS hosts
  # (modules/infra/nix/caches.nix), minus flakehub and
  # install.determinate.systems which Determinate Nix's own nix.conf
  # already carries.
  darwinCaches = let
    substituters = [
      "https://cattivi-public.cachix.org"
      "https://nix-community.cachix.org"
      "https://cache.numtide.com"
      "https://cache.nixos.org/"
      "https://pi.cachix.org"
    ];
    keys = [
      "cattivi-public.cachix.org-1:qQQ8FHPoEibPtL1FTZTmVbUL78KW2zCRk+LZPsRiwQ4="
      "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs="
      "niks3.numtide.com-1:DTx8wZduET09hRmMtKdQDxNNthLQETkc/yaX7M4qK0g="
      # Current cache.nixos.org signing key (rotated Jan 2020); the old
      # `hydra.nixos.org-1:CNHJZBh9K4tP3EKF6FkkgeVYsS3ohTl+oS0Qa8bezVs=` key
      # is retired and no longer validates anything on the cache.
      "cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY="
      "pi.cachix.org-1:lGeoGJaZ5ZDabuRzkcD5EBTNnDM4HJ1vqeOxlWk1Flk="
    ];
  in {
    inherit substituters keys;
  };

  # One nix-homebrew + determinate + home-manager block per host, keyed
  # by the mac username that owns the Homebrew prefix and home directory.
  mkDarwinHost = hostName: let
    username = "ashebanow";
  in
    nix-darwin.lib.darwinSystem {
      inherit system;
      specialArgs = {inherit inputs;};
      modules =
        [
          ../../lib/my-options-module.nix
          determinate.darwinModules.default
          {
            # Determinate Nixd owns /etc/nix/nix.conf outright (it
            # regenerates it and already `!include`s nix.custom.conf).
            # This module makes nix-darwin manage /etc/nix/nix.custom.conf
            # from determinateNix.customSettings and force-disables
            # nix-darwin's own nix module — so on these hosts the
            # flake's nix.settings (modules/infra/nix/) do NOT apply;
            # customSettings is the only daemon config channel.
            #
            # trusted-users: the compiled-in default is root only, and
            # macOS admin users are in the `admin` group (no `wheel` by
            # default). Without this, ashebanow can't add substituters
            # via --option, import unsigned paths, etc. Restores what
            # the pre-migration chezmoi /etc/nix/nix.custom.conf used to
            # provide.
            determinateNix = {
              enable = true;
              customSettings = {
                trusted-users = [
                  "ashebanow"
                  "root"
                  "@wheel"
                  "@admin"
                ];
                inherit (darwinCaches) substituters;
                "trusted-substituters" = darwinCaches.substituters;
                "trusted-public-keys" = darwinCaches.keys;
              };
            };
          }
          nix-homebrew.darwinModules.nix-homebrew
          {
            # PHASE 1 (current): migrating an existing imperative Homebrew
            # install. nix-homebrew's own README gives two different
            # recipes for "new installation" (declarative taps +
            # mutableTaps = false) vs "existing installation"
            # (autoMigrate = true alone) — combining both in one
            # activation makes the migration step and the declarative-tap
            # symlinking step fight over the same Library/Taps directory
            # ("An existing .../Library/Taps is in the way"). Once a
            # `darwin-rebuild switch` completes cleanly with just
            # autoMigrate, PHASE 2 is to re-add taps/mutableTaps below
            # (see git history) and switch again.
            nix-homebrew = {
              enable = true;
              enableRosetta = true;
              autoMigrate = true;
              user = username;
              # Third-party taps need explicit trust before Homebrew will
              # load formulae from them (docs.brew.sh/Tap-Trust). Declared
              # here instead of running `brew trust` by hand so it doesn't
              # silently drift out of sync with homebrew.brews below.
              # vjeantet/tap: alerter (in homebrew.brews on both hosts).
              trust.taps = [
                # "arto-app/tap"
                "vjeantet/tap"
              ];
            };
          }
          mac-app-util.darwinModules.default
          home-manager.darwinModules.home-manager
          {
            home-manager.useGlobalPkgs = true;
            home-manager.useUserPackages = true;
            home-manager.users.${username} = {
              imports =
                [
                  {
                    home.username = username;
                    home.homeDirectory = "/Users/${username}";
                    home.stateVersion = "26.05";
                  }
                  ../../lib/my-options-module.nix
                  mac-app-util.homeManagerModules.default
                  # config.my.* is a separate options instance inside this
                  # submodule — it does NOT inherit values set only at the
                  # darwin/system scope by hosts/${hostName}/configuration.nix.
                  # capabilities.nix carries just the my.cliXxx/guiXxx flags
                  # so both scopes agree; configuration.nix itself can't be
                  # imported here since it also sets darwin-only options
                  # (homebrew.*, system.stateVersion) HM doesn't know about.
                  ../../hosts/${hostName}/capabilities.nix
                ]
                ++ deferredHmModules;
            };
          }
          {
            system.primaryUser = username;
            # nix-darwin needs to know about the system user account so
            # the integrated Home Manager module (useGlobalPkgs/
            # useUserPackages) can derive home.homeDirectory — without
            # this it resolves to null and conflicts with the value set
            # above.
            users.users.${username} = {
              name = username;
              home = "/Users/${username}";
            };
          }
          ../../hosts/${hostName}/configuration.nix
        ]
        ++ deferredDarwinModules;
    };
in {
  flake = {
    darwinConfigurations = {
      bergamot = mkDarwinHost "bergamot";
      miraclemax = mkDarwinHost "miraclemax";
    };
  };
}
