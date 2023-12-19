{ config, pkgs, ... }: {

  home.packages = with pkgs; [
    appimage-run
    appimageTools
  ];

  home.appimageTools = {
    enable = true;
    # version = "12";
  };

  # boot.binfmt.registrations.appimage = {
  #   wrapInterpreterInShell = false;
  #   interpreter = "${pkgs.appimage-run}/bin/appimage-run";
  #   recognitionType = "magic";
  #   offset = 0;
  #   mask = ''\xff\xff\xff\xff\x00\x00\x00\x00\xff\xff\xff'';
  #   magicOrExtension = ''\x7fELF....AI\x02'';
  # };

}