# Base module — server foundation with non-root user for containers.
_: {
  my.modules.nixos.base = {
    lib,
    pkgs,
    config,
    ...
  }: {
    config = lib.mkIf config.my.base {
      # Timezone
      time.timeZone = lib.mkDefault config.my.baseTimezone;

      # Create non-root user for containers
      users.users.${config.my.baseUsername} = {
        isNormalUser = true;
        description = "Container operator";
        extraGroups = ["wheel" "docker" "podman"];
      };

      # Sudo access for wheel group
      security.sudo.wheelNeedsPassword = false;

      # Enable SSH for remote access
      services.openssh = {
        enable = true;
        settings = {
          PermitRootLogin = "no";
          PasswordAuthentication = false;
        };
      };

      # Base system packages
      environment.systemPackages = with pkgs; [
        btop
        htop
        curl
        wget
        git
        vim
        sudo
      ];

      # Enable podman for container workloads
      virtualisation.podman = {
        enable = true;
        defaultNetwork.settings.dns_enabled = true;
      };

      # Networking defaults
      networking.hostName = config.my.hostName;
    };
  };
}
