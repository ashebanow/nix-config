[macos]
switch:
  darwin-rebuild --show-trace switch --flake "$HOME/nix-config"

[linux]
switch:
  #!/usr/bin/env bash
  if [ -f /etc/NIXOS ]; then
    sudo nixos-rebuild --show-trace switch --flake "$HOME/nix-config"
  else
    home-manager --show-trace switch --flake "$HOME/nix-config"
  fi

gc:
  #!/usr/bin/env bash
  nix-collect-garbage --extra-experimental-features "nix-command flakes" --delete-old

update:
  #!/usr/bin/env bash
  nix flake update --extra-experimental-features "nix-command flakes" --commit-lock-file
