# Dux Shell 2.0: the rename, the niri integration we could not import, and the defaults we adopted

Status: accepted (2026-10-22)

DankMaterialShell released 2.0.0 on 2026-10-20 and renamed itself **Dux Shell**,
moving from `AvengeMedia/DankMaterialShell` to `duxlabs-dev/dux-shell`. yuzu was
pinned at 1.6.3 (`4a87e82`). This records what the upgrade changed, the two
things that did not work as the docs suggest, and the deliberate choice to stop
customising the compositor config.

We decided:

- **Track the renamed upstream flake**: `github:duxlabs-dev/dux-shell/stable`,
  pinned at the v2.0.0 tag commit. 2.1 does not exist yet; `stable`'s head *is*
  the v2.0.0 version bump. nixpkgs still has `dms-shell` 1.6.2, so the flake is
  now the only way to run 2.0 — ADR 0003's "the flake is one patch ahead" is
  obsolete, and the argument is now "the flake is the only source of 2.0".
- **Dux Shell's base niri config is adopted wholesale**, included by absolute
  store path from our pinned input rather than vendored. The host's only
  remaining niri customisation is the monitor.
- **`wayland.windowManager.niri.enableDefaultConfig` goes off**, because the
  adopted base *is* niri's `default-config.kdl` plus Dux Shell's changes;
  leaving niri's defaults on would emit a second copy of every bind.
- **`inputs.dms.homeModules.niri` is not imported.** See below — it cannot work
  here, and reimplementing its ~15 useful lines is cheaper than the alternative.
- **New `dux-files` input**, for the 2.0 file manager and its
  `xdg-desktop-portal` FileChooser backend.
- **`enableCalendarEvents` is off and `pkgs.dankcalendar` is installed instead**
  of khal. The option only injects `khal`; the calendar widget probes for the
  `dcal` daemon (`CalendarDankBackend.qml`), so khal would be a second, unused
  backend. dankcalendar is in nixpkgs as of this nixpkgs pin — ADR 0003 recorded
  it as "not in nixpkgs", which is no longer true.
- **The lock screen PAM stack is left alone.** See below.

## The niri module cannot be imported, and it is not our abstraction's fault

Dux Shell's docs present `inputs.dms.homeModules.niri` plus
`programs.dank-material-shell.niri.{enableKeybinds,enableSpawn,includes}` as the
way to integrate. It is written against **niri-flake**:

- every line of its `config` is `programs.niri.settings` or
  `config.lib.niri.actions`, both of which niri-flake provides;
- its config-include "hack" `mkForce`s `xdg.configFile."niri-config".target` to
  `niri/hm.kdl` — niri-flake's output file name.

This host uses Home Manager's `wayland.windowManager.niri`, whose config lands at
`xdg.configFile."niri/config.kdl"` and has no `niri-config` entry. Importing the
module therefore fails at eval with `attribute 'niri' missing` (nobody defines
`config.lib.niri`), and even with that aliased the include half would move a
file that does not exist while leaving the generated one untouched — niri would
start with none of the `include` lines, i.e. no shell binds, silently.

It is worth being explicit that **this is not a consequence of our three-shell
switch** (ADR 0004). The module would be equally unusable on a host that only
ever runs Dux Shell; what it assumes is niri-flake, which ADR 0003 rejected on
its own merits (a compositor pinned to 25.08, and the loss of the EDID-matched
output stanza).

So `modules/features/niri.nix` writes the include block itself, in Dux Shell's
own order, and this is a reimplementation of a known, small thing rather than a
dependency on an upstream file that does not fit:

```
include "<inputs.dms>/core/internal/config/embedded/niri.kdl"   # their base
include optional=true "dms/colors.kdl"
include optional=true "dms/layout.kdl"
include optional=true "dms/alttab.kdl"
include optional=true "dms/binds.kdl"
include optional=true "dms/cursor.kdl"
include optional=true "dms/input.kdl"
output "Acer Technologies XB321HK #ASOGedHl6RTd" { … }          # ours
```

Four details that are load-bearing:

- **`optional=true` on the `dms/*` includes** is required, not defensive. Home
  Manager's module validates the generated config with `niri validate` at build
  time, and those files are `dms setup` output that does not exist on a fresh
  install. Verified: niri treats a missing `optional=true` include as a warning
  and the config as valid; a missing non-optional include is a hard error.
