"""Refresh the RSSHub backend list and atomically reload its Caddy snippet."""

import fcntl
import ipaddress
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import tempfile
from html.parser import HTMLParser
from urllib.parse import urlsplit


class InstanceTable(HTMLParser):
    """Only the first cell links in the documentation's URL tables are instances."""

    def __init__(self):
        super().__init__()
        self.in_article = False
        self.in_table = False
        self.in_first_cell = False
        self.column = 0
        self.headers = []
        self.header = None
        self.links = []
        self.instances = []

    def handle_starttag(self, tag, attrs):
        attrs = dict(attrs)
        if tag == "div" and "vp-doc" in attrs.get("class", "").split():
            self.in_article = True
        if not self.in_article:
            return
        if tag == "table":
            self.in_table = True
            self.headers = []
            self.links = []
        elif self.in_table:
            if tag == "tr":
                self.column = 0
            elif tag == "th":
                self.header = ""
            elif tag == "td":
                self.column += 1
                self.in_first_cell = self.column == 1
            elif tag == "a" and self.in_first_cell and "href" in attrs:
                self.links.append(attrs["href"])

    def handle_data(self, data):
        if self.header is not None:
            self.header += data

    def handle_endtag(self, tag):
        if tag == "th" and self.header is not None:
            self.headers.append(self.header.strip().lower())
            self.header = None
        elif tag == "td":
            self.in_first_cell = False
        elif tag == "table" and self.in_table:
            if self.headers and self.headers[0] == "url":
                self.instances.extend(self.links)
            self.in_table = False


def parse_instances(document):
    parser = InstanceTable()
    parser.feed(document)
    if parser.instances:
        return parser.instances
    # The page uses this Vue component; use its url fields, not maintainerUrl.
    match = re.search(r"const\s+instances\s*=\s*\[(.*?)\];", document, re.S)
    if match:
        return re.findall(r"\burl\s*:\s*['\"](https?://[^'\"]+)['\"]", match[1])
    raise ValueError("No RSSHub instance table or source list found")


def backend_origin(value):
    url = urlsplit(value)
    if (
        url.scheme not in ("http", "https")
        or not url.hostname
        or url.username is not None
        or url.password is not None
        or url.path not in ("", "/")
        or url.query
        or url.fragment
        or re.search(r"[\s{}\"\\#]", value)
    ):
        raise ValueError(f"Backend must be an HTTP(S) origin: {value!r}")
    host = url.hostname
    if ":" in host:
        ipaddress.IPv6Address(host)
        host = f"[{host}]"
    elif not re.fullmatch(r"[A-Za-z0-9.-]+", host):
        raise ValueError(f"Invalid backend hostname: {host!r}")
    port = url.port if url.port is not None else (443 if url.scheme == "https" else 80)
    if not 1 <= port <= 65535:
        raise ValueError(f"Invalid backend port: {port}")
    return url.scheme, f"{host}:{port}", str(port)


def compatible_instances(values):
    result = []
    for value in values:
        try:
            backend_origin(value)
        except ValueError as error:
            print(f"Skipping public instance: {error}", file=sys.stderr)
        else:
            if value not in result:
                result.append(value)
    if not result:
        raise ValueError("No compatible public RSSHub origins found")
    return result


