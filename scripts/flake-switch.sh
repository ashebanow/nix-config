#!/usr/bin/env bash

# NOTE: for standalone home manager on linux, you need to install
# home manager manually:
#
#   nix-channel --add https://github.com/nix-community/home-manager/archive/release-23.05.tar.gz home-manager
#   nix-channel --update
#
# (use the version number appropriate for your platform)

if [ "$(uname -s)" == "Darwin" ]; then
  echo "Running darwin-rebuild..."
  darwin-rebuild switch --show-trace --flake .
elif [ -f "/etc/NIXOS" ]; then
  echo "Running sudo nixos-rebuild..."
  sudo nixos-rebuild switch --impure --flake .
else
  echo "Running home-manager..."
  home-manager switch -v -L --debug --show-trace --impure --flake .
fi
