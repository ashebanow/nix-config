# yuzu's niri session: DankMaterialShell from its upstream flake, GDM retained, config owned by Nix

Status: accepted (2026-09-23, BOX-210)

yuzu has run GNOME and nothing else, and the desktop model said so: a single
`my.desktopEnvironment` enum chose the display manager, the enabled session and
the default session at once. Adding niri with DankMaterialShell (DMS) therefore
needed a model change before it needed any packages — and every interesting
choice had a ready-made alternative, so each is recorded here.

We decided:

- **DMS comes from its upstream flake** (`github:AvengeMedia/DankMaterialShell/stable`,
  v1.6.2 at the time of writing), not from nixpkgs' `programs.dms-shell`
  (1.6.1). The flake tracks DMS's own release cadence; the cost is a
  from-source Go build and one more input.
- **The flake's home-manager module is used, not its NixOS module**, and
  **no declarative `settings` are set**. DMS's `settings.json` stays owned by
  the DMS GUI at runtime, which is the "vanilla install" this work was asked
  for, and it avoids DMS presenting its settings as read-only.
- **GDM remains the display manager.** GNOME must stay a reliable emergency
  session, and GDM is the supported way to start GNOME; a greeter is not.
- **The niri config is owned by Home Manager**, built from nixpkgs niri 26.04
  via `wayland.windowManager.niri`, with DMS's `dms/*.kdl` includes appended by
  hand. **niri-flake is not adopted.**
- **chezmoi's dead desktop trees are retired**: the niri and DankMaterialShell
  trees are renamed to `*.bak` and hidden behind `.chezmoiignore`; the rest
  (GTK, Hyprland, Waybar, SwayNC, Swaylock, Wlogout, nwg-look, Xfce, xsettingsd,
  swappy, hop, qt5ct, qt6ct) are deleted, because Nix and DMS own that layer.
- **The desktop options become `my.desktopSessions` (a list) plus
  `my.desktopDefaultSession`**, replacing the `desktopEnvironment` enum, and
  both are set in the host's `capabilities.nix` so the Home Manager scope can
  read them.
- **The GDM login screen is themed gruvbox**, via `gdm.extraPackages` and the
  `gdm` dconf profile.
- **The panel runs at 3840×2160, 150% scale** (2560×1440 logical) over
  DisplayPort, cabled directly from the GPU to the monitor.

## Considered options

**nixpkgs `programs.dms-shell`.** Rejected: it is a patch behind and it is DMS's
release cadence we would be waiting on, not nixpkgs'. The rejected option stays
cheap — the native module installs the same upstream package, so switching back
is a module swap, not a reimplementation. Note the flake no longer ships
Quickshell, so `pkgs.quickshell` (0.3.1) is used either way.

**DankGreeter instead of GDM.** Rejected: `services.displayManager.dms-greeter`
drives greetd, so it replaces GDM rather than joining it, and GNOME started from
a greetd greeter is not GNOME's supported login path. The failure mode is the
worst one available — a bad greeter takes *both* sessions down.

**niri-flake, to get the DMS flake's `homeModules.niri`.** Rejected: that module
is written against niri-flake (`programs.niri.settings` and `lib.niri.actions`,
neither of which home-manager's own `wayland.windowManager.niri` provides), and
DMS's own docs warn that niri-flake's stable tracks niri 25.08 against nixpkgs'
26.04. Buying a keybind preset — the thing this work explicitly wanted plain —
with a year-old compositor is the wrong trade. We get the same result by
including `dms/*.kdl` ourselves, `optional=true`.

**chezmoi keeping `~/.config/niri/config.kdl`.** Rejected: chezmoi is the
cross-platform layer, and it applies these files on the macOS hosts too, which
is exactly how they became stale.

## Consequences

- **DMS writes only two GTK files** — `~/.config/gtk-{3,4}.0/dank-colors.css`.
  The import shim (`gtk.css`) and `settings.ini` that GTK needs alongside them
  are therefore Home Manager's, not DMS's, and the old chezmoi copies (which
  pointed GTK at a Breeze `colors.css` and pinned `Andromeda-dark`) are deleted.
- **DMS's `dms/*.kdl` files are owned by neither Nix nor chezmoi.** They are
  seeded once by `dms setup` after the first switch, then maintained by DMS.
- **The GDM shell theme is best-effort.** The greeter's GTK theme and icon
  theme are set declaratively (no wallpaper — none is shipped); the login
  *shell* only picks up gruvbox if
  GDM loads the User Themes extension, which is not guaranteed. If it does not,
  the fallback is already in place and this ADR still describes the decision.
- **4K60 on yuzu requires DisplayPort, cabled direct to the GPU.** The monitor
  is an Acer XB321HK whose HDMI input is 1.4-class: its EDID marks 1080p as the
  *preferred* mode and offers 4K only at 23.98/24/29.97/30. Over DisplayPort the
  preferred mode becomes 3840×2160@60, so niri must still set the mode
  explicitly (its default is the preferred mode, which only happens to be
  correct on this input). The KVM (TESmart HDK202-M24) is not the constraint — it
  is an 8K60/4K144 unit — but it routes its DP outputs to monitor 2 only, so a
  DP run through it cannot reach this monitor. **Monitor 1 is therefore no longer
  switched by the KVM**; that is the price of 4K60 and is accepted.
- **The output stanza matches by full `make model serial`, and the make is the
  *resolved* manufacturer name.** niri reads EDID through libdisplay-info, whose
  `di_info_get_make` maps the PNP ID to a manufacturer name — the raw `ACR` in
  the EDID bytes becomes `Acer Technologies`. `di_info_get_model` and
  `di_info_get_serial` use the 0xFC and 0xFF descriptors. The matching string is
  therefore `Acer Technologies XB321HK #ASOGedHl6RTd`, verified by running a
  probe against libdisplay-info on the live EDID. niri's `matches()` also
  requires the whole triple: `output "Acer Technologies XB321HK"` never matches,
  because the remainder is compared against the serial exactly. Do not
  "simplify" it to the connector name, the model, or the raw PNP ID.
- **The output stanza omits the refresh rate deliberately.** niri's refresh
  matching is exact to three decimals, while this mode's true rate is
  533250 kHz / (4000 × 2222) ≈ 59.997 Hz — which every other tool reports as
  "60.00". `mode "3840x2160"` makes niri pick the highest rate for that
  resolution, which is this mode, without depending on a decimal nobody agrees
  on.
- **DMS's own `dms setup` cannot be run as documented on this host.** The full
  interactive setup also rewrites `~/.config/niri/config.kdl`, which Home Manager
  owns as a read-only symlink into the generation: it backs the file up and then
  fails with `read-only file system`. The four fragments niri actually includes
  come from the per-file subcommands (`dms setup binds|layout|colors|alttab`),
  which write only `~/.config/niri/dms/*.kdl` and never touch `config.kdl`. For
  niri, DMS's `cursor` and `windowrules` specs deploy empty files — they are
  Hyprland-only — which is why the include list is exactly those four.
- **DMS must be bound to `niri.service`, and `systemd.enable` set explicitly.**
  The flake's Home Manager module defaults `systemd.enable` to false (nixpkgs'
  NixOS module defaults it true), so DMS would install and never start; and its
  default target, `graphical-session.target`, is also reached under GNOME, where
  a second bar and launcher would draw over the desktop. This is the wiring DMS's
  docs suggest by hand (`systemctl --user add-wants niri.service dms`).
