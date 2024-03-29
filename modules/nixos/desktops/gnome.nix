{pkgs, ...}: {
  # Configure the X11 windowing system.
  services.xserver = {
    enable = true;

    # Enable the GNOME Desktop Environment.
    displayManager = {
      gdm = {
        enable = true;
        wayland = true;
      };
    };

    desktopManager.gnome.enable = true;

    # Configure keymap in X11
    layout = "us";
    xkbVariant = "";
    xkbOptions = "ctrl:nocaps";
  };
}
