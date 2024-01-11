{
  plugins.alpha = {
    enable = true;
    iconsEnabled = true;
    layout = [
      {
        type = "padding";
        val = 2;
      }
      {
        opts = {
          hl = "Type";
          position = "center";
        };
        type = "text";
        val = [
          "          ▀████▀▄▄              ▄█ "
          "            █▀    ▀▀▄▄▄▄▄    ▄▄▀▀█ "
          "    ▄        █          ▀▀▀▀▄  ▄▀  "
          "   ▄▀ ▀▄      ▀▄              ▀▄▀  "
          "  ▄▀    █     █▀   ▄█▀▄      ▄█    "
          "  ▀▄     ▀▄  █     ▀██▀     ██▄█   "
          "   ▀▄    ▄▀ █   ▄██▄   ▄  ▄  ▀▀ █  "
          "    █  ▄▀  █    ▀██▀    ▀▀ ▀▀  ▄▀  "
          "   █   █  █      ▄▄           ▄▀   "
        ];
      }
      {
        type = "padding";
        val = 2;
      }
      {
        type = "group";
        val = [
          {
            command = "<CMD>ene <CR>";
            desc = "  > New file";
            shortcut = "e";
          }
          {
            command = ":cd $HOME/Development | Telescope find_files<CR>";
            desc = "󰺄  > Find file";
            shortcut = "f";
          }
          {
            command = ":Telescope oldfiles<CR>";
            desc = "  > Find Recent";
            shortcut = "t";
          }
          {
            command = ":cd $HOME/Development | Telescope find_files<CR>";
            desc = " > Development";
            shortcut = "r";
          }
          {
            command = ":cd $HOME/Documents | Telescope find_files<CR>";
            desc = "󱔗  > Documents";
            shortcut = "k";
          }
          {
            command = ":qa<CR>";
            desc = "󰗼  > Quit NVIM";
            shortcut = "q";
          }
        ];
      }
      {
        type = "padding";
        val = 2;
      }
      {
        opts = {
          hl = "Keyword";
          position = "center";
        };
        type = "text";
        val = "Inspiring quote here.";
      }
    ];
  };
}