- **The base is included by absolute store path.** Its own `include
  optional=true "dms/*.kdl"` lines resolve relative to *its* directory (the store
  path), so they warn-and-skip rather than reading the user's files. This keeps
  the base byte-identical to upstream, so diffing it against a newer release is
  `nix flake update` plus `diff`, with no local edits in the way.
- **`outputs` is excluded.** Dux Shell includes it and writes
  `dms/outputs.kdl` itself; under 1.6.3 that file contained a
  `output "DP-1" { … }` stanza for *this* monitor, duplicating the EDID stanza.
  ADR 0003 already declined to let the shell own the monitor; excluding the
  include keeps the EDID stanza the single source of truth by construction
  rather than by winning an ordering race.
- **`cursor` is included even though Dux Shell currently writes it empty.** It
  is the file a future release would start populating, and an `optional=true`
  include of an empty file costs nothing.

## What adopting their base changed, deliberately

The base is *not* just niri's default config — comparing it against niri's
`default-config.kdl` shows the adoption is a behaviour change beyond keybinds.
That was the point ("I want to see the default experience"), but the regression
list is recorded so it is not mistaken for breakage later:

- **Binds niri's defaults have that Dux Shell's base drops**, with no replacement
  in `dms/binds.kdl`: `Mod+Ctrl+Page_Down/Up`, `Mod+Ctrl+1..9`, `Mod+Shift+R`,
  `Mod+M` (`maximize-window-to-edges`), `Mod+Comma`
  (`consume-window-into-column`), `Super+Alt+S` (Orca toggle), `XF86AudioStop`.
  `Mod+V` (`toggle-window-floating`) moves to `Mod+V` = clipboard, and floating
  toggling becomes `Mod+Shift+T`.
- **New in their base, absent from niri's**: `prefer-no-csd`,
  `screenshot-path`, a full explicit `animations` block,
  `config-notification { disable-failed }`, `gestures { hot-corners { off } }`,
  `overview { workspace-shadow { off } }`, and window-rules for GNOME apps,
  `pavucontrol`/`nm-connection-editor`, a floating group, and Steam toasts.
- **Borders end up off.** The base sets `border { off; width 4 }` and
  `dms/layout.kdl` sets `width 2`; `dms/colors.kdl` sets only colours. Dux
  Shell's own niri module emits `layout { border { on; } }` to work around the
  include ordering (see the comment in its `niri.nix`), but it gates that on
  `programs.niri.settings.layout.border.enable`, which does not exist here. We
  do **not** emit the fix: borders off is what a default install looks like.
- **Touchpad `tap` and `natural-scroll` move out of the base** into
  `dms/input.kdl`. Dropping that include would silently stop them working, which
  is why it is included.

## The lock screen PAM stack needed no change

A concern raised while planning: Dux Shell's lock screen authenticates via a PAM
service it generates per user, and the worry was that on NixOS it would fall back
to a bundled, session-less stack — starting a *second* logind session on unlock,
and not importing `XDG_SESSION_ID`/`XDG_RUNTIME_DIR` from the niri session (the
classic hyprlock/swaylock-on-NixOS failure).

Measured on yuzu with 1.6.3 before changing anything: lock, unlock, then
`loginctl list-sessions`. The session list was unchanged (sessions 1 and 5
before and after), and the journal showed

```
Starting pam session for user "ashebanow" with config "dankshell"
  in dir "/home/ashebanow/.local/state/DankMaterialShell/pam"
gkr-pam: unlocked login keyring
```

So the generated stack is already session-aware (it inherits `pam_systemd` and
`pam_gnome_keyring` from the resolved system stack), and it *is* what runs. 2.0
keeps the same mechanism (moving the directory to `~/.local/state/dms/pam`) and
additionally prefers `/etc/pam.d/dankshell` if that file exists.

Consequence: **declaring `security.pam.services.dankshell` would be a
regression**, not a fix — it would replace the generated stack with a hand-written
one. Nothing is declared. Re-check only if a future release changes how
`Pam.qml` selects its service.

## Considered options

**Import `inputs.dms.homeModules.niri` and set `enableIncludes = false` /
`enableKeybinds = false` anyway.** Rejected: the module errors at eval before any
of its options can be disabled, because `config.lib.niri` is undefined and
`programs.niri` is not an option here.

