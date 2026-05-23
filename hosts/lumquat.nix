# Lumquat host configuration — AI server with LLM inference.
# GMKTec Evo X2 (Strix Halo) with AMD Ryzen AI Max and 128GB unified memory.
{
  config,
  ...
}: {
  # Host metadata
  my.hostName = "lumquat";

  # Enable features via capability flags
  my.base = true;
  my.baseUsername = "podman";
  my.baseTimezone = "America/Los_Angeles";

  # LLM serving — Qwen3-70B for coding, DeepSeek v4 for planning
  my.llm = true;
  my.llmModelStorage = "/var/lib/llm-models";

  # Remote access via Tailscale
  my.access = true;
  my.accessTailnetName = "lumquat";
  my.accessEnableSSH = true;
  my.accessEnableExitNode = false;
  my.accessEnableFallbackSSH = true;
  my.accessFallbackPort = 2222;

  # System monitoring via Cockpit
  my.monitoring = true;
  my.monitoringPort = 9090;
}
