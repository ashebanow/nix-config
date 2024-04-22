{pkgs, ...}: {
  # Configure the X11 windowing system.
  services.xserver = {
    enable = true;

    # Configure keymap in X11
    xkb.layout = "us";
    xkb.variant = "";
    xkb.options = "ctrl:nocaps";
  };

  # Enable the KDE Plasma Desktop Environment.
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
}
