# Dev shell with alejandra for formatting
_: {
  perSystem = {pkgs, ...}: {
    devShells.default = pkgs.mkShell {
      name = "lumquat-dev";

      packages = with pkgs; [
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
        echo "Run 'just fmt' to format Nix files"

        # Load DEEPSEEK_API_KEY from SOPS secrets (decrypts at shell start, not stored in Nix store)
        if [ -f secrets/secrets.yaml ] && command -v sops >/dev/null 2>&1; then
          _sops_decrypt() {
            # Find the age private key for SOPS decryption:
            # 1. Use SOPS_AGE_KEY if already set
            # 2. Use SOPS_AGE_KEY_FILE if already set
            # 3. Try ~/.config/sops/age/keys.txt (macOS dev machine)
            # 4. On NixOS, derive from SSH host key via ssh-to-age
            if [ -n "$SOPS_AGE_KEY" ] || [ -n "$SOPS_AGE_KEY_FILE" ]; then
              sops -d --extract '["deepseek-api-key"]' secrets/secrets.yaml 2>/dev/null
            elif [ -f "$HOME/.config/sops/age/keys.txt" ]; then
              SOPS_AGE_KEY_FILE="$HOME/.config/sops/age/keys.txt" \
                sops -d --extract '["deepseek-api-key"]' secrets/secrets.yaml 2>/dev/null
            elif [ -f /etc/ssh/ssh_host_ed25519_key ] && command -v ssh-to-age >/dev/null 2>&1; then
              SOPS_AGE_KEY="$(sudo cat /etc/ssh/ssh_host_ed25519_key 2>/dev/null | ssh-to-age -private-key 2>/dev/null)" \
                sops -d --extract '["deepseek-api-key"]' secrets/secrets.yaml 2>/dev/null
            else
              return 1
            fi
          }
          if DEEPSEEK_API_KEY=$(_sops_decrypt) && [ -n "$DEEPSEEK_API_KEY" ]; then
            export DEEPSEEK_API_KEY
          fi
        fi
      '';
    };
  };
}
