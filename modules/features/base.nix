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
        openssh.authorizedKeys.keys = [
          "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIJhsuxHH4J5rPM5XNosTiTdHOX+NnZzHmePfEFTyaAs1 ashebanow@gmail.com"
        ];
      };

      # Root SSH access with authorized key (no password login)
      users.users.root.openssh.authorizedKeys.keys = [
        "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIJhsuxHH4J5rPM5XNosTiTdHOX+NnZzHmePfEFTyaAs1 ashebanow@gmail.com"
      ];

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
