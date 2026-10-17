# Serpantinum — the third shell choice for the niri session, selected with
# `my.desktopShell = "serpantinum"`. See docs/adr/0004 for the decision.
#
# Two things make this module look different from the Noctalia and DMS ones, and
# both come from upstream rather than from taste:
#
# 1. **It has no optional-dependency list to write.** Serpantinum's
#    nix/package.nix bakes ~45 binaries into both wrappers via
#    `--prefix PATH : lib.makeBinPath pathDeps` — grim, slurp, satty, zbar,
#    cliphist, wl-clipboard, matugen, playerctl, brightnessctl, ddcutil, cava,
#    easyeffects, gpu-screen-recorder and the rest. There is no option to prune
#    them and no need to add them. Installing those packages again here would be
#    a no-op that implies this module is responsible for them; it is not.
#
# 2. **Its settings are written once, not declaratively.** The Home Manager
#    module copies the merged settings JSON into
#    $XDG_CONFIG_HOME/serpantinum/settings.json *only if that file does not
#    already exist* (home.activation, `if [ ! -e … ]`). After the first switch,
#    editing `programs.serpantinum.settings` in Nix does nothing. To re-apply:
#
#        rm ~/.config/serpantinum/settings.json && home-manager switch
#
#    This contradicts the premise of a declarative config, which is why this
#    module sets the smallest useful settings block and says so, rather than
#    transcribing a full bar layout that would then silently drift.
{ inputs, ... }: {
  my.modules.nixos.serpantinum =
    {
      lib,
      config,
      ...
    }:
    {
      imports = [ inputs.serpantinum.nixosModules.default ];

      config = lib.mkIf config.my.desktopShellIsSerpantinum {
        # The NixOS module is small and does the system half of Serpantinum's
        # dependency story, all with mkDefault:
        #
        #   NetworkManager, Bluetooth          the network/bt widgets
        #   hardware.i2c.enable                ddcutil external brightness
        #   power-profiles-daemon              the power widget
        #   security.rtkit.enable              PipeWire realtime priority for cava
        #   services.pipewire (alsa + 32-bit)  volume control and the visualiser
        #   security.pam.services.serpantinum  the LOCK SCREEN, which probes
        #                                      /etc/pam.d/serpantinum — enable the
        #                                      Home Manager module alone and lock
        #                                      will not authenticate
        #   fonts.packages = iosevka nerd      its default bar font
        #
        # All of it is worth having, so it is enabled wholesale rather than
        # picked apart.
        programs.serpantinum.enable = true;

        # ddcutil and brightnessctl are already inside the Serpantinum wrapper's
        # PATH, but the user still needs the device access they require: the
        # wrapper supplies the binary, not the permission.
        users.users.${config.my.baseUsername}.extraGroups = [
          "i2c"
          "video"
        ];
      };
    };

  my.modules.home-manager.serpantinum =
    {
      lib,
      config,
      ...
    }:
    {
      imports = [ inputs.serpantinum.homeManagerModules.default ];

      config = lib.mkIf config.my.desktopShellIsSerpantinum {
        programs.serpantinum = {
          enable = true;

          # NOTE the attribute name: Serpantinum exports
          # `homeManagerModules`, not `homeModules` as Noctalia and DMS do.
          #
          # systemd.enable already defaults to true here (upstream uses
          # `default = pkgs.stdenv.isLinux`, not mkEnableOption) — the opposite
          # of the DMS flake. Bind it to niri's unit: graphical-session.target is
          # also reached under GNOME, where a second bar would draw over it.
          systemd = {
            enable = true;
            target = "niri.service";

            # The upstream module sets no WAYLAND_DISPLAY of its own; Qt must be
            # told it is a Wayland client or the daemon starts headless.
            environment = {
              QT_QPA_PLATFORM = "wayland";
            };
          };

          # Deliberately tiny — see the header on why editing this later is not
          # enough on its own. theme.matugen is the one setting worth forcing
          # from Nix: it drives wallpaper-derived colours, which is the feature
          # the shell is being evaluated for.
          settings = {
            theme = {
              matugen = true;
              mode = "dark";
            };

            # The bar is top-anchored, which is what this config's other shells
            # do and what the 4K panel's layout assumes.
            bar = {
              position = "top";
              style = "solid";
            };

            # Pin the location so the weather widget never IP-geolocates.
            #
            # Serpantinum's weather lookup starts by discovering where it is: it
            # asks ipapi.co, then ip-api.com (over PLAINTEXT HTTP), then
            # ipwho.is, disclosing the host's public IP to each in turn. Setting
            # latitude/longitude here short-circuits all three — the geolocation
            # path is only taken when coordinates are absent. This is the one
            # network behaviour in the shell worth suppressing by default rather
            # than leaving to a first-run click; see
            # docs/research/serpantinum-security-review.md (F-4).
            general = {
              location = {
                city = "Pleasanton";
                timezone = "America/Los_Angeles";
                latitude = 37.6624;
                longitude = -121.8747;
              };
              weatherUnit = "imperial";
            };
          };
        };

        # ── niri integration ─────────────────────────────────────────────
        # Upstream ships a niri autostart block and a keybind set; both are for a
        # *bare* niri, and neither is installed by the Home Manager module. The
        # clipboard and equaliser lines below are load-bearing and are easy to
        # miss: the HM module does not start the cliphist watchers, so without
        # them Serpantinum's clipboard panel stays empty forever.
        wayland.windowManager.niri.extraConfig = ''
          // Serpantinum's clipboard API reads cliphist's database, and cliphist
          // only records what a wl-paste watcher feeds it. These two are upstream's
          // own niri autostart lines, verbatim.
          spawn-at-startup "bash" "-c" "wl-paste --type text --watch cliphist store"
          spawn-at-startup "bash" "-c" "wl-paste --type image --watch cliphist store"

          // Starts the shell. serpantinumd flocks /tmp/serpantinumd.lock, launches
          // its wellbeing daemon, then runs quickshell in the foreground.
          spawn-at-startup "serpantinumd" "start"

          // Night-light control binds to wl-gammarelay-rs; without it the
          // blue-light-filter action is a no-op.
          spawn-at-startup "systemctl" "--user" "enable" "--now" "wl-gammarelay-rs"

          // The settings/launcher surfaces are Quickshell layers; keep them out of
          // the tiling grid.
          window-rule {
              match app-id="serpantinum"
              open-floating true
          }

          binds {
              Mod+D { spawn "serpantinum" "msg" "toggle" "launcher"; }
              Mod+C { spawn "serpantinum" "msg" "toggle" "clipboard"; }
              Mod+M { spawn "serpantinum" "msg" "toggle" "music"; }
              Mod+B { spawn "serpantinum" "msg" "toggle" "system"; }
              Mod+N { spawn "serpantinum" "msg" "toggle" "network"; }
              Mod+V { spawn "serpantinum" "msg" "toggle" "volume"; }
              Mod+W { spawn "serpantinum" "msg" "toggle" "wallpaper"; }
              Mod+A { spawn "serpantinum" "msg" "toggle" "autohide"; }

              // Screenshots go through the shell so they land in its own history
              // and picker (grim + satty + zbar are already on its PATH).
              Print { spawn "serpantinum" "screenshot"; }
              Shift+Print { spawn "serpantinum" "screenshot" "--edit"; }
              Super+Print { spawn "serpantinum" "screenshot" "--full"; }

              // Lock resolves through PAM's `serpantinum` service, created by the
              // NixOS half above.
              Mod+L { spawn "serpantinum" "lock"; }
              XF86PowerOff { spawn "serpantinum" "lock"; }

              Mod+R { spawn "serpantinum" "reload"; }

              // Media and volume route through the shell so its OSD and the bar's
              // media widget stay in sync; playerctl is on its PATH.
              Mod+Space { spawn "playerctl" "play-pause"; }
              XF86AudioPlay { spawn "playerctl" "play-pause"; }
              XF86AudioPause { spawn "playerctl" "play-pause"; }
              XF86AudioPrev { spawn "playerctl" "previous"; }
              XF86AudioNext { spawn "playerctl" "next"; }
              XF86AudioMute { spawn "serpantinum" "volume" "mute-toggle"; }
              XF86AudioMicMute { spawn "serpantinum" "volume" "mic-toggle"; }
              XF86AudioLowerVolume { spawn "serpantinum" "volume" "lower"; }
              XF86AudioRaiseVolume { spawn "serpantinum" "volume" "raise"; }
              XF86MonBrightnessDown { spawn "serpantinum" "brightness" "lower"; }
              XF86MonBrightnessUp { spawn "serpantinum" "brightness" "raise"; }
          }
        '';
      };
    };
}
