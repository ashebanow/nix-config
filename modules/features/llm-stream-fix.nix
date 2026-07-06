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
          raw = self.rfile.read(length)
          try:
              body = json.loads(raw)
          except Exception:
              self.send_response(400)
              self.end_headers()
              self.wfile.write(b'{"error":"invalid json"}')
              return

          # Force non-streaming
          if body.get("stream"):
              body["stream"] = False

          data = json.dumps(body).encode("utf-8")
          url = f"{UPSTREAM}{self.path}"
          req = urllib.request.Request(
              url, data=data,
              headers={"Content-Type": "application/json"},
              method="POST",
          )
          try:
              with urllib.request.urlopen(req, timeout=600) as resp:
                  self.send_response(resp.status)
                  ct = resp.headers.get("Content-Type", "application/json")
                  self.send_header("Content-Type", ct)
                  self.end_headers()
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
              self.wfile.write(json.dumps({"error": str(e)}).encode())

  server = HTTPServer(("0.0.0.0", 8081), Handler)
  server.serve_forever()
        ''}
      '';
    in
    {
      config = lib.mkIf config.my.llm {
        systemd.services.llm-stream-fix = {
          description = "LLM streaming fix proxy";
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
