# Desktop feature — common plumbing for a host with a graphical session, and
# the single place that decides which desktop environment / compositor is
# enabled. DE-specific configuration lives in its own module (gnome.nix today;
# a future niri.nix and its DankMaterialShell/Noctalia shell slot in the same
# way, adding a value to my.desktopEnvironment).
#
# Enabling a display manager here also turns on NixOS's
# services.graphical-desktop, which mkDefault-enables PipeWire,
# hardware.graphics, the default font packages, and the XDG
# menus/icons/autostart set.
_: {
  my.modules.nixos.desktop = {
    lib,
    config,
    pkgs,
    ...
  }: {
    config = lib.mkIf config.my.desktop {
      # ── Desktop environment pick ─────────────────────────────────
      # GNOME uses gdm as its display manager. A future compositor (niri)
      # would add its own DM/session wiring here.
      services.desktopManager.gnome.enable = lib.mkIf (config.my.desktopEnvironment == "gnome") true;
      services.displayManager.gdm.enable = lib.mkIf (config.my.desktopEnvironment == "gnome") true;

      # A graphical desktop wants declarative networking. GNOME's own module
      # also mkDefault-enables this; keep it explicit so a non-GNOME session
      # behaves the same.
      networking.networkmanager.enable = lib.mkDefault true;

      # libinput drives keyboards/mice/touchpads under both X11 and Wayland.
      services.libinput.enable = lib.mkDefault true;

      # ── Session D-Bus broker: notice home-manager installs ────────
      # dbus-broker reads $XDG_DATA_DIRS/dbus-1/services once at startup and
      # never rescans. Apps installed via home.packages (ghostty, kitty, …) put
      # their D-Bus activation files in ~/.nix-profile/share/dbus-1/services,
      # so after a `nixos-rebuild switch` the running session bus still does not
      # know about them. GNOME Shell launches a `DBusActivatable=true` desktop
      # entry by asking the bus to activate it; the bus answers
      # "ServiceUnknown: the name is not activatable", and the click silently
      # does nothing — while running the binary from a terminal works fine.
      #
      # switch-to-configuration already performs a "user switch" for logged-in
      # users and honours X-Reload-Triggers, so keying a *reload* trigger (not a
      # restart — restarting the session bus drops every client's connection)
      # on the home-manager package environment makes it reload dbus-broker
      # whenever home.packages changes, i.e. whenever a new activation file can
      # have appeared or disappeared.
      systemd.user.services.dbus-broker.reloadTriggers =
        lib.mkIf (config.services.dbus.implementation == "broker")
        (lib.optional
          (lib.hasAttr config.my.baseUsername (config.home-manager.users or {}))
          "${config.home-manager.users.${config.my.baseUsername}.home.path}");
    };
  };
}
