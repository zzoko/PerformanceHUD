#!/usr/bin/env python3
"""Run the local test suites without installing the app or publishing a release."""
import argparse
import os
from pathlib import Path
import shlex
import shutil
import subprocess
import sys
import time

ROOT = Path(__file__).resolve().parents[1]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--list", action="store_true", help="show the selected commands without running them")
    parser.add_argument("--include-launchd", action="store_true",
                        help="also register a disposable current-user launchd job to test process cleanup")
    parser.add_argument("--include-updater", metavar="SPARKLE_DIRECTORY", type=Path,
                        help="also run the local Sparkle integration tests using this distribution")
    args = parser.parse_args()

    suites = [(path.stem.removeprefix("run-"), ["/bin/sh", str(path)])
              for path in sorted((ROOT / "Tests").glob("run-*-tests.sh"))]
    suites.append(("power-lifecycle-tests", [sys.executable, str(ROOT / "Tests/run-power-lifecycle-tests.py"),
                   "--include-launchd" if args.include_launchd else "--skip-launchd"]))
    suites.append(("worker-tests", ["node", "--test",
                   *map(str, sorted((ROOT / "UpdateService/test").glob("*.test.mjs")))]))
    suites.append(("publisher-tests", [sys.executable, str(ROOT / "UpdateService/test/publish_update_test.py")]))
    suites.append(("repository-activity-tests", [sys.executable, str(ROOT / ".github/tests/test_repository_activity.py")]))
    if args.include_updater:
        suites.append(("updater-integration-tests", [sys.executable, str(ROOT / "Tests/run-updater-integration.py"),
                       "--sparkle", str(args.include_updater.resolve())]))

    if args.list:
        for name, command in suites:
            print(f"{name}: {shlex.join(command)}")
        return 0

    if sys.platform != "darwin":
        parser.error("the full suite needs macOS; see Tests/README.md for the service-only commands")
    for tool in ("xcrun", "node"):
        if shutil.which(tool) is None:
            parser.error(f"{tool} is missing from PATH; see Tests/README.md for prerequisites")

    env = {**os.environ, "PYTHONDONTWRITEBYTECODE": "1"}
    failures = []
    began = time.monotonic()
    for index, (name, command) in enumerate(suites, 1):
        print(f"\n[{index}/{len(suites)}] {name}\n$ {shlex.join(command)}", flush=True)
        started = time.monotonic()
        try:
            result = subprocess.run(command, cwd=ROOT, env=env)
            code = result.returncode
        except OSError as error:
            print(f"Could not run {name}: {error}", flush=True)
            code = 1
        elapsed = time.monotonic() - started
        if code:
            failures.append((name, code))
        print(f"{'FAIL' if code else 'PASS'} {name} ({elapsed:.1f}s, exit {code})", flush=True)

    print(f"\n{len(suites) - len(failures)}/{len(suites)} suites passed in {time.monotonic() - began:.1f}s.")
    if failures:
        print("Failed suites:")
        for name, code in failures:
            print(f"  {name} (exit {code})")
    if not args.include_launchd:
        print("Optional launchd registration test was not run (use --include-launchd).")
    if not args.include_updater:
        print("Optional Sparkle integration tests were not run (use --include-updater PATH).")
    return 1 if failures else 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except KeyboardInterrupt:
        print("\nTest run interrupted.", file=sys.stderr)
        sys.exit(130)
