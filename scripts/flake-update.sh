#!/usr/bin/env bash

nix flake update --recreate-lock-file
nix-store --gc
