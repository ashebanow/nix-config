# niri + DankMaterialShell on yuzu

Design record and implementation plan. The decisions and their rejected
alternatives are in `docs/adr/0003-niri-and-dank-material-shell.md`; the
vocabulary is in `CONTEXT.md`. This file is the *how*.

Work item: BOX-210 —
https://linear.app/boxbow/issue/BOX-210/niri-dankmaterialshell-as-yuzus-default-session-gnome-kept-as-fallback
The ticket body is the spec; this file is the implementation plan.

## Summary

yuzu gains niri as its default session with DankMaterialShell as its shell,
GNOME stays installed and selectable as the emergency session, and GDM stays
the display manager. Everything is nixpkgs-native except DMS itself, which comes
from its upstream flake. Nothing new is added to chezmoi; the dotfiles' dead
desktop trees are retired.

## 1. Flake input

`flake.nix` gains, alongside the other pinned inputs:

```nix
    # DankMaterialShell — its own flake rather than nixpkgs' programs.dms-shell,
    # which trails DMS's release cadence (1.6.1 against 1.6.2 at the time of
    # writing). The flake no longer ships quickshell, so pkgs.quickshell is used
    # either way. See docs/adr/0003.
    dms = {
      url = "github:AvengeMedia/DankMaterialShell/stable";
      inputs.nixpkgs.follows = "nixpkgs";
    };
```

`nix flake update dms` is the deliberate bump path; `stable` is a branch, so the
lock file is what pins it.

## 2. Option model

`lib/my-options-module.nix`: the `desktopEnvironment` enum is replaced by

```nix
    desktopSessions = lib.mkOption {
      type = lib.types.listOf (lib.types.enum ["gnome" "niri"]);
      default = [];
      description = "Graphical sessions this host offers at the login screen.";
    };
    desktopDefaultSession = lib.mkOption {
      type = lib.types.enum ["gnome" "niri"];
      default = "gnome";
      description = "The session the display manager starts when nobody chooses one.";
    };
    dankMaterialShell = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Enable the DankMaterialShell desktop shell (needs a session it can draw on).";
    };
```

`hosts/yuzu/capabilities.nix` — not `configuration.nix` — sets them, because
Home Manager has its own `config.my` instance and the niri config is a Home
Manager module:

```nix
  # Desktop session model. Set here rather than in configuration.nix because
  # capabilities.nix is imported into BOTH the NixOS and the Home Manager
  # module lists (see modules/infra/nixos-builder.nix).
  my.desktopSessions = ["niri" "gnome"];
  my.desktopDefaultSession = "niri";
  my.dankMaterialShell = true;
```

`hosts/yuzu/configuration.nix` drops `my.desktopEnvironment = "gnome";`.
`my.desktop = true` stays where it is (NixOS-scope only).

An assertion in `desktop.nix` should hold `desktopDefaultSession` inside
`desktopSessions`, so a typo fails the build instead of the login screen.

## 3. `modules/features/desktop.nix`

The display manager becomes unconditional for a desktop, and the session sets
become data:

```nix
      # GDM is the display manager for every desktop here, whatever sessions the
      # host offers: it is the supported way to start GNOME (see docs/adr/0003).
      services.displayManager.gdm.enable = lib.mkIf config.my.desktop true;
      services.desktopManager.gnome.enable =
        lib.mkIf (config.my.desktop && lib.elem "gnome" config.my.desktopSessions) true;
      services.displayManager.defaultSession =
        lib.mkIf config.my.desktop config.my.desktopDefaultSession;
```

## 4. `modules/features/gnome.nix`

Gate changes from `desktopEnvironment == "gnome"` to
`lib.elem "gnome" config.my.desktopSessions`. Body unchanged.

## 5. `modules/features/niri.nix` (new)

Two modules in one file, following the existing feature-module shape: the NixOS
half owns the session, portals and systemd units; the Home Manager half owns the
config file. The NixOS `programs.niri` already wires `sessionPackages`, the
niri portal config, `gnome-keyring` and `niri.service`, so the HM half sets
`portalPackage = null` to avoid configuring the portals twice.

```nix
    config = lib.mkIf (config.my.desktop && lib.elem "niri" config.my.desktopSessions) {
      programs.niri.enable = true;
    };
```

Home Manager half:

```nix
      home.packages = with pkgs; [
        grim slurp satty          # region screenshots for DMS's screenshot UI
        wl-clipboard              # DMS's clipboard
        brightnessctl playerctl   # the XF86 keys DMS binds
        gruvbox-plus-icons        # session icon theme
      ];

      wayland.windowManager.niri = {
        enable = true;
        portalPackage = null;     # the NixOS module configures xdg.portal
        enableDefaultConfig = true;   # niri's own default-config.kdl, includes keybinds
        extraConfig = ''
          output "Acer Technologies XB321HK #ASOGedHl6RTd" {
              mode "3840x2160"
              scale 1.5
          }

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

          include optional=true "dms/colors.kdl"
          include optional=true "dms/layout.kdl"
          include optional=true "dms/alttab.kdl"
          include optional=true "dms/binds.kdl"
        '';
      };
```

