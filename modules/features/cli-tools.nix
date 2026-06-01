# CLI tools module — modern command-line utilities via Home Manager.
_: {
  my.modules.home-manager.cli-tools = {
    lib,
    pkgs,
    config,
    ...
  }: {
    xdg.configFile."starship.toml".source = ./dotfiles/.config/starship.toml;

    config = lib.mkIf config.my.cliTools {
      home.packages = with pkgs; [
        bat
        bottom
        curl
        eza
        fastfetch
        fd
        fzf
        just
        neovim
        pi-coding-agent
        ripgrep
        starship
        wget
        zoxide
      ];
    };
  };
}
