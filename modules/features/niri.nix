# niri — the compositor for yuzu's default session. The NixOS half owns the
# session, portals and systemd units; the Home Manager half owns the config
# file.
#
# niri is a compositor, not a desktop environment: there is no bar, launcher or
# notification daemon here. That layer is the *shell*, and which shell is
# installed is `my.desktopShell` (see docs/adr/0004):
#
#   dank-material-shell.nix   modules/features/dank-material-shell.nix
#   noctalia.nix              modules/features/noctalia.nix
#   serpantinum.nix           modules/features/serpantinum.nix
#
# Everything shell-specific — its packages, its screenshot/clipboard/media
# tooling, its niri layer-rules and includes — lives in that shell's own module
# and is merged into `wayland.windowManager.niri.extraConfig` there. This file
# deliberately knows nothing about any of them, so adding a fourth shell is a
# new file and one enum value, not an edit here.
#
# programs.niri (NixOS) already wires displayManager.sessionPackages, the niri
# xdg-desktop-portal config, gnome-keyring and niri.service, so the Home
# Manager half deliberately sets no portal and no systemd units of its own.
_: {
  my.modules.nixos.niri =
    {
      lib,
      config,
      ...
    }:
    {
      config = lib.mkIf (config.my.desktop && lib.elem "niri" config.my.desktopSessions) {
        programs.niri.enable = true;
      };
    };

  my.modules.home-manager.niri =
    {
      lib,
      config,
      pkgs,
      ...
    }:
    {
      # Gated on the session list alone, not on my.desktop: my.desktop is set in
      # hosts/<host>/configuration.nix, which Home Manager does not evaluate, so
      # in this scope it is always false (see CONTEXT.md).
      config = lib.mkIf (lib.elem "niri" config.my.desktopSessions) {
        # Packages every session needs regardless of which shell draws on it.
        # The shell modules add their own on top (e.g. Noctalia needs almost
        # nothing because its screenshots/clipboard/OSD are built in, while
        # Serpantinum ships grim/satty/cliphist inside its own wrapper).
        home.packages = with pkgs; [
          brightnessctl # XF86MonBrightness keys — a sysfs tool, shell-agnostic
          gruvbox-plus-icons # the session icon theme, paired with the GDM gruvbox theme
        ];

        wayland.windowManager.niri = {
          enable = true;

          # programs.niri (NixOS) configures xdg.portal and installs the user
          # units; configuring them here too would define the same unit twice.
          portalPackage = null;
          systemd.enable = false;

          # niri's own default-config.kdl: Mod+O/Q/H/J/K/L, the XF86 media keys,
          # numlock, touchpad tap and natural-scroll.
          enableDefaultConfig = true;

          # Everything lives in extraConfig rather than `settings`: the module
          # emits extraConfigEarly, then the default-config include, then
          # `settings`, then extraConfig — and a shell's binds must come last so
          # that they beat upstream's Mod+T -> alacritty and Mod+D -> fuzzel.
          #
          # `extraConfig` is an attrs-merge point: each shell module concatenates
          # its own fragment here (see the shell modules), and the order in which
          # those land is not something to depend on — so a shell fragment must be
          # self-contained, and binds it needs to win must be declared in its own
          # file rather than expected to land after another's.
          extraConfig = ''
            // Matched by full "make model serial" as libdisplay-info reports them —
            // not by connector, and not by the EDID's raw "ACR". niri does not
            // accept a partial match, and it compares the serial exactly. Check
            // against `niri msg outputs` if the mode ever stops applying.
            //
            // No refresh rate: niri matches it to three decimals, and this mode is
            // 533250 kHz / (4000 x 2222) = 59.997 Hz, which everything else calls
            // "60.00". Omitting it takes the highest rate for 3840x2160.
            output "Acer Technologies XB321HK #ASOGedHl6RTd" {
                mode "3840x2160"
                scale 1.5
            }

            // Let each shell's wallpaper layer show through the overview. The
            // shells' own fragments set the matching `layout { background-color
            // "transparent"; }` and their layer-rules.
            layout {
                background-color "transparent"
            }

            // A shell that registers notification actions needs this to activate
            // windows from them; every shell here does, and it is harmless if not.
            debug {
                honor-xdg-activation-with-invalid-serial
            }
          '';
        };
      };
    };
}
