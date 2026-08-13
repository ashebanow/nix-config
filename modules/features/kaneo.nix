# Kaneo module — quadlet units + secretspec/BWS secret population.
#
# Reference: llm.nix for the NixOS wiring pattern (sops secrets,
# LoadCredential, tmpfiles store symlinks). The container mechanism is REAL
# quadlet user units (rootless, ~/.config/containers/systemd/), NOT the
# podman-compose oneshots llm.nix uses.
#
# Rootless: quadlet units install to the podman user's quadlet dir; linger is
# already enabled for that user in base.nix. The tailscale sidecar stays on
# the default TS_USERSPACE so no /dev/net/tun or capabilities are needed.
#
# Secret bootstrap: sops-nix delivers the BWS access token via LoadCredential.
# secretspec reads it through the read-only systemd-credential:// provider
# (alias `bootstrap` in compose/kaneo/secretspec.toml) — secretspec never
# declares sops or age as a provider. The sidecar's tailscale auth key also
# comes from BWS (TS_AUTHKEY). sops-nix is the one deliberate remaining
# dependency; it will be removed once sops is retired (nix-config migration
# ticket).
_: {
  my.modules.nixos.kaneo =
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
      composeDir = ../../compose/kaneo;
      secretspecToml = "/etc/kaneo/secretspec.toml";
      populateScript = pkgs.writeShellScript "kaneo-populate-secrets" ''
        export XDG_RUNTIME_DIR="/run/user/$(id -u)"
        exec ${pkgs.secretspec}/bin/secretspec run -P production -- \
          ${pkgs.bash}/bin/bash ${composeDir}/populate-secrets.sh
      '';
    in
    {
      config = lib.mkIf config.my.kaneo {
        # sops-nix secrets: BWS bootstrap token only. The sidecar's tailscale
        # auth key comes from BWS via secretspec (TS_AUTHKEY in the production
        # profile), delivered as a podman secret by the populate script.
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
          "L+ ${quadletDir}/kaneo.network - - - - ${composeDir}/kaneo.network"
          "L+ ${quadletDir}/kaneo-pgdata.volume - - - - ${composeDir}/kaneo-pgdata.volume"
          "L+ ${quadletDir}/kaneo-ts-state.volume - - - - ${composeDir}/kaneo-ts-state.volume"
          "L+ ${quadletDir}/kaneo-tailscale.container - - - - ${composeDir}/kaneo-tailscale.container"
          "L+ ${quadletDir}/kaneo-db.container - - - - ${composeDir}/kaneo-db.container"
          "L+ ${quadletDir}/kaneo.container - - - - ${composeDir}/kaneo.container"
          "d /etc/kaneo 0755 root root -"
          "L+ /etc/kaneo/secretspec.toml - - - - ${composeDir}/secretspec.toml"
          # TS_SERVE_CONFIG: symlink the containing DIRECTORY, not the file —
          # required for config-update detection when the symlink is swapped.
          "L+ /etc/kaneo/tailscale-serve - - - - ${composeDir}/ts-serve"
        ];

        # Populate podman secrets BEFORE the rootless user manager starts the
        # quadlet units. Env vars exist only inside this short-lived process;
        # nothing is written as a .env. Not a timer: --replace only affects
        # newly created containers, so a timer yields drift, not rotation.
        systemd.services.kaneo-secrets-populate = {
          description = "Populate Kaneo podman secrets from BWS via secretspec";
          wantedBy = [ "multi-user.target" ];
          # Belt-and-suspenders: quadlet containers also Restart=always, so
          # they retry until the secrets exist even if ordering ever slips.
          before = [ "user@.service" ];
          path = [
            pkgs.podman
            pkgs.secretspec
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
