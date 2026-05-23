# LLM module — Podman containers with GPU passthrough for LLM inference.
_: {
  my.modules.nixos.llm = {
    lib,
    pkgs,
    config,
    ...
  }: {
    config = lib.mkIf config.my.llm {
      # Quadlet-based container definitions directory
      systemd.tmpfiles.rules = [
        "d /etc/containers/systemd 0755 root root -"
        "d /var/lib/llm-models 0755 root root -"
      ];

      # Base environment for LLM containers
      environment.sessionVariables = {
        GPU_DEVICE = "/dev/dri";
      };
    };
  };
}
