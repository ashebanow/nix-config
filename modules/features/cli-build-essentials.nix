# Global build toolchain — the deliberate exception to "most dev tools
# are devenv-only". These are needed to rebuild other packages from
# source (e.g. Homebrew formulae) or are assumed present by other CLI
# tools (node/npm/npx). Language-specific tooling (linters, LSPs,
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
        direnv
        gcc
        gnumake
        lld
        llvm
        nodejs
        uv
      ];
    };
  };
}
