#!/usr/bin/env bash

# initialize wallpaper daemon
swww init &
# set wallpaper
swww img ~/path/to/file.png &

# networking
nm-applet --indicator &

waybar &
dunst
