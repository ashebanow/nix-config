# NixOS builder — collects deferred modules from feature modules
# (populated via import-tree) and builds one flake.nixosConfigurations entry
# per NixOS host, plus a standalone homeConfigurations entry for HM-only
# builds. Mirrors modules/infra/darwin-builder.nix's mkDarwinHost.
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

  # worktrunk + linear-cli are pinned ahead of nixpkgs (see the overlay
  # headers). Applied to every NixOS host's package set: the overlays only
  # *define* the attributes, so nothing enters a host closure unless a feature
  # module references it. lumquat leaves cli-vcs-tools off, so neither lands
  # there — matching the policy that lumquat sees worktrunk only in the dev
  # shell (modules/infra/devshell.nix).
  overlays = [
    (import ../../lib/overlays/worktrunk.nix {inherit (inputs) worktrunk;})
    (import ../../lib/overlays/linear-cli.nix)
  ];

  # mkNixosHost — build one NixOS host from hosts/<hostName>/.
  #
  # remoteBuilder:      create the `remotebuild` user (modules/infra/remote-builder.nix).
  #                     Only the dedicated build host (lumquat) wants this.
  # chezmoiActivation:  run chezmoi from the Home Manager activation and
  #                     deliver the BWS token as a systemd credential. This is
  #                     a headless-only arrangement: the dotfiles'
  #                     run_before_000-require-bws-token.sh needs BWS_ACCESS_TOKEN,
  #                     which the activation gets from the credential. A desktop
  #                     applies chezmoi itself from an interactive shell (token
  #                     from the login keyring), so it must leave this off.
  mkNixosHost = {
    hostName,
    username,
    homeDirectory,
    hmStateVersion,
    remoteBuilder ? false,
    chezmoiActivation ? false,
  }: let
    hostDir = ../../hosts/${hostName};
    capabilitiesPath = hostDir + "/capabilities.nix";
    hostHasCapabilities = builtins.pathExists capabilitiesPath;

    # Wire home-manager into NixOS activation so `nixos-rebuild switch`
    # applies it for the primary user.
    #
    # Written as a function rather than a bare attrset so that `config` and
    # `lib` below refer to the *NixOS* module arguments; the outer `config` in
    # this file is flake-parts' config.
    hmUserModule = {
      config,
      lib,
      pkgs,
      ...
    }: {
      # Deliver the out-of-band BWS bootstrap token to the HM activation as a
      # systemd credential (BOX-174) — only when that activation runs chezmoi.
      # The activation script cannot read /var/lib/secrets/bws-access-token
      # itself: the unit's PATH is nix-store paths only, so `sudo` (NixOS puts
      # it in /run/wrappers/bin) was never found and the old read silently
      # yielded an empty token. LoadCredential is performed by PID 1 as root,
      # so the root-only 0600 file is readable and the resulting credential
      # dir is handed to the service's user. The name `access_token` mirrors
      # the one the service consumers use (see secretspec.toml [providers]).
      #
      # Gated on the same condition as modules/features/secrets.nix: the token
      # only exists once that module provisions /var/lib/secrets. A host
      # without it keeps a plain, token-less home-manager activation.
      #
      # Not `:`-prefixed: the file is expected to exist on any host that has
      # this module enabled, and a missing one should surface in the unit's
      # log rather than be silently skipped.
      systemd.services."home-manager-${username}".serviceConfig.LoadCredential =
        lib.mkIf (chezmoiActivation && (config.my.access || config.my.llm))
        ["access_token:${config.my.bwsAccessTokenFile}"];

      # Use the system package set for Home Manager. Without this, HM builds
      # its own pkgs instance that neither sees the overlays above (so
      # pkgs.linear-cli is undefined) nor nixpkgs.config.allowUnfree (so
      # unfree HM packages like bws/claude-code/google-chrome fail). Same
      # choice as the Darwin hosts (modules/infra/darwin-builder.nix).
      home-manager.useGlobalPkgs = true;

      home-manager.users.${username} = {
        # The chezmoi gh template shells out to `bws`, which the activation's
        # nix-store-only PATH does not include (BOX-174). Resolve the store
        # path here, where `pkgs.bws` is available (the same package
        # modules/features/base.nix puts in environment.systemPackages):
        # hm-infra.nix's own `pkgs` argument refuses the unfree package, so the
        # value is set on the Home Manager side below.
        my.bwsBinDir =
          lib.mkIf (chezmoiActivation && (config.my.access || config.my.llm))
          "${pkgs.bws}/bin";
        imports =
          [
            {
              home.username = username;
              home.homeDirectory = homeDirectory;
              home.stateVersion = hmStateVersion;
            }
            ../../lib/my-options-module.nix
          ]
          ++ lib.optionals chezmoiActivation [./hm-infra.nix]
          # config.my.* is a separate options instance inside this submodule —
          # it does NOT inherit values set only at the NixOS/system scope by
          # hosts/<host>/configuration.nix. capabilities.nix carries just the
          # my.cliXxx/guiXxx flags so both scopes agree.
          ++ lib.optionals hostHasCapabilities [capabilitiesPath]
          ++ deferredHmModules;
      };
    };

    # Build the NixOS config, then override `type` to a string.
    # flake-parts expects nixosConfigurations.<name>.type to be a string (the
    # system), but nixosSystem in newer nixpkgs returns type as an attrset.
    nixosConfig = inputs.nixpkgs.lib.nixosSystem {
      inherit system;
      specialArgs = {inherit inputs;};
      modules =
        [
          ../../lib/my-options-module.nix
          nixos-hardware.nixosModules.common-cpu-amd
          home-manager.nixosModules.home-manager
          determinate.nixosModules.default
          (hostDir + "/configuration.nix")
          (hostDir + "/hardware-configuration.nix")
          {nixpkgs.overlays = overlays;}
          hmUserModule
        ]
        ++ lib.optionals remoteBuilder [./remote-builder.nix]
        ++ deferredNixosModules;
    };

    # Standalone Home Manager output for `nh home build . --configuration <user>`
    # (the `build-hm` recipe in ~/.justfile). Same treatment for `type`.
    homeConfig = home-manager.lib.homeManagerConfiguration {
      pkgs = import inputs.nixpkgs {
        inherit system;
        config.allowUnfree = true;
        inherit overlays;
      };
      modules =
        [
          {
            home.username = username;
            home.homeDirectory = homeDirectory;
            home.stateVersion = hmStateVersion;
          }
          ../../lib/my-options-module.nix
        ]
        ++ lib.optionals chezmoiActivation [./hm-infra.nix]
        ++ lib.optionals hostHasCapabilities [capabilitiesPath]
        ++ deferredHmModules;
    };
  in {
    nixos = nixosConfig // {type = system;};
    home = homeConfig // {type = system;};
  };

  lumquat = mkNixosHost {
    hostName = "lumquat";
    username = "podman";
    homeDirectory = "/home/podman";
    hmStateVersion = "26.05";
    remoteBuilder = true;
    chezmoiActivation = true;
  };

  yuzu = mkNixosHost {
    hostName = "yuzu";
    username = "ashebanow";
    homeDirectory = "/home/ashebanow";
    hmStateVersion = "26.11";
  };
in {
  flake = {
    nixosConfigurations = {
      lumquat = lumquat.nixos;
      yuzu = yuzu.nixos;
    };
    homeConfigurations = {
      podman = lumquat.home;
      ashebanow = yuzu.home;
    };
  };
}
