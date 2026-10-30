# niri + DankMaterialShell on yuzu

> **Superseded in part.** This file is the implementation plan for BOX-210 and
> is kept as the record of that work. The shell is no longer selected by
> `my.dankMaterialShell` (a boolean), and DMS's packages, layer-rules and
> `dms/*.kdl` includes no longer live in `niri.nix`. Shells are now chosen by
> `my.desktopShell = "dank" | "noctalia" | "serpantinum" | null`, and each
> shell's module owns its own tooling — see
> `docs/adr/0004-selectable-desktop-shell.md`. Everything below about DMS
> *itself* (why the flake, why `niri.service`, why `dms setup` cannot run
> against a Home-Manager-owned config) still applies whenever
> `desktopShell = "dank"`.
>
> **The upgrade to Dux Shell 2.0 (2026-10-22) is at the bottom of this file**,
> under "Upgrade to Dux Shell 2.0" — that section, not the 1.6.x "Rollout"
> above it, is the current procedure. The shell was renamed in 2.0 and its base
> niri config is now adopted wholesale; see `docs/adr/0005-dux-shell-2.md`.
> Note that DMS's `dms/*.kdl` includes live in `modules/features/niri.nix`, not
> in the shell module, because Dux Shell's own niri Home Manager module targets
> niri-flake and cannot be imported here.

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

---

# Upgrade to Dux Shell 2.0 (2026-10-22)

The steps above are the original 1.6.x rollout, kept as the record of BOX-210.
The 2.0 upgrade repeats most of them with different file sets — see
`docs/adr/0005-dux-shell-2.md` for what changed and why. Everything here is
done **after** `nixos-rebuild switch`, and steps 3–5 need a logged-in niri
session (Dux Shell 2.0 regenerates `input.kdl` and `layout.kdl` only when it is
actually running, and the new binary is only on PATH after the switch).

> **Step 3 was corrected on 2026-10-23 after being run for real.** The original
> text listed six `dms setup` fragments and claimed `input` and `cursor` were
> new 2.0 fragments that had to be deployed. They are not fragments at all —
> see step 3 for what actually generates them, and why `dms setup <fragment>`
> cannot be run cleanly against a Home-Manager-owned `config.kdl`.

## 0. Before switching

Nothing to remove this time: Home Manager already owns
`~/.config/niri/config.kdl`, and chezmoi already ignores it. Confirm the
chezmoi side separately (see the note at the end — deliberately not done yet).

## 1. Build, don't switch

```bash
nixos-rebuild build --flake /etc/nixos#yuzu
```

This is a real check, not a formality: Home Manager's `checkConfig` runs
`niri validate` on the generated config, which resolves the `include` lines.
A missing non-optional include fails here. The `dms/*.kdl` includes are
`optional=true`, so their absence is a warning, not a failure.

## 2. Switch and log into niri

`nixos-rebuild switch`, then log out and back in — not just a rebuild. Dux
Shell 2.0 reads `~/.config/dms/` and migrates settings from
`~/.local/share/DankMaterialShell/` on first launch. Expect the shell to look
different on first start; that is the point of the exercise.

First launch also seeds `~/.config/niri/dms/`: `ensureDmsConfigFiles()` touches
any missing fragment, and the `onIsNiriChanged` handler regenerates
`input.kdl` and `layout.kdl`. So by the time you look, most of step 3 may
already be done for you.

## 3. Reseed the niri fragments — `binds` only

The fragments in `~/.config/niri/dms/` are **1.6.3 output**. 2.0's `binds.kdl`
moves three binds and adds eight, so running 2.0 against the old file gives the
new shell with old keybinds. The local copies were verified byte-identical to
1.6.3 stock (with `ghostty` substituted), so nothing hand-made is lost:

```bash
dms setup binds      # prompts for a terminal: ghostty
```

**That is the only fragment `dms setup` can reseed here, and the only one that
needs reseeding.** Corrected 2026-10-23 against a live run; the original list
of six was wrong in three ways.

- **`input.kdl` and `cursor.kdl` are not setup outputs at all.** `input.kdl` is
  written at runtime by `NiriService.generateNiriInputConfig()`, triggered by
  `SettingsData.compositorInputRefreshNeeded` and by `CompositorService`
  reaching `isNiri`; `cursor.kdl` is written by the matching cursor signal (and
  is empty for niri, since its content is Hyprland-only). Neither appears in
  the `dms setup` subcommand list. `dms setup input` is not "new in 2.0" — it
  is not a fragment command at all, and running it does the legacy whole-config
  flow described below.
