#!/usr/bin/env bash

# NOTE: for standalone home manager on linux, you need to install
# home manager manually:
#
#   nix-channel --add https://github.com/nix-community/home-manager/archive/release-23.05.tar.gz home-manager
#   nix-channel --update
#
# (use the version number appropriate for your platform)

nix flake update --commit-lock-file

if [ "$(uname -s)" == "Darwin" ]; then
  echo "Running 'darwin-rebuild switch --flake .'..."
  darwin-rebuild switch --show-trace --flake .
elif [ -f "/etc/NIXOS" ]; then
  echo "Running 'sudo nixos-rebuild --impure switch --flake .'..."
  sudo nixos-rebuild switch --impure --flake .
else
  echo "Running 'home-manager switch --impure --flake .'..."
  home-manager switch --impure --flake .
fi
