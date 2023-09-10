#!/usr/bin/env bash

nix flake update --commit-lock-file
sudo nix-collect-garbage -d
nix-store --gc
nix-store --optimize
