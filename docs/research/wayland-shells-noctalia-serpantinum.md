# Wayland Desktop Shells: Noctalia v5 vs Serpantinum

Research date: sourced from upstream docs, upstream source trees, and nixpkgs
`master` package definitions. Every claim below is traceable to one of:

- `https://docs.noctalia.dev/noctalia/getting-started/nixos/`
- `https://docs.noctalia.dev/noctalia/getting-started/running-the-shell/`
- `https://docs.noctalia.dev/noctalia/compositor-settings/niri/`
- `github.com/noctalia-dev/noctalia` — `flake.nix`, `nix/home-module.nix`,
  `nix/nixos-module.nix`, `PACKAGING.md`, `BUILDING.md`,
  `src/system/dependency_service.cpp`
- `github.com/NixOS/nixpkgs` — `pkgs/by-name/no/noctalia/package.nix`,
  `pkgs/by-name/no/noctalia-shell/package.nix`,
  `pkgs/by-name/no/noctalia-qs/package.nix`,
  `nixos/modules/programs/wayland/noctalia.nix`
- `https://serpantinum.dev/installation/nixos`,
  `https://serpantinum.dev/installation/nixos/home-manager`,
  `https://serpantinum.dev/configure/compositors/niri`
- `github.com/ilyamiro/serpantinum` — `flake.nix`, `nix/nixos-module.nix`,
  `nix/hm-module.nix`, `nix/package.nix`, `nix/settings-options.nix`,
  `bin/serpantinum`, `bin/serpantinumd`, `compositors/niri/`

Anything marked **UNVERIFIED** could not be confirmed from those sources.

---

## Headline difference

These two are architecturally different, and that difference drives almost every
other detail:

| | Noctalia v5 | Serpantinum |
|---|---|---|
| Implementation | C++23, Meson, native Wayland + OpenGL ES. **No Qt, no GTK, no Quickshell** (`PACKAGING.md`) | Quickshell (Qt6/QML) + bash/python helper scripts |
| In nixpkgs | **Yes** — `pkgs.noctalia` (5.3.0) | **No** — flake-only |
| External CLI deps | Almost none (see table) | ~40 tools, all baked into a `PATH` wrapper |
| Settings write | declarative (`xdg.configFile`) | **activation script, writes once, then never again** |
| Rendering of screenshots / clipboard / notifications / lock / colors | built-in | delegates to `grim`/`satty`/`cliphist`/`matugen`/etc. |

A note on names: the nixpkgs attribute **`noctalia-shell`** is the *legacy
Quickshell v4* package (4.7.7) and pulls in `noctalia-qs` (a Quickshell fork).
It is **not** the thing you want for "Noctalia v5". The v5 package attribute is
**`noctalia`**.

---

# SHELL 1 — Noctalia (v5)

## 1. Flake input

```nix
# up-to-date but may not be in the binary cache yet
noctalia.url = "github:noctalia-dev/noctalia";

# OR: guaranteed-cached commit (recommended if using the cachix cache)
noctalia.url = "github:noctalia-dev/noctalia/cachix";
```

Verified: the repo has exactly these branches — `cachix`, `feat/freebsd`,
`feat/umbriel-audio-bridge`, `legacy-v4`, `main`. There is no
`nixos-unstable`-style branch. `cachix` always points at the latest *already
cached* commit; `main` tracks HEAD and may miss the cache.

**Critical cache caveat (verbatim from docs):**

> To use the binary cache, you have to omit `inputs.nixpkgs.follows` from the
> Noctalia input with flakes/tack or avoid `inherit pkgs;` with npins/tarball.

Adding `inputs.noctalia.inputs.nixpkgs.follows = "nixpkgs"` changes the
derivation hash and **disables the cache** — you then compile a C++23 codebase
locally. Pick one: cache, or dedup'd nixpkgs.

## 2. Does it need a binary cache? (yes, practically)

```
substituter:  https://noctalia.cachix.org
public key:   noctalia.cachix.org-1:pCOR47nnMEo5thcxNDtzWpOxNFQsBRglJzxWPp3dkU4=
```

Which public key to use depends on your cache tooling — `extra-trusted-public-keys`
for substituters, `extra-substituters` for the URL. NixOS scope:

```nix
nix.settings = {
  extra-substituters = [ "https://noctalia.cachix.org" ];
  extra-trusted-public-keys = [
    "noctalia.cachix.org-1:pCOR47nnMEo5thcxNDtzWpOxNFQsBRglJzxWPp3dkU4="
  ];
};
```

Flake scope: identical under `nixConfig = { ... }`.

## 3. Module attribute names

Exported from `github:noctalia-dev/noctalia` `flake.nix`:

| Attribute | Notes |
|---|---|
| `nixosModules.default` | the only nixos module output |
| `homeModules.default` | the only home-manager module output |
| `hjemModules.default` | for Hjem instead of HM |
| `packages.<system>.default` | the shell itself |
| `overlays.default` | adds `pkgs.noctalia` |

There are **no** `nixosModules.noctalia` / `homeModules.noctalia` aliases —
only `.default`.

## 4. NixOS module options — `programs.noctalia`

Two independent implementations exist and you must know which you get:

- **Flake module** (`nix/nixos-module.nix`) — `disabledModules = [ "programs/wayland/noctalia.nix" ]`,
  so importing the flake module **shadows** the nixpkgs one.
- **nixpkgs module** (`nixos/modules/programs/wayland/noctalia.nix`) if you
  import nothing and just use `pkgs.noctalia`.

Option paths in both:

