# Adapted from:
# https://github.com/kclejeune/system/blob/master/modules/darwin/syncthing.nix
# under MIT license.
{
  config,
  lib,
  pkgs,
  ...
}:
with lib; let
  cfg = config.my.modules.syncthing;
in {
  options = {
    my.modules.syncthing = {
      enable = mkOption {
        type = types.bool;
        default = false;
        description = "Whether to enable the Syncthing service.";
      };

      dataDir = mkOption {
        type =
          types.str
          // {
            check = x: types.str.check x && (substring 0 1 x == "/" || substring 0 2 x == "~/");
            description = types.str.description + " starting with / or ~/";
          };
        default = "~/.config/syncthing";
        example = "~/.config/syncthing";
        description = lib.mdDoc ''
          The location of the default data folder.
          Only absolute paths (starting with `/`) and paths relative to
          the [user](#opt-services.syncthing.user)'s home directory
          (starting with `~/`) are allowed.
        '';
      };

      homeDir = mkOption {
        type =
          types.str
          // {
            check = x: types.str.check x && (substring 0 1 x == "/" || substring 0 2 x == "~/");
            description = types.str.description + " starting with / or ~/";
          };
        default = "~/";
        example = "~/Sync";
        description = lib.mdDoc ''
          The location of the default sync folder, NOT CURRENTLY USED
          Only absolute paths (starting with `/`) and paths relative to
          the [user](#opt-services.syncthing.user)'s home directory
          (starting with `~/`) are allowed.
        '';
      };

      logDir = mkOption {
        type =
          types.str
          // {
            check = x: types.str.check x && (substring 0 1 x == "/" || substring 0 2 x == "~/");
            description = types.str.description + " starting with / or ~/";
          };
        default = "~/Library/Logs";
        example = "~/Library/Logs";
        description = lib.mdDoc ''
          The logfile directory to use for the Syncthing service.
          Only absolute paths (starting with `/`) and paths relative to
          the [user](#opt-services.syncthing.user)'s home directory
          (starting with `~/`) are allowed.
        '';
      };
    };
  };

  config = mkIf cfg.enable {
    environment.systemPackages = [pkgs.syncthing];
    launchd.user.agents.syncthing = {
      command = "${lib.getExe pkgs.syncthing}";
      serviceConfig = {
        Label = "net.syncthing.syncthing";
        KeepAlive = true;
        LowPriorityIO = true;
        ProcessType = "Background";
        # FIXME use command line arguments for logging instead of stdin/out
        # StandardOutPath = "${cfg.logDir}/Syncthing.log";
        # StandardErrorPath = "${cfg.logDir}/Syncthing-Errors.log";
        EnvironmentVariables = {
          NIX_PATH = "nixpkgs=" + toString pkgs.path;
          STNORESTART = "1";
        };
      };
    };
  };
}
