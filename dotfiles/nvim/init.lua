-- This config is almost entirely based on sindo's dotfiles:
-- https://github.com/JazzyGrim/dotfiles

if vim.loader then
	vim.loader.enable()
end

_G.dd = function(...)
	require("util.debug").dump(...)
end
vim.print = _G.dd

require("config.lazy")
