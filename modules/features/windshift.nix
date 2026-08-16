# Windshift module — quadlet units + secretspec/BWS secret population.
#
# REAL quadlet user units (rootless, ~/.config/containers/systemd/), a
# tailscale sidecar for funnel-only ingress, and secretspec/BWS for secrets
# (resolved from the shared repo-root secretspec.toml, windshift scope).
_: {
  my.modules.nixos.windshift = {
    lib,
    pkgs,
    config,
    ...
  }: let
    podmanUser = config.my.baseUsername;
    userHome = config.users.users.${podmanUser}.home;
    quadletDir = "${userHome}/.config/containers/systemd";
    composeDir = ../../compose/windshift;
    secretspecToml = config.my.secretspecManifest;
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
      exec ${pkgs.secretspec}/bin/secretspec run -P production -S windshift -- \
        ${pkgs.bash}/bin/bash ${composeDir}/populate-secrets.sh
    '';
    # Quadlet user units generated from compose/windshift/*.container — kept
    # in sync with the tmpfiles rules below via readDir, so the reload script
    # can't drift from the actual quadlet files.
    containerServices = lib.pipe composeDir [
      builtins.readDir
      lib.attrNames
      (lib.filter (f: lib.hasSuffix ".container" f))
      (map (f: lib.removeSuffix ".container" f + ".service"))
    ];
    # Regenerate the rootless quadlet units and apply them to the running
    # containers. Runs from a system service as the podman user; the user
    # manager must be reachable first (linger is enabled in base.nix, but at
    # boot it may still be starting).
    reloadScript = pkgs.writeShellScript "windshift-quadlet-reload" ''
      set -euo pipefail
      export XDG_RUNTIME_DIR="/run/user/$(id -u)"
      for _ in $(seq 1 30); do
        if systemctl --user show-environment >/dev/null 2>&1; then
          break
        fi
        sleep 1
      done
      # Re-run the podman-system-generator against the (re)swapped tmpfiles
      # symlinks, then restart the container units so new/changed definitions
      # (env, args, image) actually take effect.
      systemctl --user daemon-reload
      systemctl --user restart ${lib.concatStringsSep " " containerServices}
    '';
  in {
    config = lib.mkIf config.my.windshift {
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
        wantedBy = ["multi-user.target"];
        # Belt-and-suspenders: quadlet containers also Restart=always, so
        # they retry until the secrets exist even if ordering ever slips.
        before = ["user@.service"];
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
            "access_token:${config.my.bwsAccessTokenFile}"
          ];
          ExecStart = populateScript;
        };
      };

      # Regenerate the quadlet user units after every switch that changes the
      # compose files, and start/restart the affected containers.
      #
      # Why this exists: NixOS's own switch flow reloads user instances
      # (`systemctl --user daemon-reload`) BEFORE re-running tmpfiles
      # (sysinit-reactivation.target -> systemd-tmpfiles-resetup swaps the
      # symlinks), so the quadlet generator always sees the OLD symlinks and
      # nothing re-runs it afterwards. This unit rides the same native
      # mechanism NixOS uses for systemd-tmpfiles-resetup: restartTriggers
      # makes it a 'changed' unit on every switch where the compose files
      # changed, and the sysinit-reactivation ordering runs it AFTER the
      # symlink swap. wantedBy covers the boot path (containers also start
      # here, since quadlet units have no [Install] section and would
      # otherwise never start at boot).
      systemd.services.windshift-quadlet-reload = {
        description = "Regenerate Windshift quadlet user units and restart containers";
        wantedBy = ["multi-user.target"];
        requiredBy = ["sysinit-reactivation.target"];
        after = [
          "windshift-secrets-populate.service"
          "systemd-tmpfiles-setup.service"
          "systemd-tmpfiles-resetup.service"
        ];
        before = ["sysinit-reactivation.target"];
        # Same trigger semantics as systemd-tmpfiles-resetup: fires exactly
        # when the compose dir (referenced by the tmpfiles rules) changes.
        restartTriggers = [composeDir];
        unitConfig.DefaultDependencies = false;
        path = [
          pkgs.systemd
          pkgs.coreutils
        ];
        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
          User = podmanUser;
          Group = podmanUser;
          ExecStart = reloadScript;
        };
      };
    };
  };
}