- **`dms setup` also mutates system state**, adding the user to the `input` group
  for the Caps Lock OSD. That is declared in
  `dank-material-shell.nix` instead, so a fresh install does not depend on having
  run the step, and the capability is visible in the config rather than hidden in
  `/etc/group`.
- **DMS would migrate the output stanza into `dms/outputs.kdl`, and we decline.**
  `dms setup` copies output sections out of `config.kdl` into `dms/outputs.kdl` —
  the natural owner if the DMS GUI is to change monitor scale. We keep the output
  in Home Manager and do **not** include `dms/outputs.kdl`, so the stanza above
  stays the single source of truth and survives a fresh install with no setup
  step. Consequence: monitor settings changed in DMS's Compositor panel will
  write a file nothing reads. Change it in nix, or switch ownership deliberately
  by dropping the output stanza and adding the include.
- **DMS's System Check items are answers, not omissions.** Its optional-features
  list flags four things on this host, and three are deliberate:
  - `adw-gtk3` — *installed*. GTK3 apps otherwise look like plain GTK3 beside
    the GTK4 ones DMS's dynamic theming recolours; DMS wants both
    `adw-gtk3` and `adw-gtk3-dark`, which is exactly what the nixpkgs package
    ships.
  - `cups-pk-helper` — satisfied. The warning appeared because
    `services.printing` was off (nixpkgs' default), not because the helper was
    missing: nixpkgs' CUPS module adds `cups-pk-helper` and registers its D-Bus
    service itself whenever polkit is enabled, which it is here. Printing is now
    enabled via `my.printing` for the networked HP LaserJet — note that the CUPS
    *service* is declarative while the printer *queue* is not, since nixpkgs has
    no option for a queue.
  - `fprintd` — **the hardware is present and unsupported.** yuzu has an
    EgisTec EH577 (`1c7a:0577`), and libfprint lists that vendor/product in
    `allowlist_id_table`, whose own comment reads "Currently known and
    unsupported devices". Installing `fprintd` would add a daemon that finds no
    driver, so fingerprint unlock is not an available feature here and this is
    not a missing package. Re-check only if libfprint ships an EgisTec 0577
    driver.
  - `dankcalendar` — not in nixpkgs. It is a separate upstream project
    (`github:AvengeMedia/dankcalendar`, default branch `master`), so taking it
    means another flake input; DMS's calendar *widget* already works through
    `enableCalendarEvents` (khal).
- **Screenshots, clipboard, brightness and media keys need packages that DMS and
  niri do not pull in** — `grim`, `slurp`, `satty`, `wl-clipboard`,
  `brightnessctl`, `playerctl` — and `gruvbox-plus-icons` supplies the session
  icon theme.
- **`docs/architecture.md` and `docs/plan.md` needed no change.** Both are
  lumquat-centric and neither mentions a desktop, GNOME or yuzu; checked while
  implementing rather than assumed. (`architecture.md` does still list a
  Colmena deployment choice that BOX-209 removed from the config — pre-existing
  drift, unrelated to this work.)
