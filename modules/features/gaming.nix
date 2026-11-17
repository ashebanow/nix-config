# Gaming — three storefronts, one capability flag (`my.gaming`).
#
#   Steam   `programs.steam` from nixpkgs: the client itself, so its whole
#           library installs and updates the normal way. Plus gamemode,
#           gamescope and protontricks as tools.
#   GOG     `pkgs.heroic` in Home Manager: Heroic talks to GOG through gogdl
#           (Heroic's own official GOG CLI), installs and updates games into
#           its own per-game Wine prefixes, and runs them under Proton-GE.
#   Battle.net  The hand-rolled umu-launcher wrappers described at length below.
#               Diablo IV installs from inside Battle.net, not from any entry
#               here.
#
# ── Why this split, and not one mechanism for all three ──────────────────
# Each storefront is served by whatever the Linux gaming community actually
# uses for it, and none of the three is reimplemented here:
#
#   * Steam has a first-class NixOS module. Using it is the entire job; the
#     module already brings `hardware.steam-hardware`, 32-bit graphics, the
#     `steam-run` FHS wrapper and the firewall options. Hand-wrapping a Steam
#     client in umu would be strictly worse in every respect.
#   * GOG has no client on Linux at all — GOG ships Galaxy for Windows and
#     macOS only, and there is no Linux build to wrap. Heroic is the de facto
#     answer (Lutris is the other, and it would be a second launcher doing the
#     same job). Heroic is in nixpkgs, needs no flake input, and manages its
#     own prefixes, so there is nothing here to maintain.
#   * Battle.net ships no Linux client either, and the wrapper is the part
#     nobody else gets right for this host — see the long header below.
#
# What is deliberately NOT here, and why, since each is a common r/nixos and
# NixOS-wiki suggestion:
#
#   * No Lutris. Heroic covers GOG; Steam covers Steam; Lutris would be a
#     third launcher for the same two stores.
#   * No protonup-qt. `programs.steam.extraCompatPackages` installs Proton-GE
#     declaratively from the same nixpkgs pin the Battle.net wrappers use, so
#     there is nothing to download into `~/.steam` and no tool to keep in sync.
#   * No Flatpak, Bottles, or a `steam.override` with a hand-picked library
#     list. Those are for making one specific broken game work; none of the
#     three storefronts needs them to be installed and launchable, and a
#     hand-picked FHS library list is a maintenance burden that silently rots.
#   * No gamescope *session*. `programs.gamescope.enable` puts the tool on the
#     host so a game can be launched through it from Steam's launch options.
#     Registering a Steam Big Picture session in the display manager is a
#     separate commitment — a new entry at the login screen next to niri and
#     GNOME — and is easy to add later if it is ever wanted. Reliability over
#     cleverness.
#
# ── Two worlds of Wine prefixes, on purpose ─────────────────────────────
# Heroic does NOT share a prefix with the Battle.net wrappers, and the GOG
# games do not get `gaming-umu` launchers. Heroic owns one prefix per game
# under `~/.config/heroic/GamesConfig` and that ownership is exactly what makes
# its install/update/repair cycle work; reaching in to share a prefix, or to
# launch a GOG game through `umu-run`, would break the thing being used. There
# are therefore three independent prefix families on a gaming host:
#
#   ~/.local/share/battlenet-umu/prefixes/<name>/   Battle.net (this module)
#   ~/.config/heroic/...                            GOG (Heroic's own)
#   ~/.local/share/Steam/steamapps/compatdata/      Steam (Valve's own)
#
# Only the first is documented in docs/gaming.md's repair ladder, because only
# the first is ours. For the other two the answer to corruption is the same as
# on any other Linux box: let Steam or Heroic rebuild it, or delete the game's
# prefix and reinstall. That is a feature — it means a Proton regression in
# Cyberpunk is fixed by Heroic's UI, not by editing this repo.
#
# ── Battle.net (Diablo IV) through umu-launcher + Proton-GE ───────────────
#
# Everything here is nixpkgs: `pkgs.umu-launcher` (1.4.4) and
# `pkgs.proton-ge-bin` (GE-Proton11-11) are already inputs of this flake, so
# this module adds **no new flake input** and nothing to flake.lock. The only
# third-party code is the two wrappers below, which are ours to read.
#
# Why hand-rolled rather than github:jacobjdowning/battlenet-umu: that flake
# exists almost entirely for its WoW-addon half (instawow profiles, token
# plumbing, a per-boot sync unit), which is dead weight here — Diablo IV has no
# addons. Its remaining ~120 lines are the same two derivations, minus the
# three things wrong with them:
#
#   * it bakes `GAMEID=umu-default`, a placeholder. umu keys its Proton
#     handling and its compat-report identity off GAMEID, so this module takes
#     a real one per game (default `umu-battlenet`, which is what upstream's
#     docs use for a manually-installed Battle.net).
#   * its launcher hard-codes the Battle.net *installer* branch with a
#     `xdg-terminal-exec` fallback that finds no terminal on this host (yuzu
#     has ghostty, whose .desktop entry is not in the store closure, and
#     `xdg-terminal-exec` itself is not installed). The split below makes the
#     installer its own entry point that the user just runs *in* a terminal.
#   * it downloads Battle.net-Setup.exe on every launch where the prefix looks
#     empty. Here the download happens only in `-install`, once.
#
# ── The one non-reproducible step, stated plainly ────────────────────────
# `-install` fetches https://downloader.battle.net/download/getInstaller?... at
# runtime, every time it runs. It cannot be a pinned `fetchurl`: the URL is
# stable but the payload is not — Blizzard rotates it continuously, so a hash
# in this repo would pin a build that no longer exists within days. The
# download therefore comes from Blizzard over TLS, unpinned, and is executed
# inside a Wine prefix. That is the same trust decision installing Battle.net
# on Windows makes; it is just made here, in one visible command, instead of
# buried in a launcher's first-run branch. It runs once, as the user, with no
# root involved.
#
# ── Why no d3dx9/dxvk/vkd3d packages ────────────────────────────────────
# Proton-GE bundles DXVK (D3D9/10/11) and VKD3D-Proton (D3D12), and Battle.net
# + Diablo IV are D3D11/D3D12, so nixpkgs' `dxvk`/`vkd3d` would be dead weight.
#
# `hardware.graphics.enable32Bit`, by contrast, is required, and this module does
# set it — from the NixOS-scope half, where a NixOS option can actually be set.
# The reasoning sits next to the line that enforces it, under "Two scopes" below.
# An earlier version of this header argued the option could be skipped because
# umu's `-fhsenv` rootfs supplies its own 32-bit libvulkan; that was **wrong**,
# and it is why Battle.net's first launch died silently. Do not re-derive it.
#
# yuzu's GPU is the Strix Halo iGPU (gfx1151, RDNA 3.5), driven by mainline
# amdgpu + RADV. Two host-side consequences, neither of which this module can
# set for you:
#   * RADV must actually work. `vulkaninfo --summary` should name a
#     `RADV STRIX_HALO`-ish device; if it does not, fix `hardware.graphics`
#     before blaming Wine.
#   * The iGPU shares system RAM, so ttm/gtt sizing (the same
#     `amdgpu.gttsize` knobs the LLM research under docs/ covers) decides how
#     much memory VKD3D has for textures. For D4 an amdgpu GTT of a few GB is
#     plenty; the LLM-sized split is not needed and tends to cost performance,
#     not gain it.
#
# ── Two traps this module hit, so nobody re-learns them ──────────────────
# 1. Do **not** bind `let cfg = config.programs...;`. In a deferred-module
#    container that shadows the module's own `config` argument, and the module
#    then silently returns its `options` under the `my` attribute instead of
#    declaring them — no options, no error. Read `config.<opt>` directly.
# 2. The enable condition is `config.my.gaming`, not
#    `config.programs.gaming-umu.enable`. The latter evaluates `false` through
#    the NixOS -> Home Manager path on this host even when the module's own
#    option state says otherwise (repo: the self-registered module is spliced
#    in by import-tree, and the option's default re-enters). Keying off the
#    capability flag is also the house style: the flag *is* the switch, and it
#    is the one value capabilities.nix can guarantee is visible in both scopes.
# 3. Both wrappers `cd "$HOME"` before `umu-run`, and that is load-bearing.
#    nixpkgs' `umu-run` wrapper adds `/etc` to its bwrap `ignored` list and
#    `--tmpfs /etc` in the namespace, then passes `--chdir "$(pwd)"`. This
#    repo is normally operated from `/etc/nixos`, so `pwd` is a path under
#    `/etc` that exists on the host and nowhere in the container:
#    `bwrap: Can't chdir to /etc/nixos`. Launching from `$HOME` is the cheap,
#    total fix; anything that re-adds a cwd dependency reintroduces it.
#
# ── Two scopes, on purpose ───────────────────────────────────────────────
# This file registers TWO modules:
#
#   my.modules.nixos.gaming          — host requirements, one list, gated on
#                                      `my.gaming`: 32-bit graphics, Steam,
#                                      gamemode, gamescope.
#   my.modules.home-manager.gaming   — the wrappers, desktop entries and Wine
#                                      prefixes for Battle.net, plus Heroic
#                                      for GOG.
#
# The split is not ceremony, and it is the reason Steam lives in the NixOS
# half and Heroic in the Home Manager half:
#   * `programs.steam`, `programs.gamemode`, `programs.gamescope` and
#     `hardware.graphics.enable32Bit` are NixOS options and cannot be set from
#     the Home Manager scope — which is what the original single-scope version
#     of this file got wrong (see the 32-bit / Steam block below).
#   * anything that has to be true of the *machine* for games to run — 32-bit
#     graphics, a controller udev rule, gamemode's daemon, the gamescope tool —
#     belongs to no particular storefront. Gating those on the one `my.gaming`
#     flag means a future storefront inherits them instead of re-deriving them,
#     which is exactly what happened when Steam and GOG were added here.
#   * Heroic is a per-user application with per-user state, so it belongs to
#     the Home Manager scope: one user's GOG account, one user's game library.
#
# What deliberately does NOT move: `my.gamingWinePrefixes` and the
# `programs.gaming-umu.*` option, because Wine prefixes are per-user state under
# `$HOME` and the wrappers are per-user packages.
_: {
  # ── NixOS scope: what the host must provide for games to run ─────────────
  my.modules.nixos.gaming =
    {
      lib,
      pkgs,
      config,
      ...
    }:
    {
      config = lib.mkIf config.my.gaming {
        # Battle.net's CEF GPU process is 32-bit (`Build: x86` in DXVK's log) and
        # loads 32-bit DXVK, which needs a 32-bit Vulkan loader *and* a 32-bit
        # ICD to reach the host's RADV. Without this there is no
        # /run/opengl-driver-32 and no `*_icd.i686.json`, so DXVK logs
        #
        #     err: DxvkInstance::createInstance: Failed to create Vulkan instance
        #     err: Failed to initialize DXVK.
        #
        # ...and then faults with 0xC0000005 once ANGLE/d3d11 gets the half-built
        # device. Battle.net's own log stops at `Application path is:` with no
        # error, and its crash report reads `dxgi` -> `d3d11` -> `libGLESv2` ->
        # `libcef` — which looks like a Battle.net or Proton bug and is really a
        # missing 32-bit Vulkan on the host. docs/gaming.md triage step 5 has the
        # one-line check.
        #
        # Not Battle.net-specific: any 32-bit Windows game has the same
        # requirement, so it lives here rather than in the umu module.
        # mkDefault so a host that already asked for it (lumquat does) is not
        # fought over.
        #
        # Note `programs.steam.enable` below sets this too; the explicit line
        # stays because it is what Heroic and the Battle.net wrappers rely on,
        # and GOG games must not depend on Steam being installed for them to
        # have 32-bit Vulkan.
        hardware.graphics.enable32Bit = lib.mkDefault true;

        # ── Steam ────────────────────────────────────────────────────────
        # The nixpkgs module and nothing else. It brings, in its own `config`:
        # `hardware.steam-hardware` (controller udev rules and the HID
        # permissions for a Steam Controller / Deck / Index), 32-bit graphics
        # and pulse/pipewire ALSA, `steam` plus `steam-run` on the system path,
        # and the Remote Play / transfer firewall options (all left off here:
        # this host does not stream, and a closed firewall is the better
        # default until it does).
        #
        # `pkgs.steam` is unfreeRedistributable, already permitted globally by
        # modules/infra/nix/nix.nix's `nixpkgs.config.allowUnfree = true`.
        programs.steam = {
          enable = true;

          # Proton-GE in Steam's own compatibility dropdown, from the same
          # pkgs.proton-ge-bin the Battle.net wrappers below use — one pinned
          # build shared by both worlds, rather than a second one downloaded
          # into ~/.steam by protonup-qt. `extraCompatPackages` requires a
          # package with a `steamcompattool` output, which is exactly what
          # proton-ge-bin provides (the wrappers use the same output as
          # PROTONPATH).
          extraCompatPackages = [ pkgs.proton-ge-bin ];

          # protontricks is the standard "this one game needs a Windows DLL or
          # a registry key" escape hatch, and it needs `extraCompatPackages` to
          # find Proton-GE, so enabling it is only worth it alongside the line
          # above. It reaches the prefixes Steam owns; the Battle.net prefix
          # is reached by pointing protontricks at it explicitly.
          protontricks.enable = true;
        };

        # ── gamemode: the daemon, and the `gamemoderun` shim ─────────────
        # Distinct from `programs.steam.enable`'s 32-bit audio work: gamemode is
        # a D-Bus-activated daemon that raises the game's CPU governor and I/O
        # priority while it runs. It does nothing unless a game asks for it, so
        # enabling it host-wide costs nothing at idle and is used per-game via
        # Steam's launch options (`gamemoderun %command%`) or Heroic's
        # "Use GameMode" toggle.
        #
        # `renice` is granted through the module's own `security.polkit`
        # setup; nothing here needs a setuid binary.
        programs.gamemode.enable = true;

        # ── gamescope: the tool, not a session ──────────────────────────
        # A micro-compositor used per-game to force a resolution, add FSR or
        # HDR, or make a windowed game fullscreen. Exposed as a package so a
        # launch option can say `gamescope -W 2560 -H 1440 -f -- %command%`.
        #
        # NOT `programs.steam.gamescopeSession.enable`: that registers a Steam
        # Big Picture session in the display manager, i.e. a third entry at the
        # login screen next to niri and GNOME. Real on a console-style box, a
        # surprise on a workstation, and trivial to turn on later if wanted.
        #
        # capSysNice is left off deliberately: it needs a CAP_SYS_NICE wrapper,
        # and gamemode above already does the scheduling work it duplicates.
        programs.gamescope.enable = true;
      };
    };

  # ── Home Manager scope: wrappers, desktop entries, prefixes ──────────────
  my.modules.home-manager.gaming =
    {
      lib,
      pkgs,
      config,
      ...
    }:
    let
      # One game inside a prefix. Everything except `name` is overridable, but
      # the defaults are the Battle.net launcher itself, which is all Diablo IV
      # needs — you launch D4 from inside it.
      game = lib.types.submodule {
        options = {
          name = lib.mkOption {
            type = lib.types.str;
            description = "Display name, used for the desktop entry.";
          };
          exec = lib.mkOption {
            type = lib.types.str;
            default = "Program Files (x86)/Battle.net/Battle.net Launcher.exe";
            description = ''
              Path to the executable, relative to the prefix's C: drive. There is
              no need to add an entry for Diablo IV — Battle.net's own launcher
              starts it. This option is for launching a game directly and
              skipping the launcher.
            '';
          };
          gameId = lib.mkOption {
            type = lib.types.str;
            description = ''
              umu's GAMEID. Each distinct game id gets its own Proton appliance
              state and compat-report identity, so give each game its own. Plain
              `umu-<slug>` ids are the convention for games umu has no built-in
              id for; Steam appids work too.
            '';
          };
          launchArgs = lib.mkOption {
            type = lib.types.str;
            default = "";
            description = "Arguments passed to the executable.";
          };
        };
      };

      # One Wine prefix: a complete fake Windows C: drive, its own registry and
      # its own system32. Battle.net and whatever it installs live inside it.
      winePrefix = lib.types.submodule {
        options = {
          games = lib.mkOption {
            type = lib.types.listOf game;
            default = [
              {
                name = "Battle.net";
                gameId = "umu-battlenet";
              }
            ];
            description = ''
              Games to create launchers for, inside this prefix. The default is
              the Battle.net launcher alone.
            '';
          };
          proton = lib.mkOption {
            type = lib.types.package;
            default = pkgs.proton-ge-bin;
            description = ''
              Proton build for this prefix. Its `steamcompattool` output becomes
              PROTONPATH. Per-prefix rather than per-game because one prefix
              cannot sanely be driven by two Proton builds — that is the main
              reason to create a second prefix at all, to try a new Proton
              release without risking the working one.
            '';
          };
        };
      };

      battlenetPath = "Program Files (x86)/Battle.net/Battle.net Launcher.exe";

      installerUrl = "https://downloader.battle.net/download/getInstaller?os=win&installer=Battle.net-Setup.exe";

      slug = name: lib.toLower (builtins.replaceStrings [ " " ":" "." "/" ] [ "-" "" "" "-" ] name);

      # The environment umu-run needs, and nothing else. `UMU_RUNTIME_UPDATE` is
      # deliberately left unset so umu checks for a new Steam Linux Runtime only
      # when none is installed — the runtime is downloaded from Steam's CDN on
      # first run either way, and re-checking on every launch would put a
      # network call in the hot path.
      commonEnv = prefixPath: proton: gameId: {
        GAMEID = gameId;
        PROTONPATH = "${proton.steamcompattool}";
        WINEPREFIX = prefixPath;
      };

      # The directory each named prefix lives in. The name the user writes in
      # `winePrefixes.<name>` becomes the directory name, so `ls` on
      # ~/.local/share/battlenet-umu/prefixes answers "which C: drives do I
      # have" without opening any of them.
      prefixDir = name: "${config.xdg.dataHome}/battlenet-umu/prefixes/${name}";

      launcher =
        name: prefix: game':
        let
          prefixPath = prefixDir name;
          scriptName = "battlenet-umu-${name}-${slug game'.name}";
        in
        pkgs.writeShellApplication {
          name = scriptName;
          runtimeInputs = [
            pkgs.umu-launcher
            pkgs.coreutils
          ];
          runtimeEnv = commonEnv prefixPath prefix.proton game'.gameId // {
            BNET_PREFIX = prefixPath;
            BNET_EXE = game'.exec;
            # The "is Battle.net installed at all?" check in the not-found branch
            # below needs both of these; without them `set -o nounset` killed the
            # script at the check, so the helpful hint never printed.
            BNET_PATH = battlenetPath;
            INSTALL_NAME = name;
            LAUNCH_ARGS = game'.launchArgs;
          };
          text = ''
            # WINEPREFIX is already exported. `umu-run` is umu-launcher's entry
            # point: it maps the prefix, applies the runtime, and execs the
            # target under Proton.
            target="$WINEPREFIX/drive_c/$BNET_EXE"

            if [ ! -f "$target" ]; then
              echo "not found: C:/$BNET_EXE" >&2
              if [ ! -f "$WINEPREFIX/drive_c/$BNET_PATH" ]; then
                echo "" >&2
                echo "Battle.net is not installed in the '$INSTALL_NAME' prefix yet. Run:" >&2
                echo "    battlenet-umu-install-$INSTALL_NAME" >&2
              else
                echo "Battle.net is installed, but this game is not." >&2
                echo "Install it from within the Battle.net launcher." >&2
              fi
              exit 1
            fi

            # Wine reads /etc/localtime rather than the env var on some paths;
            # setting TZ is harmless and fixes timestamps in game logs.
            # `tail -n 1` strips the "TZif2" magic line.
            if [ -z "''${TZ:-}" ] && [ -r /etc/localtime ]; then
              TZ="$(tail -n 1 /etc/localtime)"
              [ -n "$TZ" ] && export TZ
            fi

            # Leave the caller's directory for one that is guaranteed to exist
            # in the container. `umu-run` passes `bwrap --chdir "$(pwd)"`, and
            # the wrapper `--tmpfs /etc` inside the namespace, so starting in
            # `/etc/nixos` (a path under `/etc` on this repo's hosts) dies with
            # `bwrap: Can't chdir to /etc/nixos`. `$HOME` is bind-mounted in
            # whole, and nothing here reads the caller's cwd: WINEPREFIX and the
            # target are absolute.
            cd "$HOME"

            # Intentional word splitting: LAUNCH_ARGS is a user-supplied string
            # of arguments, the same way Steam's launch options work.
            # shellcheck disable=SC2086
            exec umu-run "$target" $LAUNCH_ARGS
          '';
          meta = {
            description = "Launch ${game'.name} (${name} prefix) through umu-launcher + Proton-GE";
            mainProgram = scriptName;
          };
        };

      installer =
        name: prefix:
        let
          prefixPath = prefixDir name;
        in
        pkgs.writeShellApplication {
          name = "battlenet-umu-install-${name}";
          runtimeInputs = [
            pkgs.umu-launcher
            pkgs.curl
            pkgs.coreutils
          ];
          runtimeEnv = commonEnv prefixPath prefix.proton "umu-battlenet" // {
            BNET_PREFIX = prefixPath;
            BNET_EXE = battlenetPath;
            INSTALLER_URL = installerUrl;
            INSTALL_NAME = name;
          };
          # writeShellApplication already applies errexit/nounset/pipefail, so
          # the trap below runs on every exit path without an explicit set.
          text = ''
            target="$WINEPREFIX/drive_c/$BNET_EXE"

            if [ -f "$target" ]; then
              echo "Battle.net is already installed in the '$INSTALL_NAME' prefix:"
              echo "    $WINEPREFIX"
              echo "Launch it from your application menu."
              exit 0
            fi

            echo "Battle.net is not installed in the '$INSTALL_NAME' prefix:"
            echo "    $WINEPREFIX"
            echo ""
            echo "This downloads Battle.net-Setup.exe from Blizzard (unpinned, over"
            echo "TLS) and runs it under Proton. Nothing else on the system changes."
            echo ""
            printf 'Continue? [y/N] '
            read -r answer
            case "$answer" in
              [Yy]*) ;;
              *)
                echo "Aborted."
                exit 1
                ;;
            esac

            # Leave the caller's directory for one that is guaranteed to exist
            # in the container. `umu-run` passes `bwrap --chdir "$(pwd)"`, and
            # the wrapper `--tmpfs /etc` inside the namespace, so starting in
            # `/etc/nixos` (a path under `/etc` on this repo's hosts) dies with
            # `bwrap: Can't chdir to /etc/nixos`. The installer path is absolute
            # and lives inside the prefix, so nothing below reads the cwd.
            cd "$HOME"

            mkdir -p "$WINEPREFIX/drive_c"
            installer="$(mktemp --suffix=.exe -p "$WINEPREFIX/drive_c")"
            trap 'rm -f "$installer"' EXIT

            echo "Downloading installer…"
            if ! curl --fail --location --progress-bar -o "$installer" "$INSTALLER_URL"; then
              echo "Download failed. Re-run when the network is available." >&2
              exit 1
            fi

            echo ""
            echo "Running the installer. In its UI:"
            echo "  * leave the install location at the default"
            echo "    (it lands inside the prefix, at C:/Program Files (x86)/Battle.net)"
            echo "  * after Battle.net launches, use it to install Diablo IV"
            echo ""
            if ! umu-run "$installer"; then
              echo "Installer exited non-zero." >&2
              exit 1
            fi

            if [ -f "$target" ]; then
              echo ""
              echo "Battle.net installed. It is in your application menu now."
            else
              echo ""
              echo "Installer finished but C:/$BNET_EXE is missing." >&2
              echo "If it went somewhere else, set programs.gaming-umu.winePrefixes.${name}.games" >&2
              echo "with the real path. Prefix contents: $WINEPREFIX/drive_c" >&2
              exit 1
            fi
          '';
        };

      desktopEntry =
        name: prefix: game':
        pkgs.makeDesktopItem {
          # The desktop-file id is namespaced by prefix, so two prefixes both
          # offering "Battle.net" produce two entries instead of overwriting
          # one. `desktopName` is the human-readable Name= line, which stays
          # plain — the prefix is visible in the command, not the menu label.
          name = "battlenet-umu-${name}-${slug game'.name}";
          desktopName = game'.name;
          # terminal = false: Battle.net draws its own window. This is why the
          # upstream flake's xdg-terminal-exec fallback was a dead end here —
          # once Battle.net is installed nothing needs a terminal.
          exec = lib.getExe (launcher name prefix game');
          terminal = false;
          categories = [ "Game" ];
          comment = "Launch ${game'.name} (${name} prefix) through umu-launcher + Proton-GE";
        };
    in
    {
      options.programs.gaming-umu = {
        winePrefixes = lib.mkOption {
          type = lib.types.attrsOf winePrefix;
          default = { };
          description = ''
            Wine prefixes to manage, keyed by a name you choose. The name is
            meaningful: it becomes the directory under
            `$XDG_DATA_HOME/battlenet-umu/prefixes/`, and it is part of every
            launcher's command name (`battlenet-umu-<prefix>-<game>`) and every
            desktop entry.

            A prefix is a complete fake Windows C: drive — its own registry and
            system32 — with a Battle.net install inside it. You need exactly one
            for normal use; name it after the host. A second is worth it for
            trying a new Proton release without risking the working one, or for
            a separate Battle.net account. Whether to keep a pre-installed spare
            purely as recovery is a judgement call: it saves a reinstall at the
            price of ~25 GB of standing disk, and it goes stale as Battle.net
            patches. docs/gaming.md lays out both sides.

            Empty by default so a host opts in explicitly rather than silently
            inheriting a path.
          '';
          example = lib.literalExpression ''
            {
              yuzu = { };
            }
          '';
        };

        enable = lib.mkEnableOption "Battle.net and its games through umu-launcher + Proton-GE";
      };

      # ── GOG: Heroic, and only Heroic ──────────────────────────────────
      # GOG has no Linux client (Galaxy is Windows/macOS only), so there is
      # nothing to wrap: Heroic is the launcher, it drives GOG through gogdl,
      # and it owns everything about the installs. There is no option for it
      # because there is nothing to configure here that Heroic does not
      # already configure better through its own UI — the NixOS-wiki recipe
      # of `heroic.override { extraPkgs = [ gamescope gamemode ]; }` is
      # deliberately not used either: Heroic looks for those on the system
      # PATH, and `programs.gamescope`/`programs.gamemode` above put them in
      # /run/current-system/sw/bin, which the FHS wrapper's PATH includes.
      #
      # `pkgs.heroic` rather than `heroic-unwrapped`: the former is nixpkgs'
      # `steam.buildRuntimeEnv` wrapper, which is what makes Proton and the
      # Steam runtime usable from Heroic at all. Installing the unwrapped
      # binary on NixOS is the common broken-configuration mistake.
      #
      # Gated on `my.gaming` like everything else here, and independent of
      # `my.gamingWinePrefixes` — Heroic needs no prefix from us.
      config = lib.mkMerge [
        (lib.mkIf config.my.gaming {
          home.packages = [ pkgs.heroic ];
        })
        (lib.mkIf
          (
            config.my.gaming
            && (config.my.gamingWinePrefixes != [ ] || config.programs.gaming-umu.winePrefixes != { })
          )
          (
            let
              # `my.gamingWinePrefixes` is a list of *names*
              # (lib/my-options-module.nix is in both module lists, so
              # capabilities.nix can set it); the per-prefix settings live in
              # this module's own `winePrefixes`. Every name the host lists is
              # instantiated, falling back to defaults if it has no entry here.
              # `or { }` is not enough: a bare name has no `games`/`proton` and
              # this module supplies them here rather than relying on the
              # submodule's defaults, because the merged value is a plain attrset.
              # A game entry needs every option `game` declares, because these
              # defaults skip the submodule (they are plain values, not passed
              # through `lib.types.submodule`), so its `exec`/`launchArgs`
              # defaults would never be applied.
              battleNetGame = {
                name = "Battle.net";
                gameId = "umu-battlenet";
                exec = battlenetPath;
                launchArgs = "";
              };
              defaults = {
                games = [ battleNetGame ];
                proton = pkgs.proton-ge-bin;
              };
              prefixes =
                lib.genAttrs
                  (config.my.gamingWinePrefixes ++ builtins.attrNames config.programs.gaming-umu.winePrefixes)
                  (
                    name:
                    let
                      u = config.programs.gaming-umu.winePrefixes.${name} or null;
                    in
                    if u == null then
                      defaults
                    else
                      {
                        games = u.games;
                        proton = u.proton;
                      }
                  );
              # Carry the whole prefix value through — dropping `proton` here
              # (keeping only name+games) is what made a bare
              # `my.gamingWinePrefixes = [ "yuzu" ]` fail with
              # "attribute 'proton' missing".
              perPrefix = lib.mapAttrsToList (name: p: p // { inherit name; }) prefixes;
            in
            {
              home.packages = lib.concatMap (
                p:
                [ (installer p.name p) ] ++ map (launcher p.name p) p.games ++ map (desktopEntry p.name p) p.games
              ) perPrefix;

              assertions = [
                {
                  # The name becomes a path component and part of a command name.
                  # Anything a shell or a filesystem would mangle turns into a
                  # launcher nobody can type.
                  assertion = lib.all (n: builtins.match "[A-Za-z0-9_-]+" n != null) (builtins.attrNames prefixes);
                  message = "programs.gaming-umu.winePrefixes keys must be plain names ([A-Za-z0-9_-]+): they become directory and command names.";
                }
                {
                  # Two games with one name collide on the same wrapper name and the
                  # same desktop file, within a prefix.
                  assertion = lib.all (
                    p: lib.length p.games == lib.length (lib.unique (map (g: slug g.name) p.games))
                  ) (builtins.attrValues prefixes);
                  message = "A programs.gaming-umu.winePrefixes entry has two games whose names slugify to the same launcher name.";
                }
              ];
            }
          )
        )
      ];
    };
}