Notes that are load-bearing:

- **Everything is in `extraConfig`, not `settings`.** The module emits
  `extraConfigEarly`, then the upstream default-config include, then `settings`,
  then `extraConfig` — and the DMS includes must come last so DMS's binds win
  over upstream's `Mod+T` → alacritty and `Mod+D` → fuzzel.
- **`mode` has no refresh rate.** niri matches refresh exactly to three decimals
  and this mode is ≈59.997 Hz; omitting it makes niri take the highest rate for
  3840×2160, which is the mode we want.
- **The output target is the full `make model serial`**, and `make` is
  libdisplay-info's resolved manufacturer name, not the EDID's raw `ACR`. niri
  does not accept a partial match. Verified by running a probe against
  libdisplay-info on the live EDID: `Acer Technologies XB321HK #ASOGedHl6RTd`.
- **`optional=true` on the includes** because `dms/*.kdl` does not exist until
  `dms setup` has run.

## 6. `modules/features/dank-material-shell.nix` (new)

Home Manager only, with the flake module imported conditionally so lumquat's
evaluation does not construct the DMS derivation:

```nix
      # Imported unconditionally then gated with mkIf: a conditional import that
      # reads config recurses, because the module system collects `imports`
      # before it can settle `config`.
      imports = [inputs.dms.homeModules.dank-material-shell];

      config = lib.mkIf config.my.dankMaterialShell {
        programs.dank-material-shell = {
          enable = true;
          # The flake's HM module defaults this to false (mkEnableOption), unlike
          # nixpkgs' NixOS module: without it DMS installs but never starts.
          systemd.enable = true;
          # graphical-session.target is also reached under GNOME, where a second
          # bar would draw over the desktop; niri.service is niri's own unit.
          systemd.target = "niri.service";
          # settings / clipboardSettings / session are deliberately left unset:
          # DMS owns its own settings.json at runtime, and declaring them would
          # make its GUI read-only (docs/adr/0003).
        };
      };
```

`enableVPN`, `enableDynamicTheming`, `enableAudioWavelength` and
`enableCalendarEvents` keep the flake's defaults (all true). No plugins.

The same file also declares `users.users.<user>.extraGroups = ["input"]`, because
DMS's Caps Lock OSD reads input devices and `dms setup` adds that group
imperatively. Declaring it keeps a fresh install off that manual step.

The same file carries a small NixOS half for **DankSearch**, DMS's
filesystem-search backend: DMS shells out to `dsearch`, so it is installed
system-wide with its user service (`programs.dsearch.enable = true`,
`systemd.target = "graphical-session.target"`) rather than as a Home Manager
package. nixpkgs carries both the package and the module; the DMS flake covers
only DMS itself.

## 7. `modules/features/gdm.nix` (new)

GDM is the decision in `desktop.nix`; this module only themes it. Theme and icon
names are the ones the built packages actually install (`Gruvbox-Dark` from
`gruvbox-gtk-theme`, `Gruvbox-Plus-Dark` from `gruvbox-plus-icons`).

```nix
      services.displayManager.gdm.extraPackages = [
        pkgs.gruvbox-gtk-theme
        pkgs.gruvbox-plus-icons
        pkgs.gnome-shell-extensions     # provides the User Themes extension
      ];

      programs.dconf.profiles.gdm.databases = [
        {
          settings."org/gnome/desktop/interface" = {
            gtk-theme = "Gruvbox-Dark";
            icon-theme = "Gruvbox-Plus-Dark";
          };
          settings."org/gnome/shell" = {
            enabled-extensions = ["user-theme@gnome-shell-extensions.gcampax.github.com"];
          };
          settings."org/gnome/shell/extensions/user-theme" = {
            name = "Gruvbox-Dark";
          };
        }
      ];
```

The last two settings are the **unverified** part: GDM's own gnome-shell may
ignore user extensions. If it does, the greeter keeps the gruvbox GTK theme
and icons but the shell stays Adwaita — drop those two settings and record that
in the ADR, which already describes this as best-effort.

## 8. Chezmoi

In `~/.local/share/chezmoi` (`.chezmoiroot` is `home`, so patterns match
**target** paths):

- Rename to `*.bak`: `private_dot_config/niri/` → `niri.bak/`,
  `private_dot_config/DankMaterialShell/` → `DankMaterialShell.bak/`.
