#!/usr/bin/env python3
"""Exercise real Sparkle against the Worker locally using disposable app bundles.

Needs macOS UI/session access, Xcode, Sparkle's distribution, and installed Worker
dependencies. Never launches, replaces, or changes preferences for PerformanceHUD.
The generated signing key is only for these test bundles, not the release key.
"""
import argparse
import json
import os
from pathlib import Path
import plistlib
import shutil
import socket
import subprocess
import tempfile
import time
import urllib.error
import urllib.request
import uuid
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[1]
NS = "http://www.andymatuschak.org/xml-namespaces/sparkle"


def run(*args, **kwargs):
    result = subprocess.run([str(a) for a in args], text=True, capture_output=True, **kwargs)
    if result.returncode:
        raise RuntimeError(f"{Path(args[0]).name}: {result.stdout}{result.stderr}")
    return result.stdout.strip()


def check_case(binary, sparkle, framework, wrangler, case):
    root = Path(tempfile.mkdtemp(prefix="PerformanceHUD-updater-test-", dir="/tmp"))
    with socket.socket() as s:
        s.bind(("127.0.0.1", 0))
        port = s.getsockname()[1]
    base = f"http://127.0.0.1:{port}"
    bundle_id = "andrei.PerformanceHUD.UpdaterTest." + uuid.uuid4().hex
    installed = root / "installed/UpdaterFixture.app"
    contents = installed / "Contents"
    (contents / "MacOS").mkdir(parents=True)
    (contents / "Frameworks").mkdir()
    shutil.copy2(binary, contents / "MacOS/UpdaterFixture")
    shutil.copytree(framework, contents / "Frameworks/Sparkle.framework", symlinks=True)
    seed = root / "test-signing-key"
    public_key = run(contents / "MacOS/UpdaterFixture", "--generate-test-key", seed)
    info = {
        "CFBundleIdentifier": bundle_id, "CFBundleName": "UpdaterFixture",
        "CFBundleExecutable": "UpdaterFixture", "CFBundlePackageType": "APPL",
        "CFBundleVersion": "1", "CFBundleShortVersionString": "1.0", "LSUIElement": True,
        "LSMinimumSystemVersion": "27.0", "FixtureRoot": str(root), "FixtureCase": case,
        "SUFeedURL": base + "/appcast.xml", "SUPublicEDKey": public_key,
        "SUEnableAutomaticChecks": False, "SUAllowsAutomaticUpdates": False,
        "SUAutomaticallyUpdate": False, "SUEnableSystemProfiling": False,
        "SUVerifyUpdateBeforeExtraction": True, "SURequireSignedFeed": True,
        "SUSignedFeedFailureExpirationInterval": 0,
        "NSAppTransportSecurity": {"NSAllowsLocalNetworking": True},
    }
    with (contents / "Info.plist").open("wb") as f: plistlib.dump(info, f)
    run("/usr/bin/codesign", "--force", "--deep", "--sign", "-", installed)
    newer = root / "release/UpdaterFixture.app"
    shutil.copytree(installed, newer, symlinks=True)
    info.update(CFBundleVersion="2", CFBundleShortVersionString="2.0")
    with (newer / "Contents/Info.plist").open("wb") as f: plistlib.dump(info, f)
    run("/usr/bin/codesign", "--force", "--deep", "--sign", "-", newer)
    assets = root / "service/assets"
    (assets / "packages").mkdir(parents=True)
    file = "PerformanceHUD-test-2.zip"
    archive = assets / "packages" / file
    run("/usr/bin/ditto", "-c", "-k", "--sequesterRsrc", "--keepParent", newer, archive)
    signature = run(sparkle / "bin/sign_update", "--ed-key-file", seed, "-p", archive)
    ET.register_namespace("sparkle", NS)
    rss = ET.Element("rss", {"version": "2.0"})
    channel = ET.SubElement(rss, "channel")
    ET.SubElement(channel, "title").text = "Isolated updater test"
    if case != "empty":
        item = ET.SubElement(channel, "item")
        ET.SubElement(item, "title").text = "Disposable fixture 2.0"
        ET.SubElement(item, f"{{{NS}}}version").text = "2"
        ET.SubElement(item, f"{{{NS}}}shortVersionString").text = "2.0"
        ET.SubElement(item, f"{{{NS}}}minimumSystemVersion").text = "27.0"
        ET.SubElement(item, "enclosure", {"url": base + "/download/" + file,
            "type": "application/octet-stream", "length": str(archive.stat().st_size),
            f"{{{NS}}}edSignature": signature})
    feed = assets / "appcast.xml"
    ET.ElementTree(rss).write(feed, encoding="utf-8", xml_declaration=True)
    run(sparkle / "bin/sign_update", "--ed-key-file", seed, feed)
    if case == "bad-feed":
        feed.write_bytes(feed.read_bytes().replace(b"Disposable fixture", b"Altered fixture"))
    elif case == "bad-archive":
        data = bytearray(archive.read_bytes())
        data[len(data) // 2] ^= 1
        archive.write_bytes(data)
    elif case == "unavailable":
        feed.unlink()
    service = root / "service"
    shutil.copy2(ROOT / "UpdateService/src/worker.mjs", service / "worker.mjs")
    (service / "releases.json").write_text(json.dumps([{"file": file}]))
    (service / ".dev.vars").write_text("DOWNLOAD_SIGNING_SECRET=" + os.urandom(48).hex() + "\n")
    (service / "wrangler.jsonc").write_text(json.dumps({
        "name": "performancehud-updater-test", "main": "worker.mjs", "compatibility_date": "2026-10-06",
        "assets": {"directory": "assets", "binding": "ASSETS", "run_worker_first": True},
        "observability": {"enabled": False}
    }))
    env = {**os.environ, "WRANGLER_SEND_METRICS": "false", "WRANGLER_LOG_PATH": str(root / "wrangler-logs")}
    server_log = (root / "server.log").open("w")
    server = subprocess.Popen([str(wrangler), "dev", "--config", str(service / "wrangler.jsonc"),
        "--port", str(port), "--ip", "127.0.0.1", "--local"], cwd=service, env=env,
        stdout=server_log, stderr=subprocess.STDOUT)
    app = None
    try:
        deadline = time.monotonic() + 45
        while time.monotonic() < deadline:
            try:
                with urllib.request.urlopen(base, timeout=1) as r:
                    assert r.status == 200
                    break
            except (OSError, urllib.error.URLError):
                if server.poll() is not None: raise RuntimeError((root / "server.log").read_text())
                time.sleep(0.25)
        else: raise RuntimeError("Local Worker did not start: " + str(root))
        # Test actual static-asset routing, not only the stubbed unit-test binding.
        for path in ["/packages/" + file, "/download/" + file]:
            try: urllib.request.urlopen(base + path)
            except urllib.error.HTTPError as e: assert e.code == 403
            else: raise AssertionError("Public archive access was not blocked")
        app_log = (root / "app.log").open("w")
        def launch(phase=None):
            nonlocal app
            if app is not None: app.wait(timeout=10)
            (root / "result.txt").unlink(missing_ok=True)
            command = [str(contents / "MacOS/UpdaterFixture")]
            if phase: command.append(phase)
            app = subprocess.Popen(command, stdout=app_log, stderr=subprocess.STDOUT)
            deadline = time.monotonic() + 100
            while time.monotonic() < deadline and not (root / "result.txt").exists():
                if app.poll() not in (None, 0): raise RuntimeError(f"Fixture failed; inspect {root}")
                time.sleep(0.25)
            if not (root / "result.txt").exists():
                raise RuntimeError(f"Updater test timed out; inspect {root}")
            return (root / "result.txt").read_text()

        result = launch()
        events = (root / "events.log").read_text()
        if case == "valid":
            assert result == "INSTALLED; preferences preserved", events + result
            with (installed / "Contents/Info.plist").open("rb") as f: assert plistlib.load(f)["CFBundleVersion"] == "2"
        elif case == "empty":
            assert result == "NO UPDATE", events + result
        elif case == "settings":
            assert result == "SETTINGS saved monthly", result
            assert launch("restore") == "SETTINGS restored monthly; saved off"
            result = launch("verify-off")
            assert result == "SETTINGS retained off after relaunch", result
        elif case == "scheduled":
            assert result == "SCHEDULED menu reminder; no popup", result
            log = (root / "server.log").read_text()
            assert "GET /archive/" not in log, "Scheduled checks must not download the update"
        else:
            assert result.startswith("REJECTED:"), events + result
            assert "Ready to install" not in events, events
            with (installed / "Contents/Info.plist").open("rb") as f: assert plistlib.load(f)["CFBundleVersion"] == "1"
        print(f"PASS {case}: {result} ({root})", flush=True)
    finally:
        if app is not None and app.poll() is None:
            app.terminate()
            app.wait(timeout=10)
        server.terminate()
        try: server.wait(timeout=10)
        except subprocess.TimeoutExpired:
            server.kill()
            server.wait()
        server_log.close()
        seed.unlink(missing_ok=True)
        # Remove only this test's preference domain, never the actual app's domain.
        subprocess.run(["/usr/bin/defaults", "delete", bundle_id], capture_output=True)


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--sparkle", type=Path, required=True)
    cases = ["valid", "bad-feed", "bad-archive", "empty", "unavailable", "settings", "scheduled"]
    p.add_argument("--case", choices=cases)
    args = p.parse_args()
    sparkle = args.sparkle.resolve()
    framework = sparkle / "Sparkle.framework"
    if not framework.is_dir():
        framework = sparkle / "Sparkle.xcframework/macos-arm64_x86_64/Sparkle.framework"
    if not framework.is_dir() or not (sparkle / "bin/sign_update").is_file():
        p.error("--sparkle must point to the Sparkle distribution or resolved package artifact, including bin tools")
    with tempfile.TemporaryDirectory(prefix="phud-updater-compile-") as out:
        binary = Path(out) / "UpdaterFixture"
        run("xcrun", "swiftc", "-swift-version", "5", "-module-cache-path", Path(out) / "modules",
            "-parse-as-library", "-F", framework.parent, "-framework", "Sparkle",
            "-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks",
            ROOT / "PerformanceHUD/HUDUpdatePolicy.swift", ROOT / "PerformanceHUD/HUDUpdater.swift",
            ROOT / "Tests/UpdaterFixture.swift", "-o", binary)
        for case in ([args.case] if args.case else cases):
            check_case(binary, sparkle, framework, ROOT / "UpdateService/node_modules/.bin/wrangler", case)


if __name__ == "__main__":
    main()
