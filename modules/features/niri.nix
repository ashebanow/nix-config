# niri — the compositor for yuzu's default session, and the config DMS draws
# into. The NixOS half owns the session, portals and systemd units; the Home
# Manager half owns the config file. niri is a compositor, not a desktop
# environment: there is no bar, launcher or notification daemon here — that is
# DankMaterialShell (dank-material-shell.nix). See docs/adr/0003 for why the
# config is Home Manager's rather than chezmoi's or niri-flake's.
#
# programs.niri (NixOS) already wires displayManager.sessionPackages, the niri
# xdg-desktop-portal config, gnome-keyring and niri.service, so the Home
# Manager half deliberately sets no portal and no systemd units of its own.
_: {
  my.modules.nixos.niri = {
    lib,
    config,
    ...
  }: {
    config = lib.mkIf (config.my.desktop && lib.elem "niri" config.my.desktopSessions) {
      programs.niri.enable = true;
    };
  };

  my.modules.home-manager.niri = {
    lib,
    config,
    pkgs,
    ...
  }: {
    # Gated on the session list alone, not on my.desktop: my.desktop is set in
    # hosts/<host>/configuration.nix, which Home Manager does not evaluate, so
    # in this scope it is always false (see CONTEXT.md).
    config = lib.mkIf (lib.elem "niri" config.my.desktopSessions) {
      home.packages = with pkgs; [
        grim # region screenshots, driven by DMS's screenshot UI
        slurp
        satty
        wl-clipboard # DMS's clipboard history
        brightnessctl # the XF86MonBrightness keys DMS binds
        playerctl # the XF86AudioPlay/Next/Prev keys in niri's default config
        gruvbox-plus-icons # the session icon theme, paired with the GDM gruvbox theme
      ];

      wayland.windowManager.niri = {
        enable = true;

        # programs.niri (NixOS) configures xdg.portal and installs the user
        # units; configuring them here too would define the same unit twice.
        portalPackage = null;
        systemd.enable = false;

        # niri's own default-config.kdl: Mod+O/Q/H/J/K/L, the XF86 media keys,
        # numlock, touchpad tap and natural-scroll. DMS's binds are included
        # after it and win where they overlap.
        enableDefaultConfig = true;

        # Everything lives in extraConfig rather than `settings`: the module
        # emits extraConfigEarly, then the default-config include, then
        # `settings`, then extraConfig — and the DMS includes must come last so
        # that DMS's binds beat upstream's Mod+T -> alacritty and Mod+D -> fuzzel.
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

          // Let the wallpaper show through the overview, as DMS expects.
          layout {
              background-color "transparent"
          }

          layer-rule {
              match namespace="^quickshell$"
              place-within-backdrop true
          }

          layer-rule {
              match namespace="dms:blurwallpaper"
              place-within-backdrop true
          }

          // optional=true: these do not exist until `dms setup` has run once.
          include optional=true "dms/colors.kdl"
          include optional=true "dms/layout.kdl"
          include optional=true "dms/alttab.kdl"
          include optional=true "dms/binds.kdl"
        '';
      };
    };
  };
}
