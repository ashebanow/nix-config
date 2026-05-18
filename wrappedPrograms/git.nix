{
  inputs,
  lib,
  config,
  ...
}: let
  cfg = config.programs.git;
  userCfg = config.preferences.user;
in {
  options.programs.git = {
    enableCodeSigning = lib.mkEnableOption "SSH-based code signing for commits";
  };

  config.programs.git.enableCodeSigning = lib.mkDefault false;

  perSystem = {pkgs, ...}: {
    packages.git = inputs.wrappers.lib.wrapPackage {
      inherit pkgs;
      package = pkgs.git;
      # FIX: we need to do more than define env variables.
      # We also need to write the git config file and possible edit
      # ssh config.
      env = rec {
        GIT_AUTHOR_NAME = config.users.users.${userCfg.name}.fullName;
        GIT_AUTHOR_EMAIL = userCfg.email;
        GIT_COMMITTER_NAME = GIT_AUTHOR_NAME;
        GIT_COMMITTER_EMAIL = GIT_AUTHOR_EMAIL;
      };
    };
  };
}
