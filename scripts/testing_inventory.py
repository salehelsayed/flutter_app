#!/usr/bin/env python3
"""Discover test files and existing runner plans without executing test bodies.

This is a generated inventory, not a second coverage manifest. A discovered
file or SIMS capability is not a test case and does not establish coverage.
Only the explicit --list-runners option starts the allowlisted listing commands.
"""

from __future__ import annotations

import argparse
from collections import Counter
import hashlib
import json
import os
from pathlib import Path, PurePosixPath
import re
import signal
import subprocess
import sys
import tempfile
import time


SCHEMA_VERSION = 1
SOURCE_EXTENSIONS = {".dart", ".go", ".py", ".sh", ".js", ".mjs", ".cjs", ".swift", ".kt", ".java", ".c", ".cc", ".cpp"}
SUPPORT_PARTS = {"fixture", "fixtures", "helper", "helpers", "support", "mocks", "fakes", "testdata"}
RUNNERS = (
    {"id": "host", "command": ["bash", "scripts/run_host_test_gates.sh", "host-all", "--list"],
     "required_paths": ["scripts/run_host_test_gates.sh"], "format": "numbered_plan"},
    {"id": "sims", "command": ["dart", "tool/sims/sims.dart", "full", "--list", "--format", "json"],
     "required_paths": ["tool/sims/sims.dart", ".dart_tool/package_config.json"], "format": "sims_json"},
    {"id": "sims_contracts", "command": ["bash", "scripts/run_test_gates.sh", "sims-contracts", "--list"],
     "required_paths": ["scripts/run_test_gates.sh"], "format": "numbered_plan"},
    {"id": "flutter_full_routes", "command": ["bash", "scripts/run_flutter_full_regression.sh", "--dry-run"],
     "required_paths": ["scripts/run_flutter_full_regression.sh"], "format": "full_routes", "temporary_output": True},
)


class InventoryError(ValueError):
    """The inventory could not be obtained completely or safely."""


def source_files(root: Path) -> list[str]:
    """Existing tracked and nonignored untracked files, sorted and deduplicated.

    Deleted paths intentionally remain the diff selector's responsibility.
    Submodule internals and ignored build outputs are not silently traversed.
    """
    result = subprocess.run(
        ["git", "ls-files", "-z", "--cached", "--others", "--exclude-standard"],
        cwd=root, stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=30,
    )
    if result.returncode:
        raise InventoryError("git ls-files failed; run inventory in a Git checkout")
    paths = result.stdout.decode("utf-8", errors="surrogateescape").split("\0")
    return sorted({path for path in paths if path and (root / path).is_file()})


def _ownership(parts: tuple[str, ...]) -> str:
    if "third_party" in parts or "vendor" in parts or "stub" in parts:
        return "vendor_or_stub"
    if parts[0] in {"Test-Flight-Improv", "archive", "archives"}:
        return "historical_or_project_evidence"
    return "project"


def _family(path: str) -> str | None:
    p = PurePosixPath(path)
    parts = p.parts
    name = p.name
    if name.endswith("_test.dart"):
        if "integration_test" in parts or "test_driver" in parts:
            return "flutter_device"
        return "flutter_host"
    if name.endswith("_test.go"):
        return "go"
    if p.suffix == ".py" and (name.startswith("test_") or name.endswith("_test.py")):
        return "python_unittest"
    if p.suffix == ".sh" and (name.endswith("_test.sh") or name.startswith("test_")):
        return "shell_contract"
    if p.suffix in {".js", ".mjs", ".cjs"} and (
        re.search(r"(?:[._-](?:test|spec)|^(?:test|spec)[_-])", p.stem)
        or any(part in {"test", "tests", "__tests__"} for part in parts[:-1])
    ):
        return "javascript_node"
    if p.suffix == ".swift" and re.search(r"Tests?$", p.stem):
        return "swift_xctest_ui" if any("UITests" in part for part in parts) else "swift_xctest"
    if p.suffix in {".kt", ".java"} and re.search(r"Tests?$", p.stem):
        return "android_instrumentation" if any("androidtest" in part.lower() for part in parts) else "kotlin_java_junit"
    if p.suffix in {".c", ".cc", ".cpp"} and re.search(r"(?:^test[_-]|[_-]test$)", p.stem):
        return "native_c_cpp"
    return None


