# Gaming — Battle.net (and Diablo IV) through umu-launcher + Proton-GE.
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
# ── Why no d3dx9/dxvk/vkd3d packages and no enable32Bit ──────────────────
# Proton-GE bundles DXVK (D3D9/10/11) and VKD3D-Proton (D3D12), and Battle.net
# + Diablo IV are D3D11/D3D12, so nixpkgs' `dxvk`/`vkd3d` would be dead weight.
# umu-launcher's `-fhsenv` rootfs is self-contained: it carries its own 32-bit
# glibc, `libGL` and `libvulkan` under /usr/lib32 (verified: 702 entries), so
# `hardware.graphics.enable32Bit` is *not* required on this host for
# Battle.net's 32-bit components — Wine sees the runtime's libraries, not the
# host's. Leave that option off and keep the closure smaller.
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
_: {
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
            for normal use; name it after the host. A second is for recovery (if
            the working prefix breaks, the spare keeps a 100 GB D4 download from
            being the price of fixing it), for trying a new Proton release
            without risking the working one, or for a separate Battle.net
            account.

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

      # NOTE: the guard names the merged source, not one of the two option
      # sets. Testing `programs.gaming-umu.winePrefixes` here would be empty on
      # a host that configured `my.gamingWinePrefixes` (the normal case) and
      # would silently produce no launchers at all — the same failure mode as
      # trap 2 above. `my.gaming` stays in the condition so the flag remains the
      # master switch.
      config =
        lib.mkIf
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
          );
    };
}
