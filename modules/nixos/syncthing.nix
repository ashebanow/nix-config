{
  config,
  options,
  pkgs,
  lib,
  ...
}:
with lib; let
  cfg = config.my.modules.syncthing;
in {
  options.my.modules.syncthing = {
    enable = mkEnableOption "Setup syncthing on this device";
  };

  config = mkIf cfg.enable {
    environment.systemPackages = with pkgs; [
      syncthing
      syncthingtray
    ];

    # TODO:
    #   define per-machine cert & key in agenix
    #   define gui's user & password in agenix
    #   specify folders to share and devices to share them with
    #   to mimic google drive setup as best I can.
    #
    # See also https://github.com/jordanisaacs/dotfiles/blob/master/modules/system/services/syncthing/default.nix
    # for another take on options including relays.
    services.syncthing = rec {
      configDir = "/home/ashebanow/.config/syncthing";
      dataDir = "/home/ashebanow/.local/share/syncthing";
      enable = true;
      extraFlags = ["--no-upgrade"];
      group = "users";
      openDefaultPorts = true;
      user = "ashebanow";
      #   password = config.age.secrets."syncthing-password.age".path;
    };
  };
}
