{
  inputs,
  pkgs,
  ...
}: {
  environment.sessionVariables.NIXOS_OZONE_WL = "1";
  environment.sessionVariables.WLR_NO_HARDWARE_CURSORS = "1";

  # Enable Hyprland
  programs.hyprland = {
    enable = true;
    package = inputs.hyprland.packages.${pkgs.system}.hyprland;
    xwayland.hidpi = true;
    xwayland.enable = true;
  };

  services.dbus.enable = true;
  xdg.portal = {
    enable = true;
    wlr.enable = true;
    extraPortals = [
      pkgs.xdg-desktop-portal-gtk
    ];
  };

  # for xremap to work with wlroots
  services.xremap.withWlroots = true;

  environment.systemPackages = with pkgs; [
    hyprland
    dunst
    libnotify
    meson
    pavucontrol
    rofi-wayland
    swww # for wallpapers
    wayland-protocols
    wayland-utils
    wl-clipboard
    wlroots
    xdg-desktop-portal-gtk
    xdg-desktop-portal-hyprland
    xwayland

    foot # terminal
    imv # image viewer
    mpv # media player
    zathura # pdf viewer
  ];
}
