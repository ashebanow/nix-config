# Global build toolchain — the deliberate exception to “most dev tools
# are devenv-only”.
#
# Language toolchains themselves belong in devenv/nix shells, never here. What
# lives in this list is one of three things: tools needed to *rebuild other
# packages from source* (gcc, make, llvm), tools assumed present by other CLI
# tools (node/npm/npx), or the few tools that must be installed globally because
# they manage their own toolchains under $HOME and so cannot be provided by a
# per-project shell — uv and rustup. Language-specific tooling (linters, LSPs,
# framework package managers) stays devenv-only and is NOT listed here.
_: {
  my.modules.home-manager.cli-build-essentials = {
    lib,
    pkgs,
    config,
    ...
  }: {
    config = lib.mkIf config.my.cliBuildEssentials {
      home.packages = with pkgs; [
        devenv # per-project dev shells (moved from nix profile)
        direnv
        gcc
        gnumake
        lld
        llvm
        nix-direnv # direnv integration for nix flakes/devShells
        nodejs
        rustup # manages its own toolchains under ~/.rustup; see the NixOS half
        uv
      ];
    };
  };

  # rustup needs nix-ld to work at all, which is why it is in this module rather
  # than a shell module of its own.
  #
  # The toolchains rustup downloads are upstream binaries linked for a generic
  # Linux, so their ELF interpreter is /lib64/ld-linux-x86-64.so.2. NixOS ships
  # a *stub* at that path whose whole job is to print "Could not start
  # dynamically linked executable" and exit 127, so without nix-ld a downloaded
  # toolchain installs and then cannot run. nix-ld replaces the stub with a
  # loader that understands the FHS paths.
  #
  # The default library set is sufficient for rustc/cargo: libc resolves out of
  # the loader's own store directory, and libgcc_s/libstdc++ are in the set.
  # (Verified against a foreign binary with its RPATH stripped, not assumed.)
  # Append to programs.nix-ld.libraries if a toolchain ever needs more — the
  # missing library is named in the loader's own error.
  my.modules.nixos.cli-build-essentials = {
    lib,
    config,
    ...
  }: {
    config = lib.mkIf config.my.cliBuildEssentials {
      programs.nix-ld.enable = true;
    };
  };
}
