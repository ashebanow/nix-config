# GUI fonts — Home Manager package list.
_: {
  my.modules.home-manager.gui-fonts = {
    lib,
    pkgs,
    config,
    ...
  }: {
    config = lib.mkIf config.my.guiFonts {
      home.packages = with pkgs; [
        nerd-fonts.monaspace
        nerd-fonts.sauce-code-pro
        nerd-fonts.symbols-only
        powerline-symbols
      ];
    };
  };
}
