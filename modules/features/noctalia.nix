# Noctalia v5 — the alternative shell for the niri session, selected with
# `my.desktopShell = "noctalia"`. See docs/adr/0004 for the decision and
# docs/research/wayland-shells-noctalia-serpantinum.md for the source research.
#
# Noctalia v5 is *not* the v4 Quickshell shell. It is a C++23 native Wayland
# client that draws its own layer surfaces and implements its own feature set,
# which changes what this module has to install:
#
#   screenshots, clipboard history, notifications, OSD, wallpaper, colour
#   generation (Material Color Utilities, vendored) and the lock screen are all
#   built in. The upstream runtime dependency tracker
#   (src/system/dependency_service.cpp) lists exactly one external tool:
#   `ddcutil`.
#
# So the dependency story here is the opposite of DankMaterialShell's: there is
# no grim/slurp/satty/wl-clipboard/playerctl/matugen to add, and adding them
# would be cargo-culting the v4 setup. What Noctalia does need is *services* —
# NetworkManager, BlueTooth, UPower, a power profile daemon, PipeWire — which is
# exactly what `recommendedServices.enable` turns on.
#
# Caution: do NOT reach for `pkgs.noctalia-shell`. That attribute is the legacy
# v4 Quickshell shell; the v5 package is `pkgs.noctalia`.
{ inputs, ... }: {
  my.modules.nixos.noctalia =
    {
      lib,
      config,
      pkgs,
      ...
    }:
    {
      # Imported unconditionally then gated with mkIf, for the same reason as the
      # DMS module: a conditional import that reads `config` recurses, because
      # `imports` is collected before `config` settles.
      #
      # This flake module `disabledModules` nixpkgs' own programs/wayland/
      # noctalia.nix, so importing BOTH would collide. We import only the flake
      # module, which is the one whose `package` default is the flake's own build
      # (and whose derivations are the ones the Noctalia cache serves).
      imports = [ inputs.noctalia.nixosModules.default ];

      config = lib.mkIf config.my.desktopShellIsNoctalia {
        programs.noctalia = {
          enable = true;

          # NetworkManager, Bluetooth, UPower and power-profiles-daemon, all
          # mkDefault so a host can still override any of them. This is the module
          # half of Noctalia's dependency story: its network/bluetooth/battery
          # widgets talk to these daemons over D-Bus and show nothing without
          # them. networking.networkmanager is already on for every desktop
          # (desktop.nix), the rest are Noctalia's.
          recommendedServices.enable = true;
        };

        # The flake's NixOS module does NOT set xdg.sounds.enable (the nixpkgs one
        # does). Noctalia plays freedesktop sound effects for its own events, and
        # without this the theme referenced by xdg.sounds is absent, so the
        # feature is silently inert.
        xdg.sounds.enable = true;

        # ── Optional runtime tools ────────────────────────────────────────
        # A deliberately short list. Each entry is here because Noctalia calls the
        # binary, not because shells generally want it:
        #
        #   ddcutil   external-monitor brightness over DDC/CI. The only entry in
        #             Noctalia's upstream dependency tracker. Opt-in on the
        #             Noctalia side ([brightness] enable_ddcutil = true) and needs
        #             hardware.i2c.enable plus the user in the `i2c` group. yuzu's
        #             panel is a desktop monitor reached over DisplayPort, so this
        #             is the tool that can dim it; the internal/backlight path is
        #             plain sysfs and needs nothing.
        #   xdg-utils the launcher and notification actions open URLs through
        #             `xdg-open`, which Noctalia probes with commandExists.
        #   libnotify `notify-send`, for scripts and the shell's own hooks.
        #
        # Noctalia's own wrapper already appends `git` (for plugins that clone from
        # a source) and `gsettings-desktop-schemas` to PATH and XDG_DATA_DIRS, so
        # those need not be repeated here.
        #
        # Deliberately NOT installed: grim, slurp, satty, wl-clipboard, cliphist,
        # matugen, playerctl, pamixer, swaybg, mako, dunst, swaync, fuzzel, wofi.
        # Those are the DMS/v4 dependency set; Noctalia implements those features
        # itself over wlr-screencopy, MPRIS and its own notification server.
        environment.systemPackages = with pkgs; [
          ddcutil
          xdg-utils
          libnotify
        ];

        hardware.i2c.enable = true;
        users.users.${config.my.baseUsername}.extraGroups = [ "i2c" ];
      };
    };

  my.modules.home-manager.noctalia =
    {
      lib,
      config,
      pkgs,
      ...
    }:
    {
      imports = [ inputs.noctalia.homeModules.default ];

      config = lib.mkIf config.my.desktopShellIsNoctalia {
        programs.noctalia = {
          enable = true;

          # The Home Manager module's `systemd.enable` keys off
          # `wayland.systemd.target` (a HOME MANAGER option), not
          # `graphical-session.target` — the two are different things. Home
          # Manager's wayland module defines that target, and niri's session
          # reaches it; leaving it unset would make the unit start at a target
          # nothing reaches.
          systemd.enable = true;

          # theme/wallpaper are the keys upstream's own docs example sets, so they
          # are verified against the schema. Everything else is left to Noctalia's
          # GUI: `settings` writes a real declarative config.toml, so the GUI's
          # changes are overwritten on the next switch — which is the opposite of
          # DMS's arrangement, and is why this config is deliberately minimal
          # rather than a full transcription of the defaults.
          settings = {
            theme = {
              mode = "dark";
              source = "builtin";
              builtin = "Catppuccin";
            };
          };

          # `checkConfig = true` (the default) runs `noctalia config validate` in
          # a build step, which forces building the C++23 package — defeating the
          # point of pinning the cache branch in flake.nix. The settings above are
          # three literal keys from the docs, so build-time validation buys
          # nothing that a failed start would not report more cheaply.
          checkConfig = false;
        };

        # Noctalia draws its own wallpaper layer, so no swaybg/hyprpaper is
        # needed. What it does need from the *host* is a place to put wallpapers
        # and the icon theme the session already ships.
        home.packages = with pkgs; [
          xdg-utils # `xdg-open` for launcher results and notification actions
          ddcutil # external-monitor brightness (see the NixOS half)
        ];
        # ── niri integration ─────────────────────────────────────────────
        # Noctalia's own niri page, in full. Noctalia does not spawn itself: the
        # compositor must, and `spawn-at-startup` is upstream's recommended path
        # (their systemd service exists too, but the docs rank compositor
        # autostart first, and it is the one that cannot race the Wayland socket).
        wayland.windowManager.niri.extraConfig = ''
          spawn-at-startup "noctalia"

          // The settings window is an ordinary window; float it at its design
          // size instead of letting niri tile it into a column.
          window-rule {
              match app-id="dev.noctalia.Noctalia"
              open-floating true
              default-column-width { fixed 1080; }
              default-window-height { fixed 920; }
          }

          // Option 1 from Noctalia's wallpaper page (blurred overview backdrop):
          // Noctalia publishes a dedicated blurred-and-tinted copy of the
          // wallpaper on `noctalia-backdrop`, and it belongs inside niri's
          // overview backdrop. This requires [niri/backdrop] to stay *enabled* in
          // Noctalia's own config — the other two upstream options need it off.
          layer-rule {
              match namespace="^noctalia-backdrop"
              place-within-backdrop true
          }

          binds {
              Mod+Space { spawn-sh "noctalia msg panel-toggle launcher"; }
              Mod+S { spawn-sh "noctalia msg panel-toggle control-center"; }
              Mod+Comma { spawn-sh "noctalia msg settings-toggle"; }
              Alt+Tab { spawn-sh "noctalia msg window-switcher hold"; }

              // Screenshots are Noctalia's own (wlr-screencopy) — no grim/slurp.
              // These override niri's upstream Print binding via niri.nix's
              // ordering (extraConfig comes last).
              Print { spawn-sh "noctalia msg screenshot-region"; }
              Shift+Print { spawn-sh "noctalia msg screenshot-region"; }

              // Noctalia owns the OSD, so volume and brightness go through it
              // rather than to raw pactl/brightnessctl — the keys are the same
              // XF86 names niri's default config binds, redeclared here so the
              // OSD appears.
              XF86AudioRaiseVolume { spawn-sh "noctalia msg volume-up"; }
              XF86AudioLowerVolume { spawn-sh "noctalia msg volume-down"; }
              XF86AudioMute { spawn-sh "noctalia msg volume-mute"; }
              XF86MonBrightnessUp { spawn-sh "noctalia msg brightness-up"; }
              XF86MonBrightnessDown { spawn-sh "noctalia msg brightness-down"; }
          }
        '';
      };
    };
}
