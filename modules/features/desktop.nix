# Desktop feature — common plumbing for a host with a graphical session, and
# the single place that decides the display manager and which sessions the host
# offers. Session-specific configuration lives in its own module (gnome.nix,
# niri.nix); a shell on top of a session (DankMaterialShell) has its own module
# and its own capability flag, because a shell is not a session.
#
# The sessions themselves are data: my.desktopSessions and
# my.desktopDefaultSession, set in hosts/<host>/capabilities.nix so the Home
# Manager scope can read them too (see CONTEXT.md).
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
    # mkMerge rather than a bare `config = mkIf ...` because a module cannot
    # carry a top-level `config` attribute and top-level config values
    # (assertions) at the same time, and these assertions must be evaluated even
    # when my.desktop is false — the third one exists to catch exactly that.
    config = lib.mkMerge [
      {
        assertions = [
          {
            # Only meaningful once a host declares sessions: `desktopDefaultSession`
            # keeps its "gnome" default on a host with none, and comparing it
            # against an empty list would fail every server.
            assertion =
              config.my.desktopSessions
              == []
              || lib.elem config.my.desktopDefaultSession config.my.desktopSessions;
            message = ''
              my.desktopDefaultSession ("${config.my.desktopDefaultSession}") is not in
              my.desktopSessions (${lib.concatStringsSep ", " config.my.desktopSessions}).
            '';
          }
          {
            assertion = config.my.desktop -> config.my.desktopSessions != [];
            message = "my.desktop is true but my.desktopSessions is empty — set them together in capabilities.nix.";
          }
          {
            assertion = config.my.desktopSessions != [] -> config.my.desktop;
            message = "my.desktopSessions is set but my.desktop is false — the session plumbing is gated on my.desktop.";
          }
          {
            assertion = config.my.dankMaterialShell -> lib.elem "niri" config.my.desktopSessions;
            message = "my.dankMaterialShell is true but niri is not in my.desktopSessions.";
          }
        ];
      }
      (lib.mkIf config.my.desktop {
        # ── Display manager and sessions ──────────────────────────────
        # GDM is the display manager for every desktop here, whatever sessions
        # the host offers: it is the supported way to start GNOME, which is the
        # emergency session (docs/adr/0003). The compositor's own module
        # (niri.nix) adds niri to displayManager.sessionPackages via
        # programs.niri; gnome.nix tunes GNOME once it is on.
        services.displayManager.gdm.enable = true;
        services.desktopManager.gnome.enable = lib.elem "gnome" config.my.desktopSessions;
        services.displayManager.defaultSession = config.my.desktopDefaultSession;

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
      })
    ];
  };
}
