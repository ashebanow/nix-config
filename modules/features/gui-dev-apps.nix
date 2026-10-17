# Development GUI apps — Home Manager package list.
{inputs, ...}: {
  my.modules.home-manager.gui-dev-apps = {
    lib,
    pkgs,
    config,
    ...
  }: {
    config = lib.mkIf config.my.guiDevApps {
      home.packages =
        (with pkgs; [
          charm
          crush
          temurin-bin
          vscode
          zed-editor
        ])
        # Zed Delta — upstream's flake packages Linux binaries only
        # (x86_64-linux, aarch64-linux); macOS installs Delta outside Nix.
        ++ lib.optionals pkgs.stdenv.hostPlatform.isLinux [
          inputs.delta.packages.${pkgs.stdenv.hostPlatform.system}.delta
        ];
    };
  };
}
