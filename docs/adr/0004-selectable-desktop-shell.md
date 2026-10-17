# Selectable desktop shells for the niri session, behind one master switch

Status: accepted (2026-10-17)

yuzu's niri session had exactly one shell wired in — DankMaterialShell, chosen
by `my.dankMaterialShell`, a bare boolean. Trying another shell meant editing
`niri.nix` (whose package list, layer-rules and `include` lines were DMS's) and
`desktop.nix` (whose assertion hard-coded DMS). Three shells on one compositor
need a switch, not three flags: any two shells fight over
`org.freedesktop.Notifications` and both draw a bar.

We decided:

- **`my.desktopShell` is a single `nullOr (enum ["dank" "noctalia" "serpantinum"])`.**
  `null` means a bare niri session, which is a legitimate debug mode rather than
  an error. Each shell's module enables itself when the value equals its own
  name, so exclusivity is structural: there is no state in which two are on.
- **The three `desktopShellIs<Name>` options are `readOnly` derivations from
  `desktopShell`**, not host-set flags. A host sets one value; the modules read
  the predicates. `readOnly = true` makes a host that tries to set one fail at
  build time instead of silently disagreeing.
- **Each shell owns its own file** — `dank-material-shell.nix`,
  `noctalia.nix`, `serpantinum.nix` — including its packages, its
  screenshot/clipboard/media tooling, its niri layer-rules, its `spawn-at-startup`
  lines and its keybinds. `niri.nix` keeps only what is shell-independent: the
  compositor, the output stanza, and the overview-backdrop plumbing every shell
  needs.
- **Each shell installs its own upstream-recommended dependency set, and the
  three sets genuinely differ.** This was the point of keeping the modules
  separate: copying DMS's list into Noctalia would install the v4 Quickshell
  toolchain next to a shell that implements those features natively.
- **The global `dms` behaviour is unchanged** (ADR 0003 still governs it); only
  the gate moved from `my.dankMaterialShell` to `my.desktopShellIsDankMaterialShell`.

## What each shell actually needs

Research write-up with sources: `docs/research/wayland-shells-noctalia-serpantinum.md`.

**DankMaterialShell** shells out for its optional features, so its module adds
`grim`, `slurp`, `satty`, `wl-clipboard`, `playerctl`, `brightnessctl` and
`adw-gtk3`, plus `programs.dsearch` and the `input` group on the NixOS side.
(The list previously lived in `niri.nix`; it moved here because none of it is
true of a compositor without DMS.)

**Noctalia v5** implements its own screenshots (`wlr-screencopy`), clipboard,
notifications, OSD, lock screen, wallpaper and colour generation (Material
Color Utilities is vendored). Its upstream dependency tracker lists exactly one
external tool: `ddcutil`. So the module adds `ddcutil`, `xdg-utils` and
`libnotify` and nothing else — specifically **not** grim/slurp/satty/cliphist/
matugen/playerctl, which belong to the v4 Quickshell shell (`pkgs.noctalia-shell`,
a different package from `pkgs.noctalia`). What Noctalia needs instead is
*services*, so the NixOS half sets `recommendedServices.enable` (NetworkManager,
Bluetooth, UPower, power-profiles-daemon) and `xdg.sounds.enable`.

**Serpantinum** has no list to write: `nix/package.nix` bakes ~45 binaries into
its wrappers with `--prefix PATH : lib.makeBinPath pathDeps` — grim, slurp,
satty, zbar, cliphist, wl-clipboard, matugen, playerctl, brightnessctl, ddcutil,
cava, easyeffects, gpu-screen-recorder and the rest — with no option to prune
them. The module therefore adds no packages and instead turns on the *system*
half (`programs.serpantinum.enable`, which sets PipeWire, rtkit, i2c, and the
`serpantinum` PAM service the lock screen authenticates against). It also
starts the two `wl-paste … cliphist store` watchers by hand: the Home Manager
module does not, and without them the clipboard panel stays permanently empty.

## Considered options

**Three booleans (`my.dankMaterialShell`, `my.noctalia`, `my.serpantinum`).**
Rejected: nothing stops a host enabling two, and the failure mode is two
notification daemons racing for one D-Bus name — a session that starts and then
behaves erratically. An enum makes that unrepresentable.

**A list, mirroring `my.desktopSessions`.** Rejected: sessions can legitimately
coexist at a login screen (niri *and* GNOME). Shells cannot — they all draw on
the same compositor.

**Keeping the per-shell tooling in `niri.nix` and switching on
`my.desktopShell` there.** Rejected: it mashing all three into one place is
exactly what this work was asked to avoid, and it makes a fourth shell an edit
to a shared file rather than a new one.

**Taking Noctalia from nixpkgs (`pkgs.noctalia`) with no flake input.**
Rejected, though it is a real option: nixpkgs carries v5 as `pkgs.noctalia`, and
the nixpkgs NixOS module is functionally close. The flake is used because its
`homeModules.default` is the module that provides a declarative
`programs.noctalia.settings`, and it is what upstream documents.

**Putting the shells in an overlay.** Rejected, and deliberately: an overlay
exists to change what an *attribute name* resolves to for the whole package set,
or to patch a package nixpkgs ships wrongly. Neither applies. Only one shell is
active at a time, so nothing else consumes the attribute; the two flake-only
shells install through their own modules, which reference their own package
internally, so there is no name to override; and Noctalia's package is already a
module option (`programs.noctalia.package`), so pinning a different build is a
setting, not an overlay. Overlaying Noctalia would additionally be *harmful*: it
would build it against our nixpkgs pin, changing the derivation hash and
breaking the Cachix cache that its `cachix` branch exists to hit. Compare
`lib/overlays/worktrunk.nix` and `claude-code.nix`, which are overlays for the
opposite reason — they replace a nixpkgs attribute that other modules consume by
name.

## Version position (checked 2026-10-17)

Recorded because "why pin the flake at all" is the obvious follow-up question,
and because the answer drifts without anyone noticing:

| Shell | nixpkgs unstable | This config | |
|---|---|---|---|
| Noctalia | `pkgs.noctalia` **5.2.1** (nixpkgs pin is dated 2026-08-29) | **5.3.0** | flake ahead |
| DankMaterialShell | `pkgs.dms-shell` **1.6.2** | **1.6.3** (lock rev = tag `v1.6.3`) | flake ahead by a patch |
| Serpantinum | absent — not packaged | **2.2.12** (newest tag) | flake is the only source |

Two things follow. First, ADR 0003's stated DMS gap ("1.6.1 against 1.6.2 when
this landed") is now 1.6.2 against 1.6.3, i.e. one patch rather than one minor;
that ADR is annotated accordingly, and the from-source build cost is now the
stronger reason to keep the input than the version gap. Second, Serpantinum is
the only shell with real drift risk: it is unpackaged, has no binary cache, and
depends on `quickshell` with **no version pin between them**, so a nixpkgs bump
can break it with no upstream signal. That is an argument for a pinned rev
bumped deliberately (which `flake.lock` already gives) and not for an overlay.

## Consequences

- **`nixpkgs` is NOT `follows`-ed for the `noctalia` input, on purpose.**
  Noctalia is C++23; its Cachix cache is keyed to the exact nixpkgs it was built
  against, and adding a `follows` changes the derivation hash and silently
  disables the cache. The flake is pinned to the `cachix` branch so a
  `nix flake update noctalia` can never land on an uncached commit. The cost is
  a second nixpkgs in `flake.lock` that nothing else consumes.
- **`programs.noctalia.checkConfig` is turned off.** Its default `true` runs
  `noctalia config validate` in a build step, which forces building the very
  package the cache pin exists to avoid. The module sets three literal keys
  copied from upstream's docs example; a bad key fails at start-up with the same
  message.
- **Serpantinum's settings are not declarative, and the module says so.** Its
  Home Manager module copies the merged settings JSON into
  `~/.config/serpantinum/settings.json` only if the file does not already exist
  (`home.activation`, guarded by `if [ ! -e … ]`). After the first switch,
  editing `programs.serpantinum.settings` in Nix does nothing; re-applying needs
  `rm ~/.config/serpantinum/settings.json && home-manager switch`. The module
  therefore sets only `theme.matugen`, `theme.mode` and the bar's position/style
  rather than transcribing a full layout that would then drift silently.
- **Serpantinum binds some media and volume keys through `playerctl` and its own
  `volume`/`brightness` subcommands**, where Noctalia binds them through
  `noctalia msg …` so its OSD appears. Both override niri's upstream `XF86`
  binds because a shell module's fragment lands in `extraConfig`, after the
  default-config include.
- **`wayland.windowManager.niri.extraConfig` is now an attribute-merge point**
  shared by `niri.nix` and whichever shell module is active. Merge order between
  fragments is not something to rely on, which is why each fragment defines its
  own `binds { }` block (niri merges blocks by key) instead of appending to
  another's.
- **Switching shells across a rebuild is not reversible on its own.**
  `programs.dsearch` and the `input` group stay on the system once DMS has set
  them (removing a user from `users.users.*.extraGroups` is not how NixOS
  activation works), and Serpantinum leaves its writable `settings.json` behind.
  Neither harms another shell, but expect residue — this was designed for
  changing the switch, not to make a switch a clean round-trip.
- **The DMS `dms/*.kdl` notes in ADR 0003 still apply**, unchanged, whenever
  `desktopShell = "dank"`.
