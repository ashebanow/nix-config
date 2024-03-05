{
  inputs,
  pkgs,
  ...
}: {
  # Enable Hyprland
  programs.hyprland.enable = true;
  package = inputs.hyprland.packages.${pkgs.system}.hyprland;
  environment.sessionVariables.NIXOS_OZONE_WL = "1";
  environment.sessionVariables.WLR_NO_HARDWARE_CURSORS = "1";

  environment.systemPackages = with pkgs; [
    foot # terminal
    zathura # pdf viewer
    mpv # media player
    imv # image viewer
  ];
}
