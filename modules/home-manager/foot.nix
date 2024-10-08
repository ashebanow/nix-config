{
  config,
  pkgs,
  lib,
  ...
}: {
  home.packages = with pkgs; [
    foot
  ];

  programs.foot = {
    enable = true;
    server.enable = true;
    settings = {
      main = {
        bold-text-in-bright = true;
        dpi-aware = "yes";
        font = "monospace:size=15, termicons:size=15";
        term = "xterm-256color";
      };

      colors = {
        foreground = "D9E0EE";
        background = "1E1D2F";
        regular0 = "6E6C7E"; # black
        regular1 = "F28FAD"; # red
        regular2 = "ABE9B3"; # green
        regular3 = "FAE3B0"; # yellow
        regular4 = "96CDFB"; # blue
        regular5 = "F5C2E7"; # magenta
        regular6 = "89DCEB"; # cyan
        regular7 = "D9E0EE"; # white
        bright0 = "988BA2"; # bright black
        bright1 = "F28FAD"; # bright red
        bright2 = "ABE9B3"; # bright green
        bright3 = "FAE3B0"; # bright yellow
        bright4 = "96CDFB"; # bright blue
        bright5 = "F5C2E7"; # bright magenta
        bright6 = "89DCEB"; # bright cyan
        bright7 = "D9E0EE"; # bright white
      };
      cursor = {
        color = "1A1826 D9E0EE";
        style = "block";
        blink = true;
      };
      mouse = {
        hide-when-typing = true;
      };
    };
  };
}
