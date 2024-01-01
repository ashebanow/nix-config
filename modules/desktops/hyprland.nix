{ pkgs, ... }: {
  programs.hyprland = {
    enable = true;
    enableNvidiaPatches = true;
    xwayland.enable = true;
  };

  environment.sessionVariables = {
    # If your cursor becomes invisible
    WLR_NO_HARDWARE_CURSORS = "1";
    # Hint electron apps to use wayland
    NIXOS_OZONE_WL = "1";
  };

  hardware = {
    # Opengl
    opengl.enable = true;

    # Most wayland compositors need this
    nvidia.modesetting.enable = true;
  };

  # XDG portal
  xdg.portal.enable = true;
  xdg.portal.extraPortals = [ pkgs.xdg-desktop-portal-gtk ];

  # rofi keybind
  # bind = $mainMod, S, exec, rofi -show drun -show-icons

  environment.systemPackages = with pkgs; [
    # system bar
    (waybar.overrideAttrs (oldAttrs: {
      mesonFlags = oldAttrs.mesonFlags ++ [ "-Dexperimental=true" ];
    }))
    # eww   # alternative to waybar

    # app luncher
    rofi-wayland

    # notifications
    dunst       # or mako
    libnotify

    # wallpapers
    swww
  ];
}
