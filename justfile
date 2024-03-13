FLAKE_DIR := if path_exists("/etc/nixos/flake.nix") == "true" {
  "/etc/nixos"
} else {
  "$HOME/nix-config"
}

[macos]
switch:
  darwin-rebuild switch --flake "{{FLAKE_DIR}}"

[linux]
switch:
  #!/usr/bin/env bash
  if [ -f /etc/NIXOS ]; then
    sudo nixos-rebuild switch --impure --flake "{{FLAKE_DIR}}"
  else
    home-manager switch --impure --flake "{{FLAKE_DIR}}"
  fi

[macos]
test:
  darwin-rebuild --show-trace switch --flake "{{FLAKE_DIR}}"

[linux]
test:
  #!/usr/bin/env bash
  if [ -f /etc/NIXOS ]; then
    sudo nixos-rebuild --show-trace dry-activate --flake "{{FLAKE_DIR}}"
  else
    home-manager --show-trace -n switch --flake "{{FLAKE_DIR}}"
  fi

[macos]
build-iso:
  echo "ISO build on non-nixOS platforms unsupported"
  exit 1

[linux]
build-iso:
  #!/usr/bin/env bash
  if [ -f /etc/NIXOS ]; then
    nix build "{{FLAKE_DIR}}#nixosConfigurations.installerIso.config.system.build.isoImage"
  else
    echo "Non-nixOS platforms unsupported"
    exit 1
  fi

gc:
  #!/usr/bin/env bash
  sudo nix-collect-garbage --extra-experimental-features "nix-command flakes" --delete-old
  nix-collect-garbage --extra-experimental-features "nix-command flakes" --delete-old

update:
  nix flake update --extra-experimental-features "nix-command flakes" "{{FLAKE_DIR}}"
