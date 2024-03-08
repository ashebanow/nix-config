{
  config,
  pkgs,
  inputs,
  nixos-hardware,
  ...
}: {
  networking = {
    networkmanager.enable = true;

    # wireless = {
    #   enable = true;
    #   networks = {
    #     "Kerpow!" = {
    #       pskRaw="013d6f8e2633450c5051d7a53381da94be88a3a278eaa1e2fbc13d78a3270452";
    #     };
    #   };
    # };

    # defaultGateway = "10.40.60.1";
    # nameservers = [ "10.40.60.1" ];

    # extraHosts = ''
    #   10.40.0.1   gateway gateway.lan
    #   10.40.0.227  storage storage.lan
    #   10.40.0.11  virt1 virt1.lan
    #   10.40.0.14  virt2 virt2.lan
    #   10.40.60.6 yuzu yuzu.lan
    #   10.40.60.7 loquat loquat.lan
    #   172.21.75.8 liquid-nixos liquid-nixos.lan
    # '';

    firewall = {
      enable = true;
      allowPing = true;
      allowedTCPPorts = [
        22 # ssh
        80
        443 # HTTP/HTTPS
        # 2049 # nfs
      ];
    };
  };

  # Enable network manager applet
  # programs.nm-applet.enable = true;
}
