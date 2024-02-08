{ pkgs, ... }: {
  # Configure the X11 windowing system.
  services.xserver = {
    enable = true;

    # Enable the GNOME Desktop Environment.
    displayManager = {
      sddm = {
        enable = true;
      };
    };

    desktopManager.plasma5.enable = true;

    # modules = [ pkgs.xorg.xf86videofbdev ];
    # videoDrivers = [ "nvidia" ];

    # Configure keymap in X11
    xkb.layout = "us";
    xkb.variant = "";
    xkb.options = "ctrl:nocaps";
  };
}
