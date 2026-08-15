# Windshift module — quadlet units + secretspec/BWS secret population.
#
# Mirrors modules/features/kaneo.nix: REAL quadlet user units (rootless,
# ~/.config/containers/systemd/), a tailscale sidecar for funnel-only ingress,
# and secretspec/BWS for secrets (sops-nix only as the bootstrap-token
# transport, same transitional story as kaneo).
_: {
  my.modules.nixos.windshift =
    {
      lib,
      pkgs,
      config,
      ...
    }:
    let
      podmanUser = config.my.baseUsername;
      userHome = config.users.users.${podmanUser}.home;
      quadletDir = "${userHome}/.config/containers/systemd";
      composeDir = ../../compose/windshift;
      secretspecToml = "/etc/windshift/secretspec.toml";
      # podman 5.8 quadlet emits a dangling `windshift.network.service`
      # dependency (file name + .service) alongside the real
      # `windshift-network.service` unit. Shim so both resolve to the same
      # network creation unit.
      networkShim = pkgs.writeText "windshift.network.service" ''
        [Unit]
        Description=Windshift podman network (shim for podman quadlet naming)
        Requires=windshift-network.service
        After=windshift-network.service

        [Service]
        Type=oneshot
        RemainAfterExit=yes
        ExecStart=${pkgs.coreutils}/bin/true
      '';
      populateScript = pkgs.writeShellScript "windshift-populate-secrets" ''
        export XDG_RUNTIME_DIR="/run/user/$(id -u)"
        exec ${pkgs.secretspec}/bin/secretspec run -P production -- \
          ${pkgs.bash}/bin/bash ${composeDir}/populate-secrets.sh
      '';
    in
    {
      config = lib.mkIf config.my.windshift {
        # sops-nix secrets: BWS bootstrap token only (same declaration as the
        # kaneo module — identical values merge cleanly).
        sops.secrets = {
          "bws-access-token" = {
            mode = "0600";
            owner = "root";
          };
        };

        # Install the quadlet units + config into the rootless user's quadlet
        # dir via store symlinks (quadlet supports symlinked search paths).
        # tmpfiles-setup runs before multi-user.target, so the symlinks exist
        # before the linger-started user manager generates the units.
        systemd.tmpfiles.rules = [
          "d ${quadletDir} 0755 ${podmanUser} ${podmanUser} -"
          "L+ ${quadletDir}/windshift.network - - - - ${composeDir}/windshift.network"
          "L+ ${quadletDir}/windshift-pgdata.volume - - - - ${composeDir}/windshift-pgdata.volume"
          "L+ ${quadletDir}/windshift-ts-state.volume - - - - ${composeDir}/windshift-ts-state.volume"
          "L+ ${quadletDir}/windshift-data.volume - - - - ${composeDir}/windshift-data.volume"
          "L+ ${quadletDir}/windshift-tailscale.container - - - - ${composeDir}/windshift-tailscale.container"
          "L+ ${quadletDir}/windshift-db.container - - - - ${composeDir}/windshift-db.container"
          "L+ ${quadletDir}/windshift.container - - - - ${composeDir}/windshift.container"
          # Shim unit: resolves the quadlet-generated `windshift.network.service` dep.
          "L+ ${userHome}/.config/systemd/user/windshift.network.service - - - - ${networkShim}"
          "d /etc/windshift 0755 root root -"
          "L+ /etc/windshift/secretspec.toml - - - - ${composeDir}/secretspec.toml"
          # TS_SERVE_CONFIG: symlink the containing DIRECTORY, not the file —
          # required for config-update detection when the symlink is swapped.
          "L+ /etc/windshift/tailscale-serve - - - - ${composeDir}/ts-serve"
        ];

        # Populate podman secrets BEFORE the rootless user manager starts the
        # quadlet units. Env vars exist only inside this short-lived process;
        # nothing is written as a .env. Not a timer: --replace only affects
        # newly created containers, so a timer yields drift, not rotation.
        systemd.services.windshift-secrets-populate = {
          description = "Populate Windshift podman secrets from BWS via secretspec";
          wantedBy = [ "multi-user.target" ];
          # Belt-and-suspenders: quadlet containers also Restart=always, so
          # they retry until the secrets exist even if ordering ever slips.
          before = [ "user@.service" ];
          path = [
            pkgs.podman
            pkgs.secretspec
            pkgs.bws # secretspec 0.17+ invokes the official bws CLI
          ];
          serviceConfig = {
            Type = "oneshot";
            User = podmanUser;
            Group = podmanUser;
            Environment = [
              "SECRETSPEC_PROFILE=production"
              "SECRETSPEC_PROVIDER=bws-service"
              "SECRETSPEC_FILE=${secretspecToml}"
            ];
            # access_token is the SEMANTIC credential name the bws-service
            # alias looks up in systemd-credential:// (see secretspec.toml).
            LoadCredential = [
              "access_token:${config.sops.secrets."bws-access-token".path}"
            ];
            ExecStart = populateScript;
          };
        };
      };
    };
}