def _support_role(path: str) -> str | None:
    p = PurePosixPath(path)
    parts = p.parts
    if p.suffix not in SOURCE_EXTENSIONS:
        return "fixture" if any(part in {"fixtures", "testdata"} for part in parts) else None
    in_test_tree = any(part in {"test", "tests", "integration_test", "test_driver"} or part.endswith("Tests") for part in parts)
    if not in_test_tree:
        return None
    if p.name.endswith((".g.dart", ".mocks.dart", ".freezed.dart")):
        return "generated"
    if any(part in {"fixtures", "fixture", "testdata"} for part in parts):
        return "fixture"
    if p.name.startswith("run_") and p.suffix == ".sh":
        return "runner_helper"
    return "helper"


def discover(root: Path) -> dict:
    """Return reproducible discovery metadata; no application/test imports."""
    root = Path(root).resolve()
    paths = source_files(root)
    modules = sorted({str(PurePosixPath(path).parent) for path in paths if PurePosixPath(path).name == "go.mod"})
    entries = []
    for path in paths:
        p = PurePosixPath(path)
        family = _family(path)
        role = "test_candidate" if family else _support_role(path)
        if not role:
            continue
        # Generated and fixture files cannot become executable test evidence
        # merely by ending in a familiar test suffix.
        if any(part in {"fixtures", "fixture", "testdata"} for part in p.parts):
            role = "fixture"
        if p.name.endswith((".g.dart", ".mocks.dart", ".freezed.dart")):
            role = "generated"
        row = {"path": path, "family": family or "test_support", "role": role,
               "ownership": _ownership(p.parts), "status": "discovered",
               "actual_test_case_count": None, "runtime_seconds": None}
        if family == "go":
            matches = [module for module in modules if path.startswith(module + "/") or module == "."]
            row["module"] = max(matches, key=len) if matches else None
        entries.append(row)
    families = {}
    for name in sorted({row["family"] for row in entries}):
        rows = [row for row in entries if row["family"] == name]
        tests = [row for row in rows if row["role"] == "test_candidate"]
        families[name] = {
            "test_file_count": len(tests), "support_file_count": len(rows) - len(tests),
            "ownership_test_file_counts": dict(sorted(Counter(row["ownership"] for row in tests).items())),
            "suite_count": None, "actual_test_case_count": None,
            "runtime_seconds": None,
        }
    fingerprint = hashlib.sha256("\0".join(paths).encode("utf-8", errors="surrogateescape")).hexdigest()
    return {
        "schema_version": SCHEMA_VERSION,
        "source_file_count": len(paths), "source_paths_sha256": fingerprint,
        "test_file_count": sum(row["role"] == "test_candidate" for row in entries),
        "suite_count": None, "actual_test_case_count": None,
        "families": families, "entries": entries, "go_modules": modules,
        "runner_discovery": [dict(runner, status="NOT RUN") for runner in RUNNERS],
        "limitations": [
            "File discovery identifies candidates, not inspected assertions or verified feature coverage.",
            "Suite counts, dynamic/parameterized cases and runtimes remain unknown until authoritative listing/execution.",
            "SIMS capabilities and host planned commands are selectable groups, not actual test-case counts.",
            "Go -list runs package initialization/TestMain and does not enumerate dynamic subtests; it is not run automatically.",
            "Python imports, Node tests and native/Flutter compilation are not executed for static inventory.",
            "Ignored artifacts/build outputs and submodule interiors are excluded; vendor/stub and historical files are labeled separately.",
        ],
    }


