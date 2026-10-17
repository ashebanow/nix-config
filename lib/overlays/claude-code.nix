# claude-code — pinned to Anthropic's release channel directly, and shimmed so
# that `claude update` explains itself instead of appearing to succeed.
#
# ## Why the pin exists
#
# Claude Code ships several releases a week; a nixpkgs bump is a weekly-at-best
# event that drags every other package with it. Our locked nixpkgs (flake.lock
# rev e554fab) has 2.1.272 against Anthropic's 2.1.296 the day this landed, and
# chasing the CLI by moving the nixpkgs pin means rebuilding every host closure
# to advance one tool.
#
# ## Why the `latest` channel and not `stable`
#
# Anthropic publishes two pointers — `.../claude-code-releases/latest` and
# `.../stable` — and they are several releases apart by design (2.1.296 vs
# 2.1.287 when this was written; the @anthropic-ai/claude-code npm dist-tags
# carry the same split).
#
# `stable` is the more conservative build and was the first thing tried here.
# It was wrong, for a reason that only shows up at runtime: Claude Code
# compares the running version against `latest` (see `claude doctor` →
# "Auto-update channel: latest"). Pin `stable` and the in-session
# update notice is *permanently* true, because stable always trails latest —
# which trains you to ignore a prompt that is sometimes real. Pinning `latest`
# makes that notice mean exactly one thing: there is a release you have not
# pulled yet, and the fix is `just update-claude-code && just switch`.
#
# Matching the channel the tool itself checks against is what turns the prompt
# from noise into a reminder. That is the whole argument; it is worth more than
# the few days of soak time `stable` would buy. nixpkgs' own update.sh also
# reads `latest`, so this agrees with upstream — the pin is about cadence, not
# about disagreeing with nixpkgs on which build to trust.
#
# ## How the pin works
#
# nixpkgs' recipe (pkgs/by-name/cl/claude-code/package.nix) is already a thin
# wrapper over Anthropic's own native binaries, and it takes the release
# manifest as an overridable callPackage argument:
#
#     manifest ? lib.importJSON ./manifest.zst.json,
#
# So the pin is one `.override` fed ./claude-code-manifest.json — a VERBATIM
# copy of Anthropic's own `manifest.zst.json` for one release. That file
# carries the version string and a SHA-256 per platform for the
# zstd-compressed binaries, which is every input the derivation needs: no hash
# for us to compute, nothing to keep in sync by hand, and the checksums we
# build against are the ones Anthropic published rather than ones we
# re-derived. nixpkgs keeps owning everything else — autoPatchelfHook on Linux,
# the alsa-lib library path, ripgrep / procps / bubblewrap / socat on PATH, and
# the DISABLE_AUTOUPDATER=1 wrapper.
#
# A pinned file rather than a live lookup because flake evaluation is pure: a
# version read from the network at eval time is not expressible without an
# impure builtin that breaks the lock. The pin IS the mechanism;
# `just update-claude-code` is the refresh, and it is a one-line curl of
# Anthropic's artifact because of the manifest shape above.
#
# ## Why the shim
#
# `claude update` cannot replace a store path, but it does not fail either — it
# installs a *second*, native copy under ~/.local/share/claude/versions/ and
# repoints ~/.local/bin/claude at it. Upstream does print "Not replacing
# <path>: it was not created by the native installer ... so this update will
# not overwrite it", but that notice is easy to miss, and the result is two
# installs many releases apart, sharing ~/.claude state, with PATH order
# silently deciding which one runs. That is exactly how this config ended up
# running 2.1.272 while ~/.local/bin/claude pointed at 2.1.296.
#
# So `claude` here is a shim over `claude-code-unwrapped` (the same
# shim-over-unwrapped shape lib/overlays/linear-cli.nix uses) that intercepts
# `update` / `upgrade`, points at the just recipe, and exits non-zero so no
# script mistakes it for a successful upgrade. Everything else is exec'd
# straight through, so there is one extra process and no behaviour change.
#
# `install` is deliberately NOT intercepted: it is the documented escape hatch
# ("claude install stable|latest|<version>"), it is never hit by accident, and
# leaving it alone means there is still a way to get a native build without
# editing Nix. It does recreate the two-install situation above, which is why
# the shim's message names it.
#
# ## Applied to
#
# Every host that installs claude-code, which is the three with
# `my.cliAiTools = true` — the Darwin workstations bergamot and miraclemax
# (modules/infra/darwin-builder.nix) and the NixOS desktop yuzu
# (modules/infra/nixos-builder.nix). lumquat leaves cliAiTools off and never
# carries it, the same scoping worktrunk and linear-cli use.
#
# ## Coupling to watch
#
# The override depends on upstream's `manifest` argument existing. If nixpkgs
# restructures the recipe this fails at eval with "does not accept argument
# manifest" — loudly, not silently on a stale version. Re-point it at whatever
# replaced it, or inline the derivation.
#
# NOT self-terminating, unlike the other overlays here: it is not bridging a
# gap until nixpkgs catches up. It decouples this one tool's cadence from the
# nixpkgs pin and keeps the update prompt honest. Keep it.
final: prev:
let
  unwrapped = prev.claude-code.override {
    manifest = final.lib.importJSON ./claude-code-manifest.json;
  };
in
{
  claude-code-unwrapped = unwrapped;

  claude-code =
    final.runCommand "claude-code-${unwrapped.version}"
      {
        inherit (unwrapped) version;
        meta = unwrapped.meta // {
          mainProgram = "claude";
        };
        passthru = { inherit unwrapped; };
      }
      ''
        mkdir -p "$out/bin"
        cat > "$out/bin/claude" <<'SHIM'
        #!${final.runtimeShell}
        if [ "$#" -gt 0 ]; then
          case "$1" in
            update | upgrade)
              echo "claude-code here is managed by Nix, so 'claude $1' cannot replace it:" >&2
              echo "the binary lives in the read-only store. Running it anyway would install a" >&2
              echo "second, native copy under ~/.local/share/claude/versions/ that this one" >&2
              echo "would then shadow on PATH." >&2
              echo >&2
              echo "To upgrade, in your nix-config checkout:" >&2
              echo >&2
              echo "    just update-claude-code && just switch" >&2
              echo >&2
              echo "That re-fetches Anthropic's latest-channel manifest into" >&2
              echo "lib/overlays/claude-code-manifest.json and rebuilds." >&2
              echo >&2
              echo "If you really do want a separate native install, 'claude install' is not" >&2
              echo "intercepted — but it is what creates the two-install confusion above." >&2
              exit 1
              ;;
          esac
        fi
        exec ${unwrapped}/bin/claude "$@"
        SHIM
        chmod +x "$out/bin/claude"
      '';
}
