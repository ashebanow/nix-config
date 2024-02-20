{pkgs, ...}: {
  boot.kernelPackages = pkgs.linuxPackages.nvidia_x11;

  # services.xserver = {
  #   enable = true;
  #   videoDrivers = [ "nvidia"];
  #   displayManager.gdm = {
  #     enable = true;
  #     nvidiaWayland = true;
  #   };
  #   desktopManager.gnome.enable = true;
  # };

  environment.sessionVariables = {
    # If your cursor becomes invisible
    # WLR_NO_HARDWARE_CURSORS = "1";
    # Hint electron apps to use wayland
    NIXOS_OZONE_WL = "1";
  };

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
  xdg.portal.extraPortals = [pkgs.xdg-desktop-portal-gtk];

  # rofi keybind
  # bind = $mainMod, S, exec, rofi -show drun -show-icons

  # programs.thunar.enable = true;

  # programs.hyprland = {
  #   enable = true;
  #   enableNvidiaPatches = true;
  #   xwayland.enable = true;
  # };

  wayland.windowManager.sway = {
    enable = true;
    config = rec {
      modifier = "Mod4"; # Super key
      output = {
        "Virtual-1" = {
          mode = "1920x1080@60Hz";
        };
      };
    };
  };

  # environment.systemPackages = with pkgs; [
  #   # system bar
  #   (waybar.overrideAttrs (oldAttrs: {
  #     mesonFlags = oldAttrs.mesonFlags ++ [ "-Dexperimental=true" ];
  #   }))
  #   # eww   # alternative to waybar

  #   # app luncher
  #   rofi-wayland

  #   # notifications
  #   dunst       # or mako
  #   libnotify

  #   # wallpapers
  #   swww
  # ];
}
