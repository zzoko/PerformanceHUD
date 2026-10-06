"""Publishing safeguards; uses disposable files and never calls Cloudflare."""
import importlib.util
import json
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))
spec = importlib.util.spec_from_file_location("publish_update", ROOT / "publish_update.py")
publisher = importlib.util.module_from_spec(spec)
spec.loader.exec_module(publisher)


def feed(version="2.1", build="9", file="PerformanceHUD-2.1-9.zip"):
    return (f'<rss xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">'
            f'<channel><item><sparkle:version>{build}</sparkle:version>'
            f'<sparkle:shortVersionString>{version}</sparkle:shortVersionString>'
            f'<enclosure url="{publisher.BASE}/download/{file}" length="7" '
            f'sparkle:edSignature="test-signature"/></item></channel></rss>').encode()


class PublisherTests(unittest.TestCase):
    def test_build_increases_without_manual_project_edits(self):
        settings = {"MARKETING_VERSION": "2.1", "CURRENT_PROJECT_VERSION": "8"}
        self.assertEqual(publisher.next_build(settings, []), "8")
        self.assertEqual(publisher.next_build(settings, [{"version": "2.0", "build": "8"}]), "9")
        self.assertEqual(settings["CURRENT_PROJECT_VERSION"], "8")
        settings["CURRENT_PROJECT_VERSION"] = "20"
        self.assertEqual(publisher.next_build(settings, [{"version": "2.0", "build": "8"}]), "20")

    def test_older_marketing_version_is_rejected(self):
        settings = {"MARKETING_VERSION": "2.0", "CURRENT_PROJECT_VERSION": "20"}
        with self.assertRaisesRegex(RuntimeError, "older"):
            publisher.next_build(settings, [{"version": "2.1", "build": "9"}])
        self.assertEqual(publisher.version_tuple("2.0.0"), publisher.version_tuple("2.0"))
        self.assertGreater(publisher.version_tuple("2.10"), publisher.version_tuple("2.9"))

    def test_published_build_is_saved_for_both_xcode_configurations(self):
        with tempfile.TemporaryDirectory() as temp:
            project = Path(temp) / "project.pbxproj"
            project.write_text("CURRENT_PROJECT_VERSION = 8;\nMARKETING_VERSION = 2.1;\nCURRENT_PROJECT_VERSION = 8;\n")
            publisher.save_build_number(project, 9)
            self.assertEqual(project.read_text().count("CURRENT_PROJECT_VERSION = 9;"), 2)
            self.assertIn("MARKETING_VERSION = 2.1;", project.read_text())
            publisher.save_build_number(project, 7)
            self.assertEqual(project.read_text().count("CURRENT_PROJECT_VERSION = 9;"), 2)

    def test_feed_rejects_external_or_unsafe_archives(self):
        data = feed()
        self.assertEqual(publisher.feed_releases(data)[0]["build"], "9")
        self.assertEqual(publisher.feed_releases(b"<rss><channel/></rss>"), [])
        for bad in (data.replace(publisher.BASE.encode(), b"https://example.com"),
                    feed(file="../private.zip"), feed(file="PerformanceHUD-x.zip?query=1"),
                    feed(build="9b"), data.replace(b'length="7"', b'length="0"'),
                    data.replace(b'sparkle:edSignature="test-signature"', b"")):
            with self.assertRaises(RuntimeError):
                publisher.feed_releases(bad)

    def test_release_notes_are_for_exact_version(self):
        changelog = "# Changelog\n### v2.10\n- Later\n### v2.1 — in development\n- **New** update\n### v2.0\n- Old"
        self.assertEqual(publisher.release_notes(changelog, "2.1"), "- New update")
        self.assertEqual(publisher.release_notes(changelog, "2.2"), "")

    def make_publisher(self, root, dry_run=False):
        p = publisher.Publisher(dry_run)
        self.addCleanup(p.log.close)
        p.node = Path("node")
        p.wrangler = Path("wrangler.js")
        p.tools = Path("sparkle/bin")
        p.stage = root / "candidate"
        (p.stage / "assets/packages").mkdir(parents=True)
        (p.stage / "src").mkdir()
        (p.stage / "assets/appcast.xml").write_bytes(feed())
        (p.stage / "assets/packages/PerformanceHUD-2.1-9.zip").write_bytes(b"archive")
        (p.stage / "src/releases.json").write_text("[]\n")
        return p

    def test_dry_run_cannot_upload_or_change_published_assets(self):
        with tempfile.TemporaryDirectory() as temp, patch.object(publisher, "ROOT", Path(temp)):
            p = self.make_publisher(Path(temp), dry_run=True)
            with patch.object(p, "run") as run, patch.object(p, "fetch_feed") as fetch, \
                    patch.object(p, "remember_published") as save:
                p.publish(b"previous")
            self.assertEqual(run.call_count, 1)
            self.assertIn("--dry-run", run.call_args.args)
            fetch.assert_not_called()
            save.assert_not_called()
            self.assertFalse(p.deployment_attempted)

    def test_failed_package_check_never_reaches_upload(self):
        with tempfile.TemporaryDirectory() as temp, patch.object(publisher, "ROOT", Path(temp)):
            p = self.make_publisher(Path(temp))
            with patch.object(p, "run", side_effect=RuntimeError("check failed")) as run:
                with self.assertRaisesRegex(RuntimeError, "check failed"):
                    p.publish(b"previous")
            self.assertEqual(run.call_count, 1)
            self.assertFalse(p.deployment_attempted)

    def test_changed_live_release_never_gets_overwritten(self):
        with tempfile.TemporaryDirectory() as temp, patch.object(publisher, "ROOT", Path(temp)):
            p = self.make_publisher(Path(temp))
            with patch.object(p, "run") as run, patch.object(p, "fetch_feed", return_value=b"changed"):
                with self.assertRaisesRegex(RuntimeError, "changed during"):
                    p.publish(b"previous")
            self.assertEqual(run.call_count, 1)
            self.assertFalse(p.deployment_attempted)

    def test_success_requires_matching_live_feed_and_archive(self):
        with tempfile.TemporaryDirectory() as temp, patch.object(publisher, "ROOT", Path(temp)):
            p = self.make_publisher(Path(temp))
            with patch.object(p, "run") as run, \
                    patch.object(p, "fetch_feed", side_effect=[b"previous", feed()]), \
                    patch.object(publisher, "download", return_value=b"archive"), \
                    patch.object(p, "remember_published") as save:
                p.publish(b"previous")
            self.assertEqual(run.call_count, 2)
            self.assertIn("--dry-run", run.call_args_list[0].args)
            self.assertNotIn("--dry-run", run.call_args_list[1].args)
            save.assert_called_once()
            self.assertTrue(p.deployment_attempted)

    def test_bad_served_archive_does_not_record_success(self):
        with tempfile.TemporaryDirectory() as temp, patch.object(publisher, "ROOT", Path(temp)):
            p = self.make_publisher(Path(temp))
            with patch.object(p, "run"), patch.object(p, "fetch_feed", side_effect=[b"previous", feed()]), \
                    patch.object(publisher, "download", return_value=b"wrong"), \
                    patch.object(p, "remember_published") as save:
                with self.assertRaisesRegex(RuntimeError, "archive did not match"):
                    p.publish(b"previous")
            save.assert_not_called()

    def test_previous_archive_can_be_restored_and_verified(self):
        with tempfile.TemporaryDirectory() as temp, patch.object(publisher, "ROOT", Path(temp)):
            p = self.make_publisher(Path(temp))
            with patch.object(p, "run") as run, patch.object(publisher, "download", return_value=b"archive") as fetch:
                entries = p.restore_releases(feed())
            fetch.assert_called_once()
            self.assertIn("--verify", run.call_args.args)
            self.assertEqual(run.call_args.args[-1], "test-signature")
            self.assertEqual(entries[0]["sha256"], publisher.hashlib.sha256(b"archive").hexdigest())
            self.assertEqual(json.loads((p.stage / "src/releases.json").read_text()), entries)


if __name__ == "__main__":
    unittest.main()
