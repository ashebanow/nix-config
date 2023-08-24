#!/usr/bin/env bash

dest_machine=$1
dest_ip=""

case "$dest_machine" in
  storage )
    dest_ip="10.4.0.9";;
  virt )
    dest_ip="10.40.0.11";;
  virt2-vm )
    dest_ip="10.40.0.34";;
  liquid-ubuntu )
    dest_ip="172.26.103.196";;
  miraclemax )
    dest_ip="10.4.0.25";;
  gateway )
    dest_ip="10.4.0.1";;
  * )
    echo "Usage: copy-ssh-keys.sh dest_machine"
    echo "  dest_machine must be one of:"
    echo "    gateway"
    echo "    storage"
    echo "    virt"
    echo "    virt2-vm"
    echo "    liquid-ubuntu"
    echo "    miraclemax"
    exit 1
    ;;
esac

if [ ! -f ~/.ssh/id_ed25519 ]; then
  echo "No ~/.ssh/id_ed25519 file found"
  exit 1
fi

if [ ! -f ~/.ssh/id_ed25519.pub ]; then
  echo "No ~/.ssh/id_ed25519.pub file found"
  exit 1
fi

if [ ! -f ~/.ssh/config ]; then
  echo "No ~/.ssh/config file found"
  exit 1
fi

echo "Copying ssh files to $dest_ip($dest_machine)..."
scp -A -p -r ~/.ssh/id_ed25519 ~/.ssh/id_ed25519.pub ~/.ssh/config \
  "ashebanow@$dest_ip:/home/ashebanow/.ssh/"
echo Done
