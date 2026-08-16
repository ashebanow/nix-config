# Container/Docker ecosystem CLI tools — Home Manager package list.
_: {
  my.modules.home-manager.cli-container-tools = {
    lib,
    pkgs,
    config,
    ...
  }: {
    config = lib.mkIf config.my.cliContainerTools {
      home.packages = with pkgs; [
        dive
        docker
        docker-buildx
        docker-compose
        docker-credential-helpers
        kind
        lazydocker
        podman
        podman-compose
        # overmind
        # oxker excluded — nixpkgs' build runs a snapshot test that
        # asserts an "Alt" key-label string but gets "Option" on macOS
        # (platform-specific rendering the test snapshot wasn't updated
        # for), so the build fails. Kept on homebrew.brews instead.
        utm
      ];
    };
  };
}
