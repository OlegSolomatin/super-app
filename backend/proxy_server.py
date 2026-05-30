#!/usr/bin/env python3
"""Super-App proxy — serves Flutter web app and proxies API to super-app backend."""
import gzip
import json
from http.server import HTTPServer, BaseHTTPRequestHandler
from io import BytesIO
from pathlib import Path
from urllib.parse import urlparse
from urllib.request import Request, urlopen

# ── Super-App ──────────────────────────────────────────
FLUTTER_DIST = Path.home() / "workspace/super-app/app/build/web"
API_BASE = "http://localhost:8000"          # FastAPI backend
PORT = 8790

# ── Content Types ──────────────────────────────────────
CONTENT_TYPES = {
    ".html": "text/html",
    ".css": "text/css",
    ".js": "application/javascript",
    ".json": "application/json",
    ".png": "image/png",
    ".jpg": "image/jpeg",
    ".jpeg": "image/jpeg",
    ".svg": "image/svg+xml",
    ".ico": "image/x-icon",
    ".webp": "image/webp",
    ".woff2": "font/woff2",
    ".woff": "font/woff",
    ".ttf": "font/ttf",
    ".map": "application/json",
    ".dart": "text/plain",
}


class SuperAppProxy(BaseHTTPRequestHandler):
    def do_GET(self):
        parsed = urlparse(self.path)

        # ── API proxy (включая health и docs) ──────────
        if parsed.path.startswith("/api/") or parsed.path in ("/health", "/openapi.json", "/docs", "/redoc"):
            self._proxy(parsed, API_BASE)
            return

        # ── Serve static Flutter web app ────────────
        serve_path = parsed.path
        if serve_path in ("/", ""):
            serve_path = "/index.html"

        # SPA fallback — все неизвестные пути отдают index.html
        file_path = FLUTTER_DIST / serve_path.lstrip("/")
        if not (file_path.exists() and file_path.is_file() and
                file_path.resolve().is_relative_to(FLUTTER_DIST.resolve())):
            file_path = FLUTTER_DIST / "index.html"

        content = file_path.read_bytes()
        suffix = file_path.suffix
        ct = CONTENT_TYPES.get(suffix, "application/octet-stream")

        self.send_response(200)
        self.send_header("Content-Type", f"{ct}; charset=utf-8" if ct.startswith("text/") else ct)
        self.send_header("Access-Control-Allow-Origin", "*")
        self.send_header("Cache-Control", "no-store, no-cache, must-revalidate, max-age=0")
        self.send_header("Pragma", "no-cache")
        self.send_header("Expires", "0")
        self.end_headers()
        self.wfile.write(content)

    def do_POST(self):
        parsed = urlparse(self.path)
        if parsed.path.startswith("/api/"):
            self._proxy(parsed, API_BASE)
            return
        self.send_response(404)
        self.end_headers()

    def do_OPTIONS(self):
        self.send_response(200)
        self.send_header("Access-Control-Allow-Origin", "*")
        self.send_header("Access-Control-Allow-Methods", "GET, POST, PUT, PATCH, DELETE, OPTIONS")
        self.send_header("Access-Control-Allow-Headers", "Content-Type, Authorization")
        self.end_headers()

    def _proxy(self, parsed, api_base):
        url = f"{api_base}{parsed.path}"
        if parsed.query:
            url += f"?{parsed.query}"

        body = None
        content_length = int(self.headers.get("Content-Length", 0))
        if content_length > 0:
            body = self.rfile.read(content_length)

        req = Request(url, data=body, method=self.command)
        for key, val in self.headers.items():
            if key.lower() not in ("host", "content-length", "accept-encoding"):
                req.add_header(key, val)

        try:
            with urlopen(req, timeout=30) as resp:
                raw_body = resp.read()
                content_type = resp.headers.get("Content-Type", "application/json")
                content_encoding = resp.headers.get("Content-Encoding", "")

                if content_encoding == "gzip" or (len(raw_body) >= 2 and raw_body[:2] == b'\x1f\x8b'):
                    try:
                        raw_body = gzip.decompress(raw_body)
                    except Exception:
                        pass

                self.send_response(resp.status)
                self.send_header("Content-Type", content_type)
                self.send_header("Access-Control-Allow-Origin", "*")
                self.send_header("Cache-Control", "no-store, no-cache, must-revalidate, max-age=0")
                self.send_header("Pragma", "no-cache")
                self.send_header("Expires", "0")
                self.end_headers()
                self.wfile.write(raw_body)
        except Exception as e:
            self.send_response(502)
            self.send_header("Content-Type", "application/json; charset=utf-8")
            self.send_header("Access-Control-Allow-Origin", "*")
            self.end_headers()
            self.wfile.write(json.dumps({"error": str(e)}).encode())

    def log_message(self, format, *args):
        pass


if __name__ == "__main__":
    server = HTTPServer(("0.0.0.0", PORT), SuperAppProxy)
    print(f"🚀 Super-App proxy running on :{PORT} → Flutter web + {API_BASE}")
    server.serve_forever()
