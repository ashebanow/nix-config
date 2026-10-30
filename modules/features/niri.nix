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
# `inputs` is closed over at file level rather than requested as a module
# argument: Home Manager's module args do not include `specialArgs` (nixos-builder
# passes it to `nixosSystem` only), so `{ inputs, ... }:` inside a
# my.modules.home-manager.* module would fail with "attribute 'inputs' missing".
# This is the same shape dank-material-shell.nix uses.
{ inputs, ... }: {
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
          #
          # **Off**, because Dux Shell ships its own full niri config and this
          # module includes it (below). Their `niri.kdl` is niri's default config
          # plus DMS's changes — `prefer-no-csd`, a `screenshot-path`, an explicit
          # `animations` block, the GNOME/pavucontrol/steam window-rules,
          # `Mod+O`/`Mod+Tab` overview and the `dms/*.kdl` includes — so leaving
          # niri's defaults on as well would emit a second copy of every bind and
          # let include ordering decide the winner. One base, theirs.
          enableDefaultConfig = false;

          # Everything lives in extraConfig rather than `settings`.
          #
          # `extraConfig` is an attrs-merge point: each shell module concatenates
          # its own fragment here (see the shell modules), and the order in which
          # those land is not something to depend on — so a shell fragment must be
          # self-contained. Home Manager then writes the concatenation into
          # `~/.config/niri/config.kdl` and, with checkConfig (the default),
          # validates it with `niri validate` at build time.
          #
          # That build-time validation is why every `include` below is
          # `optional=true`: the `dms/*.kdl` fragments are Dux Shell's, seeded by
          # `dms setup` after the first switch (ADR 0003), so they must not exist
          # for the config to build.
          extraConfig = ''
            // ── Dux Shell's base config, verbatim from our pinned input ──────
            //
            // Included by absolute store path rather than vendored into this
            // repo, so "what does a default Dux install look like" is answered
            // by the flake lock and not by a file that drifts out of date
            // unnoticed. Source: `core/internal/config/embedded/niri.kdl` in
            // inputs.dms — the same text `dms setup` would write as
            // ~/.config/niri/config.kdl.
            //
            // It is niri's own default-config.kdl *plus* Dux Shell's changes, and
            // it carries its own `include optional=true "dms/*.kdl"` lines —
            // which resolve relative to this file's directory, i.e. the store
            // path, not ~/.config/niri. Those are inert; the real includes are
            // below, relative to the generated config. That duplication is
            // deliberate: it keeps the base unmodified, so a diff against
            // upstream is a plain `nix flake update` away.
            //
            // Consequence: `niri validate` prints seven warnings of the form
            //
            //   WARN niri_config: optional include not found:
            //     "/nix/store/…-source/core/internal/config/embedded/dms/colors.kdl"
            //
            // one per fragment, followed by `INFO niri: config is valid`. Those
            // are this include, not a broken setup: the path is under the
            // read-only store and never exists, `optional=true` is what keeps
            // them warnings instead of errors, and the fragments that actually
            // load are the ones in ~/.config/niri/dms/ via the includes below.
            // Do not "fix" them by vendoring the base config — that trades a
            // stable flake-lock answer for a file that rots.
            include "${inputs.dms}/core/internal/config/embedded/niri.kdl"

            // ── Dux Shell's own fragments, in Dux Shell's own order ──────────
            //
            // Generated by `dms setup`, then maintained by Dux Shell at runtime:
            // they are not Nix-owned (ADR 0003). `optional=true` because they do
            // not exist until that first run.
            //
            // Order matters and matches upstream's own config.kdl: colors,
            // layout, alttab, binds, outputs, cursor, input. Later includes win,
            // so e.g. `dms/input.kdl` supplies the touchpad tap and
            // natural-scroll that used to live in the base config.
            //
            // `outputs` is the one upstream includes that we do not: the EDID-
            // matched stanza below is the single source of truth for this
            // monitor, and ADR 0003 already declined to let the shell own it.
            include optional=true "dms/colors.kdl"
            include optional=true "dms/layout.kdl"
            include optional=true "dms/alttab.kdl"
            include optional=true "dms/binds.kdl"
            include optional=true "dms/cursor.kdl"
            include optional=true "dms/input.kdl"

            // ── Our only customisation: the monitor ──────────────────────���────
            //
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
          '';
        };
      };
    };
}
