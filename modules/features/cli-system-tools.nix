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
        binsider
        btop
        ctop
        du-dust
        duf
        fastfetch
        figlet
        gdu
        glances
        hyperfine
        htop
        inxi
        nvtopPackages.full
        procs
        tokei
      ];
    };
  };
}
