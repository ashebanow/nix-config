{pkgs ? import <nixpkgs> { config.allowUnfree = true; }}:
pkgs.mkShell {
  name = "lumquat-dev";

  nativeBuildInputs = with pkgs; [
    alejandra
    bws
    colmena
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

    # Load API keys from BWS (Bitwarden Secrets Manager), with SOPS as
    # a bootstrap fallback for the BWS access token. Uses a 24h local cache
    # to avoid slowing down direnv. Also makes SOPS_AGE_KEY available for
    # manual sops use.
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

      _bws_load_secrets() {
        local CACHE_DIR="''${XDG_CACHE_HOME:-$HOME/.cache}/nix-bws"
        local CACHE_FILE="$CACHE_DIR/env.sh"
        local CACHE_MAX_AGE=86400  # 24 hours

        # If cache exists and is fresh, just source it
        if [[ -f "$CACHE_FILE" ]]; then
          local cache_mtime now
          if [[ "$(uname)" == "Darwin" ]]; then
            cache_mtime=$(stat -f %m "$CACHE_FILE" 2>/dev/null)
          else
            cache_mtime=$(stat -c %Y "$CACHE_FILE" 2>/dev/null)
          fi
          now=$(date +%s)
          if (( now - cache_mtime < CACHE_MAX_AGE )); then
            source "$CACHE_FILE"
            return 0
          fi
        fi

        # Resolve BWS access token: env first (zshenv), then SOPS fallback
        local _bws_token="''${BWS_ACCESS_TOKEN:-}"
        if [[ -z "$_bws_token" ]]; then
          if command -v sops >/dev/null 2>&1 && _setup_sops_key; then
            _bws_token=$(sops -d --extract '["bws-access-token"]' secrets/secrets.yaml 2>/dev/null)
          fi
        fi
        if [[ -z "$_bws_token" ]]; then
          echo "  [bws] WARNING: No BWS_ACCESS_TOKEN (env or SOPS)" >&2
          echo "  [bws] Set BWS_ACCESS_TOKEN in your environment, or" >&2
          echo "  [bws] add bws-access-token to secrets/secrets.yaml" >&2
          return 1
        fi

        # Fetch all secrets from BWS
        mkdir -p "$CACHE_DIR"
        {
          echo "# Auto-generated — do not edit"
          echo "export DEEPSEEK_API_KEY=\"$(BWS_ACCESS_TOKEN=\"$_bws_token\" bws secret get fdf38fc5-3f26-446f-9808-b47701346a5d 2>/dev/null || true)\""
          echo "export MINIMAX_API_KEY=\"$(BWS_ACCESS_TOKEN=\"$_bws_token\" bws secret get 3a5ac53a-8af5-4277-a86e-b47701341630 2>/dev/null || true)\""
          echo "export GEMINI_API_KEY=\"$(BWS_ACCESS_TOKEN=\"$_bws_token\" bws secret get 3dbd4b26-485f-44d5-abc6-b477013544b4 2>/dev/null || true)\""
          echo "export ANTHROPIC_API_KEY=\"$(BWS_ACCESS_TOKEN=\"$_bws_token\" bws secret get 28893b82-be1f-407c-aa2d-b4770134fcc1 2>/dev/null || true)\""
          echo "export EXA_API_KEY=\"$(BWS_ACCESS_TOKEN=\"$_bws_token\" bws secret get 52eba787-8cb2-41b7-87b1-b4770134b198 2>/dev/null || true)\""
          echo "export ZED_GITHUB_PERSONAL_ACCESS_TOKEN=\"$(BWS_ACCESS_TOKEN=\"$_bws_token\" bws secret get 2bc9244b-acf0-4620-8e29-b4770132e6f9 2>/dev/null || true)\""
        } > "$CACHE_FILE.tmp" && mv "$CACHE_FILE.tmp" "$CACHE_FILE"
        chmod 600 "$CACHE_FILE"

        source "$CACHE_FILE"
        echo "  [bws] Secrets loaded and cached"
        return 0
      }

      _bws_load_secrets || {
        echo "  [bws] WARNING: BWS secrets unavailable" >&2
      }
    fi
  '';
}
