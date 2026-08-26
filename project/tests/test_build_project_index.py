#!/usr/bin/env python3
"""Regression tests for the Mknoon project evidence reconciler."""

from __future__ import annotations

import importlib.util
import json
import tempfile
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
TOOL_PATH = ROOT / "project" / "tools" / "build_project_index.py"
SPEC = importlib.util.spec_from_file_location("mknoon_project_index", TOOL_PATH)
assert SPEC and SPEC.loader
TOOL = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(TOOL)


def _write_json(path: Path, value: object) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(value, indent=2) + "\n", encoding="utf-8")


def _write_text(path: Path, value: str = "fixture\n") -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(value, encoding="utf-8")


def _anchor(value: str, *, required: bool = True) -> dict[str, object]:
    return {
        "kind": "file",
        "value": value,
        "required": required,
        "rationale": "fixture authority",
    }


def _behavior(
    *,
    intent_status: str = "active",
    required_boundaries: list[str] | None = None,
) -> dict[str, object]:
    return {
        "id": "DEMO-AC-01",
        "title": "Demo behavior",
        "plainDescription": "This shows the same clear result every time.",
        "requirement": "The observable result is deterministic.",
        "sourceRefs": ["AC-01"],
        "priority": "critical",
        "intentStatus": intent_status,
        "openQuestions": ["OQ-01"] if intent_status == "provisional" else [],
        "implementationAnchors": [_anchor("lib/demo.dart")],
        "proofPolicy": {
            "requiredBoundaries": required_boundaries or ["host"],
            "availabilityBounded": True,
        },
    }


