# AI-agent CLI tools — Home Manager package list.
_: {
  my.modules.home-manager.cli-ai-tools = {
    lib,
    pkgs,
    config,
    ...
  }: {
    config = lib.mkIf config.my.cliAiTools {
      home.packages = with pkgs; [
        charm
        crush
        deja
        llmfit
        opencode
      ];
    };
  };
}