| Option | Type | Default | Flake mod | nixpkgs mod |
|---|---|---|---|---|
| `programs.noctalia.enable` | bool | `false` | ✅ | ✅ |
| `programs.noctalia.package` | `package` / `nullOr package` | flake's own pkg / `pkgs.noctalia` | ✅ (`null` default) | ✅ |
| `programs.noctalia.systemd.enable` | bool | `false` | ✅ | ✅ |
| `programs.noctalia.systemd.target` | str | `"graphical-session.target"` | ✅ | ✅ |
| `programs.noctalia.recommendedServices.enable` | bool | `false` | ✅ | ✅ |

That is the **entire** option surface. There is no `settings` option at NixOS
scope — settings are Home Manager only.

Differences worth knowing:

- Flake module sets `hardware.graphics.enable = lib.mkDefault true`; nixpkgs
  module does not.
- Flake module sets `environment.PATH = lib.mkForce null` on the user unit;
  nixpkgs module does not.
- Flake module sets `restartTriggers = [ cfg.package ]`.
- nixpkgs module sets `xdg.sounds.enable = true` (needed for the
  `sound-theme-freedesktop` runtime dep); the flake module does not.
- `recommendedServices.enable` sets, all with `lib.mkDefault true`:
  `networking.networkmanager.enable`, `hardware.bluetooth.enable`,
  `services.upower.enable`, `services.power-profiles-daemon.enable`
  (flake module guards the last with `lib.mkIf (!config.services.tuned.enable)`,
  so tuned wins if already enabled).

### NixOS snippet (recommended)

```nix
{ inputs, pkgs, ... }:
{
  imports = [ inputs.noctalia.nixosModules.default ];

  programs.noctalia = {
    enable = true;
    recommendedServices.enable = true;
    systemd.enable = true;          # optional; see "how to start" below
  };
}
```

Or with zero flake and just nixpkgs unstable (loses `systemd.enable` wiring
only if your nixpkgs predates the module):

```nix
{ pkgs, ... }:
{
  programs.noctalia.enable = true;
  programs.noctalia.recommendedServices.enable = true;
}
```

## 5. Home Manager module options — `programs.noctalia`

From `nix/home-module.nix` (the real, current file):

| Option | Type | Default |
|---|---|---|
| `programs.noctalia.enable` | bool | `false` |
| `programs.noctalia.package` | `mkPackageOption pkgs "noctalia" { nullable = true; }` | `pkgs.noctalia` |
| `programs.noctalia.systemd.enable` | bool | `false` |
| `programs.noctalia.settings` | `oneOf [ tomlFormat.type str path ]` | `{ }` |
| `programs.noctalia.customPalettes` | `attrsOf (oneOf [ jsonFormat.type str path ])` | `{ }` |
| `programs.noctalia.checkConfig` | bool | `true` |

Notes:

- **No** `recommendedServices` at HM scope.
- `settings` accepts an **attrset** (serialized to TOML via `pkgs.formats.toml`),
  a **raw TOML string**, or a **path** to a `.toml` file. It writes to
  `$XDG_CONFIG_HOME/noctalia/config.toml`.
- `checkConfig = true` runs `noctalia config validate` at build time — note this
  requires building the package, so it forces a store path eval of `cfg.package`.
