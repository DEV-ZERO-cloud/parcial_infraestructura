"""
Servidor HTTP. El contenedor es stateless y no maneja credenciales ni secretos.

Rutas:
    GET /health   -> JSON con estado, versión y commit (para sondas y CI)
    GET /version  -> alias de /health
    GET /         -> interfaz web (app/static)
"""
import json
import os
import signal
import sys
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

STATIC_DIR = Path(__file__).parent / "static"
PORT = int(os.environ.get("PORT", "8080"))
COMMIT = os.environ.get("GIT_COMMIT", "dev")
APP_VERSION = "1.0.0"


class Handler(SimpleHTTPRequestHandler):
    server_version = "horus-tracker"
    sys_version = "" 

    def __init__(self, *args, **kwargs):
        super().__init__(*args, directory=str(STATIC_DIR), **kwargs)

    def end_headers(self):
        self.send_header("X-Content-Type-Options", "nosniff")
        self.send_header("X-Frame-Options", "DENY")
        self.send_header("Referrer-Policy", "no-referrer")
        self.send_header(
            "Content-Security-Policy",
            "default-src 'self'; style-src 'self' 'unsafe-inline' https://fonts.googleapis.com; "
            "font-src https://fonts.gstatic.com; img-src 'self' data:; "
            "script-src 'self'; frame-ancestors 'none'",
        )
        super().end_headers()

    def _json(self, payload, status=200):
        body = json.dumps(payload).encode()
        self.send_response(status)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Cache-Control", "no-store")
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self):
        path = self.path.split("?", 1)[0]
        if path in ("/health", "/version"):
            self._json({"status": "ok", "app": "horus-tracker",
                        "version": APP_VERSION, "commit": COMMIT})
        else:
            super().do_GET()

    def do_HEAD(self):
        path = self.path.split("?", 1)[0]
        if path in ("/health", "/version"):
            self.send_response(200)
            self.send_header("Content-Type", "application/json; charset=utf-8")
            self.end_headers()
        else:
            super().do_HEAD()

    def log_message(self, fmt, *args):
        sys.stdout.write("%s - %s\n" % (self.address_string(), fmt % args))
        sys.stdout.flush()


def main():
    server = ThreadingHTTPServer(("0.0.0.0", PORT), Handler)
    signal.signal(signal.SIGTERM, lambda *_: (_ for _ in ()).throw(KeyboardInterrupt()))
    print(f"horus-tracker {APP_VERSION} commit={COMMIT} escuchando en :{PORT}", flush=True)
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        server.server_close()


if __name__ == "__main__":
    main()
