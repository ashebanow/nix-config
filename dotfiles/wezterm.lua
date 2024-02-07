local wezterm = require 'wezterm'
local config = {}

config.font = wezterm.font 'Source Code Pro'
config.color_scheme = 'Catppuccin Mocha'

config.ssh_domains = {
  {
    -- This name identifies the domain
    name = 'storage',
    -- The hostname or address to connect to. Will be used to match settings
    -- from your ssh config file
    remote_address = 'storage.lan',
    -- The username to use on the remote host
    username = 'root',
  },
  {
    -- This name identifies the domain
    name = 'loquat',
    -- The hostname or address to connect to. Will be used to match settings
    -- from your ssh config file
    remote_address = 'loquat.lan',
    -- The username to use on the remote host
    username = 'ashebanow',
  },
  {
    -- This name identifies the domain
    name = 'yuzu',
    -- The hostname or address to connect to. Will be used to match settings
    -- from your ssh config file
    remote_address = 'yuzu.lan',
    -- The username to use on the remote host
    username = 'ashebanow',
  },
}

return config

