  my.modules.nixos.llm-dev = {
    lib,
    pkgs,
    config,
    ...
  }: let
    cfg = config.my;
  in {
    config = lib.mkIf cfg.llm-dev{
    environment.systemPackages = with pkgs; [
        pi-coding-agent
      ];
    };
  };
