{
  config,
  pkgs,
  ...
}: {
  home.packages = with pkgs; [
    appimage-run
    warp-beta.warp-terminal
  ];

  nixpkgs.config = {
    packageOverrides = pkgs: {
      warp-beta = import (fetchTarball "https://github.com/imadnyc/nixpkgs/archive/refs/heads/warp-terminal-initial-linux.zip") {
        config = config.nixpkgs.config;
      };
    };
  };
}
