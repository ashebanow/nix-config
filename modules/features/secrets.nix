# Secrets module — secretspec/BWS bootstrap and host-level secret population.
#
# This is the single place the shared secretspec wiring lives:
#   - /etc/secretspec.toml      (symlink to the repo-root shared manifest)
#   - /var/lib/secrets/         (root-only dir for the out-of-band BWS token)
#   - /run/secrets/             (tmpfs for the two file-backed host secrets)
#   - host-secrets-populate.service (root) — resolves the `host` scope from BWS
#     and materializes tailscale + flakehub secrets as root-only files, then
#     the `dev` scope for operator-tool secrets (currently the Linear CLI key)
#     as files readable only by the operator user. Two `secretspec run`
#     invocations, so neither subprocess sees the other scope. See
#     docs/adr/0001 for why operator tools get their secrets this way.
#
# Container/compose secrets (bifrost, openwebui, memory) resolve
# their own scopes directly via `secretspec run` in their own feature modules;
# they do not land in this module.
_: {
  my.modules.nixos.secrets = {
    lib,
    pkgs,
    config,
    ...
  }: let
    manifest = config.my.secretspecManifest;
    accessToken = config.my.bwsAccessTokenFile;
    populate = ../../scripts/populate-host-secrets.sh;
    populateScript = pkgs.writeShellScript "populate-host-secrets" ''
      set -euo pipefail
      ${pkgs.secretspec}/bin/secretspec run -P production -S host -- \
        ${pkgs.bash}/bin/bash ${populate} host
      ${pkgs.secretspec}/bin/secretspec run -P production -S dev -- \
        ${pkgs.bash}/bin/bash ${populate} dev ${config.my.baseUsername}
    '';
  in {
    config = lib.mkIf (config.my.access || config.my.llm) {
      # Shared paths: manifest symlink + the two secret directories.
      systemd.tmpfiles.rules = [
        "L+ /etc/secretspec.toml - - - - ${../../secretspec.toml}"
        "d /var/lib/secrets 0700 root root -"
        "d /run/secrets 0755 root root -"
      ];

      # Resolve the `host` scope from BWS and write the two file-backed
      # secrets that root system services consume, then the `dev` scope for
      # the operator user's tools. Runs once at boot, before tailscale
      # autoconnect and flakehub auth need the files.
      systemd.services.host-secrets-populate = {
        description = "Populate host + dev secrets (tailscale, flakehub, linear) from BWS via secretspec";
        wantedBy = ["multi-user.target"];
        wants = ["network-online.target"];
        after = ["network-online.target"];
        before = lib.optionals config.my.access ["tailscaled-autoconnect.service"];
        path = [
          pkgs.secretspec
          pkgs.bws # secretspec 0.17+ invokes the official bws CLI
        ];
        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
          Environment = [
            "SECRETSPEC_FILE=${manifest}"
            "SECRETSPEC_PROVIDER=bws-service"
          ];
          # access_token is the SEMANTIC credential name the bws-service
          # alias looks up in systemd-credential:// (see secretspec.toml).
          LoadCredential = ["access_token:${accessToken}"];
          ExecStart = populateScript;
        };
      };
    };
  };
}
