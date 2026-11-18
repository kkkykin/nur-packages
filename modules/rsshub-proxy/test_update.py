import json
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest.mock import patch

import update


class InstanceTests(unittest.TestCase):
    def test_only_url_cells_in_documentation_tables(self):
        document = """
        <nav><a href="https://unrelated.example">Sponsor</a></nav>
        <div class="vp-doc guide">
          <table><tr><th>URL</th><th>Maintainer</th></tr>
            <tr><td><a href="https://rsshub.app">Official</a></td>
              <td><a href="https://diygod.cc">DIYgod</a></td></tr></table>
          <table><tr><th>URL</th><th>Location</th><th>Maintainer</th></tr>
            <tr><td><a href="https://hub.example">Hub</a></td><td>US</td>
              <td><a href="https://maintainer.example">Maintainer</a></td></tr>
          </table>
          <table><tr><th>Other links</th></tr>
            <tr><td><a href="https://other.example">Other</a></td></tr></table>
        </div>
        """
        self.assertEqual(
            update.parse_instances(document), ["https://rsshub.app", "https://hub.example"]
        )

    def test_vue_fallback_does_not_include_maintainers(self):
        document = """
        const instances = [
          {url: 'https://hub.example', maintainerUrl: 'https://owner.example'},
          {url: 'https://other.example/'},
        ];
        """
        self.assertEqual(
            update.parse_instances(document), ["https://hub.example", "https://other.example/"]
        )
        with self.assertRaises(ValueError):
            update.parse_instances("<html>Cloudflare blocked this request</html>")

    def test_incompatible_public_urls_are_skipped(self):
        self.assertEqual(
            update.compatible_instances([
                "https://hub.example", "https://hub.example",
                "https://subpath.example/rsshub", "javascript:alert(1)",
                'https://hub.example/\n}\nrespond "injected"',
            ]), ["https://hub.example"]
        )
        for value in ["https://user:pass@hub.example", "https://hub.example/?token=x",
                      "https://hub.example/#fragment", "https://hub.example:0"]:
            with self.subTest(value=value), self.assertRaises(ValueError):
                update.backend_origin(value)

    def test_http_https_deduplication_and_tls(self):
        content = update.render([
            "https://hub.example", "https://hub.example/",
            "http://127.0.0.1:1200", "https://[::1]:8443",
        ], "http://127.0.0.1:10807")
        self.assertEqual(content.count("hub.example:443"), 1)
        self.assertIn("[::1]:8443", content)
        self.assertIn("tls_except_ports 1200", content)
        self.assertIn('network_proxy url "http://127.0.0.1:10807"', content)
        self.assertNotIn("network_proxy", update.render(["https://hub.example"], None))
        self.assertNotIn("        tls", update.render(["http://127.0.0.1:1200"], None))
        with self.assertRaises(ValueError):
            update.render(["https://hub.example", "http://local.example:443"], None)


class UpdateTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.state = Path(self.temporary.name)
        self.settings = {
            "stateDir": str(self.state),
            "caddy": "caddy",
            "caddyConfig": "/etc/caddy/caddy_config",
            "curl": "curl",
            "sourceUrl": "https://docs.rsshub.app/guide/instances",
            "fallbackSourceUrl": "https://source.example/InstanceList.vue",
            "extraBackends": [],
            "proxy": None,
        }

    def test_source_failure_uses_official_fallback(self):
        with patch.object(update, "fetch", side_effect=[
            subprocess.CalledProcessError(22, ["curl"]),
            "const instances = [{url: 'https://hub.example'}];",
        ]) as fetch:
            self.assertEqual(update.discover(self.settings), ["https://hub.example"])
            self.assertEqual(fetch.call_count, 2)

    def test_total_source_failure_preserves_files(self):
        target = self.state / "upstreams.caddy"
        target.write_text("previous working configuration")
        with patch.object(update, "fetch", return_value="<html>error page</html>"):
            with self.assertRaises(RuntimeError):
                update.discover(self.settings)
        self.assertEqual(target.read_text(), "previous working configuration")

    def test_validation_failure_leaves_previous_state_untouched(self):
        target = self.state / "upstreams.caddy"
        target.write_text("previous working configuration")
        with patch.object(update.subprocess, "run", side_effect=subprocess.CalledProcessError(1, "adapt")):
            with self.assertRaises(subprocess.CalledProcessError):
                update.apply(self.settings, ["https://hub.example"], reload=True)
        self.assertEqual(target.read_text(), "previous working configuration")
        self.assertFalse((self.state / "instances.json").exists())

    def test_reload_failure_rolls_back_snippet_and_cache(self):
        target = self.state / "upstreams.caddy"
        target.write_text("previous working configuration")
        cache = self.state / "instances.json"
        cache.write_text('["https://old.example"]\n')
        with patch.object(update.subprocess, "run", side_effect=[
            subprocess.CompletedProcess("adapt", 0), subprocess.CalledProcessError(1, "reload"),
        ]):
            with self.assertRaises(subprocess.CalledProcessError):
                update.apply(self.settings, ["https://hub.example"], reload=True)
        self.assertEqual(target.read_text(), "previous working configuration")
        self.assertEqual(json.loads(cache.read_text()), ["https://old.example"])

    def test_update_reloads_once_and_startup_uses_current_options(self):
        with patch.object(update.subprocess, "run") as run:
            update.apply(self.settings, ["https://hub.example"], reload=True)
            self.assertEqual(run.call_count, 2)
            self.assertEqual(run.call_args.args[0][1], "reload")
            update.apply(self.settings, ["https://hub.example"], reload=True)
            self.assertEqual(run.call_count, 2)
            self.settings["proxy"] = "http://127.0.0.1:10807"
            self.settings["extraBackends"] = ["http://127.0.0.1:1200"]
            update.apply(self.settings, ["https://hub.example"], reload=False)
            self.assertEqual(run.call_count, 3)
            self.assertIn("127.0.0.1:1200", (self.state / "upstreams.caddy").read_text())

    def test_first_start_without_backends_provides_503(self):
        with patch.object(update.subprocess, "run") as run:
            update.apply(self.settings, [], reload=False)
            self.assertEqual(run.call_count, 1)
        self.assertIn("503", (self.state / "upstreams.caddy").read_text())

    def test_unset_proxy_disables_inherited_environment_proxy(self):
        with patch.object(update.subprocess, "run", return_value=subprocess.CompletedProcess(
            "curl", 0, stdout=b"document"
        )) as run:
            update.fetch(self.settings, self.settings["sourceUrl"])
            command = run.call_args.args[0]
            self.assertEqual(command[command.index("--proxy") + 1], "")


if __name__ == "__main__":
    unittest.main()
