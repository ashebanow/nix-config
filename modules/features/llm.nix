# LLM module — declarative podman containers for llama.cpp inference.
#
# Image: kyuz0/amd-strix-halo-toolboxes:rocm-10.0
#   - ROCm 10.0 (Fedora 44, AMD-supported gfx1151 SDK) — stable toolbox
#   - MTP (Multi-Token Prediction) merged into llama.cpp mainline (no -mtp fork)
#   - https://github.com/kyuz0/amd-strix-halo-toolboxes
#
# Model catalog: lib/models.nix (adapted from Doug Campos)
#   https://random.qmx.me/posts/2026/01/08/nixifying-local-llms/
#
# Critical Strix Halo flags (from toolboxes README):
#   -fa on       Flash attention (required to avoid crashes; newer llama-server expects on|off|auto)
#   --no-mmap    Disable mmap (required for stability)
_: {
  my.modules.nixos.llm =
    {
      lib,
      pkgs,
      config,
      ...
    }:
    let
      cfg = config.my;
      modelsDir = cfg.llmModelStorage;
      hfCacheDir = "${modelsDir}/huggingface-cache";
      modelsLib = import ../../lib/models.nix { inherit lib; };

      # Shared container options for all LLM containers
      baseOptions = [
        "--device"
        "/dev/dri"
        "--device"
        "/dev/kfd"
        "--group-add"
        "video"
        "--group-add"
        "render"
        "--security-opt"
        "seccomp=unconfined"
      ];

      # Base llama-server flags shared by all models
      baseFlags = [
        "-fa"
        "on" # Flash attention (required on Strix Halo, newer llama-server expects on|off|auto)
        "--no-mmap" # Required for Strix Halo stability
        "--metrics"
        "--timeout"
        "0" # Disable HTTP read timeout (default 600s causes connection teardown on long idle)
        "--cache-ram"
        "0" # Unified KV cache in VRAM — never save/clear to disk on idle (prevents forced re-processing)
      ];

      # Resolve model: Nix store path if promoted, null otherwise
      resolveModel =
        hfRef:
        modelsLib.fetchModel {
          inherit pkgs;
          inherit hfRef;
        };

      # Build container config for a single model
      mkContainer =
        name: modelCfg: extraConfig:
        let
          modelPath = resolveModel modelCfg.hf;
          isPromoted = modelPath != null;
          gguf = modelsLib.ggufs.${modelCfg.hf} or { };
          portStr = toString modelCfg.port;
          # Host-side publish for the *inference* port. A model entry carries
          # `port` for callers that want it (the generic /llm path did, before
          # BOX-138), and it is published only when the caller does not blank it
          # — see the qwen container below, which sets `ports = [ ]` so the model
          # is reachable only through the bifrost gateway. The metrics mapping is
          # added separately, *after* `extraConfig` is applied, so blanking the
          # inference port cannot silently take the metrics port with it. That
          # coupling is the bug this arrangement avoids: a plain `ports = [ ]`
          # override would have removed both.
          inferencePorts = [ "${portStr}:8080" ];

          # The loopback-only metrics publish (BOX-331). Bound to 127.0.0.1 in
          # the port mapping itself, so it is unreachable from anywhere but this
          # host — not on the LAN, not over the tailnet, not on the
          # `llm-internal` bridge. The right-hand side is always 8080 because
          # that is what `--port` below tells llama-server to serve on;
          # `metricsPort` is the *host* side and is what gets scraped.
          #
          # A second mapping on the same HTTP listener is how llama.cpp exposes
          # /metrics: there is no separate metrics listener, and `--metrics`
          # (in baseFlags) is what turns the endpoint on at all.
          metricsPorts = lib.optional (
            modelCfg ? metricsPort
          ) "127.0.0.1:${toString modelCfg.metricsPort}:8080";
        in
        {
          image = "docker.io/kyuz0/amd-strix-halo-toolboxes:rocm-10.0";
          ports = inferencePorts;
          autoStart = true;
          extraOptions = baseOptions;
          podman.user = cfg.baseUsername; # Run rootless as the podman user
          volumes = [
            "${hfCacheDir}:/root/.cache/huggingface"
          ]
          ++ (
            if isPromoted then
              [ "${modelPath}:/models/${gguf.file}:ro" ]
            else
              [ "${modelsDir}:/root/.cache/llama.cpp" ]
          );
          cmd = [
            "llama-server"
          ]
          ++ (
            if isPromoted then
              [
                "-m"
                "/models/${gguf.file}"
              ]
            else
              [
                "-hf"
                modelCfg.hf
              ]
          )
          ++ [
            # Report the container name as the model id. Without it /v1/models
            # returns the GGUF repo id, which bifrost's key whitelist does not
            # name, so list_models filtered the local model out of every picker.
            "--alias"
            name
            "--host"
            "0.0.0.0"
            "--port"
            "8080"
            "-ngl"
            (toString modelCfg.ngl)
          ]
          ++ [
            "-c"
            (toString modelCfg.ctxSize)
          ]
          ++ (modelCfg.extraFlags or [ ])
          ++ baseFlags;
        }
        # The metrics publish is appended *after* the caller's overrides, so a
        # container that blanks `ports` to keep its inference port private still
        # has its metrics port published. It can be extended by a caller, never
        # replaced — which is the whole reason this is not a plain
        # `// extraConfig`.
        // {
          ports = (extraConfig.ports or inferencePorts) ++ metricsPorts;
        }
        // lib.removeAttrs extraConfig [ "ports" ];
    in
    {
      config = lib.mkIf cfg.llm {
        # ── Observability: one scrape target per model (BOX-331) ────────
        #
        # Declared here rather than in an observability module because this is
        # the module that owns the models: `lib/models.nix` is the catalog, and
        # a model with `metricsPort` set publishes that port above. Adding a
        # model to the catalog therefore adds its metrics with no second edit,
        # which is the property worth having — a per-model scrape target
        # written by hand beside a port written by hand is two things to forget.
        #
        # Guarded on `cfg.llm` by the enclosing mkIf *and* on there being a
        # metricsPort, so a model without one contributes nothing rather than
        # a target pointing at a port nothing publishes.
        #
        # `labels.model` is why the job name is per-model: it is what a
        # dashboard groups by, and it is the model's catalog name, which is also
        # its `--alias` and therefore what bifrost and Open WebUI call it.
        # `interval = "30s"` rather than the agent's 15 s default is deliberate:
        # see the note in llm.rules.yaml about llama.cpp's counters resetting on
        # each scrape, and change both together.
        my.observability.scrapeTargets = lib.mapAttrs' (
          name: modelCfg:
          lib.nameValuePair "llama-${name}" {
            address = "127.0.0.1:${toString modelCfg.metricsPort}";
            labels.model = name;
            interval = "30s";
          }
        ) (lib.filterAttrs (_: modelCfg: modelCfg ? metricsPort) modelsLib.models);

        # Alert rules for the containers and the inference endpoints. Declared
        # here because this module owns both; the observability host gathers
        # rule files from every agent host at build time (BOX-329), so a change
        # here means redeploying calamansi.
        my.observability.rules.llm = {
          files = [ ./llm.rules.yaml ];
          type = "metrics";
        };

        # The two dashboards (BOX-331): container health, and the inference
        # endpoints. Keys must be unique across all agent hosts — the
        # observability host asserts that — so `containers` is the risk and is
        # worth watching when a second host adds one.
        my.observability.dashboards = {
          containers = {
            path = ./containers.dashboard.json;
          };
          llm = {
            path = ./llm.dashboard.json;
          };
        };

        # Model storage (used as HF cache for unpromoted models)
        # hfCacheDir must be owned by the podman user so rootless containers can write to it
        systemd.tmpfiles.rules = [
          "d ${modelsDir} 0775 root root -"
          "d ${hfCacheDir} 0775 ${cfg.baseUsername} ${cfg.baseUsername} -"
          "d /etc/openwebui 0755 root root -"
          "L+ /etc/openwebui/compose.yml - - - - ${../../compose/llm/openwebui-compose.yml}"
        ];

        # Shared host-local podman bridge for container→container traffic on this
        # box (bifrost → llama-server, later openwebui → bifrost). Same-host
        # sidecar↔sidecar / sidecar↔host hops over the tailnet get relayed via
        # DERP (two nodes on one host can't hole-punch), and DERP mangles request
        # bodies over ~5 KB — see BOX-140. This bridge keeps that traffic on the
        # box; Tailscale still fronts every external door.
        #
        # Created out of band (rootless podman, user ${cfg.baseUsername}) so its
        # lifecycle isn't tied to any one compose stack; consumers order after it.
        systemd.services.podman-network-llm-internal = {
          description = "Create the llm-internal podman network";
          after = [
            "network-online.target"
            "linger-users.service"
          ];
          wants = [ "network-online.target" ];
          wantedBy = [ "multi-user.target" ];
          # Idempotent (the script is an `exists ||` guard), so re-running it on a
          # runtime change is free — and worth doing, because the network was
          # created BY the runtime that just got replaced.
          restartTriggers = [ config.virtualisation.podman.package ];
          # Use config.virtualisation.podman.package rather than pkgs.podman:
          # the NixOS podman module wraps podman with /run/wrappers/bin in PATH
          # so rootless podman can find the setuid newuidmap/newgidmap helpers.
          path = [ config.virtualisation.podman.package ];
          serviceConfig = {
            Type = "oneshot";
            RemainAfterExit = "yes";
            User = cfg.baseUsername;
            Environment = [ "HOME=/home/${cfg.baseUsername}" ];
          };
          script = ''
            export XDG_RUNTIME_DIR="/run/user/$(id -u)"
            podman network exists llm-internal \
              || podman network create llm-internal
          '';
        };

        # qwen also needs the network to exist before it starts.
        #
        # restartTriggers: make the podman package an explicit restart trigger.
        # `virtualisation.oci-containers` already restarts when the *generated
        # unit text* changes — and that text embeds podman in `Environment=PATH`,
        # so a runtime bump normally cycles the container on its own. This adds
        # the change as a first-class trigger anyway, because a switch must never
        # leave a container running on a runtime it was not started with: on the
        # 5.8.8 -> 6.1.4 bump the new podman could no longer talk to the running
        # container or to its own API socket, and nothing noticed.
        #
        # The cost is a model reload. That is acceptable here by decision: a
        # `just switch` is already deliberate, the GGUF is bind-mounted from the
        # Nix store / HF cache (so this is load time, not a re-download), and a
        # stale container on a new runtime is worse. Do not run a switch during
        # a live session against the local model.
        #
        # Not tied to the llama.cpp image digest or model flags: those already
        # arrive as a unit-text change.
        systemd.services.podman-qwen-35b-a3b = {
          after = [ "podman-network-llm-internal.service" ];
          requires = [ "podman-network-llm-internal.service" ];
          restartTriggers = [ config.virtualisation.podman.package ];
        };

        # Declarative podman containers
        virtualisation.oci-containers = {
          backend = "podman";
          containers = {
            # Qwen 3.6 35B-A3B UD-Q8_K_XL MTP — coding assistant (256K ctx, ~2x faster via MTP)
            qwen-35b-a3b = mkContainer "qwen-35b-a3b" modelsLib.models.qwen-35b-a3b {
              # No host publish for the *inference* port — reachable only as
              # `qwen-35b-a3b:8080` on the llm-internal bridge, i.e. only
              # through the bifrost gateway. (The host :8080 publish and the
              # direct `lumquat.ts.net/<model>` serve paths were retired with
              # LiteLLM in BOX-138.)
              #
              # This blanks the inference publish only: mkContainer re-adds the
              # loopback-only metrics mapping after applying this attrset, so
              # `127.0.0.1:<metricsPort>:8080` is still published. See the
              # `metricsPorts` binding in mkContainer.
              ports = [ ];
              extraOptions = baseOptions ++ [
                "--network"
                "llm-internal"
                "--health-cmd"
                "curl -sf http://127.0.0.1:8080/health"
                "--health-interval"
                "30s"
                "--health-retries"
                "60"
                "--health-start-period"
                "120s"
              ];
            };
          };
        };

        # Open WebUI — the one browser client, served at
        # https://openwebui.fluffy-walleye.ts.net via its Tailscale sidecar.
        # Talks to the bifrost gateway (my.bifrostServe, modules/features/
        # bifrost.nix) for every model. Secrets come from BWS via secretspec
        # (openwebui scope) at start; no .env or podman-secret readback.
        systemd.services.openwebui-compose = lib.mkIf config.my.llmServe {
          description = "Open WebUI compose stack";
          after = [ "network-online.target" ];
          wants = [ "network-online.target" ];
          wantedBy = [ "multi-user.target" ];
          # Without this a rebuild that only changes the symlinked compose content
          # (e.g. the gateway cutover, BOX-136) leaves the old stack running — the
          # unit text is unchanged. webui-data is a named volume; a restart is
          # down/up and does not touch it, so logins survive. (BOX-139.)
          #
          # The podman package is a trigger too: the stack's containers were
          # created by the runtime in `path` above, so a runtime bump must cycle
          # them for the same reason the model container is restarted. Cheap
          # here — Open WebUI has no model to reload.
          restartTriggers = [
            "${../../compose/llm/openwebui-compose.yml}"
            config.virtualisation.podman.package
          ];
          path = [
            config.virtualisation.podman.package
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
            ExecStart = pkgs.writeShellScript "openwebui-compose-start" ''
              set -e
              export XDG_RUNTIME_DIR="/run/user/$(id -u)"
              exec ${pkgs.secretspec}/bin/secretspec run -P production -S openwebui -- \
                ${pkgs.podman-compose}/bin/podman-compose -f /etc/openwebui/compose.yml up -d
            '';
            ExecStop = "${pkgs.podman-compose}/bin/podman-compose -f /etc/openwebui/compose.yml down";
          };
        };
      };
    };
}
