# Printing — CUPS, with HP driver support for yuzu's networked colour LaserJet.
#
# The *service* is declarative here; the printer *queue* is not. There is no
# nixpkgs option for a CUPS queue, so the printer itself is added once, by hand,
# through the CUPS web interface at http://localhost:631 or `lpadmin` — exactly
# as it is on any other distro. That queue lives in /etc/cups and /var/lib/cups.
#
# Enabling this also answers DMS's System Check warning about cups-pk-helper:
# nixpkgs' CUPS module adds cups-pk-helper itself and registers its D-Bus service
# whenever polkit is enabled, which it is on this host (cupsd.nix, polkitEnabled).
# Without CUPS running, the warning was correct — there was no printer stack.
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

        # Any HP LaserJet from roughly 2016 on speaks IPP Everywhere, and CUPS
        # prints to it driverlessly with no entry here — that is the preferred
        # path. hplip is here for the older ones that need an hpcups PPD, and it
        # is what `hp-setup`/`hp-info` come from.
        drivers = [pkgs.hplip];

        # Creates local queues for printers discovered on the LAN over DNS-SD, so
        # the LaserJet shows up in print dialogs without being added first.
        # avahi (already enabled for this host) does the discovery.
        browsed.enable = true;

        # openFirewall deliberately left off: CUPS here is a *client* of the
        # networked printer, which is an outbound connection and needs no inbound
        # port. Turn it on only if other machines should print through yuzu.
      };

      environment.systemPackages = [
        # Adds a printer to the queue from a GUI, and shows toner levels.
        pkgs.system-config-printer
        # hp-setup, hp-info (toner/status), hp-doctor for the HP-specific path.
        pkgs.hplip
      ];
    };
  };
}
