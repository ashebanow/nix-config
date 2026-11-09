# Shared options module providing config.my.* for host metadata.
# Following the dendritic pattern: capability flags defined centrally.
#
# `config` is in scope because the desktop-shell predicates are derived from
# `my.desktopShell` rather than set independently — see the shell option below.
{ lib, config, ... }: {
  options.my = {
    # Identity
    hostName = lib.mkOption {
      type = lib.types.str;
      description = "The hostname of the current system being configured.";
    };

    # Base feature
    base = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Enable base server configuration.";
    };
    baseUsername = lib.mkOption {
      type = lib.types.str;
      default = "podman";
      description = "Non-root user for container operations.";
    };
    baseUserFullName = lib.mkOption {
      type = lib.types.str;
      default = config.my.baseUsername;
      defaultText = lib.literalExpression "config.my.baseUsername";
      description = ''
        Display name (GECOS field) for the base user, shown by greeters on the
        login screen. Defaults to baseUsername, so the login screen shows the
        login name unless a real name is set.
      '';
    };
    baseTimezone = lib.mkOption {
      type = lib.types.str;
      default = "America/New_York";
      description = "System timezone.";
    };
    baseAllowSuspend = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Whether the host may suspend/hibernate. Defaults to false: a host that
        must be reachable over the network (a server, or a remote-accessed
        desktop) should not sleep out from under its clients. Turn it on for a
        desktop only once its resume path is known to bring networking back —
        e.g. after the r8169 workaround in hosts/yuzu/hardware-configuration.nix
        is verified on real hardware.
      '';
    };

    # LLM feature
    llm = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Enable LLM inference servers with GPU passthrough.";
    };
    llmModelStorage = lib.mkOption {
      type = lib.types.path;
      default = "/var/lib/llm-models";
      description = "Read-only mount path for model files in containers.";
    };
    llmServe = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Enable Tailscale Serve to publish LLM endpoints as paths on this node (not Tailscale Services — see TS-SERVE.MD).";
    };
    bifrostServe = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Enable the Bifrost LLM gateway compose stack, served at ai.<tailnet> via its own Tailscale sidecar node.";
    };

    # Access feature
    access = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Enable remote access via Tailscale.";
    };
    accessTailnetName = lib.mkOption {
      type = lib.types.str;
      default = "lumquat";
      description = "Hostname on the tailnet.";
    };
    accessEnableSSH = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Enable Tailscale SSH.";
    };
    accessEnableExitNode = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Act as a Tailscale exit node.";
    };
    accessEnableSubnetRouting = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Advertise local subnets via Tailscale subnet routes.";
    };
    accessSubnetRoutes = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = "CIDR ranges to advertise when accessEnableSubnetRouting is enabled (e.g. [ \"192.168.1.0/24\" ]).";
    };
    accessEnableFallbackSSH = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Enable SSH fallback on non-standard port when Tailscale is down.";
    };
    accessFallbackPort = lib.mkOption {
      type = lib.types.port;
      default = 2222;
      description = "Fallback SSH port.";
    };

    # Monitoring feature
    monitoring = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Enable Cockpit web UI for system monitoring.";
    };
    monitoringPort = lib.mkOption {
      type = lib.types.port;
      default = 9090;
      description = "Cockpit web interface port.";
    };

    # Printing feature (CUPS). The service is declarative; so are the queues:
    # nixpkgs has no option for a CUPS queue, so modules/features/printing.nix
    # renders my.printers into an lpadmin oneshot that re-creates them on every
    # boot.
    printing = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Enable CUPS printing with HP driver support.";
    };

    # Declarative CUPS queues. CUPS keeps its queues in /etc/cups/printers.conf,
    # which NixOS regenerates on every activation, so a queue added by hand
    # vanishes at the next rebuild. Each entry here is re-applied idempotently
    # by lpadmin at boot instead.
    printers = lib.mkOption {
      type = lib.types.listOf (
        lib.types.submodule {
          options = {
            name = lib.mkOption {
              type = lib.types.str;
              description = "CUPS queue name (as shown in print dialogs).";
            };
            uri = lib.mkOption {
              type = lib.types.str;
              description = ''
                Device URI. For an IPP Everywhere printer use
                ipp://<host-or-ip>/ipp/print; a literal IP is preferred because
                CUPS resolves <name>.local mDNS names unreliably.
              '';
            };
            description = lib.mkOption {
              type = lib.types.str;
              default = "";
              description = "Human-readable description shown in print dialogs.";
            };
            location = lib.mkOption {
              type = lib.types.str;
              default = "";
              description = "Free-form location string.";
            };
            isDefault = lib.mkOption {
              type = lib.types.bool;
              default = false;
              description = "Make this queue the system default destination.";
            };
            drivers = lib.mkOption {
              type = lib.types.listOf lib.types.str;
              default = [ "everywhere" ];
              description = ''
                PPD source passed to lpadmin -m. The default "everywhere"
                selects the driverless IPP Everywhere PPD and is correct for any
                printer advertising IPP Everywhere (HP LaserJet 2016+).
              '';
            };
          };
        }
      );
      default = [ ];
      description = "Declarative CUPS printer queues, re-applied at boot.";
    };

    # zmx feature
    zmx = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Enable zmx session persistence tool.";
    };

    # Rex — the terminal multiplexer, in three independent roles. A host picks
    # the ones it plays; they are separate flags because they are separate
    # layers, not three alternative setups (see modules/features/rex.nix):
    #
    #   my.rexClient      Home Manager. The `rex` command, the xterm-rex
    #                     terminfo entry and the ssh guard for one account.
    #   my.rexLoginServer NixOS. Root-run login server: one server per account,
    #                     caller identity taken from Tailscale.
    #   my.rexServer      NixOS. One shared server for this host's own use,
    #                     reachable from other tailnet machines.
    #
    # The login server and the shared server are mutually exclusive — both own
    # /run/rex and the Serve mapping.
    rexClient = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Install the Rex client for this account (programs.rex): the `rex`
        command, Rex's terminfo entry in ~/.terminfo, and its ssh guard.

        The whole story on macOS, where the Rex app runs the server itself.
      '';
    };
    rexLoginServer = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Run the Rex login server on this host (NixOS only).

        The login server maps Tailscale identities to local accounts and runs
        one Rex server per account, as that account. Nothing is exposed except
        the tailnet: the only listener is Tailscale Serve, so a user without
        Tailscale cannot reach the multiplexer at all.

        Mutually exclusive with `my.rexServer`. Configure `my.rexAccounts`.
      '';
    };
    rexServer = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Run one shared Rex server on this host as `my.rexServerUser`, reachable
        from other machines on the tailnet (NixOS only).

        This is the "my own machine, but I want to attach from elsewhere"
        server — a desktop or laptop that other devices connect into. Unlike the
        login server it knows nothing about caller identity, so it trusts the
        host's tailscaled (a `tailnet://` listener) rather than mapping callers
        to accounts, and it serves only the one account it runs as.

        Mutually exclusive with `my.rexLoginServer`. Members of the `rex` group
        can also connect locally over the Unix socket.
      '';
    };
    rexServerUser = lib.mkOption {
      type = lib.types.str;
      default = "";
      description = ''
        The account `my.rexServer` runs as, and whose sessions it serves. Must
        be an existing user; unlike the login server, the shared server has no
        accounts file and serves exactly this one account.
      '';
    };
    rexServerPort = lib.mkOption {
      type = lib.types.port;
      default = 7297;
      description = ''
        The tailnet port `my.rexServer` listens on (the `tailnet://` listener).
        Rex clients given only a hostname try 443 and then 7297, so leaving the
        default keeps `rex --server <host> ls` working without a port.
      '';
    };
    rexServerTailnetAddress = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      example = "100.127.173.24";
      description = ''
        The specific IPv4 tailnet address `my.rexServer` binds, for the
        `tailnet://` listener.

        This option exists because the obvious form, `tailnet://:<port>` (an
        empty host), **does not work on a host whose tailnet interface has no
        IPv6 address.** Rex reads the empty host as "bind every tailnet
        address" and expands it to both families. `tailscale0` here carries
        only an IPv4 address, so the IPv6 bind fails with "cannot assign
        requested address", `rex server run` exits 1, and systemd restarts it
        forever. The Rex module's own documentation uses the empty-host form,
        so this is a trap worth naming rather than a configuration mistake.

        Null leaves the listener off entirely: the server still runs and is
        reachable over its Unix socket, but nothing remote can reach it. That
        is a deliberate fail-safe rather than a silent guess at an address.

        Find the value with `tailscale ip -4`. It cannot be derived at build
        time (tailscaled must be up, and it is not during evaluation), so it is
        an explicit setting. It can change if the node is re-authenticated to
        the tailnet; if the server starts failing with "cannot assign
        requested address", re-run `tailscale ip -4` and update this.
      '';
    };
    rexAccounts = lib.mkOption {
      type = lib.types.attrsOf (lib.types.listOf lib.types.str);
      default = { };
      example = lib.literalExpression ''
        {
          # Local account name (must already exist) =
          #   Tailscale logins allowed to act as it.
          baseUsername = [ "tailscale:<login>@<domain>" ];
        }
      '';
      description = ''
        Accounts the Rex login server may reach, and the principal keys allowed
        to act as each: an attribute name is a local user, its value is the
        list of Tailscale logins (or tags, or other principal keys) that may
        use it.

        The accounts are the whole allowlist. A user who is not named here
        cannot reach the multiplexer, whatever group they are in. Nothing here
        creates a user account; declare `users.users.<name>` for that.

        Set in the host's configuration.nix — the NixOS scope owns the login
        server, and Home Manager never reads this option.
      '';
    };

    # Resilio Sync feature (NixOS desktops only).
    #
    # The nixpkgs service module is NixOS-only, so this flag is meaningless on
    # the Darwin hosts — the macs run Resilio from the upstream Homebrew cask
    # and configure it by hand. It is also not wanted on lumquat, which has no
    # interactive user account to own the synced tree (the daemon there would
    # run as `rslsync` with nobody to read the result).
    resilio = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Enable Resilio Sync for this desktop's Synced Files tree.";
    };
    resilioDeviceName = lib.mkOption {
      type = lib.types.str;
      default = "";
      description = ''
        Name other peers see for this node. Empty means use the hostname
        (my.hostName); the macs show up as `miracle_max`/`bergamot`, so a
        short, stable, distinctive name is worth setting explicitly.
      '';
    };
    resilioUser = lib.mkOption {
      type = lib.types.str;
      default = "";
      description = ''
        The interactive user who owns the synced tree. The NixOS service runs
        the daemon as the `rslsync` system user, so the shared folder has to be
        group-writable by that user while remaining the operator's own files —
        this is the user whose home holds the tree.
      '';
    };
    resilioDirectory = lib.mkOption {
      type = lib.types.str;
      default = "";
      description = ''
        Absolute path to the synced folder root (the local mirror of the
        remote "Synced Files" folder). Its subdirectories are symlinked into
        the owner's home by `resilioHomeLinks`.
      '';
    };
    resilioHomeLinks = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = ''
        Subdirectory names of `resilioDirectory` to symlink into the owner's
        home, replacing a same-named real directory. The remote folder's
        top-level layout is the source of truth (see modules/features/resilio.nix).
      '';
    };
    resilioKnownHosts = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      example = [ "10.40.60.74:4444" ];
      description = ''
        Peers to dial directly, as `host:port`, bypassing tracker, relay, DHT
        and LAN discovery entirely. Use literal LAN addresses: a name is
        resolved by the OS, and on a host whose name resolves to a Tailscale
        address this would hand Resilio an address it cannot use, since it does
        not traverse Tailscale.

        The port must be the peer's **fixed** listening port -- a peer left on
        the default random port has no stable address to name here, so pinning
        it on that peer is a prerequisite, not an optional tidy-up.

        UNUSED as of the move to UI-managed folders: the folder (and therefore
        its known-hosts list) is no longer declared in the generated config, so
        nothing reads this. Retained because it is the natural home for the
        value if the folder ever becomes declarative again; a host that sets it
        today would get no effect, which is a trap worth deleting rather than
        leaving, so it is kept only with this note attached.
      '';
    };

    # Memory feature (Mnemosyne)
    memory = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Enable Mnemosyne memory layer for AI agents.";
    };

    # Desktop workstation feature (NixOS hosts with a graphical session).
    # Distinct from `access`/`llm`: a desktop can also be an SSH target, but
    # this flag is what switches the host to workstation user defaults (zsh
    # login shell, NetworkManager group) and turns on a desktop environment.
    # It does NOT affect suspend — that is my.baseAllowSuspend, which is opt-in.
    desktop = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Enable desktop-workstation configuration (graphical session, desktop power/user defaults).";
    };
    desktopSessions = lib.mkOption {
      type = lib.types.listOf (
        lib.types.enum [
          "gnome"
          "niri"
        ]
      );
      default = [ ];
      description = ''
        The graphical sessions this host offers at the login screen, named by
        compositor or desktop environment. Distinct from the display manager
        (GDM for every desktop here) and from `desktopDefaultSession`: a host
        may offer several sessions and start one of them.

        Set in the host's capabilities.nix, not configuration.nix: the niri
        session is configured by a Home Manager module, and Home Manager
        evaluates its own `config.my` instance (see CONTEXT.md).
      '';
    };
    # Location for desktop-shell weather/widgets. Optional; a host that leaves
    # it null gets no weather configuration at all, and a shell that would
    # IP-geolocate will do so.
    #
    # Set in capabilities.nix, like `desktopShell`, because the consumers are
    # Home Manager modules and `my.baseTimezone` is NixOS-scope only.
    desktopShellLocation = lib.mkOption {
      type = lib.types.nullOr (
        lib.types.submodule {
          options = {
            city = lib.mkOption {
              type = lib.types.str;
              description = "City name shown by weather widgets.";
            };
            timezone = lib.mkOption {
              type = lib.types.str;
              description = "IANA timezone for the location.";
            };
            latitude = lib.mkOption {
              type = lib.types.float;
              description = "Latitude in decimal degrees.";
            };
            longitude = lib.mkOption {
              type = lib.types.float;
              description = "Longitude in decimal degrees.";
            };
          };
        }
      );
      default = null;
      description = ''
        Location used by desktop-shell weather widgets, and whatever else a
        shell wants to know where the machine is. Purely presentational: it is
        not the system timezone (`baseTimezone` is, and that is NixOS-scope).
      '';
    };
    desktopDefaultSession = lib.mkOption {
      type = lib.types.enum [
        "gnome"
        "niri"
      ];
      default = "gnome";
      description = ''
        The session the display manager starts when nobody chooses one. Must
        appear in `desktopSessions`; desktop.nix asserts that.
      '';
    };
    # ── Shell on top of the niri session ────────────────────────────────
    #
    # One master switch, not three booleans. `desktopShell` names the shell the
    # host installs and starts; each shell's module (dank-material-shell.nix,
    # noctalia.nix) enables itself when this equals its own
    # name, so the choice is exclusive by construction — two shells would both
    # claim org.freedesktop.Notifications and both draw a bar. See
    # docs/adr/0004.
    #
    # `null` means "no shell": the compositor runs bare. That is a real choice
    # (a niri-only debug session), so it is not an error.
    desktopShell = lib.mkOption {
      type = lib.types.nullOr (
        lib.types.enum [
          "dank"
          "noctalia"
        ]
      );
      default = null;
      example = "noctalia";
      description = ''
        The desktop shell drawn on top of the niri session: bar, launcher,
        notifications, clipboard, lock screen and OSD. A shell is not a
        session, so this is separate from `desktopSessions`.

        Exactly one shell may be selected. Each shell lives in its own module
        and installs the optional dependencies its own features need
        (screenshots, clipboard, media keys, brightness) with its
        upstream-recommended tools.

        Set in the host's capabilities.nix, not configuration.nix: the shells
        are configured by Home Manager modules, and Home Manager evaluates its
        own `config.my` instance (see CONTEXT.md).
      '';
    };
    # Convenience predicates for the shell modules. Derived, not settable: the
    # point of the master switch is that a host never sets these.
    desktopShellIsDankMaterialShell = lib.mkOption {
      type = lib.types.bool;
      readOnly = true;
      default = config.my.desktopShell == "dank";
      description = "Derived from `desktopShell`; do not set.";
    };
    desktopShellIsNoctalia = lib.mkOption {
      type = lib.types.bool;
      readOnly = true;
      default = config.my.desktopShell == "noctalia";
      description = "Derived from `desktopShell`; do not set.";
    };

    # Secrets (secretspec + BWS) — shared paths used by every secret consumer.
    secretspecManifest = lib.mkOption {
      type = lib.types.str;
      default = "/etc/secretspec.toml";
      description = "Absolute path to the shared secretspec.toml (symlinked from the repo root).";
    };
    bwsAccessTokenFile = lib.mkOption {
      type = lib.types.str;
      default = "/var/lib/secrets/bws-access-token";
      description = "Root-only BWS bootstrap access token file (provisioned out-of-band; never in the store or git).";
    };
    bwsBinDir = lib.mkOption {
      type = lib.types.str;
      default = "/run/current-system/sw/bin";
      description = ''
        Directory containing the `bws` CLI, prepended to the Home Manager
        activation's PATH. The chezmoi `gh` hosts.yml template resolves the
        GitHub token by invoking `bws secret get`, and the activation's PATH
        does not otherwise include the system profile (BOX-174).
      '';
    };

    # CLI tools feature (Home Manager)
    cliTools = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Enable modern CLI tools.";
    };

    # Topical CLI package modules (Home Manager, Darwin hosts).
    # Each is a curated package list gated by its own toggle — hosts
    # opt into the topics they want. No generic "extras" catch-all.
    cliSystemTools = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Enable system monitoring/diagnostics CLI tools (btop, htop, glances, ...).";
    };
    cliProductivityTools = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Enable everyday shell/productivity CLI tools (fzf, zoxide, starship, ...).";
    };
    cliVcsTools = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Enable git and git-adjacent CLI tools (gh, lazygit, git-lfs, ...).";
    };
    cliSecurityTools = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Enable secrets/crypto/vuln-scanning CLI tools (gitleaks, cosign, gnupg, ...).";
    };
    cliNetworkTools = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Enable networking/remote-access/download CLI tools (aria2, tailscale, caddy, ...).";
    };
    cliContainerTools = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Enable container/Docker ecosystem CLI tools (docker, colima, lazydocker, ...).";
    };
    cliMacOnlyTools = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Enable macOS-specific CLI tools (dockutil, xcodes, pinentry_mac).";
    };
    cliAiTools = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Enable AI-agent CLI tools (opencode, ...).";
    };
    cliBuildEssentials = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Enable global build toolchain needed to rebuild other packages from source (gcc, make, llvm, direnv, uv, nodejs). Most dev tooling stays devenv-only; this is the deliberate global exception.";
    };

    # GUI app modules (Home Manager, Darwin hosts). Priority order for
    # macOS apps is nix > Homebrew cask > Mac App Store — these are apps
    # that used to be Homebrew casks but have a real, darwin-buildable
    # nixpkgs package. Requires mac-app-util (wired in darwin-builder.nix)
    # for Spotlight/Launchpad to actually see them.
    guiTerminals = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Enable terminal emulator GUI apps (kitty, ghostty-bin, warp-terminal).";
    };
    guiCommunication = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Enable communication GUI apps (discord, signal-desktop, slack, zoom-us).";
    };
    guiCoreApps = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Enable core GUI apps common to every host (google-chrome, bitwarden-desktop).";
    };
    guiDevApps = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Enable development GUI apps (vscode, zed-editor, delta).";
    };
    guiMediaApps = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Enable media GUI apps (pinta, vlc-bin, dolphin-emu).";
    };
    guiProductivityApps = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Enable productivity/utility GUI apps (raycast, stats, monitorcontrol, betterdisplay, soundsource, mist, postman, utm, temurin-bin).";
    };
    guiFonts = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Enable GUI fonts (nerd-fonts, fira-mono, jetbrains-mono, powerline-symbols).";
    };

    # Gaming is its own flag rather than part of guiMediaApps: it pulls in a
    # multi-GB Proton build and creates a non-declarative Wine prefix under
    # $HOME, which is a very different commitment from "vlc is installed".
    gaming = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Enable gaming via umu-launcher + Proton-GE (Battle.net, and the Diablo IV launcher).";
    };

    # Which Wine prefixes this host manages. Names only — the per-prefix
    # settings (games, Proton build) live in programs.gaming-umu.winePrefixes,
    # which modules/features/gaming.nix turns each of these into. Split that way
    # because `programs.*` is Home Manager-only: this file is in both module
    # lists, so it can carry the switch, but the options with defaults must live
    # on the side that owns them.
    gamingWinePrefixes = lib.mkOption {
      type = lib.types.listOf (lib.types.strMatching "[A-Za-z0-9_-]+");
      default = [ ];
      description = ''
        Wine prefixes to create for Battle.net. Name each one for what it is —
        typically the host (`yuzu`), or a role (`ptr`, `probe`). The name becomes
        the prefix's directory (`~/.local/share/battlenet-umu/prefixes/<name>`)
        and part of its launcher names (`battlenet-umu-<name>-<game>`).

        One prefix is the normal case. Add a second on demand to test a Proton
        release without risking the working install, or for a separate account;
        a pre-installed `spare` kept purely as recovery is optional and costs a
        full install's disk. See "What a second prefix is actually for" in
        docs/gaming.md.

        Per-prefix configuration goes in programs.gaming-umu.winePrefixes.
      '';
      example = lib.literalExpression ''[ "yuzu" ]'';
    };
  };
}
