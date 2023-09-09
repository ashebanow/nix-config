#!/usr/bin/env bash

sudo nix-collect-garbage -d
nix-store --gc
nix-store --optimize
