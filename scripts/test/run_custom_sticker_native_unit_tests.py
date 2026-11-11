#!/usr/bin/env python3
"""Run the exact BL-17 Android JVM slice and retain fresh JUnit evidence.

The selection wrapper (or standalone caller) owns mknoon.shared-native-build.
This runner deliberately acquires no nested lease and never retries Gradle.
"""
from __future__ import annotations

from collections import Counter
from datetime import datetime, timezone
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import signal
import subprocess
import sys
import tempfile
import time
import xml.etree.ElementTree as ET


ROOT = Path(__file__).resolve().parents[2]
REPORTS = ROOT / "build/app/test-results/testDebugUnitTest"
REGISTRATION = "com.mknoon.app.StickerClipFrameRegistrationTest"
EXPECTED_COUNTS = {
    REGISTRATION: 4,
    "com.mknoon.app.NativeRuntimeOwnershipSourceTest": 3,
    "com.mknoon.app.call.MknoonCallBridgeTeardownTest": 3,
    "com.mknoon.app.MainActivityOnNewIntentTest": 2,
    "com.mknoon.app.StickerCutoutBridgeTest": 21,
    "com.mknoon.app.StickerCutoutHostPosixShadowTest": 6,
    "com.mknoon.app.StickerCutoutRegistrationTest": 4,
}
REGISTRATION_METHODS = {
    "replacement removes the old handler before installing on the same messenger",
    "replacing an engine releases its messenger before attaching the successor",
    "detach removes the handler immediately without a runtime shutdown callback",
    "detach before setup and a fresh attachment after detach remain usable",
}
SUCCESS = "CUSTOM_STICKER_NATIVE_UNIT_TESTS_PASS"


def save(path, value):
    path.write_text(json.dumps(value, indent=2, sort_keys=True) + "\n")


def snapshot(files, destination):
    """Copy evidence before parsing it; malformed/failed reports are retained."""
    destination.mkdir()
    inventory = []
    for source in sorted(files):
        if source.is_symlink() or not source.is_file():
            raise ValueError(f"JUnit report is not a regular file: {source}")
        target = destination / source.name
        shutil.copy2(source, target)
        stat = source.stat()
        inventory.append({
            "name": source.name,
            "size_bytes": stat.st_size,
            "mtime_ns": stat.st_mtime_ns,
            "sha256": hashlib.sha256(target.read_bytes()).hexdigest(),
        })
    return inventory


def interrupted(_signum, _frame):
    # subprocess.run stops its owned child on interruption. The outer wrapper
    # retains process-group cancellation and the shared native-build lease.
    raise KeyboardInterrupt


