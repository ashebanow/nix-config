# Dev shell with alejandra for formatting
_: {
  perSystem = {
    pkgs,
    system,
    ...
  }: let
    unfreePkgs = import pkgs.path {
      inherit system;
      config.allowUnfree = true;
    };
  in {
    devShells.default = pkgs.mkShell {
      name = "lumquat-dev";

      packages = with pkgs; [
        alejandra
        unfreePkgs.bws
        colmena
        dig
        gh
        git
        home-manager
        mcp-nixos
        nixd
        nixfmt
        pi-coding-agent
        secretspec
        uv
      ];

      shellHook = ''
        echo "Lumquat dev shell"

        # Load API keys from BWS (Bitwarden Secrets Manager). Requires
        # BWS_ACCESS_TOKEN in the environment (set by ~/.zshenv via chezmoi on
        # configured machines). Uses a 24h local cache to avoid slowing down direnv.
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

          # BWS access token must come from the environment (no on-disk fallback).
          local _bws_token="''${BWS_ACCESS_TOKEN:-}"
          if [[ -z "$_bws_token" ]]; then
            echo "  [bws] WARNING: BWS_ACCESS_TOKEN is not set" >&2
            echo "  [bws] Source your shell config (chezmoi) or run 'bws login'" >&2
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
            echo "export FLAKEHUB_TOKEN=\"$(BWS_ACCESS_TOKEN=\"$_bws_token\" bws secret get 8052c406-7295-4449-af40-b4b5013bea48 2>/dev/null || true)\""
          } > "$CACHE_FILE.tmp" && mv "$CACHE_FILE.tmp" "$CACHE_FILE"
          chmod 600 "$CACHE_FILE"

          source "$CACHE_FILE"
          echo "  [bws] Secrets loaded and cached"
          return 0
        }

        if command -v bws >/dev/null 2>&1; then
          _bws_load_secrets || {
            echo "  [bws] WARNING: BWS secrets unavailable" >&2
          }
        fi
      '';
    };
  };
}