class ProjectEvidenceTest(unittest.TestCase):
    def setUp(self) -> None:
        self.temporary = tempfile.TemporaryDirectory()
        self.root = Path(self.temporary.name)
        self.arch_graph = self.root / "graphify-arch" / "graphify-out" / "graph.json"
        self.full_graph = self.root / "graphify-out" / "graph.json"

    def tearDown(self) -> None:
        self.temporary.cleanup()

    def _graph(self, path: Path, nodes: list[dict[str, object]]) -> None:
        _write_json(path, {"nodes": nodes, "links": []})

    def test_exact_file_anchor_is_candidate_not_confirmation(self) -> None:
        self._graph(
            self.arch_graph,
            [
                {
                    "id": "demo_run",
                    "label": "run()",
                    "norm_label": "run",
                    "source_file": "lib/demo.dart",
                    "source_location": "L12",
                }
            ],
        )
        self._graph(self.full_graph, [])
        behavior = _behavior()
        matches = TOOL.collect_graph_evidence(
            self.root,
            behavior["implementationAnchors"],
            self.arch_graph,
            self.full_graph,
        )
        assessment = TOOL.assess_implementation(
            behavior,
            matches,
            [],
            {"revision": "abc", "applicationDirty": False},
        )
        self.assertEqual(assessment["graphStatus"], "candidate")
        self.assertEqual(assessment["status"], "candidate")
        self.assertEqual(assessment["graphScopes"], ["architecture"])
        self.assertIsNone(assessment["review"])

    def test_full_graph_match_is_explicit_fallback_evidence(self) -> None:
        self._graph(self.arch_graph, [])
        self._graph(
            self.full_graph,
            [
                {
                    "id": "native_demo",
                    "label": "NativeDemo",
                    "source_file": "android/app/src/main/kotlin/NativeDemo.kt",
                }
            ],
        )
        anchor = _anchor("android/app/src/main/kotlin/NativeDemo.kt")
        matches = TOOL.collect_graph_evidence(
            self.root, [anchor], self.arch_graph, self.full_graph
        )
        evidence = matches[TOOL._anchor_key(anchor)]
        self.assertEqual(len(evidence), 1)
        self.assertEqual(evidence[0]["graph"], "full_fallback")

    def test_graph_miss_is_not_evidenced_instead_of_missing(self) -> None:
        self._graph(self.arch_graph, [])
        self._graph(self.full_graph, [])
        behavior = _behavior()
        matches = TOOL.collect_graph_evidence(
            self.root,
            behavior["implementationAnchors"],
            self.arch_graph,
            self.full_graph,
        )
        assessment = TOOL.assess_implementation(
            behavior,
            matches,
            [],
            {"revision": "abc", "applicationDirty": False},
        )
        self.assertEqual(assessment["status"], "not_evidenced")

    def test_declared_test_is_not_a_run_result(self) -> None:
        _write_text(self.root / "test" / "demo_test.dart")
        behavior = _behavior()
        declaration = {
            "id": "DEMO-T01",
            "title": "Demo proof",
            "path": "test/demo_test.dart",
            "level": "host",
            "boundaries": ["host"],
            "platforms": ["host"],
        }
        assessment = TOOL.assess_verification(
            self.root,
            behavior,
            {"behaviorId": behavior["id"], "testIds": ["DEMO-T01"]},
            {"DEMO-T01": declaration},
            [],
            {"revision": "abc", "applicationDirty": False},
        )
        self.assertEqual(assessment["status"], "declared")
        self.assertEqual(assessment["tests"][0]["state"], "not_run")

    def test_current_pass_satisfies_only_declared_boundaries(self) -> None:
        _write_text(self.root / "test" / "demo_test.dart")
        behavior = _behavior(required_boundaries=["host", "relay"])
        declaration = {
            "id": "DEMO-T01",
            "title": "Demo proof",
            "path": "test/demo_test.dart",
            "level": "host",
            "boundaries": ["host"],
            "platforms": ["host"],
        }
        run = {
            "testId": "DEMO-T01",
            "status": "passed",
            "revision": "abc",
            "workingTreeDirty": False,
            "recordedAt": "2026-08-26T10:00:00+00:00",
            "platform": "host",
            "target": "host",
            "command": "focused-test",
        }
        assessment = TOOL.assess_verification(
            self.root,
            behavior,
            {"behaviorId": behavior["id"], "testIds": ["DEMO-T01"]},
            {"DEMO-T01": declaration},
            [run],
            {"revision": "abc", "applicationDirty": False},
        )
        self.assertEqual(assessment["status"], "missing")
        self.assertEqual(assessment["satisfiedBoundaries"], ["host"])
        self.assertEqual(assessment["undeclaredBoundaries"], ["relay"])

    def test_stale_pass_cannot_verify_current_revision(self) -> None:
        _write_text(self.root / "test" / "demo_test.dart")
        behavior = _behavior()
        declaration = {
            "id": "DEMO-T01",
            "title": "Demo proof",
            "path": "test/demo_test.dart",
            "level": "host",
            "boundaries": ["host"],
            "platforms": ["host"],
        }
        run = {
            "testId": "DEMO-T01",
            "status": "passed",
            "revision": "old",
            "workingTreeDirty": False,
            "recordedAt": "2026-08-26T10:00:00+00:00",
            "platform": "host",
            "target": "host",
            "command": "focused-test",
        }
        assessment = TOOL.assess_verification(
            self.root,
            behavior,
            {"behaviorId": behavior["id"], "testIds": ["DEMO-T01"]},
            {"DEMO-T01": declaration},
            [run],
            {"revision": "new", "applicationDirty": False},
        )
        self.assertEqual(assessment["status"], "stale")
        self.assertEqual(assessment["tests"][0]["state"], "stale_passed")

    def test_availability_bounded_na_satisfies_exact_policy_reason(self) -> None:
        _write_text(self.root / "integration_test" / "device_test.dart")
        behavior = _behavior(required_boundaries=["android_device"])
        declaration = {
            "id": "DEMO-DEVICE",
            "title": "Device proof",
            "path": "integration_test/device_test.dart",
            "level": "device",
            "boundaries": ["android_device"],
            "platforms": ["android"],
        }
        run = {
            "testId": "DEMO-DEVICE",
            "status": "not_applicable",
            "revision": "abc",
            "workingTreeDirty": False,
            "recordedAt": "2026-08-26T10:00:00+00:00",
            "platform": "android",
            "target": "unavailable",
            "command": "device-matrix-resolution",
            "reason": "N/A (target unavailable by project policy)",
        }
        assessment = TOOL.assess_verification(
            self.root,
            behavior,
            {"behaviorId": behavior["id"], "testIds": ["DEMO-DEVICE"]},
            {"DEMO-DEVICE": declaration},
            [run],
            {"revision": "abc", "applicationDirty": False},
        )
        self.assertEqual(assessment["status"], "verified")

    def test_covered_requires_current_review_and_current_proof(self) -> None:
        behavior = _behavior()
        graphs = {"architecture": {"freshness": {"status": "current"}}}
        verification = {"status": "verified"}
        candidate = {"status": "candidate", "graphStatus": "candidate"}
        confirmed = {"status": "confirmed", "graphStatus": "candidate"}
        self.assertEqual(
            TOOL.derive_assessment(behavior, candidate, verification, graphs)["status"],
            "verified_candidate",
        )
        self.assertEqual(
            TOOL.derive_assessment(behavior, confirmed, verification, graphs)["status"],
            "covered",
        )

    def test_provisional_intent_is_visible_before_unrun_proof(self) -> None:
        behavior = _behavior(intent_status="provisional")
        result = TOOL.derive_assessment(
            behavior,
            {"status": "candidate", "graphStatus": "candidate"},
            {"status": "declared"},
            {"architecture": {"freshness": {"status": "current"}}},
        )
        self.assertEqual(result["status"], "intent_open_question")

    def test_end_to_end_fixture_builds_reconciled_index(self) -> None:
        _write_text(self.root / "lib" / "demo.dart")
        _write_text(self.root / "test" / "demo_test.dart")
        _write_text(self.root / "spec.txt")
        self._graph(
            self.arch_graph,
            [{"id": "demo", "label": "Demo", "source_file": "lib/demo.dart"}],
        )
        self._graph(self.full_graph, [])
        feature_dir = self.root / "project" / "features" / "demo"
        _write_json(
            feature_dir / "feature.json",
            {
                "schemaVersion": 1,
                "id": "demo",
                "title": "Demo",
                "prd": "spec.txt",
                "prdVersion": "1",
                "intentStatus": "active",
                "behaviorsFile": "behaviors.json",
                "coverageFile": "coverage.json",
                "testResultsFile": "results.json",
                "implementationReviewsFile": "reviews.json",
            },
        )
        _write_json(
            feature_dir / "behaviors.json",
            {
                "schemaVersion": 1,
                "featureId": "demo",
                "questions": [],
                "behaviors": [_behavior()],
            },
        )
        _write_json(
            feature_dir / "coverage.json",
            {
                "schemaVersion": 1,
                "featureId": "demo",
                "tests": [
                    {
                        "id": "DEMO-T01",
                        "title": "Demo proof",
                        "testType": "unit",
                        "path": "test/demo_test.dart",
                        "level": "host",
                        "boundaries": ["host"],
                        "platforms": ["host"],
                    }
                ],
                "mappings": [
                    {"behaviorId": "DEMO-AC-01", "testIds": ["DEMO-T01"]}
                ],
            },
        )
        _write_json(
            feature_dir / "results.json",
            {"schemaVersion": 1, "featureId": "demo", "runs": []},
        )
        _write_json(
            feature_dir / "reviews.json",
            {"schemaVersion": 1, "featureId": "demo", "reviews": []},
        )
        index = TOOL.build_index(
            self.root,
            generated_at="2026-08-26T10:00:00+00:00",
            architecture_path=self.arch_graph,
            full_path=self.full_graph,
            repository={
                "revision": "abc",
                "shortRevision": "abc",
                "applicationDirty": False,
            },
        )
        self.assertEqual(index["summary"]["features"], 1)
        self.assertEqual(index["summary"]["implementationCandidates"], 1)
        self.assertEqual(index["summary"]["proofNotRun"], 1)
        behavior = index["features"][0]["behaviors"][0]
        self.assertEqual(
            behavior["plainDescription"],
            "This shows the same clear result every time.",
        )
        self.assertEqual(behavior["implementation"]["status"], "candidate")
        self.assertEqual(behavior["verification"]["status"], "declared")
        self.assertEqual(behavior["assessment"]["status"], "proof_not_run")


