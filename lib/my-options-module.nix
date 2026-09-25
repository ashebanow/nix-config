# Shared options module providing config.my.* for host metadata.
# Following the dendritic pattern: capability flags defined centrally.
{ lib, ... }: {
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
    dankMaterialShell = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Enable DankMaterialShell, the shell drawn on top of the niri session
        (see docs/adr/0003). It is a shell, not a session, so it has its own
        flag rather than an entry in `desktopSessions`.
      '';
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
      description = "Enable AI-agent CLI tools (opencode, crush, ...).";
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
      description = "Enable development GUI apps (vscode, zed-editor).";
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
  };
}
