# Lumquat host configuration — AI server with LLM inference.
# GMKTec Evo X2 (Strix Halo) with AMD Ryzen AI Max and 128GB unified memory.
{
  config,
  ...
}: {
  # Host metadata
  my.hostName = "lumquat";

  # Base configuration
  my.base = {
    username = "podman";
    timezone = "America/New_York";
    packages = [];
  };

  # LLM serving — Qwen3-70B for coding, DeepSeek v4 for planning
  my.llm = {
    enable = true;
    modelStorage = "/var/lib/llm-models";
    enableAperture = true;

    containers = [
      {
        name = "qwen-coder";
        model = "qwen3-70b";
        quant = "q5_k_m";
        port = 8080;
        ctxSize = 131072; # 128K context
      }
      {
        name = "deepseek";
        model = "deepseek-v4-moe";
        quant = "q4_k_m";
        port = 8081;
        ctxSize = 163840; # 160K context
      }
    ];
  };

  # Remote access via Tailscale
  my.access = {
    enable = true;
    tailnetName = "lumquat";
    enableSSH = true;
    enableExitNode = false;
    enableFallbackSSH = true;
    fallbackPort = 2222;
    enableFirewall = true;
  };

  # System monitoring via Cockpit
  my.monitoring = {
    enable = true;
    port = 9090;
  };
}
