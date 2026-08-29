# Transparent proxy that relays requests from LiteLLM to llama-server.
# Workaround for LiteLLM proxy bug: streaming handler truncates request
# bodies at ~12 KB when connecting directly. This proxy provides a clean
# relay — LiteLLM connects to :8081, proxy forwards to :8080 intact.
#
# LiteLLM → this proxy (8081) → llama-server (8080)
_: {
  my.modules.nixos.llm-stream-fix = {
    lib,
    pkgs,
    config,
    ...
  }: let
    proxyScript = pkgs.writeShellScript "llm-stream-fix" ''
      exec ${pkgs.python3}/bin/python3 ${pkgs.writeText "llm-stream-fix.py" ''
        import json
        import urllib.request
        from http.server import HTTPServer, BaseHTTPRequestHandler

        UPSTREAM = "http://127.0.0.1:8080"


        class Handler(BaseHTTPRequestHandler):
            def do_GET(self):
                if self.path == "/health":
                    self.send_response(200)
                    self.send_header("Content-Type", "application/json")
                    self.end_headers()
                    self.wfile.write(b'{"status":"ok"}')
                else:
                    self.send_response(404)
                    self.end_headers()

            def do_POST(self):
                length = int(self.headers.get("Content-Length", 0))
                body = self.rfile.read(length)
                ct = self.headers.get("Content-Type", "application/json")
                url = f"{UPSTREAM}{self.path}"
                req = urllib.request.Request(
                    url, data=body,
                    headers={"Content-Type": ct},
                    method="POST",
                )
                try:
                    with urllib.request.urlopen(req, timeout=600) as resp:
                        self.send_response(resp.status)
                        rct = resp.headers.get("Content-Type", ct)
                        self.send_header("Content-Type", rct)
                        self.end_headers()
                        # Relay streaming responses line-by-line (SSE),
                        # non-streaming as a single chunk.
                        if "text/event-stream" in rct:
                            for line in resp:
                                self.wfile.write(line)
                                self.wfile.flush()
                        else:
                            self.wfile.write(resp.read())
                except urllib.error.HTTPError as e:
                    self.send_response(e.code)
                    self.send_header("Content-Type", "application/json")
                    self.end_headers()
                    self.wfile.write(e.read())
                except Exception as e:
                    self.send_response(502)
                    self.send_header("Content-Type", "application/json")
                    self.end_headers()
                    self.wfile.write(
                        json.dumps({"error": str(e)}).encode()
                    )

        server = HTTPServer(("0.0.0.0", 8081), Handler)
        server.serve_forever()
      ''}
    '';
  in {
    config = lib.mkIf config.my.llm {
      systemd.services.llm-stream-fix = {
        description = "LLM relay proxy";
        after = ["podman-qwen-35b-a3b.service"];
        requires = ["podman-qwen-35b-a3b.service"];
        wantedBy = ["multi-user.target"];
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
