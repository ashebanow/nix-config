# System monitoring/diagnostics CLI tools — Home Manager package list.
_: {
  my.modules.home-manager.cli-system-tools = {
    lib,
    pkgs,
    config,
    ...
  }: {
    config = lib.mkIf config.my.cliSystemTools {
      home.packages = with pkgs; [
        bandwhich
        betterdisplay
        binsider
        btop
        chezmoi
        colmena
        ctop
        duf
        fastfetch
        figlet
        gdu
        glances
        hyperfine
        htop
        inxi
        just
        mist
        monitorcontrol
        nh
        nvtopPackages.full
        procs
        soundsource
        tokei
      ];
    };
  };
}
