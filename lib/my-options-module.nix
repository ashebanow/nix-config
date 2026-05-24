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
    llmPort = lib.mkOption {
      type = lib.types.port;
      default = 8080;
      description = "Port for llama.cpp API server.";
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

    # CLI tools feature (Home Manager)
    cliTools = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Enable modern CLI tools.";
    };
  };
}
