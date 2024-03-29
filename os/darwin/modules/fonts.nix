{
  config,
  lib,
  pkgs,
  ...
}:
with lib; {
  options.myfonts = {
    enable = mkOption {
      type = types.bool;
      default = false;
      description = mdDoc ''
        Fonts for ashebanow configuration
      '';
    };
  };

  config = mkIf config.myfonts.enable {
    fonts.fontDir.enable = true;
    fonts.fonts = with pkgs; [
      (nerdfonts.override {fonts = ["SourceCodePro" "Hack"];})
      noto-fonts
      noto-fonts-emoji
      dejavu_fonts
    ];
  };
}
