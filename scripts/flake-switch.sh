#!env bash

nix flake update

if [ "$(uname -s)" == "Darwin" ]; then
  darwin-rebuild switch --flake .
elif [ -f "/etc/NIXOS" ]; then
  sudo nixos-rebuild switch --flake .
else
  # this seems to work, but a hack for sure...
  # darwin-rebuild switch --flake .
  # the "right way" would be to run home-manager standalone,
  # but I worry that nixpkgs won't be set up properly to use
  # unstable etc.
  home-manager switch --flake .
fi
