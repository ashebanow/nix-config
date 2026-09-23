# DankMaterialShell — the bar, launcher, notification centre, clipboard, lock
# screen and settings UI for the niri session. It is a shell, not a session, so
# it has its own capability flag rather than an entry in my.desktopSessions.
#
# Home Manager scope, from DMS's own flake rather than nixpkgs'
# programs.dms-shell — see docs/adr/0003, which also records why the NixOS
# module scope and DankGreeter were rejected.
#
# settings / clipboardSettings / session are deliberately left unset: DMS owns
# ~/.config/DankMaterialShell/settings.json at runtime, so its GUI stays
# writable and this stays a vanilla install. The niri includes are the other
# half of that — `dms setup` seeds ~/.config/niri/dms/*.kdl once and DMS
# maintains them from then on.
{inputs, ...}: {
  my.modules.home-manager.dank-material-shell = {
    lib,
    config,
    ...
  }: let
    # DMS's matugen writes only ~/.config/gtk-{3,4}.0/dank-colors.css — it never
    # writes gtk.css or settings.ini. GTK therefore needs a shim that imports
    # the generated colours, and an icon theme to match them. The previous
    # chezmoi versions imported a Breeze colours.css and pinned Andromeda-dark.
    #
    # No gtk-theme-name here on purpose: the wallpaper-derived colours are the
    # theme, and naming one would fight matugen. The icon theme is named because
    # matugen does not produce icons.
    settingsIni = ''
      [Settings]
      gtk-icon-theme-name=Gruvbox-Plus-Dark
      gtk-application-prefer-dark-theme=true
    '';
  in {
    # Imported unconditionally, then gated with mkIf. A conditional import
    # (`lib.optional config.my.dankMaterialShell …`) recurses: the module system
    # collects `imports` before it can settle `config`, and the flake's module
    # reads config in turn. The flake's module is inert until `enable = true`, so
    # hosting it on a host without DMS costs only the evaluation of the dms-shell
    # derivation — not a build, and not a closure entry.
    imports = [inputs.dms.homeModules.dank-material-shell];

    config = lib.mkIf config.my.dankMaterialShell {
      programs.dank-material-shell = {
        enable = true;

        # The flake's Home Manager module defaults systemd.enable to **false**
        # (mkEnableOption), unlike nixpkgs' NixOS module which defaults it true.
        # Without this DMS is installed but never starts.
        systemd.enable = true;

        # Bind to niri's unit rather than graphical-session.target: DMS is a shell
        # for the niri session, and graphical-session.target is also reached by
        # GNOME, where a second bar and launcher would appear over the desktop.
        # niri.service is the unit `niri-session` starts, and it ships with the
        # niri package; this is the same wiring DMS's docs suggest by hand
        # (`systemctl --user add-wants niri.service dms`).
        systemd.target = "niri.service";
      };

      xdg.configFile = {
        "gtk-3.0/gtk.css".text = "@import 'dank-colors.css';\n";
        "gtk-4.0/gtk.css".text = "@import 'dank-colors.css';\n";
        "gtk-3.0/settings.ini".text = settingsIni;
        "gtk-4.0/settings.ini".text = settingsIni;
      };
    };
  };

  # DankSearch is DMS's filesystem-search backend — DMS shells out to `dsearch`,
  # so it is installed system-wide with its user service rather than as a Home
  # Manager package. nixpkgs carries both the package and the module that wires
  # the unit (the DMS flake covers only DMS itself). It starts with the graphical
  # session because there is nothing to search for without one.
  my.modules.nixos.dank-material-shell = {
    lib,
    config,
    ...
  }: {
    config = lib.mkIf config.my.dankMaterialShell {
      programs.dsearch.enable = true;
      programs.dsearch.systemd.target = "graphical-session.target";

      # DMS's Caps Lock OSD reads input devices, and its own `dms setup` adds the
      # user to this group imperatively ("Adding user to input group for Caps
      # Lock OSD support"). Declaring it here means a fresh install does not
      # depend on having run that step, so the capability is visible in the
      # config rather than hidden system state.
      users.users.${config.my.baseUsername}.extraGroups = ["input"];
    };
  };
}
