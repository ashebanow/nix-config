#!env bash

nix flake update

if [ "$(uname -s)" == "Darwin" ]; then
  echo "Running 'darwin-rebuild switch --flake '..."
  darwin-rebuild switch --flake .
elif [ -f "/etc/NIXOS" ]; then
  echo "Running 'sudo nixos-rebuild switch --flake '..."
  sudo nixos-rebuild switch --flake .
else
  echo "Running 'home-manager switch --impure --flake '..."
  home-manager switch --impure --flake .
fi
