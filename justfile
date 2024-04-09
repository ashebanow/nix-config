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
  darwin-rebuild --show-trace check --flake "{{FLAKE_DIR}}"

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

deploy machine ip='':
  #!/usr/bin/env sh
  if [ {{machine}} = "miraclemax" ]; then
    darwin-rebuild switch --flake .
  elif [ -z "{{ip}}" ]; then
    sudo nixos-rebuild switch --fast --flake ".#{{machine}}"
  else
    nixos-rebuild switch --fast --flake ".#{{machine}}" --use-remote-sudo --target-host "ashebanow@{{ip}}" --build-host "ashebanow@{{ip}}"
  fi

history:
  nix profile history --profile /nix/var/nix/profiles/system

# lint:
#   statix check .

repair:
  sudo nix-store --verify --check-contents --repair

# edit-secrets:
#   sops secrets/secrets.yaml

# rotate-secrets:
#   for file in secrets/*; do sops --rotate --in-place "$file"; done

# sync-secrets:
#   for file in secrets/*; do sops updatekeys "$file"; done

