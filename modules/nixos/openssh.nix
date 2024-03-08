{
  config,
  pkgs,
  inputs,
  nixos-hardware,
  ...
}: {
  services.openssh = {
    enable = true;
    # require public key authentication for better security
    settings.PasswordAuthentication = false;
    settings.KbdInteractiveAuthentication = false;
    settings.PermitRootLogin = "no";
  };
  security.sudo.wheelNeedsPassword = false;
}
