# prometheus-podman-exporter — Prometheus metrics for rootless podman containers.
#
# Why this exists: our pinned nixpkgs (flake.lock, rev 31ecbac) has no package
# for it. nixpkgs initialised it at d70e8bc28a, which is *newer* than our pin,
# and it has no NixOS module at any rev — so there is nothing to import, nothing
# to enable, and nothing to wait for. Bumping the whole flake lock to gain one
# Go binary would drag every other package forward for a reporter; this file
# costs the same effort and none of that risk. (BOX-331.)
#
# The derivation is nixpkgs' own, copied from
# `pkgs/by-name/pr/prometheus-podman-exporter/package.nix` at master, minus the
# parts we do not use. That is deliberate: it is a known-good build recipe
# maintained by someone else, and a hand-rolled one would have to rediscover the
# tag sets and the ldflags that stop the binary reporting "version dev". When
# nixpkgs' pin eventually passes that commit, delete this file and
# modules/infra/nixos-builder.nix's reference to it — `pkgs.prometheus-podman-exporter`
# is then nixpkgs' own.
#
# ## Why an overlay rather than a bare derivation
#
# So `pkgs.prometheus-podman-exporter` resolves wherever the host's package set
# is used — a feature module, the contract test, `nix shell` — with no
# callPackage argument threaded through any of them. That is the same shape as
# the other files in this directory, and it is what makes the consuming module
# read as if nixpkgs had the package after all.
#
# ## What it is not
#
# Not a collector of our own (the agent module owns the collector set), and not
# a container. ADR 0006: every observability component is a native NixOS
# service. It is a plain Go binary the agent module runs as `my.baseUsername`
# with `CONTAINER_HOST` pointing at that user's rootless podman socket — which
# is the whole reason it beats cadvisor here: it speaks podman's own API, so its
# labels are the container names and pods the host already thinks in, and it
# needs no cgroup v2 or /sys/fs/cgroup access at all. cadvisor stays unused.
#
# ## The build
#
# cgo is used only for gpgme/libassuan (image signature verification under the
# `containers_image_openpgp` tag); the podman API is Go. `doCheck = false`
# because upstream's test suite wants a running podman daemon and a $HOME —
# neither exists in the Nix build sandbox, and a suite that skipped itself would
# be a false green rather than a check.
#
# Built at BOX-331 time: `nix build` of this succeeded on x86_64-linux (see
# /tmp/box311/notes/BOX-331.md for the exact command and the result). It is a
# genuine compiled artifact, not a packaging guess.
_final: prev: {
  prometheus-podman-exporter = prev.callPackage (
    {
      lib,
      buildGoModule,
      fetchFromGitHub,
      pkg-config,
      gpgme,
      libassuan,
      systemd,
      btrfs-progs,
    }:
    buildGoModule (finalAttrs: {
      pname = "prometheus-podman-exporter";
      version = "2.0.0";

      src = fetchFromGitHub {
        owner = "containers";
        repo = "prometheus-podman-exporter";
        tag = "v${finalAttrs.version}";
        hash = "sha256-713r7COiEEO+zGVQPhFoWPpr9ILYxABQrRshvF9bfVU=";
      };

      buildInputs = [
        gpgme
        libassuan
        systemd
        btrfs-progs
      ];
      nativeBuildInputs = [ pkg-config ];

      # Upstream's Makefile derives these from hack/*.sh, which probe the build
      # host. Hardcoded to what those probes would say on NixOS: systemd is
      # present, and btrfs-progs is in buildInputs, so neither exclusion tag is
      # set.
      tags = [
        "remote"
        "containers_image_openpgp"
        "systemd"
      ];

      # Upstream keeps the version in a VERSION file rather than deriving it from
      # the git tag, so without these the binary reports "dev" and its own
      # version series is useless. `buildBranch=HEAD` is what a tag build yields.
      ldflags = [
        "-X github.com/containers/prometheus-podman-exporter/cmd.buildVersion=${finalAttrs.version}"
        "-X github.com/containers/prometheus-podman-exporter/cmd.buildRevision=${lib.versions.major finalAttrs.version}"
        "-X github.com/containers/prometheus-podman-exporter/cmd.buildBranch=HEAD"
      ];

      # go.mod is fully vendored upstream (the Makefile builds with -mod=vendor),
      # so there is no separate vendor hash to maintain.
      vendorHash = null;

      __structuredAttrs = true;

      doCheck = false;

      meta = {
        description = "Prometheus exporter for podman environments exposing containers, pods, images, volumes and networks information";
        homepage = "https://github.com/containers/prometheus-podman-exporter";
        license = lib.licenses.asl20;
        maintainers = with lib.maintainers; [ cobalt ];
        mainProgram = "prometheus-podman-exporter";
      };
    })
  ) { };
}
