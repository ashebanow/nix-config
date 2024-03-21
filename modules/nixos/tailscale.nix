{
  config,
  pkgs,
  inputs,
  ...
}: {
  # make the tailscale command usable to users
  environment.systemPackages = [
    pkgs.systemd
    pkgs.tailscale
  ];

  services.tailscale = {
    authKeyFile = config.age.secrets.tailscale-ashebanow-key.path;
    enable = true;
    extraUpFlags = ["--ssh"];
    openFirewall = true;
    package = pkgs.tailscale;
    useRoutingFeatures = "both";
  };
}
