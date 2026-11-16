# Running tests

From the repository root:

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer python3 Tests/run-all-tests.py
```

Adjust `DEVELOPER_DIR` if Xcode is installed elsewhere. It can be omitted when `xcode-select` already points to the correct Xcode installation.

## Prerequisites

- An Apple Silicon Mac running macOS 27 or newer, with an active graphical login session.
- Full Xcode with the macOS 27 SDK or newer. The Command Line Tools installation alone may select an older SDK.
- Python 3.9 or newer and Node.js 22 or newer on `PATH`. The standard suite uses only their built-in libraries; it does not require a package install.

The runner discovers every `Tests/run-*-tests.sh` suite, then runs the unprivileged power-sampler lifecycle cases, Worker tests, publisher safeguards, and repository-activity tests. Suites run sequentially to avoid interference between UI and timing checks. Their output remains visible, failures do not stop later suites, and the final summary lists failures with a nonzero exit status.

Some existing UI tests briefly show disposable HUD panels. Tests also read local hardware state, use temporary files and isolated preference domains, and briefly register unusual test hotkeys. The standard command does not install or launch the real PerformanceHUD app, register its helper or login item, register a launchd job, or deploy an update.

To inspect the selected commands without running them:

```sh
python3 Tests/run-all-tests.py --list
```

Individual shell suites can still be run directly, for example `sh Tests/run-host-port-tests.sh`.

`sh Tests/run-device-info-tests.sh` checks Chip Tier/Full and independent OS visibility within Misc, detected core counts and fallback text, migration from the former Mac category, saved choices/presets, Misc row geometry and CSV selection.

`sh Tests/run-hotkey-tests.sh` also checks the brief appearance/logging confirmations: message text, click-through placement, no focus change, replacement on repeated presses, and dismissal without an idle timer. These checks show a disposable notification panel.

`sh Tests/run-scale-layout-tests.sh --normal-size` checks the complete layout at normal size; omit the flag for the full scale matrix.

`sh Tests/run-process-core-tests.sh` checks independent Process controls, whole-capacity CPU normalization and stable Process column spacing, CPU/GPU GHz in both layouts, Vertical bar modes, independent collector demand, horizontal spacing and missing-value stability, presets/reset, CPU topology and live per-core counters, activity-weighted frequency decoding and helper replies (including unequal same-type clusters), CSV, and eight-core wrapping through 32 cores. An optional `--preview` writes offscreen fixture images to `/tmp/performancehud-v32-process-core-preview.png` and `/tmp/performancehud-v32-horizontal-cores.png`; it does not launch the installed app. Add `--frequency-sample /path/to/sample.plist` to replay a captured `powermetrics` sample through IPC decoding, watt continuity, PowerMonitor, and the actual CPU/GPU HUD fields. The test rebases only the sample timestamp to pass freshness checks.

## Optional integration tests

The launchd cleanup test registers a disposable job in the current user's graphical session and verifies that launchd removes its child after the test parent is killed. It requires no administrator privileges and removes the test registration afterward:

```sh
python3 Tests/run-all-tests.py --include-launchd
```

The standalone lifecycle script retains its original behavior: running it without flags includes launchd cleanup. Use `python3 Tests/run-power-lifecycle-tests.py --skip-launchd` for only the unprivileged sampler cases, or `--include-launchd` to request the full test explicitly.

The Sparkle integration suite additionally requires a Sparkle distribution containing the framework and `bin/sign_update`, plus installed Worker dependencies (`pnpm --dir UpdateService install --frozen-lockfile`). Pass the distribution directory explicitly:

```sh
python3 Tests/run-all-tests.py --include-updater /path/to/Sparkle
```

These tests start a local Worker and exercise real Sparkle updates against disposable app bundles and a generated test signing key. They do not modify the installed PerformanceHUD app or publish a release. They retain temporary fixture folders for diagnostics. Both integration flags can be combined; `DEVELOPER_DIR` applies to them as well. To run one updater case directly, see `python3 Tests/run-updater-integration.py --help`.

## Service-only tests

These commands also run without macOS or Xcode:

```sh
node --test UpdateService/test/*.test.mjs
python3 UpdateService/test/publish_update_test.py
python3 .github/tests/test_repository_activity.py
```
