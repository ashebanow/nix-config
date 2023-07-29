#!/bin/sh
sudo nix-collect-garbage -d
nix-store --gc
nix-store --optimize
