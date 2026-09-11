#!/usr/bin/env python3
"""Contract tests for conservative inventory discovery; no app test imports."""

import importlib.util
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest


SPEC = importlib.util.spec_from_file_location("testing_inventory", Path(__file__).resolve().parents[1] / "testing_inventory.py")
inventory = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(inventory)


class InventoryTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.git("init", "-q")

    def git(self, *args):
        return subprocess.run(["git", *args], cwd=self.root, check=True,
                              stdout=subprocess.PIPE, stderr=subprocess.PIPE)

    def file(self, path, content=""):
        target = self.root / path
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_text(content)
        return target

    def test_cross_family_inventory_separates_support_vendor_and_unknown_cases(self):
        paths = {
            "test/app_test.dart": "flutter_host",
            "integration_test/chat_test.dart": "flutter_device",
            "packages/plugin/test/plugin_test.dart": "flutter_host",
            "go-mknoon/node/node_test.go": "go",
            "go-mknoon/third_party/module/node_test.go": "go",
            "ios/RunnerTests/LifecycleTests.swift": "swift_xctest",
            "ios/RunnerUITests/TapUITests.swift": "swift_xctest_ui",
            "android/app/src/test/pkg/ReceiverTest.kt": "kotlin_java_junit",
            "android/app/src/flavorAndroidTest/pkg/ReceiverTest.kt": "android_instrumentation",
            "scripts/test/check_test.py": "python_unittest",
            "scripts/test/check_test.sh": "shell_contract",
            "scripts/test/check_test.js": "javascript_node",
        }
        for path in paths:
            self.file(path)
        self.file("go-mknoon/go.mod")
        self.file("go-mknoon/third_party/module/go.mod")
        self.file("test/helpers/fake.dart")
        self.file("test/fixtures/trick_test.dart")
        self.file("test/generated.mocks.dart")
        self.file("test/fixtures/sample.json")
        self.file("lib/contest.dart")
        result = inventory.discover(self.root)
        rows = {row["path"]: row for row in result["entries"]}
        for path, family in paths.items():
            self.assertEqual(rows[path]["family"], family)
            self.assertIsNone(rows[path]["actual_test_case_count"])
            self.assertEqual(rows[path]["status"], "discovered")
        self.assertEqual(result["test_file_count"], len(paths))
        self.assertEqual(rows["test/helpers/fake.dart"]["role"], "helper")
        self.assertEqual(rows["test/fixtures/trick_test.dart"]["role"], "fixture")
        self.assertEqual(rows["test/generated.mocks.dart"]["role"], "generated")
        self.assertNotIn("lib/contest.dart", rows)
        vendor = rows["go-mknoon/third_party/module/node_test.go"]
        self.assertEqual(vendor["ownership"], "vendor_or_stub")
        self.assertEqual(vendor["module"], "go-mknoon/third_party/module")
        self.assertEqual(result, inventory.discover(self.root))

    def test_added_renamed_deleted_and_ignored_files_are_not_stale_inventory(self):
        self.file(".gitignore", "ignored/\n")
        old = self.file("test/old_test.dart")
        deleted = self.file("test/deleted_test.dart")
        self.git("add", ".")
        old.rename(self.root / "test/renamed_test.dart")
        deleted.unlink()
        self.file("test/added_test.dart")
        self.file("ignored/no_test.dart")
        paths = inventory.source_files(self.root)
        self.assertEqual(paths, [".gitignore", "test/added_test.dart", "test/renamed_test.dart"])
        self.assertEqual(inventory.discover(self.root)["test_file_count"], 2)

    def runner(self, code, format="sims_json"):
        return {"id": "fixture", "command": [sys.executable, "-c", code], "required_paths": [], "format": format}

    def test_listing_counts_groups_without_claiming_actual_cases(self):
        plan = {"rows": [{"id": "one"}, {"id": "two"}]}
        result = inventory.list_runner(self.root, self.runner("print(" + repr(json.dumps(plan)) + ")"))
        self.assertEqual(result["status"], "PASS")
        self.assertEqual(result["plan_item_count"], 2)
        self.assertIsNone(result["actual_test_case_count"])
        text = inventory.list_runner(self.root, self.runner("print('  1. flutter test a_test.dart')", "numbered_plan"))
        self.assertEqual(text["plan_item_count"], 1)
        routes = inventory.list_runner(self.root, self.runner("print('RUN 001/095 example\\n  route: flutter test a_test.dart')", "full_routes"))
        self.assertEqual(routes["plan_item_count"], 1)
        self.assertIsNone(routes["actual_test_case_count"])

    def test_empty_malformed_duplicate_and_failed_listings_cannot_pass(self):
        for code in ["print('not json')", "print('{\"rows\": []}')",
                     "print('{\"rows\": [{\"id\": \"same\"}, {\"id\": \"same\"}]}')", "raise SystemExit(7)"]:
            with self.subTest(code=code):
                self.assertEqual(inventory.list_runner(self.root, self.runner(code))["status"], "FAIL")
        result = inventory.list_runner(self.root, self.runner("print('No tests')", "numbered_plan"))
        self.assertEqual(result["status"], "FAIL")
        result = inventory.list_runner(self.root, self.runner("print('RUN 001/095 example')", "full_routes"))
        self.assertEqual(result["status"], "FAIL")

    def test_missing_prerequisite_and_timeout_are_blocked(self):
        runner = self.runner("raise SystemExit('must not execute')")
        runner["required_paths"] = ["missing"]
        self.assertEqual(inventory.list_runner(self.root, runner)["status"], "BLOCKED")
        result = inventory.list_runner(self.root, self.runner("import time; time.sleep(20)"), timeout_seconds=0.05)
        self.assertEqual(result["status"], "BLOCKED")
        self.assertEqual(result["reason"], "Listing timed out")


if __name__ == "__main__":
    unittest.main()
