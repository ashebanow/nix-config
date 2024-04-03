{
  config,
  pkgs,
  inputs,
  ...
}: {
  environment.systemPackages = with pkgs; [
    inputs.agenix.packages.x86_64-linux.default
    bat
    btop
    cachix
    curl
    daemonize
    delta
    dig
    direnv
    diskus
    duf
    eza
    gh
    git
    gnupg
    jq
    just
    less
    nix-direnv
    nix-tree
    nixpkgs-fmt
    ripgrep
    starship
    tldr
    unzip
    vim
    wget
    zoxide
    zsh
  ];

  age.secrets = {
    "tailscale-authkey.age".file = ../../secrets/tailscale-authkey.age;
    "tailscale-ashebanow-key.age".file = ../../secrets/tailscale-ashebanow-key.age;
    "smb-secrets.age".file = ../../secrets/smb-secrets.age;
    "syncthing-password.age".file = ../../secrets/syncthing-password.age;
  };

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
