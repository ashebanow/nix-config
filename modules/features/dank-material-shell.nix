# Dux Shell (formerly DankMaterialShell, renamed in 2.0) — the bar, launcher,
# notification centre, clipboard, lock screen, dashboard and settings UI for the
# niri session. It is a shell, not a session, so it is selected by
# `my.desktopShell = "dank"` rather than by an entry in `my.desktopSessions`
# (see docs/adr/0004, and docs/adr/0003 for why this shell, docs/adr/0005 for
# the 2.0 upgrade and its rename).
#
# Home Manager scope, from Dux Shell's own flake rather than nixpkgs'
# `programs.dms-shell` — see docs/adr/0003 for that choice and 0005 for why the
# flake is now the *only* option: 2.0 needs a Quickshell built from source with
# features nixpkgs' 0.3.1 lacks, and only the flake's module carries it.
#
# settings / clipboardSettings / session are deliberately left unset: the shell
# owns ~/.config/dms/settings.json at runtime, so its GUI stays writable and
# this stays a vanilla install. The niri includes are the other half of that —
# Dux Shell seeds ~/.config/niri/dms/*.kdl and maintains them from then on.
{ inputs, ... }: {
  my.modules.home-manager.dank-material-shell =
    {
      lib,
      config,
      pkgs,
      ...
    }:
    let
      # Dux Shell's matugen writes only ~/.config/gtk-{3,4}.0/dank-colors.css — it
      # never writes gtk.css or settings.ini. GTK therefore needs a shim that
      # imports the generated colours, and an icon theme to match them. The
      # previous chezmoi versions imported a Breeze colours.css and pinned
      # Andromeda-dark.
      #
      # No gtk-theme-name here on purpose: the wallpaper-derived colours are the
      # theme, and naming one would fight matugen. The icon theme is named because
      # matugen does not produce icons.
      settingsIni = ''
        [Settings]
        gtk-icon-theme-name=Gruvbox-Plus-Dark
        gtk-application-prefer-dark-theme=true
      '';
    in
    {
      # Imported unconditionally, then gated with mkIf. A conditional import
      # (`lib.optional config.my.desktopShellIsDankMaterialShell …`) recurses: the
      # module system collects `imports` before it can settle `config`, and the
      # flake's module reads config in turn. Both modules are inert until
      # `enable = true`, so hosting them on a host without Dux Shell costs only
      # their evaluation — not a build, and not a closure entry.
      imports = [
        inputs.dms.homeModules.dank-material-shell

        # `inputs.dms.homeModules.niri` is deliberately **not** imported. It looks
        # like the natural way to wire the shell into niri, and in 2.0 it is not
        # usable here: it is written against *niri-flake* — it patches
        # `programs.niri.settings` and `config.lib.niri.actions`, and its
        # config-include "hack" reroutes niri-flake's `niri-config` output file.
        # This host uses Home Manager's `wayland.windowManager.niri` instead
        # (ADR 0003 rejected niri-flake), whose config file is
        # `xdg.configFile."niri/config.kdl"` — so the module would move a file
        # that does not exist and leave the generated one untouched, i.e. niri
        # would start with none of the include lines.
        #
        # What it would have done is ~15 lines, and it is done in
        # modules/features/niri.nix instead: include Dux Shell's base
        # `niri.kdl` from our pinned input, then its `dms/*.kdl` fragments. See
        # ADR 0005 for the full comparison, including why `niri.enableKeybinds`
        # and `niri.enableSpawn` stay off below.

        # Dux Files ships its own xdg-desktop-portal FileChooser backend, so it
        # is enabled here with the shell rather than in niri.nix: it is a 2.0
        # shell component, not compositor plumbing.
        inputs.dux-files.homeModules.dux-files
      ];

      config = lib.mkIf config.my.desktopShellIsDankMaterialShell {
        programs.dank-material-shell = {
          enable = true;

          # The flake's Home Manager module defaults systemd.enable to **false**
          # (mkEnableOption), unlike nixpkgs' NixOS module which defaults it true.
          # Without this the shell is installed but never starts.
          systemd.enable = true;

          # Bind to niri's unit rather than graphical-session.target: this is a
          # shell for the niri session, and graphical-session.target is also
          # reached by GNOME, where a second bar and launcher would appear over
          # the desktop. niri.service is the unit `niri-session` starts, and it
          # ships with the niri package.
          systemd.target = "niri.service";

          # Restart the shell when its package changes. The flake defaults this
          # true; setting it explicitly documents that a rebuild *replaces* the
          # running shell rather than leaving the old binary until next login.
          systemd.restartIfChanged = true;

          # ── Feature toggles ────────────────────────────────────────────
          # These are dependency injectors, not UI switches: their defaults are
          # all true, and what they do is put a binary on the shell's PATH.
          #
          # System monitoring needs nothing from us: 2.0's `dms` links dgop as a
          # Go library and serves it over its own IPC (the `"dgop"` capability is
          # unconditional in getCapabilities). The `dgop.package` option that
          # Dux Shell's docs mention no longer exists in 2.0's options.nix, and
          # the standalone `dgop` binary is not used by the shell at all.
          enableSystemMonitoring = true;

          # Wallpaper-derived theming: installs matugen.
          enableDynamicTheming = true;

          # Audio visualiser: installs cava.
          enableAudioWavelength = true;

          # Installs glib + networkmanager for the VPN/network widget. Set by
          # hand rather than left to the default so the module reads as a list of
          # decisions; NetworkManager is enabled system-wide by desktop.nix.
          enableVPN = true;

          # Deliberately **off**: this only installs khal, and the host runs
          # dankcalendar (the `dcal` daemon) instead. The calendar widget picks
          # its backend by probing for `dcal`, so khal would be an unused
          # second backend — see CalendarDankBackend.qml.
          enableCalendarEvents = false;

          # ── niri integration ───────────────────────────────────────────
          #
          # Configured in modules/features/niri.nix, not here. Dux Shell's own
          # `niri` option set (enableSpawn / enableKeybinds / includes) lives in
          # `homeModules.niri`, which this config does not import — it targets
          # niri-flake (see the imports above). Setting options for an
          # unimported module is a hard eval error, so the integration is spelled
          # out where the compositor config is written.
          #
          # Consequence worth knowing: `dms setup` writes its `dms/*.kdl`
          # fragments under ~/.config/niri/dms/ and the includes in niri.nix read
          # them from there. `dms setup`'s full interactive form must still not be
          # run on this host (it rewrites config.kdl, a read-only store symlink) —
          # use the per-file subcommands, as ADR 0003 records.
        };

        programs.dux-files = {
          enable = true;

          # Same reasoning as the shell: dfiles is an autostart *of the niri
          # session*, not of anything graphical-session.target reaches.
          systemd.enable = true;
          systemd.target = "niri.service";

          # Register the portal backend so it advertises itself, but do **not**
          # claim the FileChooser preference. niri's portal config resolves
          # FileChooser through gtk/gnome with Nautilus (programs.niri.useNautilus
          # defaults true), and silently redirecting every app's open/save dialog
          # to dfiles is a bigger behaviour change than "install a file manager".
          # Flip `preferred` to true to try it.
          portal.enable = true;
          portal.preferred = false;
        };

        xdg.configFile = {
          "gtk-3.0/gtk.css".text = "@import 'dank-colors.css';\n";
          "gtk-4.0/gtk.css".text = "@import 'dank-colors.css';\n";
          "gtk-3.0/settings.ini".text = settingsIni;
          "gtk-4.0/settings.ini".text = settingsIni;

          # Dux Search (dsearch) is the shell's filesystem-search backend — it
          # shells out to `dsearch` for the launcher's file results. nixpkgs'
          # module (the NixOS half below) installs the package and wires the user
          # unit, but has **no** options for the index: dsearch owns its TOML and
          # writes a default one on first start if none exists. Declaring it here
          # is therefore not a refinement of a default — it is what stops dsearch
          # indexing the whole home directory, which on this host is ~4 GB of
          # cache, a nixpkgs checkout, and every store path ever built.
          #
          # The path is `danksearch`, not `dsearch`. The binary's own --help says
          # `-c, --config (default: ~/.config/danksearch/config.toml)`, and the
          # package name is `dsearch` while the config directory is `danksearch`.
          # This was originally written as `dsearch/config.toml`, which Home
          # Manager dutifully created and dsearch never read — so the index ran
          # on dsearch's own default-written file instead, and the exclusions
          # below had no effect until 2026-10-23.

          # `Default()` in danksearch's internal/config is:
          #   path = $HOME, max_depth = 6, exclude_hidden = true,
          #   exclude_dirs = DefaultExcludeDirs()
          # where DefaultExcludeDirs covers .git/.cache/node_modules/… but knows
          # nothing about Nix. The high-value exclusions are ours:
          #
          #   .direnv .devenv   per-project Nix build environments (symlinks into
          #                     the store, and they churn on every shell entry)
          #   .local/state/nix, .cache/nix
          #                     the store's local metadata caches
          #   result*           profile symlink chains into the store
          #
          # `merge_default_exclude_dirs = true` keeps the upstream noise list on
          # top of these rather than replacing it. Indexing is scoped to $HOME and
          # never names /nix/store as a root, so no exclusion list has to express
          # "skip the store".
          #
          # `watch = true` is declared per root, not at the top level. It is a key
          # of the `[[index_paths]]` struct (`toml:"watch,omitempty"`), and a
          # top-level `watch` is rejected with `config: unknown key "watch" … is
          # ignored`. It already defaults to on, so this is documentation of intent
          # as much as configuration — but it fails loudly if a release ever flips
          # the default, which is what real-time launcher results depend on.
          #
          # `max_depth = 6` is per root, counted from that root — not from $HOME.
          # That is why the roots below are the ones the user actually reads from
          # rather than a single `~`. Nested as `$HOME`-only: `~/Synced Files` is
          # itself a root, so its content would already be at depth 2 before any
          # project folder, and `~/Development/<repo>/<dir>/<file>` would hit the
          # limit at a shallow level. Roots here also make the walk follow the
          # `~/Documents` → `~/Synced Files/Documents` symlinks automatically: the
          # walker resolves them (verified — results come back under the symlinked
          # `~/Documents/...` prefix), so both the symlink and its target are
          # covered without a follow-symlinks option.
          #
          # No nix-config checkout is excluded, because on this host there is no
          # checkout to exclude. Repo location is per-machine-class:
          #
          #   NixOS hosts      /etc/nixos           (outside every root below:
          #                                          a real directory at depth 1
          #                                          under `/`, never walked)
          #   macOS / non-NixOS ~/Development/nix/nix-config
          #
          # So the only home-directory Nix tree on a NixOS box is whatever sits
          # under `~/Development`, and `~/Development/nix-config-resilio` is a
          # separate checkout that *is* indexed, deliberately — it is a working
          # tree, not the deployed config. A future non-NixOS host that starts
          # running dsearch would need `nix` added to this root's `exclude_dirs`;
          # adding it now would be dead config on every host we currently ship.
          #
          # The index itself lives in $XDG_CACHE_HOME/dsearch/index, under the
          # excluded `.cache` — fine: exclusions apply to the walk, not to
          # dsearch's own data directory.
          "danksearch/config.toml".text = ''
            # Dux Search configuration — declared by Nix, not default-written by
            # dsearch. See modules/features/dank-material-shell.nix.

            # Absolute, not `~/…`: dsearch only expands environment variables
            # (`ExpandEnv`), and its own default-written config uses an absolute
            # path. Keeping the same directory the index already lives in also
            # means switching this file from the `dsearch` path does not orphan
            # an existing index.
            index_path = "/home/ashebanow/.cache/danksearch/index"
            listen_addr = "127.0.0.1:43654"
            max_file_bytes = 2097152
            index_all_files = true
            index_xattr_tags = true

            # The synced tree, entered through the names the user actually types.
            # `~/Documents` → `~/Synced Files/Documents` and its eight siblings are
            # symlinks at depth 1; the walker follows them (verified — results come
            # back under the `~/Documents/...` prefix, which is what the launcher
            # shows).
            #
            # Why each gets its own root: `max_depth` is counted **from the literal
            # root path**, not per-root-relative. Measured on this host — with only
            # a `~` root at depth 8, the indexed-depth histogram under Documents
            # stopped exactly at 8 from $HOME, while 119,030 files there are
            # deeper. Documents alone is 21 levels deep (178k files) and Google
            # Photos is 3 (43k), so one depth limit cannot serve both.
            #
            # Why not root at `~/Synced Files` itself: every entry in it has a
            # matching top-level symlink, so that root indexed each document twice
            # — once as `~/Documents/x`, once as `~/Synced Files/Documents/x` — and
            # the launcher showed duplicate hits. Excluding the directory from the
            # `~` root does not prevent it, because the symlinks are the other
            # entrance. Root at the symlinked names only.
            [[index_paths]]
            path = "~/Documents"
            max_depth = 24
            watch = true
            exclude_hidden = true
            extract_exif = true
            merge_default_exclude_dirs = true
            exclude_dirs = [
              "peepcode",
              "sass-cache",
            ]

            # Pictures/Music/Google Photos/Fonts: media, exif on. Depth 8 is ample
            # (measured maxima are 7, 8, 3 and 7) and keeps the walk cheap.
            [[index_paths]]
            path = "~/Pictures"
            max_depth = 8
            watch = true
            exclude_hidden = true
            extract_exif = true
            merge_default_exclude_dirs = true

            [[index_paths]]
            path = "~/Music"
            max_depth = 8
            watch = true
            exclude_hidden = true
            merge_default_exclude_dirs = true

            [[index_paths]]
            path = "~/Google Photos"
            max_depth = 6
            watch = true
            exclude_hidden = true
            extract_exif = true
            merge_default_exclude_dirs = true

            [[index_paths]]
            path = "~/Fonts"
            max_depth = 8
            watch = true
            exclude_hidden = true
            merge_default_exclude_dirs = true

            # `~/Development` is its own root because depth is counted per root:
            # under the `~` root below a repo's files would start at depth 3 and
            # the limit would bind quickly. Rooting here keeps `~/Development/`
            # at depth 0 for its own walk.
            [[index_paths]]
            path = "~/Development"
            max_depth = 8
            watch = true
            exclude_hidden = true
            merge_default_exclude_dirs = true
            exclude_dirs = [
              ".direnv",
              ".devenv",
              ".local/state/nix",
              ".cache/nix",
              "result",
              "result-bin",
              "result-doc",
            ]

            # The rest of $HOME, shallow — the two roots below cover the bulk.
            # This one picks up Desktop/Downloads/Projects/Templates/Public and
            # any other loose directory, without re-walking the trees above
            # (nested roots are deduplicated) or descending into the store.
            [[index_paths]]
            path = "~"
            max_depth = 3
            watch = true
            exclude_hidden = true
            merge_default_exclude_dirs = true
            exclude_dirs = [
              ".direnv",
              ".devenv",
              ".local/state/nix",
              ".cache/nix",
              "Synced Files",
              "Development",
              "Documents",
              "Pictures",
              "Music",
              "Videos",
              "Books",
              "Scans",
              "Fonts",
              "Google Photos",
              "personal_wiki",
              "Library",
              "result",
              "result-bin",
              "result-doc",
            ]
          '';
        };

        # Dux Shell's optional-feature set, as its own System Check enumerates it.
        # These are the tools it shells out to and does **not** bundle:
        #
        #   grim/slurp   region capture for the screenshot UI
        #   satty        annotate/redact after capture
        #   wl-clipboard the clipboard history and any copy/paste it drives
        #   playerctl    the media widget and the XF86AudioPlay/Next/Prev binds
        #   brightnessctl the XF86MonBrightness binds
        #   adw-gtk3     GTK3 apps otherwise look like plain GTK3 beside the GTK4
        #                ones dynamic theming recolours. The System Check wants a
        #                theme dir with both `adw-gtk3` and `adw-gtk3-dark`, which
        #                is what the nixpkgs package ships.
        #   dankcalendar the calendar backend (`dcal`), replacing khal — see
        #                enableCalendarEvents above.
        #
        # brightnessctl is also installed by niri.nix (a compositor-level XF86
        # concern); listing it again is a no-op union, and it keeps this module's
        # dependency story readable on its own.
        #
        # Notable absences, all deliberate:
        #   qt6-multimedia / qt6-wayland  compiled into dms-shell's own wrapper
        #                                 (the flake's qmlPkgs lists
        #                                 kdePackages.qtmultimedia; qt6-wayland
        #                                 comes with qt6.qtbase)
        #   pam                           compiled into Quickshell; the lock
        #                                 screen authenticates through a
        #                                 per-user service Dux Shell generates
        #                                 (see the NixOS half below)
        #   jemalloc / google-breakpad    Quickshell *build* flags (they are the
        #                                 Gentoo USE flags on gui-apps/quickshell).
        #                                 Not packages: taking them means
        #                                 overriding quickshell with
        #                                 withBreakpad/jemalloc and rebuilding it
        #                                 per nixpkgs bump. Breakpad cannot work
        #                                 anyway — 2.0's unit exports
        #                                 QS_DISABLE_CRASH_HANDLER=1 and crash
        #                                 reports would go through coredumpctl,
        #                                 which the Nix build does not hook.
        home.packages = with pkgs; [
          grim
          slurp
          satty
          wl-clipboard
          playerctl
          brightnessctl
          adw-gtk3
          dankcalendar
        ];
      };
    };

  # NixOS half: things that are not the user's packages or config.
  my.modules.nixos.dank-material-shell =
    {
      lib,
      config,
      ...
    }:
    {
      config = lib.mkIf config.my.desktopShellIsDankMaterialShell {
        # Dux Search's package and user unit. The index scoping is Home Manager's
        # (see xdg.configFile above) because this module has no options for it.
        programs.dsearch.enable = true;
        programs.dsearch.systemd.target = "graphical-session.target";

        # Dux Shell's Caps Lock OSD reads input devices, and `dms setup` adds the
        # user to this group imperatively ("Adding user to input group for Caps
        # Lock OSD support"). Declaring it here means a fresh install does not
        # depend on having run that step, so the capability is visible in the
        # config rather than hidden system state.
        users.users.${config.my.baseUsername}.extraGroups = [ "input" ];

        # Polkit: nothing to do. `security.polkit.enable` is already on (printing
        # needs it), nixpkgs' programs.niri starts no agent of its own, and the
        # shell runs a Quickshell PolkitAgent on niri.service. The
        # `niri-flake-polkit` conflict Dux Shell's docs warn about is a
        # niri-flake unit, and this host does not use niri-flake (ADR 0003).

        # Lock screen: likewise nothing to declare. Dux Shell writes its own
        # per-user PAM service (`~/.local/state/dms/pam/dankshell`, resolved from
        # the system stack so it inherits pam_systemd and pam_gnome_keyring) and
        # the Quickshell PamContext loads it from there. Measured on yuzu with
        # 1.6.3: unlocking authenticated against it, unlocked the GNOME keyring,
        # and created no extra logind session. Declaring
        # `security.pam.services.dankshell` would *replace* that generated stack
        # with a hand-written one — a regression, not a fix. See ADR 0005.
      };
    };
}
