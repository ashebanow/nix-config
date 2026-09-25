# Base module — foundation shared by servers and desktops: primary user,
# SSH, base packages, podman. User defaults are keyed off my.desktop; power/
# logind (suspend) is keyed off my.baseAllowSuspend, which is opt-in (see below).
_: {
  my.modules.nixos.base =
    {
      lib,
      pkgs,
      config,
      ...
    }:
    {
      config = lib.mkIf config.my.base {
        # Timezone
        time.timeZone = lib.mkDefault config.my.baseTimezone;

        # Create the primary user. On a server this is the non-root container
        # operator (bash, BOX-121); on a desktop it is the interactive user and
        # mirrors the macOS workstations (zsh login shell, NetworkManager group
        # so `nmcli` works without a polkit round trip).
        users.users.${config.my.baseUsername} = {
          isNormalUser = true;
          shell = if config.my.desktop then pkgs.zsh else pkgs.bash;
          description = if config.my.desktop then "Desktop user" else "Container operator";
          extraGroups = [
            "wheel"
            "docker"
            "podman"
          ]
          ++ lib.optionals config.my.desktop [ "networkmanager" ];
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
        # A host that must be reachable over the network should not sleep out
        # from under its clients, so suspend is opt-in: my.baseAllowSuspend
        # defaults false. Only a desktop whose resume path is proven (e.g.
        # yuzu's r8169 reload hook) should set it true.
        systemd = lib.mkIf (!config.my.baseAllowSuspend) {
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

        # Logind: ignore power/sleep buttons, lid switch (unless suspend is opted in)
        services.logind.settings.Login = lib.mkIf (!config.my.baseAllowSuspend) {
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
          devenv
          eza
          ghostty
          ghostty.terminfo
          git
          iputils
          neovim
          nh
          secretspec # operator shell + just recipes (secrets-check)
          sudo
          television
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

        # ...but disabling the kernel's IPv6 stack does not stop glibc from
        # *asking* for AAAA records and preferring them, because address
        # selection is RFC 6724 sorting on the resolver side, not a kernel
        # setting. A name with both A and AAAA records can still come back
        # IPv6-first to a caller that doesn't fall back, and on a host with no
        # IPv6 route that is a dead end.
        #
        # This makes the resolver agree with the sysctl above: if the stack is
        # off, don't hand out IPv6 addresses to try. Note it is *not* a fix for
        # Resilio Sync's failure to reach its tracker — that was investigated at
        # length and disproved; every resolver API the daemon uses already
        # returned IPv4 first (see docs/research/resilio-sync-nixos.md).
        #
        # The mechanism is the label table: lower value wins, and glibc's
        # RFC 6724 default puts ::ffff:0:0/96 (IPv4-mapped) at 10 and ::/0 at
        # 40, i.e. IPv6 ahead. Swapping those two is the smallest correct change
        # and leaves the other defaults (loopback, 6to4, v4-compat) untouched.
        # Supplying any label table replaces the built-in one entirely, so the
        # full default set is reproduced here with only that pair exchanged.
        networking.getaddrinfo = {
          enable = true;
          label = {
            "::1/128" = 50;
            "::ffff:0:0/96" = 40; # IPv4-mapped, was 10 — now wins
            "::/0" = 10; # native IPv6, was 40 — now loses
            "2002::/16" = 30;
            "::/96" = 20;
          };
        };

        # Networking defaults
        networking.hostName = config.my.hostName;
      };
    };
}
