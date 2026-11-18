"""Optional integration test: CADDY_BIN=/path/to/caddy python3 -B -m unittest discover."""

from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import json
import os
from pathlib import Path
import shutil
import socket
import ssl
import subprocess
import tempfile
import threading
import time
import unittest
from unittest.mock import patch
from urllib.request import urlopen

import update


CADDY = os.environ.get("CADDY_BIN") or shutil.which("caddy")


def unused_port():
    with socket.socket() as listener:
        listener.bind(("127.0.0.1", 0))
        return listener.getsockname()[1]


@unittest.skipUnless(CADDY and shutil.which("openssl"), "Caddy and OpenSSL are required")
class CaddyTests(unittest.TestCase):
    def test_mixed_tls_health_routing_and_reload(self):
        with tempfile.TemporaryDirectory() as directory:
            state = Path(directory)
            cert = state / "cert.pem"
            key = state / "key.pem"
            subprocess.run([
                "openssl", "req", "-x509", "-newkey", "rsa:2048", "-nodes",
                "-keyout", str(key), "-out", str(cert), "-days", "1",
                "-subj", "/CN=localhost", "-addext", "subjectAltName=DNS:localhost",
            ], check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)

            class Backend(BaseHTTPRequestHandler):
                def do_GET(self):
                    healthy = self.server.healthy
                    self.send_response(200 if healthy else 503)
                    self.end_headers()
                    body = "ok" if self.path == "/healthz" else json.dumps({
                        "path": self.path, "host": self.headers["Host"],
                        "tls": isinstance(self.connection, ssl.SSLSocket),
                    })
                    self.wfile.write(body.encode() if healthy else b"unhealthy")

                def log_message(self, *_):
                    pass

            servers = []
            for healthy, tls in [(True, False), (True, True), (False, False)]:
                server = ThreadingHTTPServer(("127.0.0.1", 0), Backend)
                server.healthy = healthy
                if tls:
                    context = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
                    context.load_cert_chain(cert, key)
                    server.socket = context.wrap_socket(server.socket, server_side=True)
                threading.Thread(target=server.serve_forever, daemon=True).start()
                servers.append(server)
                self.addCleanup(server.server_close)
                self.addCleanup(server.shutdown)

            http_port, https_port, bad_port = [server.server_port for server in servers]
            backends = [f"http://127.0.0.1:{http_port}", f"https://localhost:{https_port}",
                        f"http://127.0.0.1:{bad_port}"]
            port, admin = unused_port(), unused_port()
            config = state / "Caddyfile"
            config_text = (
                f"{{\n admin 127.0.0.1:{admin}\n}}\n"
                f"http://127.0.0.1:{port} {{\n"
                f"handle_path /rsshub/* {{\n import {state}/upstreams.caddy\n}}\n}}\n"
            )
            config.write_text(config_text)
            settings = {"stateDir": str(state), "caddy": CADDY,
                        "caddyConfig": str(config), "extraBackends": [], "proxy": None}
            environment = {**os.environ, "SSL_CERT_FILE": str(cert),
                           "XDG_DATA_HOME": str(state / "data"),
                           "XDG_CONFIG_HOME": str(state / "config")}
            with patch.dict(os.environ, environment):
                update.apply(settings, backends, reload=False)
                with (state / "caddy.log").open("w") as log:
                    process = subprocess.Popen([CADDY, "run", "--config", str(config)],
                                               env=environment, stdout=log, stderr=log)
                    try:
                        endpoint = f"http://127.0.0.1:{port}/rsshub/test/cache?limit=3"
                        deadline = time.monotonic() + 10
                        while True:
                            try:
                                with urlopen(endpoint, timeout=1) as response:
                                    response.read()
                                break
                            except OSError:
                                if time.monotonic() >= deadline:
                                    self.fail((state / "caddy.log").read_text())
                                time.sleep(0.05)
                        time.sleep(0.2)
                        responses = []
                        for _ in range(6):
                            with urlopen(endpoint, timeout=3) as response:
                                responses.append(json.load(response))
                        self.assertEqual({item["tls"] for item in responses}, {True, False})
                        self.assertEqual({item["path"] for item in responses}, {"/test/cache?limit=3"})
                        self.assertEqual({item["host"] for item in responses},
                                         {f"127.0.0.1:{http_port}", f"localhost:{https_port}"})

                        previous = (state / "upstreams.caddy").read_text()
                        config.write_text("{ invalid_global_directive }\n")
                        with self.assertRaises(subprocess.CalledProcessError):
                            update.apply(settings, [backends[1]], reload=True)
                        self.assertEqual((state / "upstreams.caddy").read_text(), previous)
                        config.write_text(config_text)
                        update.apply(settings, [backends[1]], reload=True)
                        with urlopen(endpoint, timeout=3) as response:
                            self.assertTrue(json.load(response)["tls"])
                    finally:
                        process.terminate()
                        process.wait(timeout=10)


if __name__ == "__main__":
    unittest.main()
