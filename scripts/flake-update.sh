#!/usr/bin/env bash

nix flake update --commit-lock-file
nix-store --gc
