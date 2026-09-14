# linear-cli — schpet's `linear` CLI for Linear.app, packaged from upstream's
# release binaries. Replaces the Linear MCP server in every agent surface
# (BOX-176): an MCP tool manifest costs ~15K tokens of context per session,
# a CLI on PATH costs nothing until it is called.
#
# Why this exists: nixpkgs has no package for the CLI (`pkgs.linear` is the
# desktop app's DMG, Darwin-only). Upstream is a Deno project; building it
# from source under Nix means a deno2nix fork and a dependency hash to
# refresh every release, which is what the y0usaf/linear-cli fork does and
# what BOX-177 declined. Upstream ships `deno compile` binaries for both of
# our systems, so this fetches those instead: two hashes, no toolchain.
#
# The Linux binary is a stock glibc executable (NEEDED: libc, libm, libdl,
# librt, libpthread, libgcc_s; interp /lib64/ld-linux-x86-64.so.2), so it
# needs the usual interpreter + rpath patch — but NOT autoPatchelfHook.
# `deno compile` output is [ELF runtime][program payload][16-byte trailer];
# the runtime finds its program at startup by reading its own file's last
# 16 bytes (libsui 0.12: u32 magic 0x501e, u32 name hash, u64 offset back
# from EOF) and slicing from EOF-offset. It is not an ELF section, and
# patchelf, which only knows the ELF, appends its relocated sections after
# the payload — the trailer is no longer at EOF and the binary dies with
# "Could not find standalone binary section". So the install step splits
# the payload off using that trailer, patches the bare ELF, and re-appends
# the payload; the trailer's end-relative offset is then correct again.
# The Darwin binary runs as shipped. Neither is stripped and the fixup
# phase's own patchelf pass is disabled, for the same reason.
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
final: _prev: let
  version = "2.6.0";

  # Release asset per system; hashes are the SRI form of upstream's
  # sha256.sum for the same tag.
  assets = {
    aarch64-darwin = {
      target = "aarch64-apple-darwin";
      hash = "sha256-uavdS1rsFEWeQ0oomSA3V96K6EfwVerk8frue7H7wHg=";
    };
    x86_64-linux = {
      target = "x86_64-unknown-linux-gnu";
      hash = "sha256-u8udNlMIvDcooeyZE60YgPiMDOaHZzgyl+NIwFfzW40=";
    };
  };

  inherit (final.stdenv.hostPlatform) system;
  asset =
    assets.${system}
    or (throw "linear-cli: no upstream release binary is pinned for ${system}; add it to lib/overlays/linear-cli.nix");
in {
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
        # Split [ELF][payload][trailer] on the libsui trailer, patch the ELF
        # alone, rejoin. Sizes via wc/od so this needs nothing but coreutils.
        size=$(wc -c < linear | tr -d ' ')
        magic=$(tail -c 16 linear | head -c 4 | od -An -tu4 | tr -d ' ')
        plen=$(tail -c 8 linear | od -An -tu8 | tr -d ' ')
        if [ "$magic" != "20510" ]; then # 0x501e
          echo "linear-cli: no libsui trailer at EOF (magic=$magic); upstream changed the deno compile layout — re-check lib/overlays/linear-cli.nix" >&2
          exit 1
        fi
        head -c $((size - plen)) linear > linear.elf
        tail -c "$plen" linear > linear.payload
        patchelf \
          --set-interpreter ${final.stdenv.cc.bintools.dynamicLinker} \
          --set-rpath ${final.lib.makeLibraryPath [final.stdenv.cc.cc.lib final.glibc]} \
          linear.elf
        cat linear.elf linear.payload > linear
        rm linear.elf linear.payload
        # Trailer must be at EOF again with the same end-relative offset.
        [ "$(tail -c 8 linear | od -An -tu8 | tr -d ' ')" = "$plen" ]
      ''}

      install -Dm755 linear $out/bin/linear-unwrapped
      install -Dm644 LICENSE $out/share/licenses/linear-cli/LICENSE
      install -Dm644 README.md $out/share/doc/linear-cli/README.md
      install -Dm644 CHANGELOG.md $out/share/doc/linear-cli/CHANGELOG.md

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
      sourceProvenance = [sourceTypes.binaryNativeCode];
    };
  };
}
