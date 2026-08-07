# Secrets/crypto/vuln-scanning CLI tools — Home Manager package list.
_: {
  my.modules.home-manager.cli-security-tools = {
    lib,
    pkgs,
    config,
    ...
  }: {
    config = lib.mkIf config.my.cliSecurityTools {
      home.packages = with pkgs; [
        age
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
        sops
        trivy
      ];
    };
  };
}