def list_runner(root: Path, runner: dict, timeout_seconds: float = 60) -> dict:
    """Run only an existing safe listing, with a process-group timeout."""
    if runner.get("temporary_output"):
        # The older full runner creates empty log directories even in dry-run
        # mode. Keep those outside the checkout and clean them reliably.
        with tempfile.TemporaryDirectory(prefix="mknoon-inventory-") as output:
            concrete = dict(runner, temporary_output=False, command=[*runner["command"], "--output", output])
            return list_runner(root, concrete, timeout_seconds)
    row = dict(runner, status="BLOCKED", actual_test_case_count=None)
    missing = [path for path in runner["required_paths"] if not (root / path).is_file()]
    if missing:
        return dict(row, reason="Missing listing prerequisite", missing_paths=missing)
    started = time.monotonic()
    try:
        process = subprocess.Popen(runner["command"], cwd=root, stdout=subprocess.PIPE,
                                   stderr=subprocess.PIPE, text=True, start_new_session=True)
    except OSError as exc:
        return dict(row, reason=f"Listing executable unavailable: {exc.strerror}")
    try:
        stdout, stderr = process.communicate(timeout=timeout_seconds)
    except subprocess.TimeoutExpired:
        try:
            os.killpg(process.pid, signal.SIGKILL)
        except ProcessLookupError:
            pass
        stdout, stderr = process.communicate()
        return dict(row, reason="Listing timed out", duration_seconds=round(time.monotonic() - started, 3),
                    exit_status=process.returncode)
    row.update(duration_seconds=round(time.monotonic() - started, 3), exit_status=process.returncode)
    if process.returncode:
        return dict(row, status="FAIL", reason="Runner listing failed", stderr=stderr[-4000:])
    if runner["format"] == "sims_json":
        try:
            plan = json.loads(stdout)
            rows = plan["rows"]
            if not isinstance(rows, list) or not rows or any(not isinstance(item, dict) or not item.get("id") for item in rows):
                raise ValueError("empty or invalid rows")
            ids = [item["id"] for item in rows]
            if len(set(ids)) != len(ids):
                raise ValueError("duplicate IDs")
        except (ValueError, KeyError, TypeError):
            return dict(row, status="FAIL", reason="Invalid or empty SIMS JSON listing")
        row.update(plan_item_count=len(rows), plan=plan)
    elif runner["format"] == "full_routes":
        labels = re.findall(r"^RUN \d+/\d+ (.+)$", stdout, flags=re.MULTILINE)
        routes = re.findall(r"^\s+route: (.+)$", stdout, flags=re.MULTILINE)
        if not labels or len(labels) != len(routes):
            return dict(row, status="FAIL", reason="Full dry-run returned zero or incomplete routes")
        row.update(plan_item_count=len(labels), planned_routes=[{"label": label, "command": command} for label, command in zip(labels, routes)])
    else:
        commands = re.findall(r"^\s*\d+[.)]\s+(.+)$", stdout, flags=re.MULTILINE)
        if not commands:
            return dict(row, status="FAIL", reason="Listing returned zero recognizable planned commands")
        row.update(plan_item_count=len(commands), planned_commands=commands)
    return dict(row, status="PASS")


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, help="Write generated JSON to an untracked artifact path; default stdout")
    parser.add_argument("--list-runners", action="store_true", help="Run bounded existing --list commands; never test bodies")
    args = parser.parse_args(argv)
    root = Path(__file__).resolve().parents[1]
    try:
        inventory = discover(root)
        if args.list_runners:
            inventory["runner_discovery"] = [list_runner(root, runner) for runner in RUNNERS]
        encoded = json.dumps(inventory, indent=2, sort_keys=True) + "\n"
        if args.output:
            target = args.output.resolve()
            try:
                relative = target.relative_to(root).as_posix()
            except ValueError:
                relative = None
            if relative:
                tracked = subprocess.run(["git", "ls-files", "--error-unmatch", "--", relative], cwd=root,
                                         stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=30)
                if tracked.returncode == 0:
                    raise InventoryError("Refusing to overwrite a tracked file with generated inventory")
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_text(encoded)
        else:
            print(encoded, end="")
        if args.list_runners and any(row["status"] != "PASS" for row in inventory["runner_discovery"]):
            return 2
        return 0
    except (InventoryError, OSError, subprocess.TimeoutExpired) as exc:
        print(f"Inventory error: {exc}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
