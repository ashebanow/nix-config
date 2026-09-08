# Bifrost LLM gateway — replaces the LiteLLM proxy.
#
# Bifrost is a Go gateway; LiteLLM is Python. The switch is specifically to
# escape the streaming-body truncation that forced clients to disable
# streaming, and the occasional hangs the relay workaround never fixed.
#
# Runs as a podman-compose stack (compose/llm/bifrost-compose.yml) whose
# gateway container shares a Tailscale sidecar's network namespace, so nothing
# is published on the host. Served at https://ai.fluffy-walleye.ts.net —
# named for its function, so a future gateway swap does not move the endpoint.
#
# Secrets (bifrost scope: BIFROST_TS_AUTHKEY for the sidecar; DEEPSEEK_API_KEY,
# ANTHROPIC_API_KEY, MINIMAX_API_KEY for the remote providers) are resolved from
# BWS via secretspec at start. Values live only in the process environment;
# config.json references the provider keys by name (env.<VAR>), never by value.
# Compose + config are symlinked to /etc/bifrost via tmpfiles below.
#
# Gated behind my.bifrostServe, separate from my.llmServe, so bifrost and
# LiteLLM can run side by side until the cutover completes.
#
# The sidecar joins the `llm-internal` bridge (podman-network-llm-internal
# .service, in llm.nix) and bifrost reaches llama-server at `qwen-35b-a3b:8080`
# on it — not over the tailnet. Two tailnet nodes on one host can't hole-punch,
# so that hop is DERP-relayed and truncates request bodies over ~5 KB
# (BOX-140). host.containers.internal isn't an option: bifrost's SSRF guard
# hard-blocks link-local (169.254.x). RFC1918 over the bridge + the provider's
# allow_private_network flag is the fix.
_: {
  my.modules.nixos.bifrost = {
    lib,
    pkgs,
    config,
    ...
  }: {
    config = lib.mkIf config.my.bifrostServe {
      systemd.tmpfiles.rules = [
        "d /etc/bifrost 0755 root root -"
        "L+ /etc/bifrost/compose.yml - - - - ${../../compose/llm/bifrost-compose.yml}"
        "L+ /etc/bifrost/config.json - - - - ${../../compose/llm/bifrost-config.json}"
      ];

      systemd.services.bifrost-compose = {
        description = "Bifrost LLM gateway compose stack";
        after = ["network-online.target" "podman-network-llm-internal.service"];
        wants = ["network-online.target"];
        requires = ["podman-network-llm-internal.service"];
        wantedBy = ["multi-user.target"];
        # The unit text never changes when only the symlinked compose/config
        # content does, so without this a rebuild leaves the old stack running.
        # A change here re-runs ExecStop (`down`, no -v) + ExecStart; the named
        # data volume — and the request logs in it — survive (BOX-133).
        restartTriggers = [
          "${../../compose/llm/bifrost-compose.yml}"
          "${../../compose/llm/bifrost-config.json}"
        ];
        path = [
          pkgs.podman
          pkgs.podman-compose
          pkgs.secretspec
          pkgs.bws
        ];
        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = "yes";
          User = config.my.baseUsername;
          Environment = [
            "SECRETSPEC_FILE=${config.my.secretspecManifest}"
            "SECRETSPEC_PROVIDER=bws-service"
          ];
          LoadCredential = [
            "access_token:${config.my.bwsAccessTokenFile}"
          ];
          ExecStart = pkgs.writeShellScript "bifrost-compose-start" ''
            set -e
            export XDG_RUNTIME_DIR="/run/user/$(id -u)"
            # secretspec injects the bifrost scope (BIFROST_TS_AUTHKEY,
            # DEEPSEEK_API_KEY, ANTHROPIC_API_KEY, MINIMAX_API_KEY) into this
            # environment; podman-compose substitutes them in compose.yml.
            exec ${pkgs.secretspec}/bin/secretspec run -P production -S bifrost -- \
              ${pkgs.podman-compose}/bin/podman-compose -f /etc/bifrost/compose.yml up -d
          '';
          ExecStop = "${pkgs.podman-compose}/bin/podman-compose -f /etc/bifrost/compose.yml down";
        };
      };
    };
  };
}
