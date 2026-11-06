# pi-coding-agent — the pi coding agent, from pi.nix.
#
# Why this exists: nixpkgs' `pi-coding-agent` does not work in NixOS's
# read-only store (nixpkgs' build expects to install/update under its own
# prefix at runtime). pi.nix's build is the one that works there. That is why
# modules/infra/devshell.nix has always extended its package set with the
# pi.nix overlay instead of using `pkgs.pi-coding-agent` directly.
#
# Once pi is a *global* tool (modules/features/cli-ai-tools.nix) the overlay
# has to reach each host's package set too, which is what this overlay is for.
# Same dev-tool policy as worktrunk and linear-cli — see the headers of
# lib/overlays/worktrunk.nix and lib/overlays/linear-cli.nix.
#
# Applied to:
#   * every NixOS host's package set (modules/infra/nixos-builder.nix)
#   * every Darwin workstation's package set (modules/infra/darwin-builder.nix)
#   * this repo's dev shell package set (modules/infra/devshell.nix)
#
# Bumping: `nix flake update pi-nix`. Note that pi's own `pi update` does
# nothing useful here — the binary lives in the read-only store, so pi moves
# only via that lock update plus a rebuild. The dev shell's PI_OFFLINE=1 also
# suppresses pi's startup version check, whose failure message ("Could not
# determine latest pi version") is a symptom of that variable, not of a
# network or permissions problem.
#
# pi.nix's callPackage argument follows the nixpkgs attr rename: it used to be
# `typescript-go`, which nixpkgs renamed to `typescript`. pi.nix HEAD
# (rev b9009565) takes `typescript`, so passing the retired name is itself an
# error (`called with unexpected argument 'typescript-go'`) and aborts
# evaluation. Nothing to override here; recorded because the old shim in
# devshell.nix was removed for exactly this reason.
{ pi-nix }: final: _prev: {
  pi-coding-agent = (final.extend pi-nix.overlays.default).pi-coding-agent;
}
