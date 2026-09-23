{
  description = "Lumquat NixOS Configuration - AI Server";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";

    # Determinate Nix — replaces stock nix-daemon with determinate-nixd
    determinate.url = "https://flakehub.com/f/DeterminateSystems/determinate/*";

    # Flake framework
    flake-parts.url = "github:hercules-ci/flake-parts";
    import-tree.url = "github:vic/import-tree";
    import-tree.flake = false;

    # Home Manager
    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # macOS system configuration (Darwin hosts)
    nix-darwin = {
      url = "github:nix-darwin/nix-darwin/master";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Declarative Homebrew installation management (Darwin hosts) —
    # taps pinned via flake inputs so nix-homebrew can manage the
    # Homebrew installation itself, not just run `brew bundle`.
    nix-homebrew.url = "github:zhaofengli/nix-homebrew";
    homebrew-core = {
      url = "github:homebrew/homebrew-core";
      flake = false;
    };
    homebrew-cask = {
      url = "github:homebrew/homebrew-cask";
      flake = false;
    };

    # Registers nix/home-manager-installed .app bundles with Spotlight
    # and Launchpad — without this, GUI apps installed via home.packages
    # are technically present but undiscoverable (Spotlight doesn't
    # index the symlinks Nix creates).
    mac-app-util.url = "github:hraban/mac-app-util";

    # NixOS hardware quirks
    nixos-hardware.url = "github:nixos/nixos-hardware";

    # DankMaterialShell — its own flake rather than nixpkgs' programs.dms-shell,
    # which trails DMS's release cadence (1.6.1 against 1.6.2 when this landed).
    # `stable` is a branch, so flake.lock is what actually pins it; bump with
    # `nix flake update dms`. The flake no longer ships quickshell, so
    # pkgs.quickshell is used either way. See docs/adr/0003.
    dms = {
      url = "github:AvengeMedia/DankMaterialShell/stable";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # pi coding agent — consumed as an overlay in the dev shell ONLY
    # (see modules/infra/devshell.nix), never in a host closure. The stock
    # nixpkgs pi-coding-agent trips over NixOS's read-only, non-FHS store;
    # pi.nix's wrapper redirects NPM_CONFIG_PREFIX to $XDG_DATA_HOME so pi
    # can start. Tracks pi.nix's default branch (it follows upstream pi
    # within a day or two and caches builds at pi.cachix.org); flake.lock
    # still pins an exact rev, so bump it deliberately with
    # `nix flake update pi-nix`. Pi moves too fast for a tag pin to be
    # worth the manual babysitting, and this is dev-shell-only anyway.
    pi-nix = {
      url = "github:lukasl-dev/pi.nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # worktrunk (wt, the git-worktree CLI) — nixpkgs unstable is 0.74.0, three
    # releases behind, and the agent integrations the workflow needs
    # (`wt config plugins pi`, .codex, .opencode) only exist from 0.77.0.
    # Upstream publishes no `overlays` output, so lib/overlays/worktrunk.nix
    # wraps the package its own flake builds with crane under the nixpkgs
    # attribute name. That overlay reaches the dev shell on every host and
    # (Darwin only) the workstations' pkgs — lumquat's host closure never
    # carries worktrunk, matching pi.nix's dev-tool policy.
    #
    # TEMPORARY RELEASE PIN (BOX-145). Both changes the fork carried are now in
    # upstream's v0.78.0 — the Pi/oh-my-pi split (max-sixty/worktrunk#4135, the
    # split we proposed; upstream closed our #4133 by landing it) and the
    # `stdenv.hostPlatform.isDarwin` fix (#4132) — so the fork pin is gone and
    # this reads upstream's tag directly. The fork's `nix-pin` branch is retired;
    # nothing here should point at a fork branch again.
    #
    # Pinned to the tag, NOT `main`: `main` runs ahead of releases with
    # release-please and would re-inherit the unreleased-commit churn this pin
    # exists to avoid. `v0.78.0` is upstream's newest *published* release; a
    # `Release v0.79.0` commit exists on `main` but the tag is not pushed, so
    # there is nothing newer to point at.
    #
    # This pin drops entirely once nixpkgs unstable ships >= 0.78.0 — then the
    # overlay in lib/overlays/worktrunk.nix goes too. Tracked in BOX-190.
    worktrunk = {
      url = "github:max-sixty/worktrunk/v0.78.0";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = inputs @ {flake-parts, ...}: let
    import-tree = import inputs.import-tree;
  in
    flake-parts.lib.mkFlake {inherit inputs;} {
      imports = [
        # Auto-discover all feature modules
        (import-tree ./modules/features)

        # Infrastructure modules (explicit — not auto-discovered)
        ./modules/infra/nix
        ./modules/infra/module-containers.nix
        ./modules/infra/devshell.nix
        ./modules/infra/nixos-builder.nix
        ./modules/infra/darwin-builder.nix
      ];

      systems = ["x86_64-linux" "aarch64-darwin"];
    };
}
