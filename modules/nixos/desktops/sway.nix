{ pkgs, ... }:
{
  # programs.zsh.sessionVariables = {
  #   # If your cursor becomes invisible
  #   # WLR_NO_HARDWARE_CURSORS = "1";
  #   # Hint electron apps to use wayland
  #   NIXOS_OZONE_WL = "1";
  # };

  # wayland-related
  # programs.sway.enable = true; # commented out due to usage of home-manager's sway
  security.polkit.enable = true;
  hardware = {
    # Opengl
    opengl.enable = true;

    # # Most wayland compositors need this
    # nvidia.modesetting.enable = true;

    # nvidia.package = config.boot.kernelPackages.nvidiaPackages.beta;
  };

  # XDG portal
  xdg.portal.enable = true;
  xdg.portal.extraPortals = [ pkgs.xdg-desktop-portal-gtk ];

  wayland.windowManager.sway = {
    enable = true;
    config = rec {
      modifier = "Mod4"; # Super key
      output = {
        "HDMI-1" = {
          # mode = "3440x1440@60Hz";
          mode = "2560x1080@60Hz";
        };
      };
    };
    extraConfig = ''
      bindsym Print               exec shotman -c output
      bindsym Print+Shift         exec shotman -c region
      bindsym Print+Shift+Control exec shotman -c window
      '';
  };

  home.packages = with pkgs; [
    # system bar
    # (waybar.overrideAttrs (oldAttrs: {
    #   mesonFlags = oldAttrs.mesonFlags ++ [ "-Dexperimental=true" ];
    # }))
    # eww   # alternative to waybar

    # app luncher
    # rofi-wayland

    wl-clipboard

    # screenshots
    shotman

    # notifications
    # dunst       # or mako
    mako
    libnotify

    # wallpapers
    swww
  ];
}
