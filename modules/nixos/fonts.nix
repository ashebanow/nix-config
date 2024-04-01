{pkgs, ...}: {
  fonts = {
    enableDefaultPackages = true;
    packages = with pkgs; [
      (nerdfonts.override {fonts = ["SourceCodePro" "Hack"];})
      noto-fonts
      noto-fonts-emoji
      dejavu_fonts
    ];

    fontconfig = {
      defaultFonts = {
        serif = ["DejaVuSerif" "NotoSerif"];
        sansSerif = ["DejaVuSans" "NotoSans"];
        monospace = ["SourceCodePro"];
      };
    };
  };
}
