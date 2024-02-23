{
  pkgs,
  config,
  lib,
  username,
  pkgs-unstable,
  ...
}: let
  homeDir = config.users.users."${username}".home;
in {
  # https://github.com/NixOS/nixpkgs/blob/nixos-unstable/pkgs/os-specific/darwin/yabai/default.nix
  services.yabai = {
    enable = true;
    # temporary workaround for https://github.com/ryan4yin/nix-config/issues/51
    package = pkgs.yabai;

    # Whether to enable yabai's scripting-addition.
    # SIP must be disabled for this to work.
    # https://github.com/koekeishiya/yabai/wiki/Disabling-System-Integrity-Protection
    enableScriptingAddition = true;

    # config = {};
    # extraConfig = builtins.readFile ../../../dotfiles/yabairc;
  };

  # custom log path for debugging
  launchd.user.agents.yabai.serviceConfig = {
    StandardErrorPath = "${homeDir}/Library/Logs/yabai.stderr.log";
    StandardOutPath = "${homeDir}/Library/Logs/yabai.stdout.log";
  };
}
