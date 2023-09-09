#!/usr/bin/env bash

nix flake update

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
