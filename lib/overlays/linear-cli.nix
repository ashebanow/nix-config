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
# librt, libpthread, libgcc_s; interp /lib64/ld-linux-x86-64.so.2), so
# autoPatchelfHook plus libgcc_s from the compiler runtime is all it takes.
# The Darwin binary runs as shipped. Neither is stripped: they are 160 MB
# Deno runtimes with the program appended, and strip has nothing to gain.
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
# Bumping: `just linear-bump vX.Y.Z` (BOX-183) rewrites `version` and both
# hashes below and re-vendors the agent skill in the chezmoi repo, which is
# pinned to the same tag. Do not bump one without the other.
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
      final.autoPatchelfHook
    ];
    buildInputs = final.lib.optionals final.stdenv.hostPlatform.isLinux [
      final.stdenv.cc.cc.lib # libgcc_s.so.1
    ];

    dontConfigure = true;
    dontBuild = true;
    dontStrip = true;

    installPhase = ''
      runHook preInstall

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
