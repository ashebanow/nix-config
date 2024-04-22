{pkgs, ...}: {
  # Configure the X11 windowing system.
  services.xserver = {
    enable = true;

    # Configure keymap in X11
    xkb.layout = "us";
    xkb.variant = "";
    xkb.options = "ctrl:nocaps";
  };

  services.desktopManager = {
    plasma6 = {
      enable = true;
    };
  };

  services.displayManager = {
    sddm = {
      enable = true;
      wayland.enable = true;
      theme = "catppuccin-sddm-corners";
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

  environment.systemPackages = with pkgs; [
    packages.self.adw-gtk3
    packages.self.papirus-icon-theme
    pkgs.vanilla-dmz
    gnome.gnome-tweaks
    gnome.gnome-shell-extensions
    gnome.dconf-editor
    libsForQt5.qtwayland
    libsForQt5.gwenview
    pkgs.gnomeExtensions.appindicator
    pkgs.gnomeExtensions.tailscale-status
    pkgs.wl-clipboard
  ];
}
