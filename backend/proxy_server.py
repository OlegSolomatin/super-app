#!/usr/bin/env python3
"""Super-App proxy — serves Flutter web app and proxies API to super-app backend."""
import gzip
import json
import re
from http.server import HTTPServer, BaseHTTPRequestHandler, ThreadingHTTPServer
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
    ".mjs": "application/javascript",
    ".json": "application/json",
    ".wasm": "application/wasm",
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

# Files that can be gzip-compressed
GZIP_TYPES = {
    ".html", ".css", ".js", ".mjs", ".json", ".svg",
    ".wasm", ".ttf", ".woff", ".woff2",
}

# Files with content hashes in their URL → cache forever
IMMUTABLE_PATTERN = re.compile(
    r"\.(js|wasm|css|woff2?|ttf|png|svg|ico|webp)(\?.*)?$",
    re.IGNORECASE,
)


class SuperAppProxy(BaseHTTPRequestHandler):
    """Super-App proxy — serves Flutter web app and proxies API to FastAPI."""

    def _redirect_http_to_https(self) -> bool:
        """Redirect HTTP → HTTPS based on X-Forwarded-Proto header.
        Returns True if redirected (caller should stop), False otherwise."""
        proto = self.headers.get("X-Forwarded-Proto", "")
        if proto == "http":
            host = self.headers.get("Host", "pfumiko.ru")
            self.send_response(301)
            self.send_header("Location", f"https://{host}{self.path}")
            self.end_headers()
            return True
        return False

    def do_GET(self):
        if self._redirect_http_to_https():
            return
        parsed = urlparse(self.path)

        # ── API proxy (включая health, docs и auth) ──
        if parsed.path.startswith("/api/") or parsed.path.startswith("/auth/") or parsed.path in (
            "/health", "/openapi.json", "/docs", "/redoc"
        ):
            self._proxy(parsed, API_BASE)
            return

        # ── Serve static Flutter web app ────────────
        serve_path = parsed.path
        if serve_path in ("/", ""):
            serve_path = "/index.html"

        # SPA fallback
        file_path = FLUTTER_DIST / serve_path.lstrip("/")
        if not (file_path.exists() and file_path.is_file() and
                file_path.resolve().is_relative_to(FLUTTER_DIST.resolve())):
            file_path = FLUTTER_DIST / "index.html"

        content = file_path.read_bytes()
        suffix = file_path.suffix
        ct = CONTENT_TYPES.get(suffix, "application/octet-stream")

        # ── Caching ─────────────────────────────────────
        is_html = suffix == ".html"
        if is_html:
            # index.html — never cache (ensures new SW gets picked up)
            cache_control = "no-cache, no-store, must-revalidate"
        else:
            # Everything else (js, wasm, css, fonts, images) — cache 1 hour
            # Short TTL so Cloudflare edge cache doesn't get stale on rebuild
            cache_control = "public, max-age=3600"

        # ── Gzip compression ────────────────────────────
        accept_gzip = self.headers.get("Accept-Encoding", "")
        can_gzip = suffix in GZIP_TYPES and "gzip" in accept_gzip and len(content) > 1400

        self.send_response(200)
        self.send_header("Content-Type", f"{ct}; charset=utf-8" if ct.startswith("text/") else ct)
        self.send_header("Cache-Control", cache_control)
        self.send_header("Access-Control-Allow-Origin", "*")
        if can_gzip:
            compressed = gzip.compress(content, compresslevel=6)
            self.send_header("Content-Encoding", "gzip")
            self.send_header("Content-Length", str(len(compressed)))
            self.end_headers()
            self.wfile.write(compressed)
        else:
            self.send_header("Content-Length", str(len(content)))
            self.end_headers()
            self.wfile.write(content)

    def do_POST(self):
        if self._redirect_http_to_https():
            return
        parsed = urlparse(self.path)
        if parsed.path.startswith("/api/") or parsed.path.startswith("/auth/"):
            self._proxy(parsed, API_BASE)
            return
        self.send_response(404)
        self.end_headers()

    def do_OPTIONS(self):
        self.send_response(200)
        self.send_header("Access-Control-Allow-Origin", "*")
        self.send_header("Access-Control-Allow-Methods",
                         "GET, POST, PUT, PATCH, DELETE, OPTIONS")
        self.send_header("Access-Control-Allow-Headers",
                         "Content-Type, Authorization")
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

                if content_encoding == "gzip" or (
                    len(raw_body) >= 2 and raw_body[:2] == b'\x1f\x8b'
                ):
                    try:
                        raw_body = gzip.decompress(raw_body)
                    except Exception:
                        pass

                self.send_response(resp.status)
                self.send_header("Content-Type", content_type)
                self.send_header("Access-Control-Allow-Origin", "*")
                self.send_header("Cache-Control", "no-store, no-cache, must-revalidate")
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
    server = ThreadingHTTPServer(("0.0.0.0", PORT), SuperAppProxy)
    print(f"🚀 Super-App proxy running on :{PORT} → Flutter web + {API_BASE} (HTTP/1.1, gzip + caching)")
    server.serve_forever()
