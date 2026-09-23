# GNOME — configuration specific to the GNOME desktop. Enabling GNOME itself
# (gdm + services.desktopManager.gnome) is desktop.nix's job; this module only
# tunes it. Gated on my.desktop plus gnome appearing in my.desktopSessions, so
# it stays inert on a niri-only host.
_: {
  my.modules.nixos.gnome = {
    lib,
    config,
    pkgs,
    ...
  }: {
    config = lib.mkIf (config.my.desktop && lib.elem "gnome" config.my.desktopSessions) {
      # gdm's autoSuspend suspends the machine after inactivity at the login
      # prompt. This desktop is reachable over Tailscale SSH, so an idle login
      # screen must not take the host off the network. The logged-in session
      # keeps its normal idle/suspend behaviour; this is only the login screen.
      services.displayManager.gdm.autoSuspend = false;

      # Skip the first-login GNOME tour/welcome dialog — the same gsettings
      # override the installer ISO uses.
      services.desktopManager.gnome.extraGSettingsOverrides = ''
        [org.gnome.shell]
        welcome-dialog-last-shown-version='9999999999'
      '';
      services.desktopManager.gnome.extraGSettingsOverridePackages = [pkgs.gnome-settings-daemon];
    };
  };
}
