{
  pkgs,
  inputs,
  ...
}: {
  age.secrets."atuin-sync.age".file = ../../secrets/atuin-sync.age;
  age.secrets."tailscale-authkey.age".file = ../../secrets/tailscale-authkey.age;
  age.secrets."tailscale-ashebanow-key.age".file = ../../secrets/tailscale-ashebanow-key.age;
  age.secrets."smb-secrets.age".file = ../../secrets/smb-secrets.age;

  environment.systemPackages = [
    inputs.ragenix.packages.x86_64-linux.default
  ];

  # Some programs need SUID wrappers, can be configured further or are
  # started in user sessions.
  # programs.mtr.enable = true;
  programs.gnupg.agent = {
    enable = true;
    enableSSHSupport = true;
  };

  # set up zsh as default shell
  programs.zsh.enable = true;
  users.defaultUserShell = pkgs.zsh;
  environment.shells = with pkgs; [zsh];

  # console ttys use the same keymap as X11
  console.useXkbConfig = true;

  # Enable touchpad support (enabled default in most desktopManager).
  # services.xserver.libinput.enable = true;

  # Enable CUPS to print documents.
  services.printing.enable = true;

  # make a single font directory with links to the original
  fonts.fontDir.enable = true;
}
