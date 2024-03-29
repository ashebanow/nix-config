{
  config,
  pkgs,
  inputs,
  ...
}: {
  hardware = {
    # optionally enable 32bit pulseaudio support if pulseaudio is enabled
    pulseaudio.support32Bit = config.hardware.pulseaudio.enable;

    steam-hardware.enable = true;
  };

  environment.systemPackages = with pkgs; [
    steam
  ];

  programs.steam = {
    enable = true;
    remotePlay.openFirewall = true; # Open ports in the firewall for Steam Remote Play
    # dedicatedServer.openFirewall = true; # Open ports in the firewall for Source Dedicated Server
  };
}
