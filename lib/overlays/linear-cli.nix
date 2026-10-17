# linear-cli — schpet's `linear` CLI for Linear.app, packaged from upstream's
# release binaries. Replaces the Linear MCP server in every agent surface
# (BOX-176): an MCP tool manifest costs ~15K tokens of context per session,
# a CLI on PATH costs nothing until it is called.
#
# Why this exists: nixpkgs has no package for the CLI (`pkgs.linear` is the
# desktop app's DMG, Darwin-only). Building it from source under Nix means a
# language toolchain pin plus a dependency hash to refresh every release,
# which is what the y0usaf/linear-cli fork does and what BOX-177 declined.
# Upstream ships prebuilt binaries for both of our systems, so this fetches
# those instead: two hashes, no toolchain.
#
# v3.0.0 is a rewrite in Rust (2.x was TypeScript run through `deno compile`),
# which simplified this derivation. The 2.x Linux binary was
# [ELF runtime][program payload][16-byte libsui trailer] and needed the
# install step to split on that trailer, patchelf the bare ELF, and rejoin —
# patchelf alone moved the trailer off EOF and the binary died with "Could
# not find standalone binary section" (denoland/deno#19961). A Rust binary
# keeps no program payload inside itself, so the 3.x Linux asset is a plain
# dynamically linked PIE (NEEDED: libc.so.6, libgcc_s.so.1; interp
# /lib64/ld-linux-x86-64.so.2) that takes a normal interpreter + rpath
# patch. That split/patch/rejoin step and its libsui guard are gone; the
# guard is what caught the change, and it fired before this was rewritten.
#
# The Darwin binary runs as shipped. Neither is stripped. ELF patching is
# disabled in the fixup phase for the Linux build only, because patchelf has
# already run in installPhase and nothing should get a second, post-prefetch
# pass at it.
#
# The `linear` on PATH is a shim over `linear-unwrapped`. When
# LINEAR_API_KEY is not already set and /run/secrets/linear-api-key is
# readable, the shim exports the key for the child process only. That file
# is how lumquat delivers the key (secretspec `dev` scope, populated by
# host-secrets-populate into tmpfs — BOX-179); on the Darwin workstations
# the key is already in the environment from chezmoi's secrets.sh, and the
# shim does nothing. The devshell never touches BWS itself either way.
#
# Applied to:
#   * this repo's dev shell package set (modules/infra/devshell.nix) — the
#     only copy on lumquat, where linear is a dev tool like pi/worktrunk;
#   * the Darwin workstations' package sets (modules/infra/darwin-builder.nix)
#     — installed globally via modules/features/cli-vcs-tools.nix.
#
# Bumping: `just linear-bump vX.Y.Z` rewrites `version` and both hashes
# below and re-vendors the agent skill in the dotfiles repo, which is pinned
# to the same tag. Do not bump one without the other. The recipe finds the
# hash lines by the `target = "..."` line above each, so keep that shape.
final: _prev:
let
  version = "3.0.0";

  # Release asset per system; hashes are the SRI form of upstream's
  # `.sha256` file for the same tag.
  assets = {
    aarch64-darwin = {
      target = "aarch64-apple-darwin";
      hash = "sha256-heuE55VUSld63Be5b4sAdxvOyU840mRC/X1WHNgjNvI=";
    };
    x86_64-linux = {
      target = "x86_64-unknown-linux-gnu";
      hash = "sha256-UGSmOn5qi1iTpVDhOMCnujc6rWXUJd3msrZrUKbBAok=";
    };
  };

  inherit (final.stdenv.hostPlatform) system;
  asset =
    assets.${system}
      or (throw "linear-cli: no upstream release binary is pinned for ${system}; add it to lib/overlays/linear-cli.nix");
in
{
  linear-cli = final.stdenvNoCC.mkDerivation {
    pname = "linear-cli";
    inherit version;

    src = final.fetchurl {
      url = "https://github.com/schpet/linear-cli/releases/download/v${version}/linear-${asset.target}.tar.xz";
      inherit (asset) hash;
    };

    nativeBuildInputs = final.lib.optionals final.stdenv.hostPlatform.isLinux [
      final.patchelf
    ];

    dontConfigure = true;
    dontBuild = true;
    dontStrip = true;
    dontPatchELF = true; # would re-break the trailer (see header comment)

    installPhase = ''
      runHook preInstall

      ${final.lib.optionalString final.stdenv.hostPlatform.isLinux ''
        # 3.x is a stock Rust binary — a plain ELF, no embedded program
        # payload — so interpreter + rpath is all it needs (2.x's split on
        # the libsui trailer is obsolete; see the header comment).
        patchelf \
          --set-interpreter ${final.stdenv.cc.bintools.dynamicLinker} \
          --set-rpath ${
            final.lib.makeLibraryPath [
              final.stdenv.cc.cc.lib
              final.glibc
            ]
          } \
          linear
      ''}

      install -Dm755 linear $out/bin/linear-unwrapped
      install -Dm644 LICENSE $out/share/licenses/linear-cli/LICENSE
      install -Dm644 README.md $out/share/doc/linear-cli/README.md
      install -Dm644 CHANGELOG.md $out/share/doc/linear-cli/CHANGELOG.md
      # 3.x release archives ship the Rust dependency notices; 2.x did not.
      install -Dm644 THIRD_PARTY_LICENSES.md $out/share/doc/linear-cli/THIRD_PARTY_LICENSES.md

      cat > $out/bin/linear <<SHIM
      #!${final.runtimeShell}
      # Key delivery for headless hosts — see the header comment in
      # lib/overlays/linear-cli.nix. Environment always wins.
      if [ -z "\''${LINEAR_API_KEY:-}" ] && [ -r /run/secrets/linear-api-key ]; then
        LINEAR_API_KEY=\$(cat /run/secrets/linear-api-key)
        export LINEAR_API_KEY
      fi
      exec "$out/bin/linear-unwrapped" "\$@"
      SHIM
      chmod 755 $out/bin/linear

      runHook postInstall
    '';

    meta = with final.lib; {
      description = "Linear.app from the command line: list, start, and create PRs for Linear issues";
      homepage = "https://github.com/schpet/linear-cli";
      changelog = "https://github.com/schpet/linear-cli/blob/v${version}/CHANGELOG.md";
      license = licenses.isc;
      mainProgram = "linear";
      platforms = builtins.attrNames assets;
      sourceProvenance = [ sourceTypes.binaryNativeCode ];
    };
  };
}
