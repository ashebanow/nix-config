[macos]
switch:
  darwin-rebuild switch --flake "$HOME/nix-config"

[linux]
switch:
  #!/usr/bin/env bash
  if [ -f /etc/NIXOS ]; then
    sudo nixos-rebuild switch --flake "$HOME/nix-config"
  else
    home-manager switch --flake "$HOME/nix-config"
  fi

[macos]
test:
  darwin-rebuild --show-trace switch --flake "$HOME/nix-config"

[linux]
test:
  #!/usr/bin/env bash
  if [ -f /etc/NIXOS ]; then
    sudo nixos-rebuild --show-trace test --flake "$HOME/nix-config"
  else
    home-manager --show-trace -n switch --flake "$HOME/nix-config"
  fi

gc:
  #!/usr/bin/env bash
  nix-collect-garbage --extra-experimental-features "nix-command flakes" --delete-old

update:
  #!/usr/bin/env bash
  nix flake update --extra-experimental-features "nix-command flakes" --commit-lock-file
