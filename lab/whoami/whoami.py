"""Stands in for 'the internet': answers every request with the caller's IP."""
import threading
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

class H(BaseHTTPRequestHandler):
    def do_GET(self):
        body = self.client_address[0].encode()
        self.send_response(200); self.send_header("Content-Length", str(len(body))); self.end_headers()
        self.wfile.write(body)
    def log_message(self, *a): pass

# 80/443: skipped by the V2Ray redirect; 8000: not. 443 (plain HTTP here) also tests the
# kill switch rule that lets the router itself reach any host on tcp/443.
for port in (8000, 443):
    threading.Thread(target=ThreadingHTTPServer(("", port), H).serve_forever, daemon=True).start()
ThreadingHTTPServer(("", 80), H).serve_forever()