def main():
    log_root = ROOT / ".codex-test-logs"
    log_root.mkdir(exist_ok=True)
    stamp = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%S.%fZ")
    run = Path(tempfile.mkdtemp(prefix=f"custom-sticker-native-{stamp}-",
                                dir=log_root))
    command = [
        "./android/gradlew", "-p", "android", "--console=plain",
        ":app:testDebugUnitTest", "--rerun",
    ]
    for classname in EXPECTED_COUNTS:
        command.extend(["--tests", classname])
    save(run / "command.json", {
        "command": command,
        "cwd": str(ROOT),
        "expected_counts": EXPECTED_COUNTS,
        "registration_methods": sorted(REGISTRATION_METHODS),
        "scope": "Android host JVM/Robolectric; no device proof",
        "lease": "mknoon.shared-native-build is owned by the caller",
    })
    print(f"native unit evidence: {run}", flush=True)

    try:
        sys.path.insert(0, str(ROOT / "scripts"))
        from full_suite_adapters import inspect as inspect_native

        if not os.access(ROOT / "android/gradlew", os.X_OK):
            raise ValueError("android/gradlew must exist and be executable")
        if REPORTS.is_symlink():
            raise ValueError("JUnit output directory must not be a symlink")

        # Preserve every old XML before Gradle can rewrite its result directory.
        # Remove only our seven selected reports, so their subsequent presence
        # proves new publication even on filesystems with coarse mtime precision.
        previous = snapshot(REPORTS.glob("*.xml"), run / "previous-junit")
        save(run / "previous-junit.json", previous)
        selected = {
            classname: REPORTS / f"TEST-{classname}.xml"
            for classname in EXPECTED_COUNTS
        }
        for report in selected.values():
            if report.exists():
                report.unlink()
        if any(report.exists() or report.is_symlink()
               for report in selected.values()):
            raise ValueError("Selected JUnit reports were not cleared before launch")

        started_ns = time.time_ns()
        was_interrupted = False
        signal.signal(signal.SIGTERM, interrupted)
        with (run / "gradle.raw.log").open("wb") as raw:
            try:
                completed = subprocess.run(
                    command, cwd=ROOT, stdout=raw, stderr=subprocess.STDOUT,
                    check=False,
                )
                code = completed.returncode
            except KeyboardInterrupt:
                code = 130
                was_interrupted = True
        save(run / "exit.json", {
            "exit_status": code,
            "interrupted": was_interrupted,
            "started_ns": started_ns,
            "finished_ns": time.time_ns(),
            "selected_reports_absent_before_launch": True,
        })

        fresh = snapshot(
            (report for report in selected.values() if report.exists()),
            run / "fresh-junit",
        )
        save(run / "fresh-junit.json", fresh)
        output = (run / "gradle.raw.log").read_text(errors="replace")
        proof = inspect_native({
            "format": "junit",
            "classes": list(EXPECTED_COUNTS),
            "report_glob": "fresh-junit/*.xml",
        }, output, code, was_interrupted, run)
        save(run / "junit-proof.json", proof)

        errors = []
        observed = Counter()
        selectors = []
        registration_methods = []
        for classname, report in selected.items():
            retained = run / "fresh-junit" / report.name
            if not retained.exists():
                errors.append(f"Missing fresh JUnit XML: {classname}")
                continue
            suite = ET.parse(retained).getroot()
            cases = suite.findall(".//testcase")
            if suite.tag != "testsuite" or not cases:
                errors.append(f"Expected a nonempty Gradle testsuite: {classname}")
            if int(suite.get("tests", "0")) != len(cases):
                errors.append(f"Declared/counted test mismatch: {classname}")
            for field in ("failures", "errors", "skipped"):
                if int(suite.get(field, "0")) != 0:
                    errors.append(f"Nonzero JUnit {field}: {classname}")
            for case in cases:
                actual_class = case.get("classname") or "<missing>"
                method = case.get("name") or ""
                if actual_class != classname or not method:
                    errors.append(f"Wrong or unnamed testcase in {report.name}")
                observed[actual_class] += 1
                selectors.append((actual_class, method))
                if actual_class == REGISTRATION:
                    registration_methods.append(method)

        if dict(observed) != EXPECTED_COUNTS:
            errors.append("Per-class case counts differ from the 4+3+3+2+21+6+4 inventory")
        if len(selectors) != len(set(selectors)):
            errors.append("Duplicate JUnit testcase selectors")
        if (len(registration_methods) != 4 or
                set(registration_methods) != REGISTRATION_METHODS):
            errors.append("Registration's four exact method names were not observed")
        task_states = [state.strip() for state in re.findall(
            r"^> Task :app:testDebugUnitTest(?: ([^\r\n]+))?\r?$",
            output, re.MULTILINE,
        )]
        if not task_states or any(state for state in task_states):
            errors.append("testDebugUnitTest did not report an executed, successful task")
        if code != 0:
            errors.append(f"Gradle exited {code}")
        if proof.get("status") != "PASS" or not proof.get("completion_observed"):
            errors.append("Existing JUnit proof reader did not confirm all cases passed")
        passed = not errors and not was_interrupted
        result = {
            "status": "PASS" if passed else "FAIL",
            "counts": proof["counts"],
            "observed_counts": dict(observed),
            "errors": errors,
            "gradle_exit_status": code,
            "registration_methods": sorted(registration_methods),
            "freshness": "selected XML absent before this Gradle invocation",
        }
        save(run / "result.json", result)
        print(json.dumps({"status": result["status"],
                          "counts": result["counts"], "evidence": str(run)}),
              flush=True)
        if passed:
            print(SUCCESS, flush=True)
            return 0
        print("Native unit evidence rejected; see result.json and gradle.raw.log.",
              file=sys.stderr)
        return 130 if was_interrupted else 1
    except (OSError, ValueError, ET.ParseError, ImportError) as error:
        save(run / "result.json", {"status": "BLOCKED", "reason": str(error)})
        print(f"Native unit runner blocked: {error}; evidence: {run}",
              file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
