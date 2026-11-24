# rex — patched around a stdenv unpack failure (BOX-339).
#
# Why this exists: Rex's release archive keeps its files at the top level with
# no enclosing directory, and its flake acknowledges that by setting
#
#   sourceRoot = ".";
#
# That is where it breaks. stdenv's unpackPhase then runs
#
#   chmod -R u+w -- "$sourceRoot"
#
# (see stdenv/setup, the block after "source root is ."). With sourceRoot "."
# the recursion covers the whole build root, including Nix's own
# `builder.json` and `env-vars`. Those are root-owned and deliberately
# read-only, so chmod cannot change them and the phase dies with:
#
#   chmod: changing permissions of '.': Operation not permitted
#   chmod: changing permissions of './builder.json': Operation not permitted
#
# This is not Darwin-specific. It fires for any non-root builder user on any
# platform, so it breaks `nix build` of every host with Rex enabled (lumquat
# and yuzu here).
#
# `dontMakeSourcesWritable = 1` is NOT the fix: it guards that chmod, but
# upstream already sets sourceRoot = "." explicitly, and the intent of the
# guard is "sources are already writable". Clearing it would suppress a chmod
# that is genuinely harmful here — but it is also not enough, because stdenv
# still walks "." elsewhere (see the `chmod -R u+w,u-s,g-s` on outputs), and
# disabling the guard would make the build depend on the store's permissions.
#
# The fix is to point sourceRoot at a real subdirectory, so the recursion stays
# inside the unpacked sources. The archive has no top-level directory, so this
# overlay creates one and moves the payload into it — a few lines, and the
# build then proceeds exactly as upstream intends (their own installPhase
# refers to the files by bare name, so the move must keep it flat).
#
# Upstream owns the real fix (give the archive a top-level directory, or set
# sourceRoot to a directory they create). Delete this overlay when they do.
#
# Applied to the NixOS hosts' package set via modules/features/rex.nix, which is
# the only place that can override services.rex.package — the Rex module
# resolves its default from its own flake, not from `pkgs`, so a plain nixpkgs
# overlay cannot reach it. See the comment there.
#
# The attribute is `rex-patched`, NOT `rex`. Overwriting `rex` in the package
# set would be a lie: nixpkgs has an unrelated `rex` (a Perl module), many
# packages reference it by that name, and a silent global replacement is a trap
# for the next reader. modules/features/rex.nix names this attribute
# explicitly instead.
{ rex }: final: _prev: {
  rex-patched = (rex.packages.${final.stdenv.hostPlatform.system}.rex).overrideAttrs (old: {
    # Unpack into a subdirectory the overlay creates, and keep the files flat
    # inside it so upstream's installPhase (which names `rex` bare) still works.
    unpackPhase = ''
      runHook preUnpack
      mkdir -p source
      tar -xf ${old.src} -C source
      sourceRoot=source
      runHook postUnpack
    '';
    dontMakeSourcesWritable = 1;
  });
}