**Adopt niri-flake so the module works.** Rejected for the reasons in ADR 0003,
which this does not reopen: niri-flake's stable tracks an older niri than the
nixpkgs one we use, and the output stanza would have to move into
`programs.niri.settings`. Buying a keybind preset we do not want with a
year-old compositor is the wrong trade, and the includes are 15 lines.

**Vendor Dux Shell's `niri.kdl` into the repo.** Rejected: it is a file that must
be re-diffed on every `nix flake update dms`, which is a standing maintenance
task. Including it from `inputs.dms` makes the flake lock the single place that
answers "which base config are we on".

**Keep niri's own `default-config.kdl` and include only `dms/*.kdl`.** Rejected
per the request that the default experience be reproducible: Dux Shell's base
carries settings (animations, `prefer-no-csd`, window rules, screenshot path)
that its own fragments do not, so this would be a third configuration — neither
niri's default nor Dux Shell's.

**Keep khal via `enableCalendarEvents`.** Rejected: the widget would not use it.

**Set `dfiles` as the preferred FileChooser portal.** Rejected for now: niri's
portal config resolves FileChooser through `gtk`/`gnome` with Nautilus
(`programs.niri.useNautilus` defaults true). Making every app's open/save dialog
switch backends is a bigger change than "install a file manager", and it is one
boolean (`portal.preferred`) away if we want it.

## Consequences

- **`~/.config/niri/dms/*.kdl` must be reseeded after the upgrade.** The
  existing files are 1.6.3 output; 2.0's `binds.kdl` moves `Mod+M`
  (task manager → media), `Mod+N` (notifications → notepad), `Super+X` → `Mod+X`
  (power menu), and adds `Mod+A`, `Mod+D`, `Mod+Shift+C`, `Mod+Alt+N`,
  `Mod+Alt+I`, `Ctrl+Alt+M`, `XF86TouchpadToggle` and `Mod+Return`. Running 2.0
  against the old files yields the new shell with old keybinds. The local copies
  were verified byte-identical to 1.6.3 stock (with `ghostty` substituted), so
  nothing hand-made is lost. Procedure: `docs/niri-dank-material-shell.md`.
- **`dms setup` still cannot be run in its bare form here** (ADR 0003): it
  rewrites `config.kdl`, which Home Manager owns as a read-only symlink. The
  per-file subcommands remain the path. For 2.0 the set is
  `binds layout colors alttab input` — `input` is now needed because the touchpad
  settings live there, and `cursor` is written empty.
- **`dms/cursor.kdl` and `dms/input.kdl` now exist in the include list**, so a
  fresh install gets them only after `dms setup`.
- **dgop needs nothing.** The 2.0 `dms` binary links `dux-gop` as a Go library and
  serves it over its own IPC; the `"dgop"` capability is unconditional. The
  `dgop.package` option the docs mention no longer exists in 2.0's
  `options.nix`, and the standalone binary is unused by the shell.
- **`jemalloc`, `google-breakpad` and `pam` are Quickshell build flags, not
  packages.** They are the Gentoo `USE` flags on `gui-apps/quickshell`. Taking
  `jemalloc`/`breakpad` means overriding `quickshell` and rebuilding it per
  nixpkgs bump; and breakpad cannot work regardless, since 2.0's unit exports
  `QS_DISABLE_CRASH_HANDLER=1`. `qt6-multimedia` and `qt6-wayland` are already
  compiled into Dux Shell's own `dms-shell` wrapper.
- **`dsearch`'s index is now declared by Nix** (`dsearch/config.toml` via Home
  Manager). It had never run on this host, and its default is `$HOME` with Nix-unaware
  exclusions. Scoped to `$HOME` and excluding `.direnv`, `.devenv`,
  `.local/state/nix`, `.cache/nix`, `nixos`, `result*`, with
  `merge_default_exclude_dirs` keeping upstream's noise list.
- **`enableSystemd` → `systemd.enable`** and the other renamed options are
  handled by the flake's `mkRenamedOptionModule`s; this config sets the new
  names. `systemd.restartIfChanged` is set explicitly so a rebuild replaces the
  running shell.
- **The GTK shim and `settings.ini` are unchanged.** Dux Shell still writes only
  `~/.config/gtk-{3,4}.0/dank-colors.css`.
