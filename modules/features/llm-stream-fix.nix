# Tiny reverse proxy that converts streaming requests to non-streaming.
# Workaround for LiteLLM proxy bug: streaming handler truncates request
# bodies at ~12 KB. This proxy intercepts requests from LiteLLM, forces
# stream=false, and forwards to llama-server.
#
# LiteLLM → this proxy (8081) → llama-server (8080)
_: {
  my.modules.nixos.llm-stream-fix =
    {
      lib,
      pkgs,
      config,
      ...
    }:
    let
      proxyScript = pkgs.writePython3 "llm-stream-fix" {
        libraries = with pkgs.python3Packages; [
          flask
        ];
        flakeIgnore = [ "E501" ];
      } ''
        import json
        import flask
        import urllib.request

        app = flask.Flask(__name__)
        UPSTREAM = "http://127.0.0.1:8080"

        @app.route("/health", methods=["GET"])
        def health():
            return flask.jsonify({"status": "ok"})

        @app.route("/v1/<path:path>", methods=["POST"])
        def proxy(path):
            try:
                body = flask.request.get_json(force=True)
            except Exception:
                return flask.jsonify({"error": "invalid json"}), 400

            # Force non-streaming — LiteLLM proxy has a known bug where
            # streaming request bodies are truncated at ~12 KB.
            if body.get("stream"):
                body["stream"] = False

            url = f"{UPSTREAM}/v1/{path}"
            req = urllib.request.Request(
                url,
                data=json.dumps(body).encode("utf-8"),
                headers={"Content-Type": "application/json"},
                method="POST",
            )
            try:
                with urllib.request.urlopen(req, timeout=600) as resp:
                    return flask.Response(
                        resp.read(),
                        status=resp.status,
                        content_type=resp.headers.get("Content-Type", "application/json"),
                    )
            except urllib.error.HTTPError as e:
                return flask.Response(e.read(), status=e.code, content_type="application/json")
            except Exception as e:
                return flask.jsonify({"error": str(e)}), 502

        if __name__ == "__main__":
            app.run(host="0.0.0.0", port=8081)
      '';
    in
    {
      config = lib.mkIf config.my.llm {
        systemd.services.llm-stream-fix = {
          description = "LLM streaming fix proxy (forces non-streaming)";
          after = [ "podman-qwen-35b-a3b.service" ];
          requires = [ "podman-qwen-35b-a3b.service" ];
          wantedBy = [ "multi-user.target" ];
          serviceConfig = {
            Type = "simple";
            User = config.my.baseUsername;
            Restart = "always";
            RestartSec = "5";
          };
          script = "${proxyScript}";
        };
      };
    };
}