- Ignore them by adding `.config/niri.bak` and `.config/DankMaterialShell.bak`
  to the **existing `home/.chezmoiignore.tmpl`** — there is no plain
  `.chezmoiignore`, and the template already carries the machine-class host
  gating for these trees. The new entries are deliberately *not* host-gated:
  these trees are retired for every host, not just for one class of host.
- Delete: `private_dot_config/private_gtk-3.0/`,
  `private_dot_config/private_gtk-4.0/`, `hypr/`, `waybar/`, `swaync/`,
  `swaylock/`, `wlogout/`, `nwg-look/`, `xfce4/`, `xsettingsd/`, `swappy/`,
  `hop/`, `qt5ct/`, `qt6ct/`. All of it is recoverable from the dotfiles git
  history; use `git mv`/`git rm` so it stays that way.
- `cava/` and the app dials (kitty, ghostty, zed, …) stay: those tools are
  installed.

`gtk.css` and `settings.ini` were not DMS's and not correct — the old shim
imported a Breeze `colors.css` and pinned `Andromeda-dark`/`breeze-dark`. DMS
writes only `dank-colors.css`, so the shim and a gruvbox icon theme come from
Home Manager instead — in `dank-material-shell.nix`, since the files exist to
serve DMS's generated colours:

```nix
      xdg.configFile."gtk-3.0/gtk.css".text = "@import 'dank-colors.css';";
      xdg.configFile."gtk-4.0/gtk.css".text = "@import 'dank-colors.css';";
```

After editing the source, `chezmoi apply`, then remove whatever it leaves behind
under `~/.config/` for the deleted trees.

## 9. Docs corrections

`docs/architecture.md` and `docs/plan.md` were checked and are lumquat-centric:
neither mentions a desktop, GNOME or yuzu, so neither needed a change. The
assumption that they described a GNOME-only yuzu was wrong. (`architecture.md`
still lists a Colmena deployment decision that the config no longer uses —
pre-existing drift, not part of this work.)

## Rollout

0. **Remove the stale targets before switching.** Home Manager refuses to
   clobber files it does not own, and it now owns `~/.config/niri/config.kdl`
   and `~/.config/gtk-{3,4}.0/{gtk.css,settings.ini}`, which chezmoi had put
   there. Either let `chezmoi apply` remove them, or delete them by hand, before
   the switch — otherwise the activation fails. The trees chezmoi no longer
   manages (the 16 removed above) can go at the same time.
1. Implement, then `nixos-rebuild build` (or the `just` recipe) — no switch.
   The HM niri module's `checkConfig` runs `niri validate` on the generated
   config at build time, so a KDL mistake fails here rather than at login
   (which is how the `#`-vs-`//` KDL comment mistake was caught).
2. Switch, locally, while GNOME is running. GNOME is unaffected by a niri
   session being enabled.
3. Seed DMS's niri fragments. **Not** the bare `dms setup`: that run also
   rewrites `~/.config/niri/config.kdl`, which Home Manager owns as a read-only
   symlink into the generation, so it backs the config up and then dies with
   `read-only file system`. Use the per-file subcommands, which only write
   `~/.config/niri/dms/*.kdl`:

   ```bash
   dms setup binds     # prompts for a terminal: ghostty
   dms setup layout
   dms setup colors
   dms setup alttab
   ```

   Compositor detection is by binary presence (`niri` exists), not by the running
   session, so this works from GNOME. Only these four are needed: for niri, DMS's
   `cursor` and `windowrules` specs deploy *empty* files (they are Hyprland-only),
   and `outputs` is Home Manager's by design — see the ADR on why DMS's monitor
   settings UI therefore will not move this output.
4. Log into niri from GDM and check, in this order:
   - `niri msg outputs` — confirm 3840×2160 @ ≈60 Hz and 150% scale. If the
     output stanza did not match, niri silently uses the preferred mode at
     **scale 1.0**, which is the visible symptom; compare the printed
     make/model/serial against the stanza.
   - the bar, launcher (`Mod+Space`), notifications, clipboard (`Mod+V`).
   - **lock and unlock** (`Mod+Alt+L` or `Super+Alt+L`) early — the lock screen
     is the one part that needs PAM, and it is better to find a PAM problem
     before trusting the session.
   - a screenshot, an X11 app under `xwayland-satellite`, a GTK app to confirm
     matugen recolouring, and the `XF86` audio/brightness keys.
5. Reboot into GDM and confirm: the gruvbox greeter, GNOME still selectable and
   working, and niri the default session.

## Rollback

`nixos-rebuild switch --rollback` returns the system. The only hand-made state
is `~/.config/niri/dms/*.kdl` from `dms setup`, which is inert once the niri
session is gone.
