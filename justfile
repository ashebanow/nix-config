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
