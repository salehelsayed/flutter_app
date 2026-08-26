#!/usr/bin/env python3
"""Build Mknoon's revisioned intent → code evidence → proof index.

The repository is authoritative for code. Graphify is treated as an exact-anchor
navigation index, never as a behavioral oracle. Test declarations and recorded
runs remain separate so a file on disk cannot masquerade as a passing result.
"""

from __future__ import annotations

import argparse
import datetime as dt
import hashlib
import json
import os
import re
import subprocess
import sys
import tempfile
from collections import Counter, defaultdict
from pathlib import Path
from typing import Any, Iterable


DEFAULT_ROOT = Path(__file__).resolve().parents[2]
PROJECT_SCHEMA_VERSION = 1
GRAPH_MATCH_LIMIT = 6
RUN_STATUSES = {"passed", "failed", "blocked", "not_applicable"}
REVIEW_DECISIONS = {"confirmed", "rejected", "unclear"}
TEST_TYPES = {"unit", "integration", "contract", "native_unit", "device"}
UNAVAILABLE_REASON = "target unavailable by project policy"

ARCH_SOURCE_ROOTS = (
    "lib",
    "go-mknoon",
    "go-relay-server",
    "integration_test",
    "test",
    "scripts",
    "ios/NotificationService",
)
ARCH_SOURCE_SUFFIXES = {".dart", ".go", ".py", ".sh", ".swift"}
APPLICATION_DIRTY_ROOTS = (
    "lib",
    "go-mknoon",
    "go-relay-server",
    "integration_test",
    "test",
    "scripts",
    "ios",
    "android",
)


class ModelError(ValueError):
    """Raised when authored project data is internally inconsistent."""


def _utc_now() -> str:
    return dt.datetime.now(dt.timezone.utc).isoformat()


def _read_json(path: Path) -> dict[str, Any]:
    try:
        value = json.loads(path.read_text(encoding="utf-8"))
    except FileNotFoundError as error:
        raise ModelError(f"missing project data: {path}") from error
    except json.JSONDecodeError as error:
        raise ModelError(f"invalid JSON in {path}: {error}") from error
    if not isinstance(value, dict):
        raise ModelError(f"expected an object in {path}")
    return value


