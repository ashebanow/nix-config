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
        antigravity-cli # Google's AI TUI agent client — may be unmaintained/dead upstream
        charm
        cmux # agent-aware tmux-like terminal built on Ghostty
        crush
        deja
        llmfit
        opencode
      ];
    };
  };
}
