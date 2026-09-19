#!/usr/bin/env python3
"""Run relay/diagnostics recovery with observed virtual-device backgrounding.

The runner never boots a target. It requires an explicit running emulator or
simulator, and backgrounds only the test app on that target. Raw Flutter output
is retained separately from the fixed, redacted measurement markers.
"""

from __future__ import annotations

import argparse
import datetime as dt
import json
import os
from pathlib import Path
import plistlib
import queue
import re
import shutil
import signal
import subprocess
import threading
import time


ROOT = Path(__file__).resolve().parents[2]
HARNESS = "integration_test/relay_recovery_diagnostics_harness.dart"
READY = "RELAY_DIAGNOSTICS_OS_BACKGROUND_READY "
OBSERVED = "RELAY_DIAGNOSTICS_OS_BACKGROUND_OBSERVED "
TRIAL = "RELAY_DIAGNOSTICS_TRIAL "
DONE = "RELAY_DIAGNOSTICS_DONE "
PREFIXES = (READY, OBSERVED, TRIAL, DONE)


def command(arguments: list[str], timeout: float = 20) -> str:
    result = subprocess.run(
        arguments, cwd=ROOT, text=True, capture_output=True, timeout=timeout
    )
    if result.returncode:
        # Command output is retained by Flutter or the exception context, not
        # mixed into the allowlisted measurement stream.
        raise RuntimeError(
            f"Command failed ({result.returncode}): {' '.join(arguments)}"
        )
    return result.stdout.strip()


def android_sdk() -> Path:
    for name in ("ANDROID_HOME", "ANDROID_SDK_ROOT"):
        if os.environ.get(name):
            return Path(os.environ[name])
    properties = ROOT / "android/local.properties"
    if properties.exists():
        for line in properties.read_text().splitlines():
            if line.startswith("sdk.dir="):
                return Path(line.split("=", 1)[1])
    raise RuntimeError("Android SDK path is unavailable")


def adb_binary() -> str:
    return shutil.which("adb") or str(android_sdk() / "platform-tools/adb")


def require_virtual_target(platform: str, device: str) -> None:
    if platform == "android":
        adb = adb_binary()
        if command([adb, "-s", device, "get-state"]) != "device":
            raise RuntimeError("The selected Android target is not running")
        if command([adb, "-s", device, "shell", "getprop", "ro.kernel.qemu"]) != "1":
            raise RuntimeError("This runner requires an Android emulator")
    else:
        inventory = json.loads(command(["xcrun", "simctl", "list", "devices", "available", "--json"]))
        matches = [
            row
            for rows in inventory["devices"].values()
            for row in rows
            if row["udid"] == device
        ]
        if len(matches) != 1 or matches[0]["state"] != "Booted":
            raise RuntimeError("The selected iOS simulator must already be booted")


def built_app_id(platform: str, override: str | None) -> str:
    if override:
        value = override
    elif platform == "android":
        apk = ROOT / "build/app/outputs/flutter-apk/app-debug.apk"
        if not apk.is_file():
            raise RuntimeError("Built debug APK not found; pass --app-id explicitly")
        candidates = list((android_sdk() / "build-tools").glob("*/aapt"))
        if not candidates:
            candidates = list((android_sdk() / "build-tools").glob("*/aapt2"))
        if not candidates:
            raise RuntimeError("aapt/aapt2 is unavailable; pass --app-id explicitly")
        aapt = max(candidates, key=lambda path: path.stat().st_mtime_ns)
        badging = command([str(aapt), "dump", "badging", str(apk)])
        match = re.search(r"^package: name='([^']+)'", badging, re.MULTILINE)
        if not match:
            raise RuntimeError("Cannot read the built APK package name")
        value = match.group(1)
    else:
        paths = [
            ROOT / "build/ios/iphonesimulator/Runner.app/Info.plist",
            ROOT / "build/ios/Debug-iphonesimulator/Runner.app/Info.plist",
        ]
        path = next((candidate for candidate in paths if candidate.is_file()), None)
        if path is None:
            raise RuntimeError("Built simulator Info.plist not found; pass --app-id")
        value = plistlib.loads(path.read_bytes())["CFBundleIdentifier"]
    if not re.fullmatch(r"[A-Za-z][A-Za-z0-9_-]*(?:\.[A-Za-z0-9_-]+)+", value):
        raise RuntimeError("Invalid app identifier")
    return value


def background_cycle(platform: str, device: str, app_id: str, hold: float) -> None:
    if platform == "android":
        adb = adb_binary()
        resolved = command([
            adb, "-s", device, "shell", "cmd", "package", "resolve-activity",
            "--brief", app_id,
        ])
        component = next(
            (line.strip() for line in reversed(resolved.splitlines()) if line.startswith(app_id + "/")),
            None,
        )
        if component is None:
            raise RuntimeError("Cannot resolve the selected test app's activity")
        command([adb, "-s", device, "shell", "input", "keyevent", "KEYCODE_HOME"])
        time.sleep(hold)
        command([adb, "-s", device, "shell", "am", "start", "-W", "-n", component])
    else:
        command(["xcrun", "simctl", "get_app_container", device, app_id, "app"])
        command(["xcrun", "simctl", "launch", device, "com.apple.mobilesafari"])
        time.sleep(hold)
        command(["xcrun", "simctl", "launch", device, app_id])


