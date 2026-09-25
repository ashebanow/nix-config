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
# The owner license is required before the daemon will connect to anything.
# Without one it adds a shared folder in the *stopped* state and never attempts
# a peer connection: it binds its listen sockets, walks the tree, and looks
# entirely healthy, so the symptom is indistinguishable from a firewall, DNS or
# routing fault. It is applied with the rslsync `--license` flag, because the
# Web UI's licensing page cannot install the file (its picker opens on a fixed,
# non-navigable directory) and because a flag is reproducible from a module
# where a GUI click is not. An identity must exist first -- `--license` fails
# with SE_SM_NO_IDENTITY otherwise -- so applyLicense creates one if absent.
#
# The Web UI is enabled and the shared folder is NOT declared here; Resilio
# makes those mutually exclusive, and a config-declared folder cannot be put
# into the connecting state (see the service block below for the full account).
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

      # The well-known port from the setup guide. Pinned rather than left at
      # the default 0 (random) because a stable port is what makes the peer's
      # address expressible at all: `known_hosts` entries are `host:port` and
      # the port is dialed verbatim, so a peer on a random port has no address
      # anyone can hard-code. The macs currently run on random ports, which is
      # why LAN/tracker discovery is the only path between them today.
      listeningPort = 4444;

      user = config.users.users.${resilioUser};
      home = user.home;
      rslsyncGroup = config.users.groups.rslsync.name;

      # Root-owned and root-only, living on tmpfs. Deliberately NOT a
      # services.resilio.sharedFolders.secret value, which would be written to
      # the world-readable Nix store.
      keyFile = "/run/secrets/resilio-synced-files-token";

      # The owner license, resolved the same way and staged next to the key.
      # rslsync reads it from a path we control (--license), so it never needs
      # to live under storagePath where a wiped store would lose it.
      licenseFile = "/run/secrets/resilio-license-key";

      # Directories the daemon must be able to *traverse* to reach the synced
      # tree. Path resolution walks one component at a time, so a mode-0700
      # ancestor stops it long before it reaches the tree — and the ancestor in
      # question here is the operator's home itself, which is exactly 0700.
      #
      # Returns `from` and every directory between it and `to`, excluding `to`
      # (the caller grants the tree root rwx separately). So for
      # /home/ashebanow -> /home/ashebanow/Synced Files it returns
      # ["/home/ashebanow"].
      treeAncestors =
        from: to:
        let
          rel = lib.removePrefix (from + "/") to;
          # The leaf is the tree root itself and is handled by the caller.
          parts = lib.init (lib.splitString "/" rel);
          n = builtins.length parts;
        in
        [ from ] ++ lib.genList (i: from + "/" + lib.concatStringsSep "/" (lib.take (i + 1) parts)) n;

      # Owner/group/mode ACLs are applied by an activation script rather than
      # systemd.tmpfiles: they have to follow the *operator's* uid/gid, and
      # tmpfiles' numeric-only syntax cannot express that portably.
      applyPerms = pkgs.writeShellScript "resilio-apply-perms" ''
        set -euo pipefail
        root=${lib.escapeShellArg resilioDirectory}

        # The daemon runs as `rslsync` but the tree lives under the operator's
        # home, which is mode 0700 — so rslsync cannot even *traverse* into it,
        # and the daemon dies on startup (SIGSEGV on an internal assertion
        # about the path, with no mention of permissions). Grant traverse-only
        # on each ancestor between $HOME and the tree root rather than loosening
        # the home's mode or adding rslsync to the operator's primary group:
        # `rx`, not `x`. Traverse-only is enough for the daemon to follow a
        # path to the tree, but not for the Web UI: its folder picker calls
        # getdir(dir) to *enumerate* a directory, and that needs read. Without
        # it the call returns `{"folders":[]}` -- an empty listing rather than
        # an error -- so the picker renders a directory with nothing in it and
        # no way to navigate, which reads as a broken dialog. Observed directly:
        # `getdir /home/ashebanow/Synced Files` returned an empty list while the
        # home had only `x`, and listed its contents immediately once `r` was
        # added.
        ${lib.concatMapStrings (dir: ''
          if [ -d ${lib.escapeShellArg dir} ]; then
            ${pkgs.acl}/bin/setfacl -m "g:${rslsyncGroup}:rx" ${lib.escapeShellArg dir}
          fi
        '') (treeAncestors home resilioDirectory)}

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
      #
      # Ownership is established here rather than by systemd.tmpfiles alone.
      # A tmpfiles `d` line applies its mode/owner only when it *creates* the
      # directory, so if anything else got there first — as the `mkdir -p`
      # below did on the first run — the rule silently becomes a no-op and the
      # root stays root:root. `install -d` here is therefore authoritative and
      # re-applied every run, and tmpfiles keeps the same values for the case
      # where this script is not reached.
      migrateHome = pkgs.writeShellScript "resilio-migrate-home" ''
        set -euo pipefail
        home=${lib.escapeShellArg home}
        root=${lib.escapeShellArg resilioDirectory}

        install -d -m 2775 -o ${resilioUser} -g ${rslsyncGroup} "$root"

        # Only create a subdirectory when there is something to put in it.
        #
        # Resilio adopts a share by inspecting the directory, and refuses one
        # that already has contents with error 105, "Destination folder is not
        # empty. Add anyway?" — which needs an interactive confirmation we
        # cannot give from a unit. Pre-creating all nine destinations as empty
        # directories was enough to trigger it and left the folder unadded.
        #
        # The daemon creates any destination it needs during its first sync, so
        # the only case that requires us to make one up front is a real home
        # directory whose contents we are migrating into it.
        ${lib.concatMapStrings (sub: ''
          target="$root/${sub}"
          link="$home/${sub}"

          if [ -L "$link" ]; then
            # Already a link — make sure it points where we want. The target
            # is created only if the link's destination is missing, so a
            # synced-but-empty directory is not resurrected as ours.
            if [ "$(readlink "$link")" != "$target" ]; then
              echo "resilio: relinking $link -> $target"
              rm -f "$link"
              install -d -m 2775 -o ${resilioUser} -g ${rslsyncGroup} "$target"
              ln -s "$target" "$link"
            fi
          elif [ -d "$link" ]; then
            # A real directory. Move its contents in without clobbering
            # anything already synced, then replace it with the link.
            if [ -n "$(ls -A "$link" 2>/dev/null)" ]; then
              echo "resilio: migrating contents of $link -> $target"
              install -d -m 2775 -o ${resilioUser} -g ${rslsyncGroup} "$target"
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
            # Nothing there yet. Link without creating the target: the daemon
            # will build it from the share, and creating it ourselves would
            # be the non-empty condition above.
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
        # Group-readable by rslsync, NOT root-only. nixpkgs' create-resilio-config
        # runs as ExecStartPre in a unit with User=rslsync, so it reads the
        # secret file as the unprivileged service user. A 0400 root:root file
        # makes its `cat` fail with EACCES, and — because the generated config
        # is built with a shell loop rather than set -e — the failure was silent:
        # the daemon started happily with "secret": "" and simply never synced.
        # 0440 root:rslsync keeps the value off every other account while letting
        # the one consumer read it.
        install -m 0440 -o root -g ${rslsyncGroup} "$tmp" ${lib.escapeShellArg keyFile}

        # The license, same treatment. It is consumed by the `--license` flag
        # below rather than by the generated config. Unlike the key it is NOT
        # secret-on-the-wire (it is signed, not an access credential), but it
        # carries the licensee's name, so it stays off world-readable paths.
        ${pkgs.secretspec}/bin/secretspec run -P production -S resilio -- \
          ${pkgs.bash}/bin/bash -c 'printf %s "$RESILIO_LICENSE_KEY"' > "$tmp"
        install -m 0440 -o root -g ${rslsyncGroup} "$tmp" ${lib.escapeShellArg licenseFile}
      '';

      # Apply the owner license. This has to run before the daemon starts, and
      # it has to run as the daemon's own user against the daemon's own storage,
      # because the license is written into storagePath/License/.
      #
      # Why this exists at all: without a license the daemon adds a shared folder
      # in the *stopped* state and then never attempts a peer connection. It
      # binds its listen sockets, scans the tree and looks entirely healthy —
      # which is indistinguishable from a firewall or DNS problem, and is what
      # made this opaque for so long. Installing the license flips
      # `stopped: 1 -> 0` and peer connections begin immediately.
      #
      # The Web UI would normally do this, but its licensing page cannot install
      # the file (the picker's directory is not editable and cannot navigate), so
      # the CLI flag is the only workable route -- and it is the reproducible one.
      applyLicense = pkgs.writeShellScript "resilio-apply-license" ''
        set -euo pipefail
        # Already installed: nothing to do. `--license` writes storagePath/License
        # once, so this keeps a reboot from rewriting it.
        if [ -e /var/lib/rslsync/.sync/License ]; then
          echo "resilio: license already installed"
          exit 0
        fi

        # An identity has to exist before a license can be attached to it.
        # `--license` on a bare storage fails with `SE_SM_NO_IDENTITY` -- and,
        # like the pid-file refusal below, still exits 0 while printing nothing
        # useful, so the failure is invisible unless the output is inspected.
        # Observed directly: identical command, identical file, succeeded once
        # an identity existed and installed nothing before that.
        if [ ! -e /var/lib/rslsync/.sync/.SyncUser* ]; then
          echo "resilio: creating storage identity"
          ${pkgs.resilio-sync}/bin/rslsync \
            --identity ${lib.escapeShellArg deviceName} \
            --storage /var/lib/rslsync/.sync >/dev/null 2>&1 || true
        fi

        # `--license` refuses to run while a daemon holds the pid file, and --
        # this is the part that hides the problem -- it still exits 0 when it
        # bails out that way, printing only "Can't lock pid file" on stdout. A
        # script that trusted the exit status reported success while installing
        # nothing. So capture the output and treat the refusal as fatal here,
        # where systemd will surface it instead of letting the daemon start
        # unlicensed and silently refuse to connect to any peer.
        if ! out=$(${pkgs.resilio-sync}/bin/rslsync \
                  --license ${lib.escapeShellArg licenseFile} \
                  --storage /var/lib/rslsync/.sync 2>&1); then
          echo "resilio: license install failed: $out" >&2
          exit 1
        fi
        case "$out" in
          *"already running"*)
            echo "resilio: refusing to run --license while a daemon holds the pid file" >&2
            exit 1
            ;;
          *"NO_IDENTITY"*)
            echo "resilio: identity was not created; cannot attach the license" >&2
            exit 1
            ;;
        esac

        # Verify rather than trusting the exit status, for the same reason.
        if [ ! -e /var/lib/rslsync/.sync/License ]; then
          echo "resilio: --license exited 0 but installed nothing (output: $out)" >&2
          exit 1
        fi
        echo "resilio: license applied"
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
          {
            # The folder is managed through the Web UI, so known hosts are set
            # there too and this option has no effect. Failing loudly rather
            # than letting a host set a value that silently does nothing.
            assertion = config.my.resilioKnownHosts == [ ];
            message = ''
              my.resilioKnownHosts is set but has no effect: the shared folder is
              no longer declared in the generated config (Resilio will not bind
              its Web UI while one is), so known hosts are configured in the UI
              at http://127.0.0.1:8888 instead. Remove the option from this host.
            '';
          }
        ];

        services.resilio = {
          enable = true;
          inherit deviceName listeningPort;

          # Keep the trees off the wider network: Resilio meshes directly on the
          # LAN, which is what we want, but nothing here should reach the open
          # internet except the tracker/relay rendezvous it needs to find peers.
          # Those are live and reachable (see docs/research/resilio-sync-nixos.md):
          # trackers on :4000, relays on :3000/:3001, all reachable over IPv4.
          useUpnp = false;
          downloadLimit = 0;
          uploadLimit = 0;
          checkForUpdates = false;
          encryptLAN = true;

          # The Web UI is ENABLED, and the shared folder is deliberately NOT
          # declared here. Resilio makes the two mutually exclusive: a
          # config-file folder list disables the UI (upstream's sample config:
          # "if you set shared folders in config file WebUI will be DISABLED"),
          # which nixpkgs encodes as `enableWebUI -> sharedFolders == []`. It is
          # literal -- with a folder declared, a `webui` block is ignored and
          # nothing binds the port.
          #
          # The folder is therefore added once through the UI and lives in the
          # daemon's storage rather than in the Nix store. That costs us
          # declarativeness for the folder, its known_hosts and its initial sync
          # mode, and buys the one thing the config file provably cannot set: a
          # folder's connect state. Resilio keeps that as runtime state
          # (`stopped` in sync.dat) and overrides any `stopped`/`sync_level` given
          # in the folder block, so a config-declared folder lands `stopped: 1`
          # and the daemon never dials a peer. Verified on this host, and the
          # reason the declarative approach kept looking like a network fault.
          enableWebUI = true;

          # Explicit IPv4 loopback. The nixpkgs default is `[::1]`, and this host
          # has no usable IPv6 (`::1` is not even bindable: "Cannot assign
          # requested address"), so the default leaves the UI unreachable.
          httpListenAddr = "127.0.0.1";
          httpListenPort = 8888;

          # The UI's folder picker starts *at* directory_root and lists its
          # contents, so the root itself is never among the selectable entries.
          # Pointing this at the tree therefore makes the tree unpickable -- the
          # picker browses inside it and can only offer its children, which is
          # the "I can create subfolders but cannot choose the folder I want"
          # symptom. It has to be the tree's PARENT so the tree appears in the
          # listing. nixpkgs' option docs call this the "default directory to add
          # folders in", which is the same thing.
          directoryRoot = dirOf resilioDirectory;
          storagePath = "/var/lib/rslsync/.sync";

          # Nothing to declare: see above. The folder is added via the UI.
          sharedFolders = [ ];
        };

        systemd.services.resilio = {
          after = [
            "resilio-populate-secrets.service"
            "resilio-migrate-home.service"
            # The stock module only sets `after = [ "network.target" ]`, which
            # systemd reaches *before* interfaces, DHCP, and a usable resolver.
            # The daemon fetches its tracker/relay list from config.resilio.com
            # over HTTPS at startup, so starting that early can leave it with no
            # tracker list and a cached DNS failure — the failure mode is a
            # daemon that looks healthy, opens its listen sockets, and then
            # dials nothing. Same treatment modules/features/secrets.nix gives
            # host-secrets-populate.
            "network-online.target"
          ];
          wants = [
            "resilio-migrate-home.service"
            "network-online.target"
          ];
          requires = [ "resilio-populate-secrets.service" ];

          # The license has to be applied BEFORE the daemon starts, not merely
          # alongside it: `rslsync --license` refuses to touch the storage while
          # any daemon holds the pid file. As a separate unit that only `After=`
          # the daemon, systemd happily runs it *after* resilio has come up, and
          # the flag then no-ops. An ExecStartPre in this unit is serialised by
          # systemd against the start itself, which is the ordering that is
          # actually needed.
          #
          # Deliberately NOT `+`-prefixed. `+` runs it as root, and everything
          # rslsync writes into storagePath would then be root-owned -- the
          # daemon itself runs as the `rslsync` user and then cannot write its
          # own pid file ("Can't open pid file ... Permission denied"), which
          # fails the unit. It runs as the unit's User, which is the same user
          # that owns that tree.
          serviceConfig.ExecStartPre = [ "${applyLicense}" ];

          # The generated config is written to /run/rslsync by ExecStartPre,
          # which reads the secret files as the rslsync user — so the service
          # must not start until they exist with the right group and mode.
          unitConfig.ConditionPathExists = keyFile;
        };

        # Resolves the folder key and the license from BWS into /run/secrets.
        # The key has no consumer in the config any more (the folder is added
        # through the UI), but it is still staged: it is the value that has to be
        # pasted into the UI's "add folder" prompt, and having it in a known
        # root-owned file beats copying it out of Bitwarden by hand.
        systemd.services.resilio-populate-secrets = {
          description = "Resolve the Resilio folder key and license from BWS";
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

        # Direct peer connections. Resilio meshes peer-to-peer rather than
        # proxying through a server, so the listening port has to be reachable
        # from the other peers.
        #
        # BOTH protocols, and UDP is the one that matters. Resilio's peer
        # transport is uTP-over-UDP: a live peer listens on the same port in
        # both protocols (`TCP *:<port>` and `UDP *:<port>`), and the daemon's
        # outbound connections to other peers are UDP, not TCP. Opening only
        # TCP looks correct and does nothing, because no peer ever dials it.
        # The stock module opens no ports at all, so this is ours to get right.
        #
        # Confined to the LAN by omission: nothing here forwards either port,
        # and use_upnp is off, so the daemon will not punch a hole itself.
        networking.firewall.allowedTCPPorts = [ listeningPort ];
        networking.firewall.allowedUDPPorts = [ listeningPort ];

        # The tree root is owned by the operator, group rslsync; the ACLs from
        # applyPerms (applied at activation) make it group-writable. The daemon's
        # own storage lives under /var/lib/rslsync, which the module's user
        # definition creates.
        systemd.tmpfiles.rules = [
          "d ${resilioDirectory} 2775 ${resilioUser} ${rslsyncGroup} -"
          # storagePath is a *subdirectory* of the daemon's home, and Resilio
          # refuses to start when it is missing ("Storage path specified in
          # config file does not exist"), so it has to be created explicitly —
          # the module's `createHome` only makes the parent.
          "d /var/lib/rslsync/.sync 0700 rslsync rslsync -"
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