def render(backends, proxy):
    origins = list(dict.fromkeys(backend_origin(value) for value in backends))
    if not origins:
        return 'respond "RSSHub backends are not available yet" 503\n'
    http_ports = {port for scheme, _, port in origins if scheme == "http"}
    https_ports = {port for scheme, _, port in origins if scheme == "https"}
    if http_ports & https_ports:
        raise ValueError("HTTP and HTTPS backends must use different ports")
    lines = ["reverse_proxy " + " ".join(address for _, address, _ in origins) + " {"]
    lines += [
        "    header_up Host {http.reverse_proxy.upstream.hostport}",
        "    header_up -X-Forwarded-*",
        "    header_up -Via",
        "    health_uri /healthz",
        "    health_interval 5m",
        "    health_timeout 10s",
        "    health_status 200",
        "    health_body ok",
        "    lb_policy round_robin",
        "    fail_duration 120s",
        "    max_fails 2",
        "    unhealthy_latency 18s",
        "    unhealthy_status 3xx 4xx 5xx",
        "    lb_try_duration 120s",
        "    lb_retry_match method GET HEAD",
        "    transport http {",
    ]
    if https_ports:
        lines.append("        tls")
        if http_ports:
            lines.append("        tls_except_ports " + " ".join(sorted(http_ports)))
    if proxy is not None:
        url = urlsplit(proxy)
        if url.scheme not in ("http", "https", "socks5", "socks5h") or not url.hostname:
            raise ValueError("Unsupported proxy URL")
        lines.append("        network_proxy url " + json.dumps(proxy))
    lines += [
        "        dial_timeout 3s",
        "        response_header_timeout 15s",
        "        read_timeout 20s",
        "        write_timeout 20s",
        "    }",
        "}",
    ]
    return "\n".join(lines) + "\n"


def fetch(settings, url):
    command = [
        settings["curl"], "--fail", "--silent", "--show-error", "--location",
        "--connect-timeout", "10", "--max-time", "30",
        "--proto", "=http,https", "--proto-redir", "=http,https",
    ]
    # An unset option means direct access, independently of inherited proxy env.
    command += ["--proxy", settings["proxy"] or ""]
    return subprocess.run(command + [url], check=True, capture_output=True).stdout.decode()


def discover(settings):
    for url in (settings["sourceUrl"], settings["fallbackSourceUrl"]):
        if url is None:
            continue
        try:
            instances = compatible_instances(parse_instances(fetch(settings, url)))
        except (ValueError, UnicodeError, subprocess.CalledProcessError) as error:
            print(f"Cannot fetch instances from {url}: {error}", file=sys.stderr)
        else:
            print(f"Loaded {len(instances)} public origins from {url}", flush=True)
            return instances
    raise RuntimeError("All instance-list sources failed; keeping the last working list")


def atomic_write(path, content):
    descriptor, temporary = tempfile.mkstemp(prefix=".rsshub-", dir=path.parent)
    try:
        with os.fdopen(descriptor, "w") as stream:
            stream.write(content)
        os.chmod(temporary, 0o640)
        os.replace(temporary, path)
    finally:
        if os.path.exists(temporary):
            os.unlink(temporary)


def apply(settings, instances, reload):
    state = Path(settings["stateDir"])
    target = state / "upstreams.caddy"
    content = render(instances + settings["extraBackends"], settings["proxy"])
    previous = target.read_text() if target.exists() else None
    if content != previous:
        # Validate a standalone site first, before replacing the imported file.
        with tempfile.TemporaryDirectory(dir=state) as directory:
            candidate = Path(directory) / "Caddyfile"
            candidate.write_text("http://localhost:18080 {\n" + content + "}\n")
            subprocess.run(
                [settings["caddy"], "adapt", "--config", str(candidate),
                 "--adapter", "caddyfile", "--validate"],
                check=True, stdout=subprocess.DEVNULL,
            )
        atomic_write(target, content)
        try:
            if reload:
                subprocess.run(
                    [settings["caddy"], "reload", "--config", settings["caddyConfig"],
                     "--adapter", "caddyfile"], check=True, timeout=60,
                )
        except (subprocess.SubprocessError, OSError):
            if previous is not None:
                atomic_write(target, previous)
            else:
                target.unlink()
            raise
    if reload:
        atomic_write(state / "instances.json", json.dumps(instances) + "\n")


def main():
    settings = json.loads(Path(sys.argv[1]).read_text())
    state = Path(settings["stateDir"])
    state.mkdir(parents=True, exist_ok=True)
    with (state / "update.lock").open("w") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        if sys.argv[2] == "init":
            cache = state / "instances.json"
            instances = json.loads(cache.read_text()) if cache.exists() else []
            apply(settings, instances, reload=False)
        elif sys.argv[2] == "update":
            apply(settings, discover(settings), reload=True)
        else:
            raise ValueError("Expected init or update")


if __name__ == "__main__":
    main()
