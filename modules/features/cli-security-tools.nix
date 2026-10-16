# Secrets/crypto/vuln-scanning CLI tools — Home Manager package list.
_: {
  my.modules.home-manager.cli-security-tools = {
    lib,
    pkgs,
    config,
    ...
  }: {
    config = lib.mkIf config.my.cliSecurityTools {
      home.packages =
        (with pkgs; [
          bitwarden-cli
          bws # bitwarden-secrets-manager (unfree — needs nixpkgs.config.allowUnfree)
          _1password-cli
          cfssl
          cosign
          gitleaks
          gnupg
          lego
          minisign
          rbw
          trivy
        ])
        # secret-tool, which the dotfiles' ~/.config/shell/secrets.sh uses to
        # read the BWS token from the login keyring on Linux desktops. macOS
        # uses its built-in `security` instead.
        ++ lib.optionals pkgs.stdenv.hostPlatform.isLinux [pkgs.libsecret];
    };
  };

  # 1Password CLI on NixOS goes through the system module rather than
  # home.packages alone: programs._1password installs `op` behind a setgid
  # wrapper (onepassword-cli group), which the desktop app's CLI integration
  # requires. https://www.1password.dev/cli/get-started#nixos
  my.modules.nixos.cli-security-tools = {
    lib,
    config,
    ...
  }: {
    config = lib.mkIf config.my.cliSecurityTools {
      programs._1password.enable = true;
    };
  };
}
