[macos]
switch:
  darwin-rebuild switch --impure --flake "$HOME/nix-config"

[linux]
switch:
  #!/usr/bin/env bash
  if [ -f /etc/NIXOS ]; then
    sudo nixos-rebuild switch --flake "$HOME/nix-config"
  else
    home-manager switch --impure --flake "$HOME/nix-config"
  fi

update:
  #!/usr/bin/env bash
  nix flake update --commit-lock-file
  nix-collect-garbage --delete-old

# Update all gems in packages/**
bundix:
  #!/usr/bin/env bash
  for i in packages/*; do
    cd $i 1>/dev/null
    [ -f Gemfile ] && nix run nixpkgs#bundix -- -l
    cd - 1>/dev/null
  done
