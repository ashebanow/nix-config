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

gc:
  #!/usr/bin/env bash
  nix-collect-garbage --extra-experimental-features "nix-command flakes" --delete-old

update:
  #!/usr/bin/env bash
  nix flake update --extra-experimental-features "nix-command flakes" --commit-lock-file
