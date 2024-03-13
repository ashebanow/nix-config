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
    xwayland.enable = true;
    # systemd.enable = true;
  };

  services.dbus.enable = true;
  xdg.portal = {
    enable = true;
    wlr.enable = true;
    extraPortals = [
      pkgs.xdg-desktop-portal-gtk
    ];
  };

  # enable programs hyprland uses
  programs.thunar.enable = true;
  programs.waybar.enable = true;

  # enable services hyprland uses
  # services.cliphist.enable = true;
  # services.dunst.enable = true;
  # services.udiskie.enable = true;
  # services.udiskie.tray = "always";

  # for xremap to work with wlroots
  # services.xremap.withWlroots = true;

  environment.systemPackages = with pkgs; [
    dunst
    foot
    hyprland
    hypridle
    hyprlock
    hyprpaper
    hyprpicker
    imv
    libnotify
    meson
    mpv
    pavucontrol
    rofi-wayland
    udiskie
    wayland-protocols
    wayland-utils
    wl-clipboard
    wlroots
    xdg-desktop-portal-gtk
    xdg-desktop-portal-hyprland
    zathura
  ];
}