def _atomic_write_json(path: Path, value: dict[str, Any]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    handle, temporary_name = tempfile.mkstemp(
        prefix=f".{path.name}.", suffix=".tmp", dir=path.parent
    )
    try:
        with os.fdopen(handle, "w", encoding="utf-8") as temporary:
            json.dump(value, temporary, indent=2, ensure_ascii=False)
            temporary.write("\n")
            temporary.flush()
            os.fsync(temporary.fileno())
        os.replace(temporary_name, path)
    except BaseException:
        try:
            os.unlink(temporary_name)
        except FileNotFoundError:
            pass
        raise


def _require(condition: bool, message: str) -> None:
    if not condition:
        raise ModelError(message)


def _unique(items: Iterable[dict[str, Any]], key: str, label: str) -> dict[str, dict[str, Any]]:
    indexed: dict[str, dict[str, Any]] = {}
    for item in items:
        value = item.get(key)
        _require(isinstance(value, str) and bool(value), f"{label} has no {key}")
        _require(value not in indexed, f"duplicate {label} {value}")
        indexed[value] = item
    return indexed


def _resolve_within(base: Path, value: str, label: str) -> Path:
    _require(bool(value) and not Path(value).is_absolute(), f"{label} must be relative")
    resolved = (base / value).resolve()
    try:
        resolved.relative_to(base.resolve())
    except ValueError as error:
        raise ModelError(f"{label} escapes {base}: {value}") from error
    return resolved


def _git_output(root: Path, *arguments: str) -> str:
    try:
        result = subprocess.run(
            ["git", *arguments],
            cwd=root,
            check=True,
            capture_output=True,
            text=True,
        )
    except (OSError, subprocess.CalledProcessError):
        return ""
    return result.stdout.strip()


def repository_state(root: Path) -> dict[str, Any]:
    revision = _git_output(root, "rev-parse", "HEAD") or "unknown"
    dirty = _git_output(
        root,
        "status",
        "--porcelain",
        "--untracked-files=no",
        "--",
        *APPLICATION_DIRTY_ROOTS,
    )
    return {
        "revision": revision,
        "shortRevision": revision[:12] if revision != "unknown" else revision,
        "applicationDirty": bool(dirty),
    }


def _fingerprint(path: Path) -> str:
    if not path.exists():
        return "missing"
    stat = path.stat()
    payload = f"{stat.st_size}:{stat.st_mtime_ns}".encode()
    return hashlib.sha256(payload).hexdigest()[:16]


def architecture_freshness(root: Path, graph_path: Path) -> dict[str, Any]:
    if not graph_path.exists():
        return {"status": "missing", "newerSource": None}
    marker = root / "graphify-arch" / ".needs_incremental_refresh"
    if marker.exists():
        return {"status": "stale", "newerSource": marker.relative_to(root).as_posix()}
    graph_time = graph_path.stat().st_mtime_ns
    for root_name in ARCH_SOURCE_ROOTS:
        base = root / root_name
        if not base.exists():
            continue
        for path in base.rglob("*"):
            if not path.is_file() or path.suffix not in ARCH_SOURCE_SUFFIXES:
                continue
            if any(part in {"third_party", ".gocache", "testdata"} for part in path.parts):
                continue
            if path.name.startswith("app_localizations") and path.suffix == ".dart":
                continue
            if path.stat().st_mtime_ns > graph_time:
                return {
                    "status": "stale",
                    "newerSource": path.relative_to(root).as_posix(),
                }
    return {"status": "current", "newerSource": None}


def graph_metadata(root: Path, architecture_path: Path, full_path: Path) -> dict[str, Any]:
    root = root.resolve()
    architecture_path = architecture_path.resolve()
    full_path = full_path.resolve()
    return {
        "architecture": {
            "path": architecture_path.relative_to(root).as_posix(),
            "available": architecture_path.exists(),
            "fingerprint": _fingerprint(architecture_path),
            "freshness": architecture_freshness(root, architecture_path),
        },
        "fullFallback": {
            "path": full_path.relative_to(root).as_posix(),
            "available": full_path.exists(),
            "fingerprint": _fingerprint(full_path),
            "freshness": {
                "status": "not_checked",
                "newerSource": None,
                "reason": "The full graph is a fallback; exact evidence still requires source verification.",
            },
        },
    }


def _normalize_source(root: Path, value: object) -> str:
    source = str(value or "").replace("\\", "/")
    if not source:
        return ""
    marker = "/.graphify-arch-src/"
    if marker in source:
        return source.split(marker, 1)[1].removeprefix("./")
    candidate = Path(source)
    if candidate.is_absolute():
        try:
            return candidate.resolve().relative_to(root.resolve()).as_posix()
        except (OSError, ValueError):
            return candidate.as_posix()
    return source.removeprefix("./")


def _normalize_label(value: object) -> str:
    return str(value or "").strip().rstrip("()").casefold()


def _anchor_key(anchor: dict[str, Any]) -> tuple[str, str]:
    return str(anchor["kind"]), str(anchor["value"])


def _node_evidence(root: Path, node: dict[str, Any], scope: str) -> dict[str, Any]:
    return {
        "graph": scope,
        "nodeId": str(node.get("id") or ""),
        "label": str(node.get("label") or node.get("norm_label") or node.get("id") or ""),
        "sourceFile": _normalize_source(root, node.get("source_file")),
        "sourceLocation": str(node.get("source_location") or ""),
    }


def _collect_from_graph(
    root: Path,
    graph_path: Path,
    scope: str,
    anchors: list[dict[str, Any]],
    matches: dict[tuple[str, str], list[dict[str, Any]]],
) -> None:
    if not graph_path.exists() or not anchors:
        return
    try:
        raw = json.loads(graph_path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as error:
        raise ModelError(f"cannot load Graphify data {graph_path}: {error}") from error
    nodes = raw.get("nodes", [])
    _require(isinstance(nodes, list), f"Graphify nodes are invalid in {graph_path}")
    wanted_files = {
        str(anchor["value"]).removeprefix("./"): _anchor_key(anchor)
        for anchor in anchors
        if anchor["kind"] == "file"
    }
    wanted_symbols = {
        _normalize_label(anchor["value"]): _anchor_key(anchor)
        for anchor in anchors
        if anchor["kind"] == "symbol"
    }
    for node in nodes:
        if not isinstance(node, dict):
            continue
        source = _normalize_source(root, node.get("source_file"))
        keys: set[tuple[str, str]] = set()
        if source in wanted_files:
            keys.add(wanted_files[source])
        labels = {
            _normalize_label(node.get("label")),
            _normalize_label(node.get("norm_label")),
            _normalize_label(node.get("id")),
        }
        for label in labels:
            if label in wanted_symbols:
                keys.add(wanted_symbols[label])
        if not keys:
            continue
        evidence = _node_evidence(root, node, scope)
        for key in keys:
            bucket = matches[key]
            duplicate = any(
                row["nodeId"] == evidence["nodeId"] and row["graph"] == scope
                for row in bucket
            )
            if not duplicate and len(bucket) < GRAPH_MATCH_LIMIT:
                bucket.append(evidence)


def collect_graph_evidence(
    root: Path,
    anchors: list[dict[str, Any]],
    architecture_path: Path,
    full_path: Path,
) -> dict[tuple[str, str], list[dict[str, Any]]]:
    matches: dict[tuple[str, str], list[dict[str, Any]]] = defaultdict(list)
    _collect_from_graph(root, architecture_path, "architecture", anchors, matches)
    missing = [anchor for anchor in anchors if not matches[_anchor_key(anchor)]]
    _collect_from_graph(root, full_path, "full_fallback", missing, matches)
    return matches


def _load_feature(root: Path, feature_dir: Path) -> dict[str, Any]:
    feature = _read_json(feature_dir / "feature.json")
    feature_id = feature.get("id")
    _require(feature.get("schemaVersion") == PROJECT_SCHEMA_VERSION, f"{feature_dir}: unsupported feature schema")
    _require(feature_id == feature_dir.name, f"{feature_dir}: feature id must match directory")

    for key in (
        "title",
        "prd",
        "prdVersion",
        "intentStatus",
        "behaviorsFile",
        "coverageFile",
        "testResultsFile",
        "implementationReviewsFile",
    ):
        _require(isinstance(feature.get(key), str) and bool(feature[key]), f"{feature_id}: missing {key}")

    prd_path = _resolve_within(root, feature["prd"], f"{feature_id} PRD")
    behavior_path = _resolve_within(feature_dir, feature["behaviorsFile"], f"{feature_id} behaviors")
    coverage_path = _resolve_within(feature_dir, feature["coverageFile"], f"{feature_id} coverage")
    results_path = _resolve_within(feature_dir, feature["testResultsFile"], f"{feature_id} results")
    reviews_path = _resolve_within(feature_dir, feature["implementationReviewsFile"], f"{feature_id} reviews")

    behaviors_document = _read_json(behavior_path)
    coverage = _read_json(coverage_path)
    results = _read_json(results_path)
    reviews = _read_json(reviews_path)
    for label, document in (
        ("behaviors", behaviors_document),
        ("coverage", coverage),
        ("results", results),
        ("reviews", reviews),
    ):
        _require(document.get("schemaVersion") == PROJECT_SCHEMA_VERSION, f"{feature_id}: unsupported {label} schema")
        _require(document.get("featureId") == feature_id, f"{feature_id}: {label} featureId mismatch")

    behaviors = behaviors_document.get("behaviors")
    questions = behaviors_document.get("questions")
    tests = coverage.get("tests")
    mappings = coverage.get("mappings")
    runs = results.get("runs")
    review_rows = reviews.get("reviews")
    _require(isinstance(behaviors, list), f"{feature_id}: behaviors must be an array")
    _require(isinstance(questions, list), f"{feature_id}: questions must be an array")
    _require(isinstance(tests, list), f"{feature_id}: tests must be an array")
    _require(isinstance(mappings, list), f"{feature_id}: mappings must be an array")
    _require(isinstance(runs, list), f"{feature_id}: runs must be an array")
    _require(isinstance(review_rows, list), f"{feature_id}: reviews must be an array")

    behavior_by_id = _unique(behaviors, "id", "behavior")
    question_by_id = _unique(questions, "id", "question")
    test_by_id = _unique(tests, "id", "test")
    mapping_by_behavior = _unique(mappings, "behaviorId", "coverage mapping")
    _require(set(mapping_by_behavior) == set(behavior_by_id), f"{feature_id}: every behavior needs exactly one coverage mapping")

    for question_id, question in question_by_id.items():
        _require(isinstance(question.get("title"), str) and bool(question["title"].strip()), f"{question_id}: missing question title")
        _require(isinstance(question.get("prompt"), str) and bool(question["prompt"].strip()), f"{question_id}: missing question prompt")

    for behavior in behaviors:
        plain_description = behavior.get("plainDescription")
        _require(
            isinstance(plain_description, str) and bool(plain_description.strip()),
            f"{behavior['id']}: needs a plainDescription",
        )
        _require(
            len(plain_description) <= 240,
            f"{behavior['id']}: plainDescription must be 240 characters or fewer",
        )
        open_question_ids = behavior.get("openQuestions", [])
        _require(isinstance(open_question_ids, list), f"{behavior['id']}: openQuestions must be an array")
        unknown_questions = set(open_question_ids) - set(question_by_id)
        _require(not unknown_questions, f"{behavior['id']}: unknown questions {sorted(unknown_questions)}")
        anchors = behavior.get("implementationAnchors")
        proof_policy = behavior.get("proofPolicy")
        _require(isinstance(anchors, list) and bool(anchors), f"{behavior['id']}: needs implementation anchors")
        _require(isinstance(proof_policy, dict), f"{behavior['id']}: needs proofPolicy")
        _require(isinstance(proof_policy.get("requiredBoundaries"), list), f"{behavior['id']}: requiredBoundaries must be an array")
        for anchor in anchors:
            _require(isinstance(anchor, dict), f"{behavior['id']}: invalid anchor")
            _require(anchor.get("kind") in {"file", "symbol"}, f"{behavior['id']}: invalid anchor kind")
            _require(isinstance(anchor.get("value"), str) and bool(anchor["value"]), f"{behavior['id']}: empty anchor")
            _require(isinstance(anchor.get("required"), bool), f"{behavior['id']}: anchor required must be boolean")

    for test_id, test in test_by_id.items():
        _require(isinstance(test.get("path"), str), f"{test_id}: missing path")
        _resolve_within(root, test["path"], f"{test_id} path")
        _require(test.get("testType") in TEST_TYPES, f"{test_id}: invalid testType")
        _require(isinstance(test.get("boundaries"), list) and test["boundaries"], f"{test_id}: missing boundaries")

    for behavior_id, mapping in mapping_by_behavior.items():
        test_ids = mapping.get("testIds")
        _require(isinstance(test_ids, list), f"{behavior_id}: testIds must be an array")
        unknown = set(test_ids) - set(test_by_id)
        _require(not unknown, f"{behavior_id}: unknown tests {sorted(unknown)}")

    for run in runs:
        _require(isinstance(run, dict), f"{feature_id}: invalid run")
        _require(run.get("testId") in test_by_id, f"{feature_id}: run references unknown test {run.get('testId')}")
        _require(run.get("status") in RUN_STATUSES, f"{feature_id}: invalid run status")
        if run.get("status") == "not_applicable":
            _require(UNAVAILABLE_REASON in str(run.get("reason") or "").casefold(), f"{feature_id}: not_applicable requires project-policy reason")

    for review in review_rows:
        _require(isinstance(review, dict), f"{feature_id}: invalid review")
        _require(review.get("behaviorId") in behavior_by_id, f"{feature_id}: review references unknown behavior")
        _require(review.get("decision") in REVIEW_DECISIONS, f"{feature_id}: invalid review decision")
        evidence = review.get("evidence")
        _require(isinstance(evidence, list) and bool(evidence), f"{feature_id}: implementation review needs evidence")

    return {
        "feature": feature,
        "featureDir": feature_dir,
        "prdPath": prd_path,
        "behaviors": behaviors,
        "behaviorById": behavior_by_id,
        "questionById": question_by_id,
        "tests": tests,
        "testById": test_by_id,
        "mappingByBehavior": mapping_by_behavior,
        "runs": runs,
        "reviews": review_rows,
        "resultsPath": results_path,
    }


def _latest(rows: Iterable[dict[str, Any]], time_key: str) -> dict[str, Any] | None:
    values = list(rows)
    if not values:
        return None
    return max(values, key=lambda row: str(row.get(time_key) or ""))


def _current_run(run: dict[str, Any] | None, repository: dict[str, Any]) -> bool:
    if not run:
        return False
    return bool(
        run.get("revision") == repository["revision"]
        and not run.get("workingTreeDirty", False)
        and not repository["applicationDirty"]
    )


def assess_implementation(
    behavior: dict[str, Any],
    matches: dict[tuple[str, str], list[dict[str, Any]]],
    reviews: list[dict[str, Any]],
    repository: dict[str, Any],
) -> dict[str, Any]:
    anchor_rows = []
    required_total = 0
    required_matched = 0
    matched_total = 0
    scopes: set[str] = set()
    for anchor in behavior["implementationAnchors"]:
        evidence = matches.get(_anchor_key(anchor), [])
        if anchor["required"]:
            required_total += 1
            required_matched += int(bool(evidence))
        matched_total += int(bool(evidence))
        scopes.update(row["graph"] for row in evidence)
        anchor_rows.append({**anchor, "matched": bool(evidence), "evidence": evidence})

    if matched_total == 0:
        graph_status = "not_evidenced"
    elif required_matched < required_total:
        graph_status = "partial"
    else:
        graph_status = "candidate"

    current_reviews = [
        row
        for row in reviews
        if row.get("behaviorId") == behavior["id"]
        and row.get("revision") == repository["revision"]
        and not repository["applicationDirty"]
    ]
    current_review = _latest(current_reviews, "reviewedAt")
    all_reviews = [row for row in reviews if row.get("behaviorId") == behavior["id"]]
    latest_review = _latest(all_reviews, "reviewedAt")
    review_state = "none"
    status = graph_status
    if current_review:
        review_state = "current"
        status = str(current_review["decision"])
    elif latest_review:
        review_state = "stale"

    return {
        "status": status,
        "graphStatus": graph_status,
        "matchedAnchors": matched_total,
        "totalAnchors": len(anchor_rows),
        "requiredMatched": required_matched,
        "requiredTotal": required_total,
        "graphScopes": sorted(scopes),
        "anchors": anchor_rows,
        "reviewState": review_state,
        "review": current_review or latest_review,
    }


def assess_verification(
    root: Path,
    behavior: dict[str, Any],
    mapping: dict[str, Any],
    test_by_id: dict[str, dict[str, Any]],
    runs: list[dict[str, Any]],
    repository: dict[str, Any],
) -> dict[str, Any]:
    run_by_test: dict[str, list[dict[str, Any]]] = defaultdict(list)
    for run in runs:
        run_by_test[str(run["testId"])].append(run)

    test_rows: list[dict[str, Any]] = []
    declared_boundaries: set[str] = set()
    satisfied_boundaries: set[str] = set()
    current_failed = False
    current_blocked = False
    stale_pass = False
    missing_files = False

    for test_id in mapping["testIds"]:
        declaration = test_by_id[test_id]
        path = _resolve_within(root, declaration["path"], f"{test_id} path")
        exists = path.is_file()
        missing_files = missing_files or not exists
        boundaries = set(str(value) for value in declaration["boundaries"])
        declared_boundaries.update(boundaries)
        latest_run = _latest(run_by_test.get(test_id, []), "recordedAt")
        is_current = _current_run(latest_run, repository)
        if not exists:
            state = "missing_file"
        elif latest_run is None:
            state = "not_run"
        elif not is_current:
            state = f"stale_{latest_run['status']}"
            stale_pass = stale_pass or latest_run["status"] == "passed"
        else:
            state = str(latest_run["status"])
            current_failed = current_failed or state == "failed"
            current_blocked = current_blocked or state == "blocked"
            unavailable_satisfies = (
                state == "not_applicable"
                and behavior["proofPolicy"].get("availabilityBounded", False)
                and UNAVAILABLE_REASON in str(latest_run.get("reason") or "").casefold()
            )
            if state == "passed" or unavailable_satisfies:
                satisfied_boundaries.update(boundaries)
        test_rows.append(
            {
                **declaration,
                "exists": exists,
                "state": state,
                "current": is_current,
                "latestRun": latest_run,
            }
        )

    required = set(str(value) for value in behavior["proofPolicy"]["requiredBoundaries"])
    undeclared = required - declared_boundaries
    missing = required - satisfied_boundaries
    if not test_rows or undeclared:
        status = "missing"
    elif missing_files:
        status = "invalid"
    elif current_failed:
        status = "failed"
    elif current_blocked:
        status = "blocked"
    elif not missing:
        status = "verified"
    elif satisfied_boundaries:
        status = "partial"
    elif stale_pass:
        status = "stale"
    else:
        status = "declared"

    return {
        "status": status,
        "requiredBoundaries": sorted(required),
        "declaredBoundaries": sorted(declared_boundaries),
        "satisfiedBoundaries": sorted(satisfied_boundaries),
        "missingBoundaries": sorted(missing),
        "undeclaredBoundaries": sorted(undeclared),
        "tests": test_rows,
    }


def derive_assessment(
    behavior: dict[str, Any],
    implementation: dict[str, Any],
    verification: dict[str, Any],
    graphs: dict[str, Any],
) -> dict[str, str]:
    if verification["status"] == "failed":
        return {"status": "failing_proof", "reason": "A current qualifying proof failed."}
    if implementation["status"] == "rejected":
        return {"status": "implementation_gap_reviewed", "reason": "A current bounded review rejected the implementation claim."}
    if behavior["intentStatus"] == "provisional":
        return {"status": "intent_open_question", "reason": "The requirement still depends on an unresolved product decision."}
    if graphs["architecture"]["freshness"]["status"] != "current":
        return {"status": "stale_evidence", "reason": "The architecture graph is not current."}
    if implementation["graphStatus"] == "not_evidenced":
        return {"status": "implementation_not_evidenced", "reason": "No exact declared implementation anchor matched."}
    if implementation["graphStatus"] == "partial":
        return {"status": "implementation_partial", "reason": "At least one required implementation anchor did not match."}
    if verification["status"] in {"missing", "invalid"}:
        return {"status": "test_gap", "reason": "Required qualifying proof is missing or invalid."}
    if verification["status"] == "blocked":
        return {"status": "proof_blocked", "reason": "A current qualifying proof is blocked."}
    if verification["status"] in {"declared", "stale"}:
        return {"status": "proof_not_run", "reason": "Proof is declared but no current qualifying pass is recorded."}
    if verification["status"] == "partial":
        return {"status": "proof_partial", "reason": "Only part of the required proof boundary is current."}
    if verification["status"] == "verified" and implementation["status"] == "confirmed":
        return {"status": "covered", "reason": "Current proof and a revision-matched implementation review agree."}
    if verification["status"] == "verified":
        return {"status": "verified_candidate", "reason": "Current proof exists, but implementation remains a graph candidate."}
    return {"status": "investigate", "reason": "The evidence dimensions do not resolve to a terminal assessment."}


def _feature_summary(behaviors: list[dict[str, Any]]) -> dict[str, Any]:
    assessments = Counter(row["assessment"]["status"] for row in behaviors)
    verification_states = Counter(
        row["verification"]["status"] for row in behaviors
    )
    implementation_candidates = sum(
        row["implementation"]["graphStatus"] == "candidate" for row in behaviors
    )
    confirmed = sum(row["implementation"]["status"] == "confirmed" for row in behaviors)
    verified = sum(row["verification"]["status"] == "verified" for row in behaviors)
    return {
        "requiredBehaviors": len(behaviors),
        "implementationCandidates": implementation_candidates,
        "implementationConfirmed": confirmed,
        "verified": verified,
        "covered": assessments["covered"],
        "implementationNotEvidenced": sum(
            row["implementation"]["graphStatus"] == "not_evidenced"
            for row in behaviors
        ),
        "testGaps": verification_states["missing"] + verification_states["invalid"],
        "proofNotRun": verification_states["declared"] + verification_states["stale"],
        "proofPartial": verification_states["partial"],
        "openIntent": sum(row["intentStatus"] == "provisional" for row in behaviors),
        "failingProof": verification_states["failed"],
        "staleEvidence": assessments["stale_evidence"],
        "assessments": dict(sorted(assessments.items())),
    }


def build_index(
    root: Path = DEFAULT_ROOT,
    *,
    generated_at: str | None = None,
    architecture_path: Path | None = None,
    full_path: Path | None = None,
    repository: dict[str, Any] | None = None,
) -> dict[str, Any]:
    root = root.resolve()
    architecture_path = (
        architecture_path or root / "graphify-arch" / "graphify-out" / "graph.json"
    ).resolve()
    full_path = (full_path or root / "graphify-out" / "graph.json").resolve()
    repository = repository or repository_state(root)
    graphs = graph_metadata(root, architecture_path, full_path)

    feature_root = root / "project" / "features"
    feature_dirs = sorted(path.parent for path in feature_root.glob("*/feature.json"))
    _require(bool(feature_dirs), "no project feature contracts found")
    loaded = [_load_feature(root, feature_dir) for feature_dir in feature_dirs]
    all_anchors = [
        anchor
        for item in loaded
        for behavior in item["behaviors"]
        for anchor in behavior["implementationAnchors"]
    ]
    graph_matches = collect_graph_evidence(
        root, all_anchors, architecture_path, full_path
    )

    feature_rows: list[dict[str, Any]] = []
    for item in loaded:
        feature = item["feature"]
        behavior_rows = []
        for behavior in item["behaviors"]:
            implementation = assess_implementation(
                behavior, graph_matches, item["reviews"], repository
            )
            verification = assess_verification(
                root,
                behavior,
                item["mappingByBehavior"][behavior["id"]],
                item["testById"],
                item["runs"],
                repository,
            )
            assessment = derive_assessment(
                behavior, implementation, verification, graphs
            )
            behavior_rows.append(
                {
                    "id": behavior["id"],
                    "title": behavior["title"],
                    "plainDescription": behavior["plainDescription"],
                    "requirement": behavior["requirement"],
                    "sourceRefs": behavior["sourceRefs"],
                    "priority": behavior["priority"],
                    "intentStatus": behavior["intentStatus"],
                    "openQuestions": [
                        item["questionById"][question_id]
                        for question_id in behavior.get("openQuestions", [])
                    ],
                    "implementation": implementation,
                    "verification": verification,
                    "assessment": assessment,
                }
            )
        feature_rows.append(
            {
                "id": feature["id"],
                "title": feature["title"],
                "description": feature.get("description", ""),
                "intentStatus": feature["intentStatus"],
                "prd": {
                    "path": feature["prd"],
                    "exists": item["prdPath"].is_file(),
                    "version": feature["prdVersion"],
                    "date": feature.get("prdDate"),
                },
                "openQuestions": feature.get("openQuestions", []),
                "summary": _feature_summary(behavior_rows),
                "behaviors": behavior_rows,
            }
        )

    project_assessments = Counter(
        behavior["assessment"]["status"]
        for feature in feature_rows
        for behavior in feature["behaviors"]
    )
    summary = {
        "features": len(feature_rows),
        "requiredBehaviors": sum(feature["summary"]["requiredBehaviors"] for feature in feature_rows),
        "implementationCandidates": sum(feature["summary"]["implementationCandidates"] for feature in feature_rows),
        "implementationConfirmed": sum(feature["summary"]["implementationConfirmed"] for feature in feature_rows),
        "verified": sum(feature["summary"]["verified"] for feature in feature_rows),
        "covered": sum(feature["summary"]["covered"] for feature in feature_rows),
        "testGaps": sum(feature["summary"]["testGaps"] for feature in feature_rows),
        "implementationNotEvidenced": sum(feature["summary"]["implementationNotEvidenced"] for feature in feature_rows),
        "proofNotRun": sum(feature["summary"]["proofNotRun"] for feature in feature_rows),
        "proofPartial": sum(feature["summary"]["proofPartial"] for feature in feature_rows),
        "openIntent": sum(feature["summary"]["openIntent"] for feature in feature_rows),
        "failingProof": sum(feature["summary"]["failingProof"] for feature in feature_rows),
        "staleEvidence": sum(feature["summary"]["staleEvidence"] for feature in feature_rows),
        "assessments": dict(sorted(project_assessments.items())),
    }
    return {
        "schemaVersion": PROJECT_SCHEMA_VERSION,
        "generatedAt": generated_at or _utc_now(),
        "repository": repository,
        "graphs": graphs,
        "evidencePolicy": {
            "graphMatchesAreCandidates": True,
            "graphMissesAreNotAbsenceProof": True,
            "testFilesAreNotRunResults": True,
            "coveredRequiresCurrentReviewAndProof": True,
        },
        "summary": summary,
        "features": feature_rows,
    }


def _comparable(value: dict[str, Any]) -> dict[str, Any]:
    clone = json.loads(json.dumps(value))
    clone.pop("generatedAt", None)
    return clone


def build_command(args: argparse.Namespace) -> int:
    root = Path(args.repo_root).resolve()
    output = Path(args.output)
    if not output.is_absolute():
        output = root / output
    index = build_index(root)
    if args.check:
        if not output.exists():
            print(f"project index missing: {output}", file=sys.stderr)
            return 1
        current = _read_json(output)
        if _comparable(current) != _comparable(index):
            print(f"project index is stale: {output}", file=sys.stderr)
            return 1
        print(f"project index is current: {output.relative_to(root)}")
        return 0
    _atomic_write_json(output, index)
    summary = index["summary"]
    print(
        "project index built: "
        f"{summary['features']} feature(s), {summary['requiredBehaviors']} behavior(s), "
        f"{summary['implementationCandidates']} implementation candidate(s), "
        f"{summary['verified']} verified"
    )
    print(output.relative_to(root))
    return 0


def record_run_command(args: argparse.Namespace) -> int:
    root = Path(args.repo_root).resolve()
    feature_dir = root / "project" / "features" / args.feature
    loaded = _load_feature(root, feature_dir)
    _require(args.test_id in loaded["testById"], f"unknown test id {args.test_id}")
    _require(args.status in RUN_STATUSES, f"invalid run status {args.status}")
    if args.status == "not_applicable":
        _require(args.reason and UNAVAILABLE_REASON in args.reason.casefold(), "not_applicable requires the exact project-policy reason")
    if args.platform in {"android", "ios"}:
        _require(bool(args.target) and not re.search(r"[<>*]", args.target), "device evidence requires an explicit discovered target id")

    repository = repository_state(root)
    run = {
        "testId": args.test_id,
        "status": args.status,
        "revision": repository["revision"],
        "workingTreeDirty": repository["applicationDirty"],
        "recordedAt": _utc_now(),
        "platform": args.platform,
        "target": args.target,
        "command": args.command,
    }
    if args.reason:
        run["reason"] = args.reason
    if args.artifact:
        run["artifacts"] = sorted(set(args.artifact))
    results = _read_json(loaded["resultsPath"])
    results["runs"].append(run)
    _atomic_write_json(loaded["resultsPath"], results)
    print(f"recorded {args.status}: {args.test_id} @ {repository['shortRevision']}")
    build_args = argparse.Namespace(
        repo_root=str(root),
        output=args.output,
        check=False,
    )
    return build_command(build_args)


def parser() -> argparse.ArgumentParser:
    root = str(DEFAULT_ROOT)
    default_output = "dashboard/project-data/project-index.json"
    result = argparse.ArgumentParser(description=__doc__)
    subparsers = result.add_subparsers(dest="command", required=True)

    build = subparsers.add_parser("build", help="validate contracts and build dashboard data")
    build.add_argument("--repo-root", default=root)
    build.add_argument("--output", default=default_output)
    build.add_argument("--check", action="store_true", help="fail when generated data differs")
    build.set_defaults(handler=build_command)

    record = subparsers.add_parser("record-run", help="append a revisioned test result")
    record.add_argument("--repo-root", default=root)
    record.add_argument("--output", default=default_output)
    record.add_argument("--feature", required=True)
    record.add_argument("--test-id", required=True)
    record.add_argument("--status", required=True, choices=sorted(RUN_STATUSES))
    record.add_argument("--platform", required=True)
    record.add_argument("--target", required=True)
    record.add_argument("--command", required=True)
    record.add_argument("--reason")
    record.add_argument("--artifact", action="append", default=[])
    record.set_defaults(handler=record_run_command)
    return result


def main(argv: list[str] | None = None) -> int:
    args = parser().parse_args(argv)
    try:
        return int(args.handler(args))
    except ModelError as error:
        print(f"project model error: {error}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
