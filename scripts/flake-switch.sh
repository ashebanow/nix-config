#!/usr/bin/bash

nix flake update

if [ "$(uname -s)" == "Darwin" ]; then
  echo "Running 'darwin-rebuild switch --flake .'..."
  darwin-rebuild switch --show-trace --flake .
elif [ -f "/etc/NIXOS" ]; then
  echo "Running 'sudo nixos-rebuild switch --flake .'..."
  sudo nixos-rebuild switch --show-trace --flake .
else
  echo "Running 'home-manager switch --impure --flake .'..."
  home-manager switch --show-trace --impure --flake .
fi
