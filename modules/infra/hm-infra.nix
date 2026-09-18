# Home Manager infrastructure for podman user.
#
# Also installs chezmoi and applies it on every HM activation (which runs
# on every `nh os switch` via the home-manager NixOS module). Lumquat is a
# chezmoi-managed headless host: `programs.chezmoi` does not exist upstream,
# so the wiring is home.packages + a home.activation entry. The init is
# guarded by the presence of the chezmoi source repo so it is idempotent,
# and `--force` makes `apply` non-interactive (suppresses the changed-file
# TTY prompt).
#
# The BWS access token is delivered to `home-manager-podman.service` as a
# systemd credential by the NixOS layer (the `LoadCredential=access_token:`
# added in modules/infra/nixos-builder.nix, the same BOX-131 pattern the
# service consumers use). Home Manager activation cannot reliably reach the
# root-only token file itself: its PATH is nix-store paths only, so `sudo`
# (which NixOS puts in /run/wrappers/bin) was never found and the read
# silently produced an empty string for every activation (BOX-174). Reading
# ${CREDENTIALS_DIRECTORY} instead depends on neither `sudo` nor `PATH`.
#
# Apply safety is handled chezmoi-side: the headless .chezmoiignore excludes
# the personal-secret templates that must not exist on lumquat (hermes, git
# signingkey). The gh token template is deliberately *not* excluded -- `gh`
# is the remaining BWS_ACCESS_TOKEN consumer -- so the token must genuinely
# reach apply, and a failure to obtain it must be visible (BOX-174).
{
  config,
  lib,
  pkgs,
  ...
}: {
  my.cliTools = true;

  home.packages = [pkgs.chezmoi]; # nixpkgs chezmoi 2.72.0

  home.activation.chezmoiApply = lib.hm.dag.entryAfter ["writeBoundary"] ''
    # Provision the BWS token (SECRET_SYNC.md) as BWS_ACCESS_TOKEN so
    # templates that need it (gh github-cli-token) render on headless.
    #
    # Delivered as a systemd credential named `access_token` by the unit's
    # LoadCredential (modules/infra/nixos-builder.nix). Three cases, only one
    # of which is fine to swallow:
    #   - CREDENTIALS_DIRECTORY unset  -> unit not wired for credentials
    #     (standalone `home-manager switch`, VM test). Token-less apply.
    #   - directory set, file absent   -> intended token-less fallback
    #     (host bootstrapped without a BWS token). Token-less apply.
    #   - directory set, file present but unreadable -> a real failure. Do
    #     not degrade to an empty BWS_ACCESS_TOKEN in silence; a token that
    #     exists is expected to work.
    if [ -n "''${CREDENTIALS_DIRECTORY:-}" ]; then
      if [ -e "$CREDENTIALS_DIRECTORY/access_token" ]; then
        if ! BWS_ACCESS_TOKEN="$(cat "$CREDENTIALS_DIRECTORY/access_token")" || [ -z "$BWS_ACCESS_TOKEN" ]; then
          echo "chezmoiApply: FATAL: $CREDENTIALS_DIRECTORY/access_token exists but could not be read" >&2
          exit 1
        fi
        export BWS_ACCESS_TOKEN
      fi
    fi
    # The gh hosts.yml template resolves the token by shelling out to the
    # `bws` CLI (chezmoi's `output "bws" "secret" get ...`), not by using
    # BWS_ACCESS_TOKEN itself -- so `bws` must be callable from here. HM's
    # activation PATH is nix-store coreutils/findutils/... only, and the
    # system-wide `bws` in /run/current-system/sw/bin is not on it; the
    # template would abort apply even with a valid token (BOX-174).
    #
    # The path comes from `config.my.bwsBinDir`: the system profile by default
    # (modules/features/base.nix installs `bws` there), set by the NixOS layer
    # to the exact store path. It cannot be written as `pkgs.bws` here -- that
    # package is unfree and nixpkgs' allowUnfree is not threaded into this
    # Home Manager module's `pkgs` argument.
    export PATH="${config.my.bwsBinDir}''${PATH:+:$PATH}"
    run test -d "$HOME/.local/share/chezmoi/.git" \
      || run ${pkgs.chezmoi}/bin/chezmoi init https://github.com/ashebanow/dotfiles.git
    run ${pkgs.chezmoi}/bin/chezmoi apply --force
  '';
}
