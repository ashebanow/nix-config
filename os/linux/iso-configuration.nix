{
  pkgs,
  modulesPath,
  ...
}: {
  nix = {
    settings = {
      experimental-features = ["nix-command" "flakes"];
      warn-dirty = false;
    };
  };
  # Allow unfree packages
  nixpkgs.config.allowUnfree = true;

  imports = [
    "${modulesPath}/installer/cd-dvd/installation-cd-minimal.nix"
    ../../modules/basics.nix
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

  # including this here because some hardware is dog slow without it,
  # like my EKWB Vanquish 275
  powerManagement = {
    enable = true;
    cpuFreqGovernor = "performance";
  };

  nixpkgs.hostPlatform = "x86_64-linux";

  environment.sessionVariables = {
    EDITOR = "nvim";
    GDK_SCALE = "1.5";
  };
}
