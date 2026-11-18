# RSSHub proxy

Import `inputs.kkkykin.nixosModules.rsshub-proxy` (also included in
`nixosModules.default`) and enable Caddy with the Caddyfile adapter:

```nix
services.rsshubProxy = {
  enable = true;
  virtualHost = ":80";
  pathPrefix = "/rsshub";
  extraBackends = [
    "http://127.0.0.1:1200"
    "https://rsshub.example.com"
  ];
  # Optional; omit or set null for direct connections.
  proxy = "http://127.0.0.1:1080";
  interval = "12h";
};
```

The timer downloads <https://docs.rsshub.app/guide/instances> shortly after boot
and every 12 hours. If fetching or parsing fails, it tries the official page's
`InstanceList.vue` source on GitHub. Set `fallbackSourceUrl = null` to disable
this fallback. Only URL-column links are used, excluding maintainer links.

The public origins and `extraBackends` are deduplicated. Caddy checks `/healthz`
every five minutes and balances requests among healthy backends, retaining
passive health checks and GET/HEAD retries. `proxy` applies both to list downloads
and backend traffic; it requires the Caddy `network_proxy url` module.

Only HTTP(S) origins are supported. Public instances hosted under a subpath
(e.g. `/rsshub`) are skipped with a journal message. HTTP and HTTPS origins must
use different ports, since Caddy's shared TLS transport uses `tls_except_ports`.

Updates validate the generated snippet and reload Caddy only when it changes.
A failed download, parse, validation or reload keeps the previous configuration.
State is stored in `/var/lib/rsshub-proxy`. Caddy startup regenerates its snippet
from cached public origins and the current Nix options without a network request.
Before the first update, only `extraBackends` are used; without extras, the route
returns 503 until an instance list is fetched.

Refresh manually with `systemctl start rsshub-proxy-update.service`, and inspect
results with `journalctl -u rsshub-proxy-update.service`.

Run the parser and update tests with
`python3 -B -m unittest discover -s modules/rsshub-proxy -p 'test_*.py'`.
Set `CADDY_BIN=/path/to/caddy` to also run the local HTTP/HTTPS integration test
(OpenSSL is required).
