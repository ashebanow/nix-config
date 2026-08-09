# FlakeHub cache authentication for determinate-nixd.
#
# cache.flakehub.com is an active substituter (see ./caches.nix) but requires a
# FlakeHub login. determinate-nixd stores auth state itself over its daemon
# socket — there is no nix.conf knob for it. This module provisions the
# FlakeHub token from SOPS and logs nixd in once at boot, re-running whenever
# the secret rotates or the nixd binary changes (a version upgrade invalidates
# the daemon's auth state, e.g. 3.21.7 → 3.22.0).
#
# Gated on the same capability flags as modules/features/secrets.nix (sops is
# only configured when my.access or my.llm is set) and on determinate being
# enabled (the determinate module — default true — runs nixd as
# nix-daemon.service).
{
  lib,
  config,
  pkgs,
  inputs,
  ...
}: {
  config = lib.mkIf (config.determinate.enable && (config.my.access || config.my.llm)) {
    sops.secrets.flakehub-token = {
      # defaultSopsFile (../../secrets/secrets.yaml) comes from
      # modules/features/secrets.nix.
    };

    systemd.services.flakehub-nixd-auth = {
      description = "Authenticate determinate-nixd to FlakeHub";
      wantedBy = [ "multi-user.target" ];
      wants = [ "sops-install-secrets.service" ];
      after = [
        "sops-install-secrets.service"
        "nix-daemon.service"
        "determinate-nixd.socket"
      ];
      serviceConfig = {
        Type = "oneshot";
        # Same determinate-nixd binary the determinate module runs as the
        # daemon (from the determinate flake input, not nixpkgs).
        ExecStart = "${inputs.determinate.packages.${pkgs.stdenv.system}.default}/bin/determinate-nixd auth login token --token-file ${config.sops.secrets.flakehub-token.path}";
        # Token may be rotated between switches; retry hourly until OK.
        Restart = "on-failure";
        RestartSec = "1h";
      };
      # Re-run when sops-nix rewrites the secret (token rotation) or when the
      # nixd / nix packages change (version upgrade), so the cache keeps
      # authenticating without manual steps. restartTriggers fires when any
      # listed path's mtime is newer than the last start — a rebuilt store path
      # always has a fresh mtime, an unchanged one does not.
      restartTriggers = [
        config.sops.secrets.flakehub-token.path
        config.nix.package
        inputs.determinate.packages.${pkgs.stdenv.system}.default
      ];
    };
  };
}
