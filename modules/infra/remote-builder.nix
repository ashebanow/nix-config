# Remote builder — creates a remotebuild user for distributed Nix builds.
# This is the server-side counterpart to the local machine's Nix daemon,
# which offloads x86_64-linux builds to this server via SSH.
#
# Before deploying, copy the public key from your local machine:
#   scp /root/.ssh/remotebuild.pub lumquat:/path/to/repo/modules/infra/
{
  lib,
  config,
  pkgs,
  ...
}: let
  pubKeyFile = ./remotebuild.pub;
in {
  # Dedicated system user for remote build authentication
  users.users.remotebuild = {
    isSystemUser = true;
    group = "remotebuild";
    useDefaultShell = true;
    openssh.authorizedKeys.keyFiles =
      lib.optionals (builtins.pathExists pubKeyFile) [pubKeyFile];
  };

  users.groups.remotebuild = {};

  # Grant build access. Includes @wheel so admins retain Nix trust.
  nix.settings.trusted-users = ["remotebuild" "@wheel"];

  # Optimize Nix for a build machine
  nix = {
    nrBuildUsers = 64;
    settings = {
      min-free = 10 * 1024 * 1024; # 10 GiB
      max-free = 200 * 1024 * 1024; # 200 GiB
      max-jobs = "auto";
      cores = 0;
    };
  };

  # Prevent Nix builds from starving the system of memory
  systemd.services.nix-daemon.serviceConfig = {
    MemoryAccounting = true;
    MemoryMax = "90%";
    OOMScoreAdjust = 500;
  };
}
