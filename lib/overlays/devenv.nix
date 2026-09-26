# devenv — pinned ahead of nixpkgs for the macOS keyring fix.
#
# Why this exists: devenv wraps the macOS login keychain through SecretSpec's
# keyring provider, and SecretSpec 0.20.0 seals the ACL it writes. The item
# below (created by an older devenv) ends up with an EMPTY change_acl list:
#
#     entry 4:
#         authorizations (1): change_acl
#         applications (0):
#
# "Always Allow" works by appending the caller to the decrypt entry, and that
# append *is* a change_acl operation — so with the list empty the grant is
# denied and silently discarded. No error reaches the user. Every directory
# entry re-prompts, forever, and this reads as "Always Allow doesn't stick".
#
# Nix-store devenv is adhoc/linker-signed with no Team ID, so macOS cannot
# match it by identity and falls back to pinning the raw cdhash — meaning every
# devenv bump orphans the previous ACL entries. Confirmed on the 2.3.1 store
# path: `Signature=adhoc`, `TeamIdentifier=not set`, and both recorded ACL
# entries reporting `status -67068` (errSecCSReqFailed).
#
# SecretSpec 0.21.0 fixes this: reads preserve the item and its access settings,
# and the upgrade path transfers ownership to the new build so a single
# "Always Allow" sticks. devenv v2.4.0 is the first release that carries it
# (Cargo.toml pins `secretspec = "0.21"`, Cargo.lock resolves 0.21.0; verified
# on the built binary: `devenv 2.4.0`, `secretspec 0.21.0`).
#
# Why devenv ONLY — do not add a `secretspec` override here:
# SecretSpec is vendored into the devenv workspace and built from source. The
# nixpkgs devenv recipe (pkgs/by-name/de/devenv/package.nix) has no secretspec
# input and no `lib.getBin secretspec` on PATH; the `secretspec` binary that
# ships in $out/bin comes out of that same cargo build. nixpkgs' top-level
# `secretspec` is an unrelated package on its own cadence — 0.10.1 in our
# current lock against devenv's bundled 0.20.0, and neither tracks the other.
# Overriding it would shadow the bundled CLI with a different build and give
# the CLI and the in-process library distinct code identities, which is the
# exact mismatch class this overlay exists to remove. The bundled copy is the
# one that reads the keychain; keep them identical by not splitting them.
#
# Why we take nixpkgs unstable's package rather than re-deriving 2.4.0 from our
# own nixpkgs: the recipe hardcodes version/src/cargoHash inside its
# `buildRustPackage` call, so `overrideAttrs` cannot swap them cleanly — it
# leaves the already-materialized `cargoDeps` from 2.3.1 in place, and nulling
# `cargoDeps` breaks cargoSetupPostUnpackHook. Overriding a function argument
# is not available either, because the recipe is a pre-built package value, not
# a callable. Re-deriving would also mean compiling devenv from source; taking
# unstable's derivation substitutes straight from cache.nixos.org (verified).
#
# `devenvUnstable` is a *second* nixpkgs input used for this one attribute, not
# an overlay on the workstation's whole package set — everything else on those
# hosts stays on the FlakeHub 0.2605 pin. Bumping the pin is therefore
# independent of this host's nixpkgs.
#
# Applied to: the Darwin workstations' package set, so `pkgs.devenv` resolves
# to the pin wherever it is consumed (modules/features/cli-build-essentials.nix,
# modules/features/base.nix). lumquat is NixOS and keeps nixpkgs' devenv; its
# `secretspec` in base.nix is the standalone operator-shell package for the
# `just` recipes and is deliberately untouched by this overlay.
#
# RETIRE ME: this overlay is self-terminating. Darwin hosts already compute
# `pkgs` from the 0.2605 pin, so `nix flake update` on that pin eventually
# brings devenv >= 2.4.0 in on its own. Once it does, delete this file and the
# `devenvUnstable` input in flake.nix, and confirm the bundled secretSpec is
# >= 0.21 with `secretspec --version`. Tracked in BOX-245.
{devenvUnstable}:
final: _prev: {
  devenv = devenvUnstable.legacyPackages.${final.stdenv.hostPlatform.system}.devenv;
}
