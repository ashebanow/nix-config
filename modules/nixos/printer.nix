{ config, pkgs, ... }:

{
  # This will enable the Avahi service and open the firewall for it. 
  # The nssmdns option is necessary to make the Avahi service work with the nss-mdns package. 
  # The openFirewall option is necessary to open the firewall for the Avahi service. 
  services.avahi.nssmdns4 = {
    enable = true;
    nssmdns = true;
    openFirewall = true;
  };

  # These are open source drivers for HP printers. 
  services.printing.drivers = [ pkgs.hplip ];
  # Alternatively, we could load the proprietary HP drivers here instead:
  #     pkgs.hplipWithPlugin
  # Use the following command to add the printer, regular CUPS UI
  # doesn't seem to work:
  #   NIXPKGS_ALLOW_UNFREE=1 nix-shell -p hplipWithPlugin --run 'sudo -E hp-setup'
}
