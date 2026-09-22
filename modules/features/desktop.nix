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
    };
  };
}
