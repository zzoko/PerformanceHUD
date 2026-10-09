#!/usr/bin/env python3
"""Build, sign, check and publish the saved Xcode project in one operation.

Use --dry-run to exercise preparation without changing the live service or the
local published assets. No app is launched, and no Git commit or tag is created.
"""
import argparse
import fcntl
import hashlib
import json
import os
from pathlib import Path
import plistlib
import re
import shutil
import subprocess
import sys
import tempfile
import time
import urllib.request
import xml.etree.ElementTree as ET
from urllib.parse import urlparse

from prepare_release import BASE, KEY_ACCOUNT, MAX_ASSET, PUBLIC_KEY

ROOT = Path(__file__).resolve().parent
REPO = ROOT.parent
NS = "{http://www.andymatuschak.org/xml-namespaces/sparkle}"
HEADER = {"X-PerformanceHUD-Updater": "1", "Cache-Control": "no-cache",
          "User-Agent": "PerformanceHUD-Release-Publisher/1.0"}


def version_tuple(value):
    if not re.fullmatch(r"[0-9]+(?:\.[0-9]+)*", value):
        raise RuntimeError("Set a numeric app Version in Xcode, such as 2.1.")
    parts = [int(p) for p in value.split(".")]
    while len(parts) > 1 and parts[-1] == 0:
        parts.pop()
    return tuple(parts)


def next_build(settings, releases):
    version = settings["MARKETING_VERSION"]
    numeric_version = version_tuple(version)
    current = settings["CURRENT_PROJECT_VERSION"]
    if not re.fullmatch(r"[0-9]+", current):
        raise RuntimeError("Set an integer Build number in Xcode.")
    if releases and numeric_version < max(version_tuple(r["version"]) for r in releases):
        raise RuntimeError("This project's Version is older than the published app. Update it in Xcode first.")
    # Apply the number to this build first; save it to the project only after
    # publication succeeds, so failed attempts do not change source metadata.
    return str(max(int(current), max((int(r["build"]) for r in releases), default=0) + 1))


def save_build_number(project, build):
    text = project.read_text()
    pattern = r"(\bCURRENT_PROJECT_VERSION\s*=\s*)([0-9]+)(\s*;)"
    changed, count = re.subn(pattern, lambda match: match[1] + str(max(int(match[2]), int(build))) + match[3], text)
    if not count:
        raise RuntimeError("The update is live, but its build number could not be saved in the Xcode project.")
    if changed != text:
        temporary = project.with_suffix(".pbxproj.new")
        temporary.write_text(changed)
        os.replace(temporary, project)


def feed_releases(data):
    releases = []
    seen = set()
    for item in ET.fromstring(data).findall("./channel/item"):
        enclosure = item.find("enclosure")
        if enclosure is None:
            raise RuntimeError("The live update feed contains an incomplete release.")
        url = urlparse(enclosure.get("url", ""))
        file = url.path.removeprefix("/download/")
        if (url.scheme != "https" or url.netloc != urlparse(BASE).netloc
                or url.query or url.fragment or not url.path.startswith("/download/")
                or not re.fullmatch(r"PerformanceHUD-[A-Za-z0-9._-]+\.zip", file)
                or file in seen):
            raise RuntimeError("The live update feed contains an unexpected archive URL.")
        build = item.findtext(NS + "version") or enclosure.get(NS + "version", "")
        version = item.findtext(NS + "shortVersionString") or enclosure.get(NS + "shortVersionString", "")
        length = int(enclosure.get("length", "0"))
        signature = enclosure.get(NS + "edSignature")
        version_tuple(version)
        if not re.fullmatch(r"[0-9]+", build) or not signature or not 0 < length <= MAX_ASSET:
            raise RuntimeError("The live update feed contains invalid release metadata.")
        seen.add(file)
        release = dict(file=file, build=build, version=version, length=length, signature=signature)
        description = item.find("description")
        if description is not None:
            release["notes"] = (description.get(NS + "format", "html"), description.text or "")
        releases.append(release)
    return releases


class SameOriginRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, request, fp, code, msg, headers, newurl):
        url = urlparse(newurl)
        if url.scheme != "https" or url.netloc != urlparse(BASE).netloc:
            raise RuntimeError("The update service redirected outside its expected address.")
        return super().redirect_request(request, fp, code, msg, headers, newurl)


def download(path, limit):
    request = urllib.request.Request(BASE + path, headers=HEADER)
    with urllib.request.build_opener(SameOriginRedirect()).open(request, timeout=45) as response:
        data = response.read(limit + 1)
    if len(data) > limit:
        raise RuntimeError("The update service returned a file larger than expected.")
    return data


def release_notes(changelog, version):
    lines = changelog.splitlines()
    for i, line in enumerate(lines):
        if re.match(r"^#{1,6}\s+v?" + re.escape(version) + r"(?:\s|$)", line):
            end = next((j for j in range(i + 1, len(lines)) if re.match(r"^#{1,6}\s", lines[j])), len(lines))
            # Notes are embedded as plain text, so remove Markdown emphasis.
            return "\n".join(lines[i + 1:end]).strip().replace("**", "")
    return ""


class Publisher:
    def __init__(self, dry_run=False):
        self.dry_run = dry_run
        self.staging = ROOT / "staging"
        self.staging.mkdir(exist_ok=True)
        self.log_path = self.staging / "publish.log"
        self.log = self.log_path.open("w")
        self.env = {**os.environ, "WRANGLER_SEND_METRICS": "false"}
        self.node = None
        self.tools = None
        self.stage = None
        self.deployment_attempted = False

    def run(self, *args, cwd=None):
        args = [str(a) for a in args]
        self.log.write("\n> " + " ".join(args) + "\n")
        self.log.flush()
        with tempfile.TemporaryFile(mode="w+") as output:
            result = subprocess.run(args, cwd=cwd or REPO, env=self.env,
                                    stdout=output, stderr=subprocess.STDOUT, text=True)
            output.seek(0)
            text = output.read()
        self.log.write(text)
        self.log.flush()
        if result.returncode:
            raise RuntimeError(f"{Path(args[0]).name} failed. Details: {self.log_path}")
        return text.strip()

    def setup(self):
        candidates = [shutil.which("node"), "/opt/homebrew/opt/node@22/bin/node",
                      "/opt/homebrew/bin/node", "/usr/local/opt/node@22/bin/node", "/usr/local/bin/node"]
        for candidate in candidates:
            if candidate and Path(candidate).is_file():
                if int(self.run(candidate, "-p", "process.versions.node.split('.')[0]")) >= 22:
                    self.node = Path(candidate)
                    break
        if self.node is None:
            raise RuntimeError("One-time setup: install Node 22 or later (brew install node@22), then try again.")
        self.env["PATH"] = str(self.node.parent) + os.pathsep + self.env.get("PATH", "/usr/bin:/bin")
        self.wrangler = ROOT / "node_modules/wrangler/bin/wrangler.js"
        if not self.wrangler.is_file():
            raise RuntimeError("One-time setup: run pnpm install --frozen-lockfile inside UpdateService.")
        developer = self.env.get("DEVELOPER_DIR") or self.run("/usr/bin/xcode-select", "-p")
        if not (Path(developer) / "usr/bin/xcodebuild").is_file():
            developer = "/Applications/Xcode.app/Contents/Developer"
        self.env["DEVELOPER_DIR"] = developer
        self.derived = self.staging / "DerivedData"
        self.xcode = ["/usr/bin/xcodebuild", "-quiet", "-project", REPO / "PerformanceHUD.xcodeproj",
                      "-scheme", "PerformanceHUD", "-configuration", "Release",
                      "-derivedDataPath", self.derived, "-destination", "generic/platform=macOS",
                      "-onlyUsePackageVersionsFromResolvedFile"]

    def fetch_feed(self, destination):
        data = download("/appcast.xml", 4 * 1024 * 1024)
        destination.write_bytes(data)
        self.run(self.tools / "sign_update", "--account", KEY_ACCOUNT, "--verify", destination)
        return data

    def restore_releases(self, data):
        """Use the signed live feed as authority, including after interrupted uploads."""
        packages = self.stage / "assets/packages"
        packages.mkdir(parents=True, exist_ok=True)
        (self.stage / "assets/appcast.xml").write_bytes(data)
        entries = []
        for release in feed_releases(data):
            file = release["file"]
            destination = packages / file
            local = ROOT / "assets/packages" / file
            if local.is_file():
                shutil.copy2(local, destination)
            else:
                destination.write_bytes(download("/download/" + file, MAX_ASSET))
            if destination.stat().st_size != release["length"]:
                raise RuntimeError(f"The saved archive has the wrong size: {file}")
            self.run(self.tools / "sign_update", "--account", KEY_ACCOUNT, "--verify",
                     destination, release["signature"])
            # generate_appcast removes descriptions unless companion notes exist.
            # Prefer the already-verified feed; local notes can recover releases
            # whose descriptions were dropped by an earlier publisher version.
            if "notes" in release:
                notes_format, notes = release["notes"]
                suffix = {"plain-text": ".txt", "markdown": ".md"}.get(notes_format, ".html")
                destination.with_suffix(suffix).write_text(notes, encoding="utf-8")
            else:
                for suffix in (".html", ".txt", ".md", ".markdown"):
                    local_notes = local.with_suffix(suffix)
                    if local_notes.is_file():
                        shutil.copy2(local_notes, destination.with_suffix(suffix))
                        break
            entries.append({key: release[key] for key in ("file", "build", "version")})
            entries[-1]["sha256"] = hashlib.sha256(destination.read_bytes()).hexdigest()
        (self.stage / "src/releases.json").write_text(json.dumps(entries, indent=2) + "\n")
        return entries

    def remember_published(self):
        # Preserve old archive bytes. A later run can recover them from the
        # verified live feed if the machine lost its local generated assets.
        assets = ROOT / "assets"
        assets.mkdir(exist_ok=True)
        shutil.copytree(self.stage / "assets/packages", assets / "packages", dirs_exist_ok=True)
        for source, destination in [(self.stage / "assets/appcast.xml", assets / "appcast.xml"),
                                    (self.stage / "src/releases.json", ROOT / "src/releases.json")]:
            temporary = destination.with_name(destination.name + ".new")
            shutil.copy2(source, temporary)
            os.replace(temporary, destination)
        releases = json.loads((self.stage / "src/releases.json").read_text())
        save_build_number(REPO / "PerformanceHUD.xcodeproj/project.pbxproj",
                          max(int(release["build"]) for release in releases))

    def publish(self, previous_feed):
        command = [self.node, self.wrangler, "deploy", "--config", self.stage / "wrangler.jsonc"]
        print("Checking the upload package…", flush=True)
        self.run(*command, "--dry-run", cwd=self.stage)
        if self.dry_run:
            print("\nDry run passed. Nothing was uploaded or published.", flush=True)
            return
        # Avoid overwriting a release another machine published during this build.
        if self.fetch_feed(self.stage / "before-upload.xml") != previous_feed:
            raise RuntimeError("The live release changed during this build. Run Publish Update again.")
        print("Uploading the update to Cloudflare…", flush=True)
        self.deployment_attempted = True
        self.run(*command, cwd=self.stage)
        expected = (self.stage / "assets/appcast.xml").read_bytes()
        for attempt in range(30):
            try:
                if self.fetch_feed(self.stage / "after-upload.xml") == expected:
                    break
            except (OSError, RuntimeError):
                if attempt == 29:
                    raise
            if attempt == 29:
                raise RuntimeError("Cloudflare accepted the upload, but its live feed is not confirmed yet.")
            time.sleep(2)
        # Verify the actual served ZIP, including its redirect/ticket route.
        latest = max(feed_releases(expected), key=lambda r: int(r["build"]))
        archive = download("/download/" + latest["file"], MAX_ASSET)
        if archive != (self.stage / "assets/packages" / latest["file"]).read_bytes():
            raise RuntimeError("The published archive did not match the signed release.")
        self.remember_published()
        print("\nUpdate published and verified. Users can now choose Check for updates.", flush=True)

    def execute(self):
        print("PerformanceHUD — " + ("Test publishing (no upload)" if self.dry_run else "Publish update"), flush=True)
        print("Using the saved project in " + str(REPO), flush=True)
        self.setup()
        print("Checking the update service and resolving build tools…", flush=True)
        self.run(*self.xcode, "-resolvePackageDependencies")
        self.tools = self.derived / "SourcePackages/artifacts/sparkle/Sparkle/bin"
        if self.run(self.tools / "generate_keys", "--account", KEY_ACCOUNT, "-p") != PUBLIC_KEY:
            raise RuntimeError("This Mac's update signing key does not match PerformanceHUD.")
        self.stage = Path(tempfile.mkdtemp(prefix="candidate-", dir=self.staging))
        shutil.copytree(ROOT / "src", self.stage / "src")
        for file in ("wrangler.jsonc", "prepare_release.py"):
            shutil.copy2(ROOT / file, self.stage / file)
        (self.stage / "node_modules").symlink_to(ROOT / "node_modules", target_is_directory=True)
        previous = self.fetch_feed(self.stage / "previous.xml")
        releases = self.restore_releases(previous)
        settings = json.loads(self.run(*self.xcode, "-showBuildSettings", "-json"))
        settings = next(item["buildSettings"] for item in settings if item["target"] == "PerformanceHUD")
        version = settings["MARKETING_VERSION"]
        build = next_build(settings, releases)
        print(f"Building PerformanceHUD {version} (build {build})…", flush=True)
        self.run(*self.xcode, "build", "ONLY_ACTIVE_ARCH=NO", "CURRENT_PROJECT_VERSION=" + build)
        source_app = self.derived / "Build/Products/Release/PerformanceHUD.app"
        app = self.stage / "PerformanceHUD.app"
        self.run("/usr/bin/ditto", source_app, app)
        with (app / "Contents/Info.plist").open("rb") as file:
            info = plistlib.load(file)
        if info["CFBundleVersion"] != build or info["CFBundleShortVersionString"] != version:
            raise RuntimeError("The built app's version did not match the requested release.")
        print("Checking and signing the update…", flush=True)
        self.run(self.node, "--test", *sorted((ROOT / "test").glob("*.test.mjs")), cwd=ROOT)
        self.run(sys.executable, "-m", "unittest", "discover", "-s", ROOT / "test", "-p", "*_test.py")
        self.run("/bin/sh", REPO / "Tests/run-update-policy-tests.sh")
        prepare = [sys.executable, self.stage / "prepare_release.py", "--app", app, "--sparkle-tools", self.tools]
        notes = release_notes((REPO / "docs/CHANGELOG.md").read_text(), version)
        if notes:
            notes_path = self.stage / "release-notes.txt"
            notes_path.write_text(notes)
            prepare.extend(["--notes", notes_path])
        self.run(*prepare, cwd=self.stage)
        self.publish(previous)
        print("\nFinished app (also usable for Ko-fi):\n" + str(app), flush=True)
        print("Release files:\n" + str(self.stage / "assets/packages"), flush=True)
        if not self.dry_run:
            # Finder makes the exact published app easy to reuse on Ko-fi.
            subprocess.run(["/usr/bin/open", "-R", str(app)], check=False)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--dry-run", action="store_true", help="Build and check without uploading anything")
    args = parser.parse_args()
    staging = ROOT / "staging"
    staging.mkdir(exist_ok=True)
    with (staging / "publish.lock").open("w") as lock:
        try:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError:
            print("Publish Update is already running. Check its other window.")
            return 1
        publisher = Publisher(args.dry_run)
        try:
            publisher.execute()
            return 0
        except (Exception, SystemExit) as error:
            if publisher.deployment_attempted:
                print("\nPublishing did not finish verification. The upload may already be live; check before retrying.")
            else:
                print("\nStopped before uploading. The live update service was not changed.")
            print(str(error))
            print("Details: " + str(publisher.log_path))
            if publisher.stage:
                print("Prepared files kept in: " + str(publisher.stage))
            return 1
        except KeyboardInterrupt:
            print("\nStopped. " + ("An upload may already be live." if publisher.deployment_attempted else "Nothing was uploaded."))
            return 130
        finally:
            publisher.log.close()


if __name__ == "__main__":
    sys.exit(main())
