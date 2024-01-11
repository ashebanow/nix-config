{
  globals.mapleader = " ";
  keymaps = [
    {
      key = "<leader>a";
      options.silent = true;
      action = "<cmd>Alpha<CR>";
    }
    {
      key = "<leader>m";
      options.silent = true;
      action = "<cmd>Telescope live_grep<CR>";
    }
    {
      key = "<leader>f";
      options.silent = true;
      action = "<cmd>Telescope find_files<CR>";
    }
    {
      key = "<leader>b";
      options.silent = true;
      action = "<cmd>Telescope buffers<CR>";
    }
  ];
}