#!/usr/bin/env python3
"""Prepare signed update assets locally. Does not deploy or publish a release."""
import argparse
import hashlib
import html
import json
import os
from pathlib import Path
import plistlib
import re
import shutil
import subprocess
import tempfile
import xml.etree.ElementTree as ET
from urllib.parse import urlparse, unquote

ROOT = Path(__file__).resolve().parent
BASE = "https://performancehud-updates.unturneded7.workers.dev"
KEY_ACCOUNT = "PerformanceHUD-Updates"
PUBLIC_KEY = "BHm+yGOdxJQspqx+vuPUIye0zWmnELuUrmFjbjg5Cfg="
MAX_ASSET = 25 * 1024 * 1024


def run(*args):
    result = subprocess.run([str(a) for a in args], text=True, capture_output=True)
    if result.returncode:
        raise SystemExit(f"{Path(args[0]).name} failed:\n{result.stdout}{result.stderr}")
    return result.stdout.strip()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    mode = parser.add_mutually_exclusive_group(required=True)
    mode.add_argument("--app", type=Path, help="Exported, signed PerformanceHUD.app")
    mode.add_argument("--empty", action="store_true", help="Initialize a signed feed with no published updates")
    parser.add_argument("--sparkle-tools", type=Path, required=True, help="Sparkle distribution's bin directory")
    parser.add_argument("--notes", type=Path, help="Plain-text release notes to embed in the signed feed")
    args = parser.parse_args()
    tools = args.sparkle_tools.resolve()
    if run(tools / "generate_keys", "--account", KEY_ACCOUNT, "-p") != PUBLIC_KEY:
        raise SystemExit("Signing key does not match PerformanceHUD's public key.")
    assets = ROOT / "assets"
    manifest = ROOT / "src/releases.json"
    published = json.loads(manifest.read_text())
    if args.empty and published:
        raise SystemExit("Refusing to replace a populated release feed with an empty feed.")
    if args.empty and (assets / "appcast.xml").exists():
        raise SystemExit("An appcast already exists; initialization is only needed once.")
    for entry in published:
        package = assets / "packages" / entry["file"]
        if not package.is_file() or hashlib.sha256(package.read_bytes()).hexdigest() != entry["sha256"]:
            raise SystemExit(f"Restore the original local package before preparing another release: {entry['file']}")

    # Stage everything first, so a failed signing/archive step preserves the existing feed.
    with tempfile.TemporaryDirectory(prefix="PerformanceHUD-release-") as work:
        stage = Path(work) / "assets"
        if assets.exists():
            shutil.copytree(assets, stage)
        else:
            stage.mkdir()
        packages = stage / "packages"
        packages.mkdir(exist_ok=True)
        feed = stage / "appcast.xml"
        if args.empty:
            feed.write_text('<?xml version="1.0" encoding="utf-8"?>\n'
                '<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">'
                '<channel><title>PerformanceHUD updates</title>'
                '<link>https://github.com/zzoko/PerformanceHUD</link>'
                '<description>Official PerformanceHUD updates</description></channel></rss>\n')
        else:
            app = args.app.resolve()
            with (app / "Contents/Info.plist").open("rb") as f:
                info = plistlib.load(f)
            build, version = info["CFBundleVersion"], info["CFBundleShortVersionString"]
            if info.get("CFBundleIdentifier") != "andrei.PerformanceHUD":
                raise SystemExit("This is not a PerformanceHUD app bundle.")
            if not re.fullmatch(r"[0-9]+", build) or not re.fullmatch(r"[0-9]+(?:\.[0-9]+)*", version):
                raise SystemExit("Use a numeric release version and an increasing integer build number.")
            if published and int(build) <= max(int(r["build"]) for r in published):
                raise SystemExit("Increment CURRENT_PROJECT_VERSION before preparing a new update.")
            expected = {"SUPublicEDKey": PUBLIC_KEY, "SUFeedURL": BASE + "/appcast.xml",
                        "SURequireSignedFeed": True, "SUVerifyUpdateBeforeExtraction": True,
                        "SUSignedFeedFailureExpirationInterval": 0,
                        "SUEnableAutomaticChecks": False, "SUAllowsAutomaticUpdates": False,
                        "SUAutomaticallyUpdate": False, "SUEnableSystemProfiling": False}
            if any(info.get(k) != v for k, v in expected.items()):
                raise SystemExit("The exported app has incorrect updater configuration.")
            run("/usr/bin/codesign", "--verify", "--deep", "--strict", app)
            file = f"PerformanceHUD-{version}-{build}.zip"
            archive = packages / file
            if archive.exists():
                raise SystemExit("This build is already staged; use a new build number.")
            run("/usr/bin/ditto", "-c", "-k", "--sequesterRsrc", "--keepParent", app, archive)
            if archive.stat().st_size > MAX_ASSET:
                raise SystemExit("Archive exceeds Cloudflare's 25 MiB static-asset limit.")
            if args.notes:
                (packages / file.replace(".zip", ".html")).write_text(
                    "<pre>" + html.escape(args.notes.read_text()) + "</pre>")
            run(tools / "generate_appcast", "--account", KEY_ACCOUNT, "--maximum-deltas", "0",
                "--download-url-prefix", BASE + "/download/", "--embed-release-notes",
                "--link", "https://github.com/zzoko/PerformanceHUD", "-o", feed, packages)
        run(tools / "sign_update", "--account", KEY_ACCOUNT, feed)
        run(tools / "sign_update", "--account", KEY_ACCOUNT, "--verify", feed)
        entries = []
        ns = "{http://www.andymatuschak.org/xml-namespaces/sparkle}"
        for item in ET.parse(feed).getroot().findall("./channel/item"):
            enclosure = item.find("enclosure")
            url = urlparse(enclosure.attrib["url"])
            if url.scheme != "https" or url.netloc != urlparse(BASE).netloc or not url.path.startswith("/download/"):
                raise SystemExit("Unexpected archive URL in generated feed.")
            file = unquote(url.path.removeprefix("/download/"))
            if not re.fullmatch(r"PerformanceHUD-[A-Za-z0-9._-]+\.zip", file):
                raise SystemExit("Unexpected archive name in generated feed.")
            package = packages / file
            entries.append({"file": file,
                "build": item.findtext(ns + "version") or enclosure.get(ns + "version"),
                "version": item.findtext(ns + "shortVersionString") or enclosure.get(ns + "shortVersionString"),
                "sha256": hashlib.sha256(package.read_bytes()).hexdigest()})
        # Copy archives before atomically switching the feed and allowlist. Deploying
        # remains a separate explicit step after checking these prepared files.
        assets.mkdir(exist_ok=True)
        shutil.copytree(packages, assets / "packages", dirs_exist_ok=True)
        temporary_feed = assets / "appcast.xml.new"
        shutil.copy2(feed, temporary_feed)
        os.replace(temporary_feed, assets / "appcast.xml")
        temporary_manifest = manifest.with_suffix(".json.new")
        temporary_manifest.write_text(json.dumps(entries, indent=2) + "\n")
        os.replace(temporary_manifest, manifest)
    print(f"Prepared and verified {len(entries)} signed release(s). Nothing has been deployed.")


if __name__ == "__main__":
    main()
