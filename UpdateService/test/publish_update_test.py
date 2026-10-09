"""Publishing safeguards; uses disposable files and never calls Cloudflare."""
import importlib.util
import json
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import patch
import xml.etree.ElementTree as ET

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


def feed_with_notes(notes, notes_format=None):
    root = ET.fromstring(feed())
    description = ET.SubElement(root.find("./channel/item"), "description")
    description.text = notes
    if notes_format is not None:
        description.set(publisher.NS + "format", notes_format)
    return ET.tostring(root)


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

    def test_delayed_live_feed_succeeds_after_old_six_attempt_window(self):
        with tempfile.TemporaryDirectory() as temp, patch.object(publisher, "ROOT", Path(temp)):
            p = self.make_publisher(Path(temp))
            with patch.object(p, "run"), \
                    patch.object(p, "fetch_feed", side_effect=[b"previous"] * 7 + [feed()]) as fetch, \
                    patch.object(publisher, "download", return_value=b"archive") as download, \
                    patch.object(publisher.time, "sleep") as sleep, \
                    patch.object(p, "remember_published") as save:
                p.publish(b"previous")
            self.assertEqual(fetch.call_count, 8, "One pre-upload check plus seven confirmation attempts")
            self.assertEqual(sleep.call_count, 6)
            self.assertTrue(all(call.args == (2,) for call in sleep.call_args_list))
            download.assert_called_once_with("/download/PerformanceHUD-2.1-9.zip", publisher.MAX_ASSET)
            save.assert_called_once()

    def test_exhausted_confirmation_retries_do_not_record_success(self):
        for response in (b"previous", OSError("Service unavailable")):
            with self.subTest(response=response), tempfile.TemporaryDirectory() as temp, \
                    patch.object(publisher, "ROOT", Path(temp)):
                p = self.make_publisher(Path(temp))
                with patch.object(p, "run"), \
                        patch.object(p, "fetch_feed", side_effect=[b"previous"] + [response] * 30) as fetch, \
                        patch.object(publisher, "download") as download, \
                        patch.object(publisher.time, "sleep") as sleep, \
                        patch.object(p, "remember_published") as save:
                    with self.assertRaises(OSError if isinstance(response, OSError) else RuntimeError):
                        p.publish(b"previous")
                self.assertEqual(fetch.call_count, 31, "One pre-upload check plus thirty confirmation attempts")
                self.assertEqual(sleep.call_count, 29)
                download.assert_not_called()
                save.assert_not_called()
                self.assertTrue(p.deployment_attempted, "A failed confirmation must still report a possible live upload")

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

    def test_previous_local_notes_are_restored_when_feed_lost_description(self):
        for suffix in (".html", ".txt", ".md", ".markdown"):
            with self.subTest(suffix=suffix), tempfile.TemporaryDirectory() as temp, \
                    patch.object(publisher, "ROOT", Path(temp)):
                p = self.make_publisher(Path(temp))
                local = Path(temp) / "assets/packages/PerformanceHUD-2.1-9.zip"
                local.parent.mkdir(parents=True)
                local.write_bytes(b"archive")
                notes = "Previously published notes: 2 < 3 & café\n"
                local.with_suffix(suffix).write_text(notes, encoding="utf-8")
                with patch.object(p, "run"), patch.object(publisher, "download") as fetch:
                    p.restore_releases(feed())
                fetch.assert_not_called()
                restored = p.stage / "assets/packages" / local.with_suffix(suffix).name
                self.assertEqual(restored.read_text(encoding="utf-8"), notes)

    def test_previous_notes_can_be_recovered_from_verified_feed_without_local_files(self):
        cases = [(None, ".html", "<pre>Fixes &amp; improvements — café</pre>"),
                 ("plain-text", ".txt", "Literal <tags> & punctuation\n"),
                 ("markdown", ".md", "# Fixes\n\n- **Preserve** formatting\n"),
                 ("../../unsafe", ".html", "Unknown formats use Sparkle's HTML fallback")]
        for notes_format, suffix, notes in cases:
            with self.subTest(notes_format=notes_format), tempfile.TemporaryDirectory() as temp, \
                    patch.object(publisher, "ROOT", Path(temp)):
                p = self.make_publisher(Path(temp))
                data = feed_with_notes(notes, notes_format)
                with patch.object(p, "run"), patch.object(publisher, "download", return_value=b"archive") as fetch:
                    entries = p.restore_releases(data)
                fetch.assert_called_once_with("/download/PerformanceHUD-2.1-9.zip", publisher.MAX_ASSET)
                restored = p.stage / "assets/packages" / ("PerformanceHUD-2.1-9" + suffix)
                self.assertEqual(restored.read_text(encoding="utf-8"), notes)
                self.assertNotIn("notes", entries[0], "Embedded notes do not belong in the download allowlist")
                self.assertEqual((p.stage / "assets/appcast.xml").read_bytes(), data)

    def test_verified_feed_notes_take_priority_over_stale_local_notes(self):
        with tempfile.TemporaryDirectory() as temp, patch.object(publisher, "ROOT", Path(temp)):
            p = self.make_publisher(Path(temp))
            local = Path(temp) / "assets/packages/PerformanceHUD-2.1-9.zip"
            local.parent.mkdir(parents=True)
            local.write_bytes(b"archive")
            local.with_suffix(".html").write_text("Stale local notes")
            with patch.object(p, "run"), patch.object(publisher, "download") as fetch:
                p.restore_releases(feed_with_notes("Signed **markdown** notes", "markdown"))
            fetch.assert_not_called()
            packages = p.stage / "assets/packages"
            self.assertEqual((packages / "PerformanceHUD-2.1-9.md").read_text(), "Signed **markdown** notes")
            self.assertFalse((packages / "PerformanceHUD-2.1-9.html").exists(),
                             "A stale HTML companion would override the restored Markdown")

    def test_external_release_notes_are_not_downloaded(self):
        with tempfile.TemporaryDirectory() as temp, patch.object(publisher, "ROOT", Path(temp)):
            p = self.make_publisher(Path(temp))
            root = ET.fromstring(feed())
            ET.SubElement(root.find("./channel/item"), publisher.NS + "releaseNotesLink").text = \
                "https://example.com/untrusted.html"
            with patch.object(p, "run"), patch.object(publisher, "download", return_value=b"archive") as fetch:
                p.restore_releases(ET.tostring(root))
            fetch.assert_called_once_with("/download/PerformanceHUD-2.1-9.zip", publisher.MAX_ASSET)
            self.assertEqual([path.name for path in (p.stage / "assets/packages").iterdir()],
                             ["PerformanceHUD-2.1-9.zip"])


if __name__ == "__main__":
    unittest.main()
