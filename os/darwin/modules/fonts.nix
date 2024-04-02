{
  config,
  lib,
  pkgs,
  ...
}:
with lib; {
  options.my.modules.fonts = {
    enable = mkOption {
      type = types.bool;
      default = false;
      description = mdDoc ''
        Fonts for ashebanow configuration
      '';
    };
  };

  config = mkIf config.my.modules.fonts.enable {
    fonts = {
      fontDir.enable = true;
      fonts = with pkgs; [
        (nerdfonts.override {fonts = ["SourceCodePro" "Hack" "JetBrainsMono"];})
        noto-fonts
        noto-fonts-emoji
        dejavu_fonts
      ];
    };
  };
}
