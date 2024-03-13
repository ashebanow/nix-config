{
  pkgs,
  modulesPath,
  ...
}: {
  imports = [
    "${modulesPath}/installer/cd-dvd/installation-cd-minimal.nix"
  ];

  environment.systemPackages = with pkgs; [
    bat
    btop
    curl
    dig
    disko
    diskus
    eza
    fastfetch
    gh
    git
    just
    kitty
    less
    neovim
    (nerdfonts.override {fonts = ["SourceCodePro" "Hack"];})
    parted
    ripgrep
    unzip
    wget
    zoxide
  ];

  environment.interactiveShellInit = ''
    alias cat='bat --paging=never --style=plain'
    alias eza='eza --icons'
    alias gst='git status'
    alias ls="eza"
    alias less="bat"
    alias ll='eza -al'
    alias llt='eza -al --sort modified -r'
    alias ltree='eza -lDT --sort modified'
    alias mkdir='mkdir -pv'
    alias more=bat
    alias vi=nvim
    alias vim=nvim
    alias ack=rg
    alias grep=rg
  '';

  programs = {
    # Some programs need SUID wrappers, can be configured further or are
    # started in user sessions.
    # programs.mtr.enable = true;
    gnupg.agent = {
      enable = true;
      enableSSHSupport = true;
    };
  };

  # set up zsh as default shell
  programs.zsh.enable = true;
  users.defaultUserShell = pkgs.zsh;
  environment.shells = with pkgs; [zsh];

  # console ttys use the same keymap as X11
  console.useXkbConfig = true;

  powerManagement = {
    enable = true;
    cpuFreqGovernor = "performance";
  };

  nixpkgs.hostPlatform = "x86_64-linux";

  environment.sessionVariables = {
    EDITOR = "vim";
    GDK_SCALE = "1.5";
    STEAM_FORCE_DESKTOPUI_SCALING = "1.5";
  };

  fonts.fontconfig.enable = true;
}
