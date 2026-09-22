# System monitoring/diagnostics CLI tools — Home Manager package list.
_: {
  my.modules.home-manager.cli-system-tools = {
    lib,
    pkgs,
    config,
    ...
  }: {
    config = lib.mkIf config.my.cliSystemTools {
      home.packages =
        (with pkgs; [
          bandwhich
          binsider
          btop
          cachix # binary cache management
          chezmoi
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
          nh
          nix-output-monitor # pretty-print nix build output (nom)
          nvd # diff nix store generations
          nvtopPackages.full
          procs
          tokei
        ])
        # macOS-only system tools (no Linux build in nixpkgs).
        ++ lib.optionals pkgs.stdenv.hostPlatform.isDarwin (with pkgs; [
          betterdisplay
          mist
          monitorcontrol
          soundsource
        ]);
    };
  };
}
