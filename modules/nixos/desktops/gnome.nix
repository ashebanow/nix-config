{ pkgs, ... }: {
  # Configure the X11 windowing system.
  services.xserver = {
    enable = true;

    # Enable the GNOME Desktop Environment.
    displayManager = {
      gdm = {
        enable = true;
        wayland = false;
        autoSuspend = false;
      };
    };

    desktopManager.gnome.enable = true;

    modules = [ pkgs.xorg.xf86videofbdev ];
    videoDrivers = [ "nvidia" ];

    # Configure keymap in X11
    layout = "us";
    xkbVariant = "";
    xkbOptions = "ctrl:nocaps";
  };

  # make sure we turn off suspending power. There may be additional settings
  # that are specific to each desktop environment, see modules/nixos/desktops.
  powerManagement.enable = false;
  security.polkit.extraConfig = ''
    polkit.addRule(function(action, subject) {
      if (action.id == "org.freedesktop.login1.suspend" ||
          action.id == "org.freedesktop.login1.suspend-multiple-sessions" ||
          action.id == "org.freedesktop.login1.hibernate" ||
          action.id == "org.freedesktop.login1.hibernate-multiple-sessions")
      {
        return polkit.Result.NO;
      }
    });
  '';
  # Disable the GNOME3/GDM auto-suspend feature that cannot be disabled in GUI!
  # If no user is logged in, the machine will power down after 20 minutes.
  systemd.targets.sleep.enable = false;
  systemd.targets.suspend.enable = false;
  systemd.targets.hibernate.enable = false;
  systemd.targets.hybrid-sleep.enable = false;

}