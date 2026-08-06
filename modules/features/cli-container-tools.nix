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
        colima
        dive
        docker
        docker-buildx
        docker-compose
        docker-credential-helpers
        kind
        lazydocker
        overmind
        oxker
      ];
    };
  };
}