- `customPalettes.<name>` → `$XDG_CONFIG_HOME/noctalia/palettes/<name>.json`.
- `systemd.enable` uses `config.wayland.systemd.target` (a **home-manager**
  option, from HM's `wayland` module) rather than a NixOS-style target string.
  This is a real gotcha: it is *not* `graphical-session.target`.
- Assertion: `systemd.enable` requires `package != null`.
- The module declares `disabledModules = [ "programs/noctalia.nix" "programs/noctalia" ]`
  and renames `validateConfig` → `checkConfig`, because HM upstream turned
  `programs/noctalia` into a folder. Import the flake module and the flake's
  version wins.

`X-Restart-Triggers` is wired to the generated config + palettes, so `settings`
changes restart the service.

### Home Manager snippet

```nix
{ inputs, ... }:
{
  imports = [ inputs.noctalia.homeModules.default ];

  programs.noctalia = {
    enable = true;
    systemd.enable = true;
    settings = {
      theme = {
        mode = "dark";
        source = "builtin";
        builtin = "Catppuccin";
      };
      wallpaper = {
        enabled = true;
        default.path = "/path/to/wallpapers/wallpaper.png";
      };
    };
  };
}
```

`theme` and `wallpaper` above are the exact keys used in the official docs
example, so they are verified. For the full TOML schema, see the docs
configuration section per-feature (`[shell]`, `[bar]`, `[theme]`, `[audio]`,
`[brightness]`, `[idle.behavior.*]`, `[niri/backdrop]`, `[lockscreen]`,
`[shell.screenshot]`, `[widget.<name>]`, `[keybinds]`). The `settings` attrset is
passed straight to TOML with no schema validation beyond `noctalia config validate`.

## 6. Optional / recommended external CLI dependencies

This is where Noctalia differs sharply from v4 and from Serpantinum. From
`PACKAGING.md` § Runtime plus source inspection:

| Feature | Binary | nixpkgs attribute | Status |
|---|---|---|---|
| Screenshots (region / full / annotate) | **none** — uses `wlr-screencopy` + Noise's own overlay | — | ✅ built-in |
| Clipboard history / management | **none** — built-in panel (`[shell]` `clipboard_*` keys) | — | ✅ built-in |
| Media / music control | **none** — MPRIS via D-Bus | — | ✅ built-in |
| Volume / audio | **none** — PipeWire client; needs the **daemon** | `pipewire` + `wireplumber` (>= 0.5) | ⚠️ daemon required |
| OSD | **none** — built-in overlay | — | ✅ built-in |
| Notifications | **none** — registers `org.freedesktop.Notifications` itself | — | ✅ built-in |
| Idle / lock screen | **none** — native actions `lock`, `screen_off`, `suspend`, `lock_and_suspend`; PAM service `login` | `pam` (lib, already linked) | ✅ built-in |
| Color generation (matugen?) | **none** — Material Color Utilities is **vendored** in `third_party/` | — | ✅ built-in, no matugen |
| Network widget | **none** — talks to NetworkManager over D-Bus | `networkmanager` | ⚠️ service |
| Bluetooth widget | **none** — D-Bus | `bluez` (service: `hardware.bluetooth.enable`) | ⚠️ service |
| Battery / power devices | **`upower`** | `upower` | optional |
| External monitor brightness (DDC/CI) | **`ddcutil`** | `ddcutil` | optional, opt-in via `[brightness] enable_ddcutil = true` |
| Built-in display brightness | **none** — sysfs kernel backlight | — | ✅ built-in |
| Plugins from git sources / plugin auto-update | **`git`** | `gitMinimal` | required only for plugins |
| Opening URLs (launcher, notifications) | **`xdg-open`** | `xdg-utils` | optional (checked via `commandExists`) |
| Shell sound effects | **none** (libsndfile decodes) but needs a *theme* | `sound-theme-freedesktop` (nixpkgs mod sets `xdg.sounds.enable = true`) | optional |
| Privileged actions (systemctl etc.) | `run0` or `pkexec` | `systemd` / `polkit` | optional |
| Secret persistence | a **Secret Service provider** (GNOME Keyring / KWallet / KeePassXC) | `gnome-keyring` etc. | optional, recommended |
| Launcher search / calc / emoji | **`fzy`** (fuzzy), **`libqalculate`**, `assets/emoji.json` — all vendored/bundled | — | ✅ built-in |
| Wallpaper | **none** — draws its own layer surfaces | — | ✅ built-in |

The single-file authoritative tracker in the source is
`src/system/dependency_service.cpp`, whose `kTrackedTools` array contains
**exactly one** entry: `"ddcutil"`. That is strong confirmation that v5 has no
other external-tool dependencies it cares about.

nixpkgs already wraps `noctalia` with `--suffix PATH : ${gitMinimal}` and
`--suffix XDG_DATA_DIRS : ${gsettings-desktop-schemas}` in `postFixup`, so
`git` and the GNOME settings schemas are handled for you.

**Do not** install `grim`, `slurp`, `swappy`, `satty`, `cliphist`, `wl-clipboard`,
`matugen`, `playerctl`, `pamixer`, `brightnessctl`, `swaybg`, `hyprpaper`,
`mako`, `dunst`, `swaync`, `fuzzel`, `wofi`, or `anyrun` for Noctalia v5.
Those belong to the v4/Quickshell world.

### Explicit non-dependency caveat: notification daemon conflict

From `PACKAGING.md` § Session conflicts — on non-Plasma sessions Noctalia
**registers** `org.freedesktop.Notifications` **and**
`org.kde.StatusNotifierWatcher`. Do not run `mako`, `dunst`, `swaync`, or a
second tray host alongside it.

## 7. How to start it under niri

Three options; the docs rank them.

**Option A — compositor autostart (docs: "primary method", "recommended")**

`~/.config/niri/config.kdl`:
```kdl
spawn-at-startup "noctalia"
```
If niri expects startup commands to return, use daemon mode:
```kdl
spawn-at-startup "noctalia" "--daemon"
```
`--daemon` returns after the shell initializes; the optional polkit auth agent
starts asynchronously afterwards.

**Option B — systemd user service (via the modules)**

`programs.noctalia.systemd.enable = true`. The unit is literally named
**`noctalia`** (`systemd.user.services.noctalia`), `Restart = on-failure`,
`WantedBy`/`PartOf`/`After` the configured target.

Gotcha from the docs: with the service enabled you should also enable
`launch_apps_as_systemd_services`, otherwise apps Noctalia launches get killed
when the service restarts.

**Option C — manual:** `noctalia`

Logs go to `$XDG_CACHE_HOME/noctalia/noctalia.log` (`~/.cache/noctalia/noctalia.log`
fallback), rotated to `noctalia.log.1` at 1 MiB. **No systemd unit ships with
the package** (`PACKAGING.md`: "Not shipped ... systemd units") — the unit comes
from the Nix modules only.

IPC control is `noctalia msg ...`; it uses a Unix socket under `XDG_RUNTIME_DIR`.

## 8. Niri-specific config

Autostart line (above), plus:

```kdl
// Floating settings window
window-rule {
  match app-id="dev.noctalia.Noctalia"
  open-floating true
  default-column-width { fixed 1080; }
  default-window-height { fixed 920; }
}

debug {
  // Allows notification actions and window activation from Noctalia.
  honor-xdg-activation-with-invalid-serial
}
```

Layer namespaces you can target with `layer-rule`:

| Namespace | Purpose |
|---|---|
| `noctalia-bar-*` | bar |
| `noctalia-notification` | notifications |
| `noctalia-dock` | dock |
| `noctalia-panel`, `noctalia-attached-panel` | panels |
| `noctalia-osd` | OSD |
| `noctalia-window-switcher` | window switcher (a **window**, not a layer — docs put it in a `layer-rule` anyway; treat with suspicion) |
| `noctalia-backdrop` | blurred overview backdrop |
| `noctalia-wallpaper` | stationary wallpaper layer |
| `noctalia-desktop-widget-<type>-<id>` | one per desktop widget |

Useful regex used by the docs themselves:
`match namespace="^noctalia-(bar-[^\"]+|notification|dock|panel|attached-panel|osd)$"`.

Three wallpaper/overview strategies are documented — pick exactly one:

1. **Blurred overview wallpaper** — `layer-rule { match namespace="^noctalia-backdrop"; place-within-backdrop true; }`,
   requires `[niri/backdrop]` **enabled** in Noctalia config.
2. **Stationary wallpaper** — `layer-rule { match namespace="^noctalia-wallpaper"; place-within-backdrop true; }`
   plus `layout { background-color "transparent"; }`; requires `[niri/backdrop]`
   **disabled**.
3. **Flat colored overview** — `overview { backdrop-color "#26233a"; }`; also
   requires `[backdrop]` disabled.

Blur caveat: blur needs **niri >= 26.04**; adding the blur rules on older niri is
a config error. When Noctalia detects `ext-background-effects` it publishes blur
regions automatically, so *omitting* the layer-rule does **not** disable blur —
you must set `blur false` explicitly.

Optional: type-to-launch from overview, off by default:
```kdl
[shell]
niri_overview_type_to_launch_enabled = true
```

Laptop: with the lock screen enabled, `[lockscreen].lock_before_suspend = true`
is the default. To lock on lid close from niri:
```kdl
switch-events { lid-close { spawn "noctalia" "msg" "session" "lock-and-suspend"; } }
```
and set `HandleLidSwitch=ignore` / `HandleLidSwitchExternalPower=ignore` in
`/etc/systemd/logind.conf`.

Keybind example (all verified from the docs page):
```kdl
Mod+Space { spawn-sh "noctalia msg panel-toggle launcher"; }
Mod+S     { spawn-sh "noctalia msg panel-toggle control-center"; }
Mod+Comma { spawn-sh "noctalia msg settings-toggle"; }
Alt+Tab   { spawn-sh "noctalia msg window-switcher hold"; }
XF86AudioRaiseVolume  { spawn-sh "noctalia msg volume-up"; }
XF86AudioLowerVolume  { spawn-sh "noctalia msg volume-down"; }
XF86AudioMute         { spawn-sh "noctalia msg volume-mute"; }
XF86MonBrightnessUp   { spawn-sh "noctalia msg brightness-up"; }
XF86MonBrightnessDown { spawn-sh "noctalia msg brightness-down"; }
```
Both `spawn` and `spawn-sh` work for Noctalia binds. Screenshots:
`noctalia msg screenshot-region`, `noctalia msg screenshot-fullscreen [pick|DP-2|all]`.

## 9. Package names

| nixpkgs attribute | Version | What it is |
|---|---|---|
| **`pkgs.noctalia`** | 5.3.0 | ✅ **Noctalia v5**. `pname = "noctalia"`, `mainProgram = "noctalia"`, binary `noctalia` |
| `pkgs.noctalia-shell` | 4.7.7 | ❌ legacy Quickshell v4 shell — different code, different config, `mainProgram = "noctalia-shell"` |
| `pkgs.noctalia-qs` | 0.0.12 | Quickshell fork, dependency of `noctalia-shell` only |
| `pkgs.noctalia-greeter` | — | greetd greeter, separate product |

`pkgs.noctalia` build inputs (nixpkgs `package.nix`): requires **sdbus-c++ >= 2**
(`sdbus-cpp_2`) and **WirePlumber 0.5** pkg-config — a reason the openSUSE
packaging note says Leap 16.0 can't build it. Also `libqalculate` (calculator),
`libjxl`/`libwebp`/`stb` (images), `libsndfile` (sounds), `pam`, `polkit`,
`libsecret`, `pipewire`, `jemalloc`, `libical`, `md4c`, `tomlplusplus`,
`nlohmann_json`, `wayland`/`wayland-protocols`, `libGL`, `cairo`, `pango`,
`harfbuzz`, `freetype`, `fontconfig`, `glib`, `libxkbcommon`, `librsvg`, `curl`.
C++23, GCC 13+ / Clang 16+.

## 10. Gotchas

1. **`inputs.nixpkgs.follows` kills the binary cache.** C++23 compile from
   scratch otherwise.
2. **`main` ≠ cached.** Use the `cachix` branch if you want a guaranteed hit.
3. **Two modules named `programs.noctalia`.** Importing the flake's NixOS module
   disables the nixpkgs one via `disabledModules`. Don't mix assumptions.
4. **No `settings` at NixOS scope.** TOML config only through HM (or Hjem, or by
   hand).
5. **HM `systemd.enable` keys off `config.wayland.systemd.target`**, not
   `graphical-session.target`. Set `wayland.systemd.target` correctly or the
   unit will start at the wrong time.
6. **`checkConfig = true` (default) runs `noctalia config validate` at build
   time**, forcing a real build of the package — which is exactly what you were
   trying to avoid by not compiling. Consider `checkConfig = false` when pairing
   with the cachix cache, or accept the build.
7. **Notification/tray conflict.** Noctalia owns `org.freedesktop.Notifications`
   and `org.kde.StatusNotifierWatcher` on non-Plasma. Remove mako/dunst/swaync.
8. **`xdg.sounds.enable = true`** is set by the *nixpkgs* module but **not** by
   the flake module. If you import the flake module, set it yourself or you lose
   the freedesktop sound theme.
9. **`launch_apps_as_systemd_services`** should be on when using the service.
10. **v4 → v5 is not an upgrade.** Different package, different config files, no
    migration. Only compositor keybinds carry over (the IPC verbs changed).
11. **The `noctalia` binary needs its `assets/` tree** — fonts, glyphs, emoji,
    translations, templates. Never package just the binary.
12. **PipeWire *daemon* required**, not just the libraries, for audio/OSD/privacy
    indicators/spectrum. Libraries alone → those features silently stay off.
13. **Do not use `pkgs.noctalia-shell`** expecting v5.

---

# SHELL 2 — Serpantinum

## 1. Flake input

```nix
serpantinum.url = "github:ilyamiro/serpantinum";
```

No branch, no cache branch, no `follows` guidance in the docs. **UNVERIFIED:**
whether a binary cache exists — none is documented and nothing in the flake
configures `nixConfig`. It is a `stdenv.mkDerivation` copying QML/bash sources,
so it's cheap-ish, but it pulls in `quickshell` and a Qt6 stack.

It also has a non-flake input `serpantinum-wallpapers`
(`github:ilyamiro/shell-wallpapers`, `flake = false`) that HM's module receives
but that the current `hm-module.nix` destructures and then **does not use**.

Not in nixpkgs — a `nixpkgs` code search for `serpantinum` returns 0 results.

## 2. Module attribute names

From `flake.nix`:

| Attribute | |
|---|---|
| `nixosModules.default` | ✅ documented |
| `nixosModules.serpantinum` | alias |
| `homeManagerModules.default` | ✅ documented (note: **`homeManagerModules`**, not `homeModules`) |
| `homeManagerModules.serpantinum` | alias |
| `packages.<system>.default`, `packages.<system>.serpantinum` | |
| `apps.<system>.default`, `apps.<system>.serpantinumd` | |
| `overlays.default` | |

The attribute is `homeManagerModules`, which differs from Noctalia's
`homeModules`. Easy to typo.

## 3. NixOS module — `programs.serpantinum`

From `nix/nixos-module.nix`, the **entire** option surface is one option:

| Option | Type | Default |
|---|---|---|
| `programs.serpantinum.enable` | bool | `false` |

That's it. No `package`, no `systemd`, no `settings` at NixOS scope. Enabling it
sets, all `mkDefault`:

```nix
networking.networkmanager.enable = true;
hardware.bluetooth.enable        = true;
hardware.i2c.enable              = true;   # for DDC/CI brightness
services.power-profiles-daemon.enable = true;
security.rtkit.enable            = true;   # PipeWire realtime
security.pam.services.serpantinum = { };   # for the lock screen
services.pipewire = { enable, alsa.enable, alsa.support32Bit, pulse.enable } = true;
fonts.packages = [ pkgs.nerd-fonts.iosevka ];
```

Note the **`i2c`** requirement (DDC/CI) and the **PAM service literally named
`serpantinum`** — the lock screen probes `/etc/pam.d/serpantinum`.

### NixOS snippet

```nix
{ serpantinum, ... }:
{
  imports = [ serpantinum.nixosModules.default ];
  programs.serpantinum.enable = true;
}
```

## 4. Home Manager module — `programs.serpantinum`

From `nix/hm-module.nix`:

| Option | Type | Default |
|---|---|---|
| `programs.serpantinum.enable` | bool | `false` |
| `programs.serpantinum.package` | `package` | `serpantinum.packages.${system}.default` |
| `programs.serpantinum.settings` | freeform submodule (see below) | `{ }` |
| `programs.serpantinum.systemd.enable` | bool | **`pkgs.stdenv.isLinux`** (i.e. defaults to **on**) |
| `programs.serpantinum.systemd.target` | str | `"graphical-session.target"` |
| `programs.serpantinum.systemd.environment` | `attrsOf str` | `{ }` |

`systemd.enable` defaulting to `true` is unusual — with the module imported at
all, you get a user service.

### How settings actually work — read this before designing around it

`settings` is layered, not declarative:

1. Reads the package's bundled `config/serpantinum/settings.json` as the base
   template (`builtins.fromJSON (builtins.readFile "${self}/config/serpantinum/settings.json")`).
2. Deep-merges your `cfg.settings` (with all `null`s filtered out — hence every
   typed field defaults to `null` meaning "unset, use template value").
3. Generates `serpantinum-settings.json` in the store.
4. **Copies it to `$XDG_CONFIG_HOME/serpantinum/settings.json` only if that file
   does not already exist**, in a `home.activation` script:

```nix
home.activation.serpantinumSettings = hm.dag.entryAfter [ "writeBoundary" ] ''
  run mkdir -p ${...}
  if [ ! -e ${settingsTarget} ]; then
    run install -m 0644 ${settingsFile} ${settingsTarget}
  fi
'';
```

Consequences — these are the biggest gotchas in this whole report:

- Settings are **not** a `xdg.configFile` symlink. They are a **writable copy**
  in the user's home.
- **Editing `settings` in Nix after the first activation does nothing.** The file
  exists, so the `if` short-circuits. The shell keeps reading the old JSON.
- To actually apply a change you must `rm ~/.config/serpantinum/settings.json`
  and re-run `home-manager switch`, or edit the JSON by hand.
- `X-Restart-Triggers = [ settingsFile ]` points at the **store** file, which
  will never be what the app reads after first activation. So config changes do
  not reliably restart the service either.
- Also: the app itself writes back to that JSON at runtime (the `serpantinum`
  CLI calls `set_setting`/`jq`), so the file drifts from your Nix source of truth.
- `wallpaperDir` has `mkDefault "${config.home.homeDirectory}/Pictures/Wallpapers"`.

### Settings keys (from `nix/settings-options.nix`)

Top-level sections: `general`, `bar`, `dock`, `launcher`, `osd`, `widgets`,
`theme`, `idle`, `inputs`, `notifications`, `display`, plus `wallpaperDir`
(and its alias `wallpaper_dir`). Unknown keys pass through unchanged
(`freeformType = jsonFreeform`).

**`general`** — `language`, `avatarPath`, `wallpaperDir`, `workspaceCount`,
`muteSfx`, `sfxVolume` (0-100), `screenshotCaptureOnRelease`, `weatherInterval`
(minutes), `weatherUnit` (`metric`|`imperial`|`standard`), `quickactions`,
`location.{city,timezone,latitude,longitude}`.

**`bar`** — `position` (`left`|`right`|`top`|`bottom`), `width`, `opacity`,
`style` (`solid`|`fill`|`modular`), `distinctPills`, `centerByEdges`, `autohide`,
`autohideTimeout`, `workspaceCount`, `hideEmptyWorkspaces`, `workspacesStyle`
(`pills`|`numbers`|`pacman`), `timeStyle` (`classic`|`material`|`badge`),
`timeShowDate`, `visBarCount` (4-32), `visAlignment`, `visContinuous`,
`sysmonStyle` (`wave`|`circle`|`bars`), `sysmonStats` (`cpu`/`ram`/`temp`/`disk`),
`batStyle`, `batShowPercent`, `batShowIcon`, `wifiStyle`, `wifiShowIcon`,
`wifiShowName`, `btStyle`, `btShowIcon`, `btShowName`, `volStyle`,
`volShowIcon`, `volShowPercent`, `kbStyle`, `kbShowIcon`, `mediaInfoMode`
(`duration`|`author`), `mediaWidth` (80-400), `mediaShowIcon`,
`mediaShowControls`, `groupColors` (attrset of hex), `time.format`,
`modules.{left,center,right}` — each a `listOf (either str (listOf str))` where a
bare string is a module name and a nested list clusters icons.

**`dock`** — `enabled`, `position`, `onTop`, `elementSize`, `floating`,
`opacity`, `exclusive`, `exclusiveMode` (alias), `autohide`, `smartAutohide`,
`autohideTimeout`, `editing`, `apps`, `overrideBoundsCorrection`,
`enableScrolling`, `visibleElements`, `hoverScale`, `cascadeScale`,
`focusRunning`, `showRunningIndicators`, `showRunningApps`, `runningScope`
(`auto`|`workspace`|`all`).

**`launcher`** — `position` (`top`|`bottom`|`left`|`right`|`center`), `width`,
`itemCount`, `terminalCommand`, `smartRanking`.

**`osd`** — `horizontalPosition` (0-100), `verticalPosition`, `orientation`
(`horizontal`|`vertical`), `showCapsLock`, `showNumLock`, `showAirplane`,
`attachToBar`.

**`widgets`** — `hideBarInRedactor`.

**`theme`** — `fontFamily`, `borderRadius`, `activePreset`, **`matugen`** (bool —
"auto-generate colors from the current wallpaper"), `mode` (dark/light),
`schemeType` (matugen scheme type), `colors` (Catppuccin-shaped hex palette:
`base`, `crust`, `mantle`, `text`, `surface0..2`, ...).

**`idle`** — `enabled`, `manualInhibit`, `actions.{dim,dpms,lock,suspend}`,
`customActions`. Each action: `id`, `name`, `desc`, `enabled`, `timeout`
(seconds), `respectInhibitors`, `mprisInhibit`, `command`, `beforeCommand`,
`resumeCommand`, `warningTimeout`, `warningCommand`, `isCustom`.

**`notifications`** — `dnd`, `position` (`top right`|`top center`|`top left`|
`bottom right`|`bottom center`|`bottom left`|`custom`), `horizontalPosition`,
`verticalPosition`, `sound`, `soundFile`, `showEmptyGraphic`.

**`inputs`** — `passwordReveal`.

**`display`** — `monitors.<output>` with `enabled`, `powerEnabled`, `scale`,
`auto`, `temperature`.

### Home Manager snippet

```nix
{ serpantinum, ... }:
{
  imports = [ serpantinum.homeManagerModules.default ];

  programs.serpantinum = {
    enable = true;
    systemd.enable = true;
    settings = {
      wallpaperDir = "/home/username/Pictures/Wallpapers";

      general = {
        language = "en";
        weatherUnit = "metric";
        weatherInterval = 30;
      };

      bar = {
        position = "top";
        style = "solid";
        width = 40;
        workspaceCount = 10;
        modules = {
          left = [ "workspaces" ];
          center = [ "time" ];
          right = [ "tray" [ "kb" "wifi" "bt" "vol" "bat" ] ];
        };
      };

      theme = { fontFamily = "Adwaita Mono"; borderRadius = 12; matugen = true; };

      notifications = { dnd = false; position = "top right"; sound = true; };
    };
  };
}
```

## 5. External CLI dependencies

Serpantinum is the opposite of Noctalia here: `nix/package.nix` builds a
`pathDeps` list and bakes it into both binaries via
`--prefix PATH : ${lib.makeBinPath pathDeps}`. **All of these are installed
automatically** — you do not add them to `environment.systemPackages`, and there
is no option to prune them. The table therefore documents *what feature each
unlocks*, not what you must install.

| Feature | Binary | nixpkgs attribute | Notes |
|---|---|---|---|
| Screenshots (region/full/annotate) | `grim` | `grim` | regions via Quickshell overlay, not `slurp` |
| Screenshot annotate / editor | `satty` | `satty` | `GSK_RENDERER=gl satty --init-tool brush --copy-command "wl-copy ..."` |
| Screenshot OCR / QR | `zbarimg` | `zbar` | `zbarimg --xml` |
| Screen recording | `gpu-screen-recorder` (default) or `wf-recorder` | `gpu-screen-recorder`, `wf-recorder` | selected by `VIDEO_BACKEND` |
| Clipboard copy | `wl-copy` | `wl-clipboard` | |
| Clipboard history store | `cliphist` + `wl-paste` | `cliphist`, `wl-clipboard` | **you must run the watchers yourself** (see niri autostart) |
| Media / music control | *(none)* — native Quickshell MPRIS | — | `import Quickshell.Services.Mpris`; `playerctl` is in `pathDeps` but grep found no invocation |
| Volume / audio | *(none)* — native `Quickshell.Services.Pipewire` | `pipewire`, `pulseaudio` libs | `pamixer`/`pavucontrol`/`pactl`/`alsa-utils` present but audio path is native |
| Equalizer | `easyeffects` | `easyeffects` | needs `systemctl --user enable --now easyeffects` |
| Audio visualizer | `cava` | `cava` | `import`ed as a cava process (`Cava.qml`) |
| Brightness (internal) | `brightnessctl` | `brightnessctl` | via `serpantinum brightness` script |
| Brightness (external DDC/CI) | `ddcutil` | `ddcutil` | needs `hardware.i2c.enable` |
| Night light / blue light | `wl-gammarelay-rs` | `wl-gammarelay-rs` | run as a service to bind its shortcut |
| Wallpaper | *(none)* — Quickshell layer surface | — | no swaybg/hyprpaper needed |
| Color generation | **`matugen`** | `matugen` | `theme.matugen = true`; `Matugen.qml`, `theme_sorter.py` |
| Idle / lock screen | *(none)* — native Quickshell Pam | — | PAM service `serpantinum` |
| Notifications | *(none)* — built-in daemon | — | config under `notifications`; `libnotify`/`notify-send` for its *own* toasts |
| Network widget | `nmcli` | `networkmanager` | `NetworkPopup.qml` |
| Bluetooth widget | *(none)* — D-Bus via python `jeepney` | `bluez` + python env | `python3.withPackages (ps: [ ps.websockets ps.jeepney ])` |
| Battery | `acpi` | `acpi` | |
| System monitor | `lm_sensors`, `fastfetch`, `pciutils` | same | |
| Launcher search | `fd`, `ripgrep` | `fd`, `ripgrep` | |
| Launcher calc | *(none)* | — | UNVERIFIED whether it has a calculator |
| Launcher emoji | *(none)* | — | UNVERIFIED |
| OSD | *(none)* — built-in | — | config under `osd` |
| File manager / terminal / browser | `nautilus`, `kitty`, `xdg-desktop-portal-gtk` | same | defaults |
| Misc | `jq`, `bc`, `file`, `ffmpeg`, `imagemagick`, `inotify-tools`, `iw`, `socat`, `util-linux`, `psmisc`, `wget`, `wmctrl`, `power-profiles-daemon`, `wireplumber`, `calf` | eponymous | |

Missing from `pathDeps` but required in practice: `bash` (both `bin/serpantinum`
and `bin/serpantinumd` are `#!/usr/bin/env bash`) and `flock`/`pgrep`/`pkill`
(from `util-linux`/`psmisc`, which *are* included).

**Does the launcher delegate to fuzzel/wofi/anyrun/rofi?** **No.** There is no
invocation of any of those (grep across `*.qml`/`*.sh`/`*.py` found none). It is
a QML launcher built in. `dmenu_provider.cpp` in Noctalia is a *Noctalia*
feature, not Serpantinum.

**Qt/Quickshell runtime libs** (`qtDeps`, wired via `QML2_IMPORT_PATH` /
`QT_PLUGIN_PATH`): `quickshell`, `qt6.qtwayland`, `qt6.qtmultimedia`,
`qt6.qt5compat`, `qt6.qtwebsockets`, plus `libpulseaudio` and `pipewire`
buildInputs. Note it uses **upstream `quickshell`**, not a fork — and that Qt5 is
listed in the package's function arguments but unused.

## 6. How it starts

**Option A — systemd user service (the module path)**

`programs.serpantinum.systemd.enable = true` (default on). Unit name is
**`serpantinum`**:

```nix
systemd.user.services.serpantinum = {
  Unit = {
    Description = "Serpantinum shell daemon";
    After = [ cfg.systemd.target ];
    PartOf = [ cfg.systemd.target ];
    X-Restart-Triggers = [ "${settingsFile}" ];
  };
  Service = {
    ExecStart = "${cfg.package}/bin/serpantinumd start";
    Restart = "on-failure";
    KillMode = "mixed";
    TimeoutStopSec = "5s";
  };
  Install.WantedBy = [ cfg.systemd.target ];
};
```

Note there is **no `Environment = [ "WAYLAND_DISPLAY=..." ]` by default** — only
via `systemd.environment` (the docs' example is `{ QT_QPA_PLATFORM = "wayland"; }`).
Verify the unit actually sees the Wayland socket before trusting it.

**Option B — niri autostart (what upstream ships)**, from
`compositors/niri/config/autostart.kdl`:

```kdl
spawn-at-startup "bash" "-c" "wl-paste --type text --watch cliphist store"
spawn-at-startup "bash" "-c" "wl-paste --type image --watch cliphist store"
spawn-at-startup "systemctl" "--user" "enable" "--now" "easyeffects"
spawn-at-startup "serpantinumd" "start"
```

That is the full run sequence: two `cliphist` watchers, `easyeffects`, then the
shell. The `serpantinumd start` path is `exec`-like — it `flock`s
`/tmp/serpantinumd.lock`, writes `/tmp/serpantinumd.pid`, launches
`quickshell/guide/wellbeing/launch_daemon.sh` (the focus/wellbeing daemon,
`focus_daemon.py`) and then `quickshell -p "$MAIN_QML"` in the foreground.

**Option C — manual:** `serpantinumd start` / `stop` / `status`, and
`serpantinum` for everything else.

Process management is via `/tmp/serpantinumd.pid` + `pkill -f`. Note this means
Serpantinum and a stale daemon can fight; also `pkill` patterns are broad.

`serpantinum` CLI subcommands (verified from `bin/serpantinum`):
`launch {start,widgetredactor}`, `msg {workspace N [move], open ...|toggle ...|close}`,
`ipc ...`, `kill`, and the allowlisted scripts `exit`, `lock`, `volume`,
`reload`, `weather`, `location`, `screenshot`, `brightness`, `current_focus`,
`monitors_detect`, `location_manual`, `blue_light_filter`.

## 7. Niri-specific config

`~/.config/niri/config.kdl` includes a `config/` directory:
`env.kdl`, `input.kdl`, `output.kdl`, `layout.kdl`, `autostart.kdl`,
`keybinds.kdl`. The autostart block is quoted above.

Keybinds from the docs:

```kdl
Mod+D { spawn "serpantinum" "msg" "toggle" "launcher"; }
Mod+B { spawn "serpantinum" "msg" "toggle" "system"; }
Mod+C { spawn "serpantinum" "msg" "toggle" "clipboard"; }
Mod+M { spawn "serpantinum" "msg" "toggle" "music"; }
Mod+W { spawn "serpantinum" "msg" "toggle" "wallpaper"; }
Mod+S { spawn "serpantinum" "msg" "toggle" "calendar"; }
Mod+N { spawn "serpantinum" "msg" "toggle" "network"; }
Mod+V { spawn "serpantinum" "msg" "toggle" "volume"; }
Mod+H { spawn "serpantinum" "msg" "toggle" "guide"; }
Mod+A { spawn "serpantinum" "msg" "toggle" "autohide"; }

Mod+1 { spawn "serpantinum" "msg" "workspace" "1"; }
Mod+Shift+1 { spawn "serpantinum" "msg" "workspace" "1" "move"; }

Mod+L { spawn "serpantinum" "lock"; }
Mod+R { spawn "serpantinum" "reload"; }
Print { spawn "serpantinum" "screenshot"; }   # add --edit or --full
```

Brightness/volume on `XF86MonBrightness*` and `XF86Audio*`.

Workspace switching is **routed through the shell** so bar indicators update —
this is a real difference from Noctalia, where niri owns workspaces and Noctalia
just observes.

Upstream provides no niri `window-rule`/`layer-rule` for Serpantinum in the docs
page; the bundled `compositors/niri/config/` has `env/input/output/layout/
autostart/keybinds` but no layer rules. **UNVERIFIED:** the exact layer
namespaces Serpantinum uses (I did not enumerate them from the QML).

## 8. Gotchas

1. **Settings only apply once.** The `home.activation` script is
   `if [ ! -e settings.json ]`, so after the first switch, changes to
   `programs.serpantinum.settings` are silently ignored. You must delete
   `~/.config/serpantinum/settings.json` to re-apply. This is the single most
   important thing to know and it is not documented.
2. **Config is not a symlink** — it's a writable copy that the app itself mutates
   at runtime. There is no clean declarative story.
3. **`X-Restart-Triggers` is misleading** — it points at the store file, not the
   copy the app reads.
4. **`systemd.enable` defaults to `true`.** Importing the HM module gives you a
   service whether you asked or not.
5. **Attribute is `homeManagerModules`**, not `homeModules`.
6. **Not in nixpkgs.** No binary cache documented; you compile `quickshell` if
   you don't already have it.
7. **~40 binaries on `PATH`**, unconditionally. No way to slim it down. Expect a
   large closure (nautilus, kitty, easyeffects, gpu-screen-recorder, ffmpeg,
   imagemagick, matugen, ...).
8. **`cliphist` needs manual watchers.** The HM module does *not* start
   `wl-paste --watch cliphist store`; only the bundled niri `autostart.kdl`
   does. If you use the systemd path, clipboard history stays empty.
9. **`easyeffects` likewise** — `systemctl --user enable --now easyeffects` is in
   the niri autostart, not the module.
10. **PAM service name is `serpantinum`** and is created by the *NixOS* module.
    Enable only the HM module and the lock screen won't authenticate.
11. **Requires `hardware.i2c.enable`** for `ddcutil` external brightness — set by
    the NixOS module.
12. **Quickshell ABI risk.** `quickshell` is a fast-moving Qt6 package; there is
    no version pin between Serpantinum and nixpkgs' `quickshell`, so a nixpkgs
    update can break it.
13. **Runtime process wrangling via `/tmp/*.pid` and `pkill -f`** — brittle,
    especially with `KillMode = mixed` plus a daemon that spawns a python
    `focus_daemon.py`.
14. **`bin/serpantinum` calls `jq` and mutates settings on first run** (it writes
    `general.language` from `$LANG` if unset), so even a "pristine" install
    immediately diverges from your Nix config.
15. **`serpantinum-wallpapers` flake input is unused** by the current HM module.

---

## Side-by-side recommendation for this repo

Both integrate cleanly with niri and both have a NixOS + Home Manager module.
The deciding factors are not features but *what you can reason about*:

- **Noctalia v5** wins on: being in nixpkgs (`pkgs.noctalia`), a real declarative
  `xdg.configFile`-based `settings`, near-zero external deps, and a documented
  binary cache. Its costs: one more flake input (or a nixpkgs-only install that
  loses `systemd.enable` wiring), the `follows`-breaks-cache trap, and
  `checkConfig` forcing a build.
- **Serpantinum** wins on: a genuinely tiny module surface and zero setup
  decisions (it wires networkmanager/bluetooth/i2c/pipewire/rtkit/PAM/nerd-font
  for you). Its costs are serious for a Nix config: **settings apply once and
  then drift**, ~40 implicit binaries, no nixpkgs packaging, no cache, and
  process management via `/tmp` pidfiles.

For a declaratively-managed `nix-config`, Noctalia v5 is the better fit; the
Serpantinum settings mechanism actively contradicts the premise of the repo.
Note that these are not mutually exclusive with niri at the compositor level,
but running both would mean two shells claiming `org.freedesktop.Notifications`
and two tray hosts — pick one.
