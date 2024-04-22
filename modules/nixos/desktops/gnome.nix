{pkgs, ...}: {
  # Configure the X11 windowing system.
  services.xserver = {
    enable = true;

    # Configure keymap in X11
    layout = "us";
    xkbVariant = "";
    xkbOptions = "ctrl:nocaps";
  };

  services.desktopManager = {
    gnome = {
      enable = true;
    };
  };

  services.displayManager = {
    gdm = {
      enable = true;
      wayland = true;
    };
  };

  environment.sessionVariables = {
    _JAVA_AWT_WM_NONREPARENTING = "1";
    CLUTTER_BACKEND = "wayland";
    GDK_BACKEND = "wayland";
    GDK_SCALE = "1.5";
    MOZ_ENABLE_WAYLAND = "1";
    NIXOS_OZONE_WL = "1";
    QT_QPA_PLATFORM = "wayland;xcb";
    QT_WAYLAND_DISABLE_WINDOWDECORATION = "1";
    WLR_NO_HARDWARE_CURSORS = "1";
    XCURSOR_SIZE = "32";
    XDG_SESSION_TYPE = "wayland";
  };

  environment.systemPackages = [
    pkgs.vanilla-dmz
    pkgs.kdePackages.discover
    pkgs.kdePackages.ksshaskpass
  ];

  services.packagekit = {
    enable = true;
  };
}
