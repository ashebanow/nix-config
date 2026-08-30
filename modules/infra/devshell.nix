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

        # TEMP-DISABLED (2026-08-29): BWS secret loading in the devshell
# is commented out while we test whether it is needed at all - darwin
# gets API keys from ~/.zshenv (chezmoi), lumquat via secretspec/systemd.
# Restore by uncommenting the block below.
#
# # Load API keys from BWS (Bitwarden Secrets Manager). Requires
        # # BWS_ACCESS_TOKEN in the environment (set by ~/.zshenv via chezmoi on
        # # configured machines). Uses a 24h local cache to avoid slowing down direnv.
        # _bws_load_secrets() {
          # local CACHE_DIR="''${XDG_CACHE_HOME:-$HOME/.cache}/nix-bws"
          # local CACHE_FILE="$CACHE_DIR/env.sh"
          # local CACHE_MAX_MINUTES=1440  # 24 hours
# 
          # # Reuse the cache only if it is fresh AND complete. `find -mmin` works
          # # with both BSD (macOS) and GNU (NixOS) find, so we never depend on a
          # # particular `stat` flavour — inside `nix develop` the PATH already
          # # carries GNU coreutils even on macOS, where BSD-style `stat -f %m`
          # # produced garbage and made the `(( ))` freshness check explode.
          # if [[ -f "$CACHE_FILE" ]] && [[ -n "$(find "$CACHE_FILE" -mmin -"$CACHE_MAX_MINUTES" 2>/dev/null)" ]] && grep -q '^# nix-bws cache v2' "$CACHE_FILE" && ! grep -q '=""' "$CACHE_FILE"; then
            # source "$CACHE_FILE"
            # return 0
          # fi
# 
          # # BWS access token must come from the environment (no on-disk fallback).
          # local _bws_token="''${BWS_ACCESS_TOKEN:-}"
          # if [[ -z "$_bws_token" ]]; then
            # echo "  [bws] WARNING: BWS_ACCESS_TOKEN is not set" >&2
            # echo "  [bws] Source your shell config (chezmoi) or run 'bws login'" >&2
            # return 1
          # fi
# 
          # # One secret value by BWS item ID. bws 2.x prints JSON by default;
          # # `-o tsv` yields "id<TAB>key<TAB>value", so take field 3. The value
          # # is escaped so it stays safe inside a double-quoted `export VAR="..."`.
          # _bws_fetch() {
            # BWS_ACCESS_TOKEN="$_bws_token" bws secret get "$1" -o tsv 2>/dev/null \
              # | tail -n 1 \
              # | cut -f3 \
              # | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g' -e 's/\$/\\$/g' -e 's/`/\\`/g'
          # }
# 
          # # Fetch all secrets from BWS
          # mkdir -p "$CACHE_DIR"
          # {
            # echo "# nix-bws cache v2 - auto-generated, do not edit"
            # echo "export DEEPSEEK_API_KEY=\"$(_bws_fetch fdf38fc5-3f26-446f-9808-b47701346a5d)\""
            # echo "export MINIMAX_API_KEY=\"$(_bws_fetch 3a5ac53a-8af5-4277-a86e-b47701341630)\""
            # echo "export GEMINI_API_KEY=\"$(_bws_fetch 3dbd4b26-485f-44d5-abc6-b477013544b4)\""
            # echo "export ANTHROPIC_API_KEY=\"$(_bws_fetch 28893b82-be1f-407c-aa2d-b4770134fcc1)\""
            # echo "export EXA_API_KEY=\"$(_bws_fetch 52eba787-8cb2-41b7-87b1-b4770134b198)\""
            # echo "export ZED_GITHUB_PERSONAL_ACCESS_TOKEN=\"$(_bws_fetch 2bc9244b-acf0-4620-8e29-b4770132e6f9)\""
            # echo "export FLAKEHUB_TOKEN=\"$(_bws_fetch 8052c406-7295-4449-af40-b4b5013bea48)\""
          # } > "$CACHE_FILE.tmp" && mv "$CACHE_FILE.tmp" "$CACHE_FILE"
          # chmod 600 "$CACHE_FILE"
# 
          # source "$CACHE_FILE"
          # if ! grep -q '=""' "$CACHE_FILE"; then
            # echo "  [bws] Secrets loaded and cached"
          # else
            # echo "  [bws] WARNING: some secrets could not be fetched (check BWS_ACCESS_TOKEN)" >&2
          # fi
          # return 0
        # }
# 
        # if command -v bws >/dev/null 2>&1; then
          # _bws_load_secrets || {
            # echo "  [bws] WARNING: BWS secrets unavailable" >&2
          # }
        # fi
      '';
    };
  };
}
