{pkgs, ...}: {
  environment.systemPackages = with pkgs; [
    # appimagekit
    linuxKernel.packages.linux_6_1.turbostat
    msrtool
  ];

  # Bootloader
  boot = {
    loader = {
      systemd-boot.enable = true;
      efi.canTouchEfiVariables = true;
    };

    # Warp terminal app comes as an appimage, so we need to register
    # the binary format to run using the appimage-run wrapper
    # binfmt.registrations.appimage = {
    #   wrapInterpreterInShell = false;
    #   interpreter = "${pkgs.appimage-run}/bin/appimage-run";
    #   recognitionType = "magic";
    #   offset = 0;
    #   mask = ''\xff\xff\xff\xff\x00\x00\x00\x00\xff\xff\xff'';
    #   magicOrExtension = ''\x7fELF....AI\x02'';
    # };
  };
}
