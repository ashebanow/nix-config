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
        nixd
        nixfmt
        pi-coding-agent
        sops
      ];

      shellHook = ''
        echo "Lumquat dev shell"
        echo "Run 'just fmt' to format Nix files"

        # Load DEEPSEEK_API_KEY from SOPS secrets (decrypts at shell start, not stored in Nix store)
        if [ -f secrets/secrets.yaml ] && command -v sops >/dev/null 2>&1; then
          if DEEPSEEK_API_KEY=$(sops -d --extract '["deepseek-api-key"]' secrets/secrets.yaml 2>/dev/null) && [ -n "$DEEPSEEK_API_KEY" ]; then
            export DEEPSEEK_API_KEY
          fi
        fi
      '';
    };
  };
}
