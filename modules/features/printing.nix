# Printing — CUPS, with HP driver support, and declarative printer queues.
#
# The service and the queues are both declarative here. nixpkgs has no option
# for a CUPS queue, and CUPS keeps its queues in /etc/cups/printers.conf, which
# NixOS regenerates on every activation — so a printer added by hand through the
# web interface at http://localhost:631 or `lpadmin` disappears at the next
# rebuild. Instead, each `my.printers` entry is re-applied idempotently at boot
# by an lpadmin oneshot, so the queue survives rebuilds and is described in the
# config like everything else.
#
# The preferred path is driverless IPP Everywhere: any HP LaserJet from roughly
# 2016 on advertises it, and `lpadmin -m everywhere` prints to it with no
# vendor PPD. hplip is present for older printers that need an hpcups PPD, and
# is where `hp-setup`/`hp-info` (toner levels, status) come from.
#
# Enabling this also answers DMS's System Check warning about cups-pk-helper:
# nixpkgs' CUPS module adds cups-pk-helper itself and registers its D-Bus service
# whenever polkit is enabled, which it is on this host (cupsd.nix, polkitEnabled).
_: {
  my.modules.nixos.printing = {
    lib,
    config,
    pkgs,
    ...
  }: {
    config = lib.mkIf config.my.printing {
      services.printing = {
        enable = true;

        drivers = [pkgs.hplip];

        # Discovers LAN printers over DNS-SD and creates local queues for them.
        # Kept on as a convenience — it is what makes a printer appear in a
        # print dialog without being added first — but it is not what provides
        # the queues below, which are declared explicitly instead.
        browsed.enable = true;

        # openFirewall deliberately left off: CUPS here is a *client* of the
        # networked printer, which is an outbound connection and needs no
        # inbound port. Turn it on only if other machines should print through
        # this host.
      };

      environment.systemPackages = [
        # Adds a printer to the queue from a GUI, and shows toner levels.
        pkgs.system-config-printer
        # hp-setup, hp-info (toner/status), hp-doctor for the HP-specific path.
        pkgs.hplip
      ];

      # Re-apply the declarative queues on every boot. Runs after cupsd is up;
      # each invocation is a no-op if the queue already exists with the same
      # URI, so repeated rebuilds and restarts converge rather than duplicate.
      #
      # The `-E` after `-p` both creates the queue and enables it; `-v` and
      # `-m` are only passed on creation, because lpadmin rejects changing a
      # device URI on an existing queue without `-x` first.
      systemd.services.cups-declarative-printers = lib.mkIf (config.my.printers != []) {
        description = "Re-apply declarative CUPS printer queues";
        after = ["cups.service"];
        requires = ["cups.service"];
        wantedBy = ["multi-user.target"];
        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
        };
        script = let
          inherit (pkgs) coreutils cups;
          lpadmin = "${cups}/bin/lpadmin";
          lpstat = "${cups}/bin/lpstat";
          queueFor = p: ''
            if ${lpstat} -p ${lib.escapeShellArg p.name} >/dev/null 2>&1; then
              echo "queue ${p.name} already exists; leaving it alone"
            else
              echo "creating queue ${p.name} -> ${p.uri}"
              ${lpadmin} -p ${lib.escapeShellArg p.name} -E \
                -v ${lib.escapeShellArg p.uri} \
                ${lib.concatMapStrings (m: "-m ${lib.escapeShellArg m} ") p.drivers} \
                ${lib.optionalString (p.description != "") "-D ${lib.escapeShellArg p.description}"} \
                ${lib.optionalString (p.location != "") "-L ${lib.escapeShellArg p.location}"}
            fi
            ${lib.optionalString p.isDefault ''
              ${lpadmin} -d ${lib.escapeShellArg p.name}
            ''}
          '';
        in ''
          export PATH=${lib.makeBinPath [coreutils cups]}
          ${lib.concatMapStrings queueFor config.my.printers}
        '';
      };
    };
  };
}
