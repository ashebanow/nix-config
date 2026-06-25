{
  pkgs ? import <nixpkgs> { },
}:
pkgs.mkShell {
  name = "lumquat-dev";

  nativeBuildInputs = with pkgs; [
    alejandra
    dig
    gh
    git
    home-manager
    mcp-nixos
    nixd
    nixfmt
    pi-coding-agent
    sops
    ssh-to-age
    uv
  ];

  shellHook = ''
    echo "Lumquat dev shell"

    # Load DEEPSEEK_API_KEY and MINIMAX_API_KEY from SOPS secrets.
    # Also makes SOPS_AGE_KEY available in the dev shell for manual sops use.
    if [ -f secrets/secrets.yaml ] && command -v sops >/dev/null 2>&1; then
      _setup_sops_key() {
        # Find / derive the age private key for SOPS decryption.
        # Sets SOPS_AGE_KEY or SOPS_AGE_KEY_FILE as appropriate.
        # Returns 0 on success, 1 if no key can be found.

        # 1. Already set via environment
        if [ -n "$SOPS_AGE_KEY" ] || [ -n "$SOPS_AGE_KEY_FILE" ]; then
          return 0
        fi

        # 2. Repo-local age key (secrets/keys/lumquat.age)
        if [ -f secrets/keys/lumquat.age ]; then
          export SOPS_AGE_KEY_FILE="$(realpath secrets/keys/lumquat.age)"
          return 0
        fi

        # 3. macOS dev machine: ~/.config/sops/age/keys.txt
        if [ -f "$HOME/.config/sops/age/keys.txt" ]; then
          export SOPS_AGE_KEY_FILE="$HOME/.config/sops/age/keys.txt"
          return 0
        fi

        # 4. NixOS: derive from SSH host key via ssh-to-age
        if [ -f /etc/ssh/ssh_host_ed25519_key ] && command -v ssh-to-age >/dev/null 2>&1; then
          export SOPS_AGE_KEY="$(sudo cat /etc/ssh/ssh_host_ed25519_key 2>/dev/null | ssh-to-age -private-key 2>/dev/null)"
          [ -n "$SOPS_AGE_KEY" ] && return 0
        fi

        return 1
      }

      if _setup_sops_key; then
        # Decrypt individual secrets (one sops call each)
        if DEEPSEEK_API_KEY=$(sops -d --extract '["deepseek-api-key"]' secrets/secrets.yaml 2>/dev/null) && [ -n "$DEEPSEEK_API_KEY" ]; then
          export DEEPSEEK_API_KEY
          echo "  [sops] DEEPSEEK_API_KEY loaded"
        fi
        if MINIMAX_API_KEY=$(sops -d --extract '["minimax-api-key"]' secrets/secrets.yaml 2>/dev/null) && [ -n "$MINIMAX_API_KEY" ]; then
          export MINIMAX_API_KEY
          echo "  [sops] MINIMAX_API_KEY loaded"
        fi
      else
        echo "  [sops] WARNING: No age key found — SOPS secrets unavailable" >&2
        echo "  [sops] Run: sudo cat /etc/ssh/ssh_host_ed25519_key | ssh-to-age -private-key > secrets/keys/lumquat.age" >&2
      fi
    fi
  '';
}