def stop_owned_process(process: subprocess.Popen[str]) -> None:
    if process.poll() is not None:
        return
    os.killpg(process.pid, signal.SIGINT)
    try:
        process.wait(timeout=15)
    except subprocess.TimeoutExpired:
        os.killpg(process.pid, signal.SIGTERM)
        try:
            process.wait(timeout=5)
        except subprocess.TimeoutExpired:
            os.killpg(process.pid, signal.SIGKILL)
            process.wait(timeout=5)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--device", required=True)
    parser.add_argument("--platform", choices=("android", "ios"), required=True)
    parser.add_argument("--flutter", default="flutter")
    parser.add_argument("--app-id", help="Override app identity when build output is nonstandard")
    parser.add_argument(
        "--relay-addresses",
        help="Comma-separated relay multiaddresses, including an isolated local relay",
    )
    parser.add_argument("--background-seconds", type=float, default=10)
    parser.add_argument("--timeout-seconds", type=float, default=1800)
    parser.add_argument("--output", type=Path)
    args = parser.parse_args()
    if not 1 <= args.background_seconds <= 20:
        parser.error("--background-seconds must be between 1 and 20")
    if not 60 <= args.timeout_seconds <= 3600:
        parser.error("--timeout-seconds must be between 60 and 3600")
    require_virtual_target(args.platform, args.device)
    stamp = dt.datetime.now(dt.timezone.utc).strftime("%Y%m%dT%H%M%S%fZ")
    output = args.output or ROOT / ".codex-test-logs/relay-diagnostics-virtual" / f"{stamp}-{args.platform}"
    output.mkdir(parents=True, exist_ok=False, mode=0o700)
    flutter = str(Path(args.flutter).resolve()) if "/" in args.flutter else args.flutter
    invocation = [
        flutter, "test", "--no-pub", HARNESS, "-d", args.device,
        "--reporter", "expanded", "--dart-define=REQUIRE_OS_BACKGROUND=true",
    ]
    if args.relay_addresses:
        invocation.append("--dart-define=MKNOON_RELAY_ADDRESSES=" + args.relay_addresses)
    environment = dict(os.environ)
    environment["GOTOOLCHAIN"] = "go1.25.0"
    if "/" in flutter:
        environment["PATH"] = str(Path(flutter).parent) + os.pathsep + environment["PATH"]
    (output / "command.json").write_text(json.dumps(invocation, indent=2) + "\n")
    process = subprocess.Popen(
        invocation, cwd=ROOT, env=environment, stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT, text=True, bufsize=1, start_new_session=True,
    )
    messages: queue.Queue[str] = queue.Queue()

    def capture() -> None:
        assert process.stdout is not None
        with (output / "flutter.log").open("w") as raw:
            for line in process.stdout:
                raw.write(line)
                raw.flush()
                for prefix in PREFIXES:
                    if prefix in line:
                        messages.put(line[line.index(prefix):].strip())
                        break

    reader = threading.Thread(target=capture, daemon=True)
    reader.start()
    deadline = time.monotonic() + args.timeout_seconds
    metrics: list[dict] = []
    observed: list[dict] = []
    requested: set[tuple[int, bool]] = set()
    app_id: str | None = None
    error: str | None = None
    try:
        while process.poll() is None or reader.is_alive() or not messages.empty():
            if time.monotonic() >= deadline:
                raise TimeoutError("Flutter harness exceeded the runner deadline")
            try:
                message = messages.get(timeout=0.2)
            except queue.Empty:
                continue
            print(message, flush=True)
            if message.startswith(READY):
                row = json.loads(message[len(READY):])
                key = (row["repetition"], row["diagnosticsEnabled"])
                if key in requested:
                    raise RuntimeError("Duplicate background request")
                requested.add(key)
                app_id = built_app_id(args.platform, args.app_id)
                background_cycle(args.platform, args.device, app_id, args.background_seconds)
            elif message.startswith(OBSERVED):
                observed.append(json.loads(message[len(OBSERVED):]))
            elif message.startswith(TRIAL):
                metrics.append(json.loads(message[len(TRIAL):]))
    except (Exception, KeyboardInterrupt) as failure:
        error = str(failure) or type(failure).__name__
        stop_owned_process(process)
    finally:
        reader.join(timeout=5)
    exit_code = process.wait(timeout=10)
    passed = (
        error is None and exit_code == 0 and len(metrics) == 4
        and len(observed) == 4 and len(requested) == 4
        and all(row.get("osPauseObserved") and row.get("osResumeObserved") for row in metrics)
    )
    summary = {
        "status": "PASS" if passed else "FAIL", "platform": args.platform,
        "device": args.device, "appId": app_id, "flutterExitCode": exit_code,
        "error": error, "backgroundRequests": len(requested),
        "observedBackgroundCycles": len(observed), "trials": metrics,
        "rawLog": str(output / "flutter.log"),
        "limitation": "Virtual OS background/foreground; physical deep suspension is not tested",
    }
    (output / "summary.json").write_text(json.dumps(summary, indent=2) + "\n")
    print(f"{summary['status']}: {output / 'summary.json'}", flush=True)
    return 0 if passed else 1


if __name__ == "__main__":
    raise SystemExit(main())