@unittest.skipUnless(
    (ROOT / "graphify-arch" / "graphify-out" / "graph.json").is_file(),
    "repository Graphify data is unavailable",
)
class LiveNotificationContractTest(unittest.TestCase):
    def test_notification_prd_vertical_slice_reconciles_without_missing_artifacts(self) -> None:
        index = TOOL.build_index(ROOT)
        feature = next(row for row in index["features"] if row["id"] == "notifications")
        self.assertTrue(feature["prd"]["exists"])
        self.assertEqual(feature["prd"]["version"], "1.2")
        self.assertEqual(feature["openQuestions"], ["OQ-05"])
        self.assertEqual(len(feature["behaviors"]), 13)
        behavior_by_id = {row["id"]: row for row in feature["behaviors"]}
        self.assertEqual(behavior_by_id["NOTIF-AC-01"]["intentStatus"], "active")
        self.assertEqual(behavior_by_id["NOTIF-AC-01"]["openQuestions"], [])
        self.assertIn("play a sound or vibrate", behavior_by_id["NOTIF-AC-01"]["plainDescription"])
        self.assertTrue(
            all(
                test["testType"] in TOOL.TEST_TYPES
                for row in feature["behaviors"]
                for test in row["verification"]["tests"]
            )
        )
        self.assertTrue(
            all(
                row["plainDescription"].strip()
                and len(row["plainDescription"]) <= 240
                for row in feature["behaviors"]
            )
        )
        self.assertTrue(
            all(
                row["implementation"]["graphStatus"] == "candidate"
                for row in feature["behaviors"]
            )
        )
        missing_tests = [
            test["path"]
            for behavior in feature["behaviors"]
            for test in behavior["verification"]["tests"]
            if not test["exists"]
        ]
        self.assertEqual(missing_tests, [])


if __name__ == "__main__":
    unittest.main()
