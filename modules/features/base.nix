# Base module — foundation shared by servers and desktops: primary user,
# SSH, base packages, podman. Power/logind/user differences between the two
# are keyed off my.desktop (see below).
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

      # Create the primary user. On a server this is the non-root container
      # operator (bash, BOX-121); on a desktop it is the interactive user and
      # mirrors the macOS workstations (zsh login shell, NetworkManager group
      # so `nmcli` works without a polkit round trip).
      users.users.${config.my.baseUsername} = {
        isNormalUser = true;
        shell =
          if config.my.desktop
          then pkgs.zsh
          else pkgs.bash;
        description =
          if config.my.desktop
          then "Desktop user"
          else "Container operator";
        extraGroups =
          ["wheel" "docker" "podman"]
          ++ lib.optionals config.my.desktop ["networkmanager"];
        linger = true; # Required for rootless podman systemd services
        openssh.authorizedKeys.keys = [
          "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIJhsuxHH4J5rPM5XNosTiTdHOX+NnZzHmePfEFTyaAs1 ashebanow@gmail.com"
        ];
      };

      programs.direnv.enable = true;
      programs.zsh.enable = true;

      # Root SSH access with authorized key (no password login)
      users.users.root.openssh.authorizedKeys.keys = [
        "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIJhsuxHH4J5rPM5XNosTiTdHOX+NnZzHmePfEFTyaAs1 ashebanow@gmail.com"
      ];

      # Sudo access for wheel group
      security.sudo.wheelNeedsPassword = false;

      # ── Power management ─────────────────────────────────────────
      # A server must never sleep — it serves LLM requests. A desktop is a
      # normal machine: leave logind/sleep at their NixOS defaults so the
      # session can suspend and the power button does something.
      systemd = lib.mkIf (!config.my.desktop) {
        sleep.settings.Sleep = {
          AllowSuspend = "no";
          AllowHibernation = "no";
          AllowHybridSleep = "no";
          AllowSuspendThenHibernate = "no";
        };
        # Mask sleep targets to prevent any sleep action
        targets = {
          sleep.enable = false;
          suspend.enable = false;
          hibernate.enable = false;
          hybrid-sleep.enable = false;
        };
      };

      # Logind: ignore power/sleep buttons, lid switch (servers only)
      services.logind.settings.Login = lib.mkIf (!config.my.desktop) {
        HandleLidSwitch = "ignore";
        HandleLidSwitchExternalPower = "ignore";
        HandleLidSwitchDocked = "ignore";
        HandlePowerKey = "ignore";
        HandleSuspendKey = "ignore";
        HandleHibernateKey = "ignore";
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
        bws # bitwarden-secrets-manager (unfree) — operator shell + just recipes
        curl
        eza
        ghostty.terminfo
        git
        htop
        iputils
        nh
        secretspec # operator shell + just recipes (secrets-check)
        sudo
        vim
        wget
      ];

      # Enable podman for container workloads
      virtualisation.podman = {
        enable = true;
        defaultNetwork.settings.dns_enabled = true;
      };

      # IPv4-only — no IPv6 configured on this network, and passt/podman
      # port forwarding only binds IPv4. Disabling avoids localhost → ::1 issues.
      boot.kernel.sysctl."net.ipv6.conf.all.disable_ipv6" = true;
      boot.kernel.sysctl."net.ipv6.conf.default.disable_ipv6" = true;

      # Networking defaults
      networking.hostName = config.my.hostName;
    };
  };
}
