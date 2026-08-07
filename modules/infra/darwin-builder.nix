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
          {determinateNix.enable = true;}
          nix-homebrew.darwinModules.nix-homebrew
          {
            nix-homebrew = {
              enable = true;
              enableRosetta = true;
              user = username;
              taps = {
                "homebrew/homebrew-core" = homebrew-core;
                "homebrew/homebrew-cask" = homebrew-cask;
              };
              mutableTaps = false;
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
