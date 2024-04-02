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
        Fonts for ashebanow's configuration
      '';
    };
  };

  config = mkIf config.my.modules.fonts.enable {
    fonts = {
      enableDefaultPackages = true;
      fontDir.enable = true;

      packages = with pkgs; [
        (nerdfonts.override {fonts = ["SourceCodePro" "Hack" "JetBrainsMono"];})
        noto-fonts
        noto-fonts-emoji
        dejavu_fonts
      ];

      fontconfig = {
        enable = true;
        defaultFonts = {
          serif = ["DejaVuSerif" "NotoSerif"];
          sansSerif = ["DejaVuSans" "NotoSans"];
          monospace = ["SourceCodePro"];
        };
      };
    };
  };
}
