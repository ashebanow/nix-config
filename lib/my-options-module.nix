# Shared options module providing config.my.* for host metadata.
# Following the dendritic pattern: capability flags defined centrally.
{lib, ...}: {
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
      description = "Enable Tailscale Serve to publish LLM endpoints via Tailscale Services.";
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
      default = [];
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

    # zmx feature
    zmx = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Enable zmx session persistence tool.";
    };

    # Memory feature (Mnemosyne)
    memory = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Enable Mnemosyne memory layer for AI agents.";
    };

    # Kaneo feature
    kaneo = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Enable the Kaneo project-management app (quadlet units + secretspec/BWS secrets).";
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
      description = "Enable secrets/crypto/vuln-scanning CLI tools (age, sops, gitleaks, ...).";
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