- **`layout.kdl` is generated at runtime too**, by
  `generateNiriLayoutConfig()`, which fires on the same `isNiri` transition and
  whenever the bar spacing or blur/xray settings change. It will be rewritten
  on first login whether or not you run a setup command.
- **`colors.kdl` and `alttab.kdl` are already correct.** Their 12:11 mtimes show
  2.0 wrote them on first launch, and their content matched the 1.6.3 copies
  byte for byte — there was nothing to change.

### `dms setup <fragment>` is not a fragment command

Every `dms setup` subcommand — including `binds` — runs the same interactive
whole-config flow: compositor, terminal, systemd, keybinds bookkeeping, then
deploy. The fragment named on the command line selects *which* file gets
written; it does not limit the run to that file. The deploy stage therefore
always backs up and rewrites `~/.config/niri/config.kdl` and
the terminal's own config (`~/.config/ghostty/config`), which is exactly the
thing Home Manager owns as a read-only symlink.

Consequences, all observed live:

- Against the Home Manager symlink the run dies with
  `failed to write config: open /home/<user>/.config/niri/config.kdl: read-only
  file system`, **after** writing the fragment. Check the fragment before
  concluding the run failed.
- It first copies `config.kdl` — following the symlink — to
  `~/.config/niri/config.kdl.backup.<timestamp>`. Harmless but easy to mistake
  for damage; delete it.
- Because the fragment is already written by the time the config write fails,
  and because a re-run then refuses with
  `FATAL  go: Error: binds already exists and is not empty`, the successful
  half of the run must be checked by content, not by exit status.
- `dms setup headless --compositor niri --terminal ghostty --skip-existing` is
  the scriptable equivalent and is *safe*: it skips the Home-Manager-owned
  files outright instead of trying to write them, and `--stock-binds` replaces
  only the keybinds.
- The `FATAL  go: Error: <fragment> already exists and is not empty` you get
  the first time is not a failure either: it means a previous 2.0 launch
  already generated the fragment and the stock content is already in place.
  Compare content before deleting anything.

What changed in `binds.kdl` 1.6.3 → 2.0, so you can check it took:
`Mod+M` task manager → media, `Mod+N` notifications → notepad,
`Super+X` → `Mod+X` power menu, plus new `Mod+A` (control centre), `Mod+D`
(dash), `Mod+Shift+C` (colour picker), `Mod+Alt+N` (night mode), `Mod+Alt+I`
(idle inhibit), `Mod+Return` (terminal), `Ctrl+Alt+M` (task manager) and
`XF86TouchpadToggle`. Note `Mod+Return` opens the **hotkey overlay** in 1.6.3
and the terminal in 2.0 — an easy one to check by eye:

```bash
grep -nE 'Mod\+M |Mod\+A |Mod\+Return|Ctrl\+Alt\+M' ~/.config/niri/dms/binds.kdl
```

`dms` names the 1.6.3 copy `binds.kdl.1.6.3.bak` if you renamed it by hand, or
`binds.kdl.bak` if a setup run moved it aside; either way it is inert and safe
to delete once the new content is confirmed.

## 4. Check the session, in this order

**Verified on yuzu 2026-10-23; every item below passes.** Two commands in the
original version of this list did not exist — corrected in place.

- `niri msg outputs` — 3840×2160 @ ≈60 Hz, scale 1.5. If the EDID stanza did
  not match, niri silently falls back to the preferred mode at **scale 1.0**.
- **There is no `niri msg config`.** `niri msg` in 26.04 offers no way to query
  the loaded config or list failed includes (subcommands: `outputs workspaces
  windows layers keyboard-layouts focused-output focused-window pick-window
  pick-color action output event-stream version request-error overview-state
  casts`). Failed includes surface as an in-session notification. To get the
  same assurance from a terminal, validate the same file the session loaded:
  `niri validate -c ~/.config/niri/config.kdl`, and treat a working
  `niri msg outputs` as proof the config applied.

  **Expect seven `optional include not found` warnings from `niri validate`**,
  all naming paths under `/nix/store/…-source/core/internal/config/embedded/dms/`,
  then `INFO niri: config is valid`. They are not a fault: they come from Dux
  Shell's embedded base config, which we include by store path (`niri.nix`) and
  which carries its own `include optional=true "dms/*.kdl"` lines that resolve
  relative to *its* directory. Everything it warns about is inert; the
  fragments that really load are `~/.config/niri/dms/*.kdl` via the includes
  relative to the generated config, and those are the ones whose absence would
  matter. See the comment at the `include` in `modules/features/niri.nix`.
