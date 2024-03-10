{
  config,
  pkgs,
  inputs,
  ...
}: {
  hardware.bluetooth = {
    enable = true;
    powerOnBoot = true; # powers up the default Bluetooth controller on boot
    settings = {
      General = {
        Experimental = true;
      };
    };
  };
  services.blueman.enable = true;
}
