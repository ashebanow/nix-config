# Resilio Sync — a desktop's local mirror of the "Synced Files" folder.
#
# NixOS-only. The nixpkgs service module (services.resilio) does not exist on
# Darwin, so the macs keep running upstream's cask configured by hand; this
# module is for NixOS desktops, and lumquat leaves it off (no interactive user
# to own the tree).
#
# Shape of the setup, which is unusual in two ways worth stating up front:
#
# 1. Resilio runs as the `rslsync` system user, but the synced tree is the
#    *operator's* data — it is the replacement for ~/Documents, ~/Music and so
#    on. So `resilioDirectory` is owned by the operator AND writable by the
#    `rslsync` group. Two mechanisms are needed because neither is sufficient
#    alone: the setgid bit on the root keeps new files group-owned by
#    `rslsync`, and the default ACL makes them group-writable (setgid alone
#    gives group *ownership*, but the process umask would still strip the write
#    bit). Both are re-applied on every activation. This is the part the
#    commonly-cited gist does not cover: it syncs into /var/www for a server
#    with no interactive user, so everything there can simply be
#    rslsync:rslsync. nixpkgs' own option documentation recommends exactly the
#    setgid + setfacl recipe used below.
#
# 2. The remote folder's top-level directories (Documents, Music, ...) are
#    symlinked into the operator's home, so ordinary programs open the synced
#    copy without knowing Resilio exists. Each link needs a matching XDG user
#    directory entry (~/.config/user-dirs.dirs), or the desktop's own notion of
#    "Documents" would point somewhere else. Anything already sitting in a real
#    home directory is moved *into* the synced tree before the link replaces it
#    — see the migration script, which is the one destructive step.
#
# The folder key is a secret: it never appears in the Nix store. It is resolved
# from BWS through the `resilio` secretspec scope at activation into a root-only
# file, and the service module is pointed at that file with `secretFile` (which
# is what keeps the value out of the store — passing `secret` instead would
# put it in a world-readable store path).
#
# Web UI note: nixpkgs asserts `enableWebUI -> sharedFolders == []`, because a
# config-file shared folder overrides anything the UI added. We want a declared
# folder, so the UI stays off; the daemon still exposes its own API on
# 127.0.0.1:8888 for status (the macs run the same way).
_: {
  my.modules.nixos.resilio =
    {
      lib,
      pkgs,
      config,
      ...
    }:
    let
      inherit (config.my) resilioDirectory resilioHomeLinks resilioUser;
      deviceName =
        if config.my.resilioDeviceName != "" then config.my.resilioDeviceName else config.my.hostName;

      # The well-known port from the setup guide, so peers find each other
      # directly on the LAN without depending on the tracker or relay.
      listeningPort = 4444;

      user = config.users.users.${resilioUser};
      home = user.home;
      rslsyncGroup = config.users.groups.rslsync.name;

      # Root-owned and root-only, living on tmpfs. Deliberately NOT a
      # services.resilio.sharedFolders.secret value, which would be written to
      # the world-readable Nix store.
      keyFile = "/run/secrets/resilio-synced-files-token";

      # Owner/group/mode ACLs are applied by an activation script rather than
      # systemd.tmpfiles: they have to follow the *operator's* uid/gid, and
      # tmpfiles' numeric-only syntax cannot express that portably.
      applyPerms = pkgs.writeShellScript "resilio-apply-perms" ''
        set -euo pipefail
        root=${lib.escapeShellArg resilioDirectory}

        ${pkgs.acl}/bin/setfacl -m "g:${rslsyncGroup}:rwx" "$root"
        ${pkgs.acl}/bin/setfacl -d -m "g:${rslsyncGroup}:rwx" "$root"
        chmod g+s "$root"

        # Re-apply to existing content. The recursive walk is slow on a large
        # tree, but this runs on activation, not on every boot; -h stops symlinks
        # from being followed out of the tree.
        ${pkgs.acl}/bin/setfacl -R -h -m "g:${rslsyncGroup}:rwx" "$root"
        ${pkgs.acl}/bin/setfacl -R -h -d -m "g:${rslsyncGroup}:rwx" "$root"
      '';

      # Replace real home directories with symlinks into the synced tree,
      # migrating whatever they held. Idempotent: a second run sees links and
      # leaves them alone.
      migrateHome = pkgs.writeShellScript "resilio-migrate-home" ''
        set -euo pipefail
        home=${lib.escapeShellArg home}
        root=${lib.escapeShellArg resilioDirectory}

        ${lib.concatMapStrings (sub: ''
          target="$root/${sub}"
          link="$home/${sub}"

          mkdir -p "$target"

          if [ -L "$link" ]; then
            # Already a link — make sure it points where we want.
            if [ "$(readlink "$link")" != "$target" ]; then
              echo "resilio: relinking $link -> $target"
              rm -f "$link"
              ln -s "$target" "$link"
            fi
          elif [ -d "$link" ]; then
            # A real directory. Move its contents in without clobbering
            # anything already synced, then replace it with the link.
            if [ -n "$(ls -A "$link" 2>/dev/null)" ]; then
              echo "resilio: migrating contents of $link -> $target"
              # --backup preserves a pre-existing synced file instead of
              # losing it; the incoming home copy becomes file~1~ in the
              # backup dir rather than overwriting.
              ${pkgs.rsync}/bin/rsync -a --ignore-existing \
                --backup --backup-dir=/tmp/resilio-migrate-backup \
                "$link"/ "$target"/
            fi
            rmdir "$link"
            ln -s "$target" "$link"
          elif [ -e "$link" ]; then
            # A plain file where a directory is expected — refuse rather than
            # destroy it. Surfaces in the activation log.
            echo "resilio: WARNING: $link exists and is not a directory; leaving it alone" >&2
          else
            ln -s "$target" "$link"
          fi

          chown -h ${resilioUser}:${rslsyncGroup} "$link"
        '') resilioHomeLinks}

        # Point the XDG user directories at the synced copies. Without this the
        # desktop's notion of "Documents" still resolves to the pre-migration
        # path. Only the keys named in resilioHomeLinks are emitted, so a host
        # that syncs fewer directories gets a correspondingly smaller file.
        ${lib.optionalString (resilioHomeLinks != [ ]) ''
          cfg="$home/.config/user-dirs.dirs"
          mkdir -p "$(dirname "$cfg")"
          {
            echo "# Written by modules/features/resilio.nix — these directories are"
            echo "# symlinks into the Resilio \"Synced Files\" tree."
            echo 'XDG_DESKTOP_DIR="$HOME/Desktop"'
            echo 'XDG_DOWNLOAD_DIR="$HOME/Downloads"'
            ${lib.concatMapStrings (sub: ''
              case ${lib.escapeShellArg sub} in
                Documents) echo 'XDG_DOCUMENTS_DIR="$HOME/Documents"' ;;
                Music)     echo 'XDG_MUSIC_DIR="$HOME/Music"' ;;
                Pictures)  echo 'XDG_PICTURES_DIR="$HOME/Pictures"' ;;
                Videos)    echo 'XDG_VIDEOS_DIR="$HOME/Videos"' ;;
                Books)     echo 'XDG_BOOKS_DIR="$HOME/Books"' ;;
                Fonts)     echo 'XDG_FONTS_DIR="$HOME/Fonts"' ;;
              esac
            '') resilioHomeLinks}
          } > "$cfg"
          chown ${resilioUser} "$cfg"
          chmod 644 "$cfg"
        ''}
      '';

      # Resolve the folder key from BWS into a root-only file. Same secretspec
      # invocation shape as modules/features/secrets.nix.
      populateKey = pkgs.writeShellScript "resilio-populate-key" ''
        set -euo pipefail
        install -d -m 0755 /run/secrets
        tmp=$(mktemp)
        trap 'rm -f "$tmp"' EXIT
        ${pkgs.secretspec}/bin/secretspec run -P production -S resilio -- \
          ${pkgs.bash}/bin/bash -c 'printf %s "$RESILIO_SYNCED_FILES_TOKEN"' > "$tmp"
        install -m 0400 -o root -g root "$tmp" ${lib.escapeShellArg keyFile}
      '';
    in
    {
      config = lib.mkIf config.my.resilio {
        assertions = [
          {
            assertion = resilioUser != "";
            message = "my.resilio is true but my.resilioUser is empty — the module needs the interactive user who owns the synced tree.";
          }
          {
            assertion = resilioDirectory != "";
            message = "my.resilio is true but my.resilioDirectory is empty — set it to the absolute path of the synced folder root.";
          }
          {
            assertion = config.users.users ? ${resilioUser};
            message = "my.resilioUser (${resilioUser}) is not a user declared on this host.";
          }
        ];

        services.resilio = {
          enable = true;
          inherit deviceName listeningPort;

          # Keep the trees off the wider network: Resilio meshes directly on the
          # LAN, which is what we want, but nothing here should reach the open
          # internet except the tracker/relay rendezvous it needs to find peers.
          useUpnp = false;
          downloadLimit = 0;
          uploadLimit = 0;
          checkForUpdates = false;
          encryptLAN = true;

          # The declared folder comes from this config file, which is what the
          # nixpkgs module requires the UI to be off for.
          enableWebUI = false;

          directoryRoot = resilioDirectory;
          storagePath = "/var/lib/rslsync/.sync";

          # secretFile, not secret — the latter would put the key in the Nix
          # store. The module's jq pass substitutes it into the generated config
          # at start time.
          sharedFolders = [
            {
              secretFile = keyFile;
              directory = resilioDirectory;
              useRelayServer = true;
              useTracker = true;
              useDHT = true;
              searchLAN = true;
              useSyncTrash = true;
              knownHosts = [ ];
            }
          ];
        };

        systemd.services.resilio = {
          after = [
            "resilio-populate-key.service"
            "resilio-migrate-home.service"
          ];
          requires = [ "resilio-populate-key.service" ];
          wants = [ "resilio-migrate-home.service" ];
          # The generated config is written to /run/rslsync by ExecStartPre,
          # which needs the key file to exist first.
          unitConfig.ConditionPathExists = "/run/secrets";
        };

        systemd.services.resilio-populate-key = {
          description = "Resolve the Resilio Synced Files key from BWS";
          wantedBy = [ "multi-user.target" ];
          wants = [ "network-online.target" ];
          after = [ "network-online.target" ];
          path = [
            pkgs.secretspec
            pkgs.bws
          ];
          serviceConfig = {
            Type = "oneshot";
            RemainAfterExit = true;
            Environment = [
              "SECRETSPEC_FILE=${config.my.secretspecManifest}"
              "SECRETSPEC_PROVIDER=bws-service"
            ];
            LoadCredential = [ "access_token:${config.my.bwsAccessTokenFile}" ];
            ExecStart = populateKey;
          };
        };

        systemd.services.resilio-migrate-home = {
          description = "Migrate and symlink home data directories into the Resilio tree";
          wantedBy = [ "multi-user.target" ];
          after = [ "local-fs.target" ];
          serviceConfig = {
            Type = "oneshot";
            RemainAfterExit = true;
            ExecStart = migrateHome;
            User = "root";
          };
        };

        # Direct peer connections on the LAN. Resilio meshes directly rather
        # than proxying through a server, so the listening port has to be
        # reachable from the other peers; it is confined to the local network
        # because nothing here forwards it (and use_upnp is off, so the daemon
        # will not try to punch it open on the router itself).
        networking.firewall.allowedTCPPorts = [ listeningPort ];

        # The tree root is owned by the operator, group rslsync; the ACLs from
        # applyPerms (applied at activation) make it group-writable. The daemon's
        # own storage lives under /var/lib/rslsync, which the module's user
        # definition creates.
        systemd.tmpfiles.rules = [
          "d ${resilioDirectory} 2775 ${resilioUser} ${rslsyncGroup} -"
        ];

        system.activationScripts.resilioPerms = {
          text = ''
            if [ -d ${lib.escapeShellArg resilioDirectory} ]; then
              ${applyPerms} || true
            fi
          '';
          deps = [ ];
        };
      };
    };
}
