# GUI fonts — Home Manager package list.
_: {
  my.modules.home-manager.gui-fonts = {
    lib,
    pkgs,
    config,
    ...
  }: {
    config = lib.mkIf config.my.guiFonts {
      # These go in home.packages, not a fonts.packages option — Home Manager
      # has no such option here (it was removed; fontconfig discovers anything
      # installed into the profile when fonts.fontconfig.enable is on, which it
      # is by default on a NixOS submodule). The NixOS-scope equivalent is
      # fonts.packages under system config; this module is the Home Manager one.
      home.packages = with pkgs; [
        noto-fonts
        noto-fonts-cjk-sans
        noto-fonts-color-emoji
        nerd-fonts.monaspace
        nerd-fonts.sauce-code-pro
        nerd-fonts.symbols-only
        powerline-symbols
      ];
    };
  };
}
