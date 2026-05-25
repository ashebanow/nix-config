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

      # ── Power management: prevent sleep/hibernate ────────────────
      # Server must never sleep — it serves LLM requests
      systemd.sleep.extraConfig = ''
        AllowSuspend=no
        AllowHibernation=no
        AllowHybridSleep=no
        AllowSuspendThenHibernate=no
      '';

      # Mask sleep targets to prevent any sleep action
      systemd.targets = {
        sleep.enable = false;
        suspend.enable = false;
        hibernate.enable = false;
        hybrid-sleep.enable = false;
      };

      # Logind: ignore power/sleep buttons, lid switch
      services.logind = {
        lidSwitch = "ignore";
        lidSwitchExternalPower = "ignore";
        lidSwitchDocked = "ignore";
        handlePowerKey = "ignore";
        handleSuspendKey = "ignore";
        handleHibernateKey = "ignore";
      };

      # CPU governor: schedutil (scheduler-driven, scales under load)
      powerManagement.cpuFreqGovernor = lib.mkDefault "schedutil";

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