- **Borders are off**. That is Dux Shell's default, not a bug — the base sets
  `border { off }` and nothing turns it back on (ADR 0005).
- **Lock and unlock early** (`Mod+Alt+L`). The PAM stack was measured working
  under 1.6.3 and 2.0 keeps the mechanism, but it is the one part that can
  strand a session — check it before trusting the session. After unlocking:
  `loginctl list-sessions` should still show exactly two entries, and
  `~/.local/state/dms/pam/dankshell` should carry a fresh mtime: that file is
  the 2.0 lock stack, and its presence proves the migration off
  `~/.local/state/DankMaterialShell/pam/` happened.
- Bar, launcher (`Mod+Space`), notifications (`Mod+Ctrl+N`), clipboard
  (`Mod+V`), screenshots (`Print`).
- `dfiles` — it should be running under `niri.service`; open/save dialogs still
  go to Nautilus (portal preference deliberately not taken).
- Calendar widget — its backend must be `dankcalendar` in settings, not the
  migrated-forward `khal` (which is not installed; `dcal` is). Check with
  `python3 -c "import json,pathlib;print(json.load(open(pathlib.Path.home()/'.config/dms/settings.json'))['calendarBackend'])"`
  and change it in DMS's own settings UI rather than by hand — the shell keeps
  `settings.json` in memory and will overwrite an external edit.
- A GTK app, to confirm matugen recolouring still writes
  `~/.config/gtk-{3,4}.0/dank-colors.css`.
- `dsearch` — **there is no `dsearch ping`**; `dsearch search ping` is a query
  for the word "ping", which returns plausible results and looks like a pass.
  Use `dsearch index status` and expect `Status: idle` with a recent `Last
  index` and a non-zero file count. For scoping, read
  `~/.config/danksearch/config.toml` (it lists `~` with `exclude_hidden = true`
  and `.cache` in `exclude_dirs`) or run `dsearch index check` on a path — but
  `index check` reports `cannot open metastore: metastore locked by another
  process` while the daemon runs, so its `indexed:` field is not usable
  in-session. `dsearch index dirs` is the other safe read.

## 5. Known leftover state

- ~~`~/.local/share/DankMaterialShell/`~~ — **already gone on yuzu** (checked
  2026-10-23). 1.6.3's settings were migrated into `~/.config/dms/` on first
  2.0 launch and the directory removed. Nothing to delete.
- ~~`~/.local/state/DankMaterialShell/pam/`~~ — inert since the 2026-10-23
  lock/unlock cycle; 2.0 writes `~/.local/state/dms/pam/dankshell`. Safe to
  delete. The rest of `~/.local/state/DankMaterialShell/`
  (`appusage.json`, `session.json`, `notepad-*`, `wellbeing/`) is also 1.6-era
  but harmless — check whether `appusage.json` still gets written today before
  deleting it, since it may be a still-used path.
- `~/.config/niri/dms/outputs.kdl` still holds a `DP-1` stanza that nothing
  reads (we exclude that include). Left in place rather than deleted: Dux Shell
  may rewrite it, and it is inert.
- **chezmoi**: `~/.local/share/chezmoi/home/.chezmoiignore.tmpl` still carries
  a "retired desktop trees, kept as a record" block referencing
  `.config/niri.bak` and `.config/DankMaterialShell.bak`. Those trees are
  already deleted from the repo — the entries are stale bookkeeping, and
  `.config/dms` (2.0's config dir) is not listed at all. Deliberately **not**
  changed in this upgrade; see the handoff note.

## Rollback

`nixos-rebuild switch --rollback` and re-pin `dms` to
`github:AvengeMedia/DankMaterialShell/stable` at `4a87e82`. Only `binds.kdl` is
restored from 1.6.3-era content by hand (step 3), so a rollback means putting
the 1.6.3 binds back — the `binds.kdl.bak` / `binds.kdl.1.6.3.bak` copy left by
the reseed, or `dms setup binds` from the rolled-back generation.
`~/.config/niri/dms/input.kdl` and `layout.kdl` will be regenerated by whatever
shell is running, so they need no attention. No data migration happens in the
other direction that matters: 2.0 writes `~/.config/dms/` and leaves
`~/.local/share/DankMaterialShell/` alone until first launch.
