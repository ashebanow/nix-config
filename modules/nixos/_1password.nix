{
  config,
  options,
  pkgs,
  lib,
  ...
}:{
  options = {
    my.modules._1password = {
      enable =    lib.mkEnableOption "Enable 1password master switch" // {default = false;};
      enableGUI = lib.mkEnableOption "Enable 1password GUI app" // {default = false;};
    };
  };

  config = lib.mkIf config.my.modules._1password.enable {
    # Enable the 1Password CLI, this also enables a SGUID wrapper so the CLI can authorize against the GUI app
    programs._1password = {
      enable = true;
    };

    # Enable the 1Passsword GUI with myself as an authorized user for polkit
    programs._1password-gui = {
      enable = config.my.modules._1password.enableGUI;
      polkitPolicyOwners = ["ashebanow"];
    };
  };
}
