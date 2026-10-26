#!/usr/bin/env python3
"""Check candidate-bound MCP receipts; never connect to or control a device.

PASS_RECORDED means the executor supplied all required observations and files.
It does not independently interpret screenshots, measure audio, or certify a build.
"""

import argparse
from datetime import datetime, time
import hashlib
import json
from pathlib import Path
import re
from zoneinfo import ZoneInfo


CHECKS = {
    "RG-002": (
        "fresh_unseeded_install", "onboarding_ui", "real_contact_acceptance",
        "reciprocal_keys", "first_direct_both_ways", "first_group_all_members",
    ),
    "CR-009": (
        "ios_initiates_real_add", "android_initiates_real_add",
        "explicit_acceptance_and_keys", "first_text_both_ways", "reopen_unique",
    ),
    "DC-011": (
        "text_exact_order_both_ways", "image_full_caption_both_ways",
        "video_content_both_ways", "voice_content_both_ways",
        "both_apps_restarted", "reopened_content_order_unique",
    ),
    "GX-002": (
        "mixed_three_member_group", "initial_all_entitled_receivers",
        "member_removed", "removed_window_no_leak",
        "member_readded_current_authority", "post_readd_all_entitled_receivers",
    ),
    "VC-015": (
        "ios_calls_android_answered", "android_calls_ios_answered",
        "ios_origin_audio_both_ways", "android_origin_audio_both_ways",
        "both_hangups_release_once",
    ),
    "VC-014": (
        "android_background_ring_answer_audio", "android_locked_ring_answer_audio",
        "ios_background_ring_answer_audio", "ios_locked_ring_answer_audio",
        "supported_process_termination", "no_stale_or_duplicate_call",
    ),
}
AUDIO_CHECKS = {
    "video_content_both_ways", "voice_content_both_ways",
    "ios_origin_audio_both_ways", "android_origin_audio_both_ways",
    "android_background_ring_answer_audio", "android_locked_ring_answer_audio",
    "ios_background_ring_answer_audio", "ios_locked_ring_answer_audio",
}


def template(case, source):
    platforms = ["android", "android"] if case == "RG-002" else ["ios", "android"]
    if case == "GX-002":
        platforms.append("android")
    return {
        "schema_version": 1, "case": case, "run_id": "",
        "source_revision": source, "availability": "available",
        "availability_evidence": [],
        "artifacts": {
            chr(65 + i): {"platform": platform, "source_revision": source,
                          "sha256": "", "version": ""}
            for i, platform in enumerate(platforms)
        },
        "checks": {key: {"status": "NOT_RUN", "evidence": [],
                         "observed_by": "", "started_at": ""}
                   for key in CHECKS[case]},
    }


def validate(receipt, source, root):
    errors, hashes = [], {}
    root = Path(root).resolve()

    def require(condition, reason):
        if not condition:
            errors.append(reason)

    def evidence(refs, label):
        require(isinstance(refs, list) and bool(refs), f"{label}: evidence required")
        if not isinstance(refs, list):
            return
        for ref in refs:
            if not isinstance(ref, str) or not ref or Path(ref).is_absolute():
                errors.append(f"{label}: evidence must be a relative file path")
                continue
            path = (root / ref).resolve()
            if not path.is_relative_to(root) or not path.is_file():
                errors.append(f"{label}: evidence missing or outside root")
            elif path.stat().st_size == 0:
                errors.append(f"{label}: empty evidence file")
            else:
                hashes[ref] = hashlib.sha256(path.read_bytes()).hexdigest()

    require(isinstance(receipt, dict), "receipt must be an object")
    if not isinstance(receipt, dict):
        return {"status": "INCOMPLETE", "problems": errors}
    case = receipt.get("case")
    valid_case = isinstance(case, str) and case in CHECKS
    require(valid_case, "unknown case")
    require(receipt.get("schema_version") == 1, "schema_version must be 1")
    require(isinstance(source, str) and bool(re.fullmatch(r"[0-9a-f]{40}", source)), "expected source must be a full Git revision")
    require(receipt.get("source_revision") == source, "candidate source mismatch")
    require(isinstance(receipt.get("run_id"), str) and bool(receipt["run_id"].strip()), "run_id required")
    availability = receipt.get("availability")
    require(isinstance(availability, str) and availability in {"available", "target_unavailable"}, "invalid availability")
    if availability == "target_unavailable":
        evidence(receipt.get("availability_evidence"), "live target availability")
    elif valid_case:
        artifacts = receipt.get("artifacts")
        require(isinstance(artifacts, dict), "artifact bindings required")
        artifacts = artifacts if isinstance(artifacts, dict) else {}
        require(len(artifacts) >= (3 if case == "GX-002" else 2), "insufficient bound roles")
        platforms = set()
        for role, artifact in artifacts.items():
            if not isinstance(artifact, dict):
                errors.append(f"{role}: invalid artifact")
                continue
            platform = artifact.get("platform")
            require(isinstance(platform, str) and platform in {"android", "ios"}, f"{role}: invalid platform")
            if isinstance(platform, str):
                platforms.add(platform)
            require(artifact.get("source_revision") == source, f"{role}: artifact source mismatch")
            require(isinstance(artifact.get("sha256"), str) and bool(re.fullmatch(r"[0-9a-f]{64}", artifact["sha256"])), f"{role}: artifact SHA-256 required")
            require(isinstance(artifact.get("version"), str) and bool(artifact["version"].strip()), f"{role}: artifact version required")
        if case != "RG-002":
            require({"android", "ios"} <= platforms, "actual Android and iOS roles required")
        checks = receipt.get("checks")
        checks = checks if isinstance(checks, dict) else {}
        for key in CHECKS[case]:
            check = checks.get(key)
            if not isinstance(check, dict):
                errors.append(f"{key}: observation missing")
                continue
            status = check.get("status")
            if key == "supported_process_termination" and status == "N/A":
                require(check.get("reason") == "unsupported_os_state", f"{key}: specific unsupported OS state required")
            else:
                require(status == "PASS", f"{key}: not passed")
            evidence(check.get("evidence"), key)
            if key in AUDIO_CHECKS and status == "PASS":
                require(check.get("observed_by") in {"human", "acoustic"}, f"{key}: content/audio observer required")
            if case.startswith("VC-") and status == "PASS":
                try:
                    started = datetime.fromisoformat(check.get("started_at", ""))
                    if started.tzinfo is None:
                        raise ValueError("timezone missing")
                    local = started.astimezone(ZoneInfo("Europe/Berlin"))
                    require(local.time() >= time(8, 30), f"{key}: call before 08:30 Europe/Berlin")
                except (TypeError, ValueError):
                    errors.append(f"{key}: timezone-aware call start required")
    status = "INCOMPLETE" if errors else ("N/A_TARGET_UNAVAILABLE" if availability == "target_unavailable" else "PASS_RECORDED")
    return {"case": case, "run_id": receipt.get("run_id"), "source_revision": source,
            "status": status, "problems": errors, "evidence_sha256": hashes}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("action", choices=["template", "check"])
    parser.add_argument("--source", required=True, help="Expected exact candidate Git revision")
    parser.add_argument("--case", choices=sorted(CHECKS))
    parser.add_argument("--receipt", type=Path)
    parser.add_argument("--evidence-root", type=Path)
    args = parser.parse_args()
    if args.action == "template":
        if not args.case:
            parser.error("template requires --case")
        print(json.dumps(template(args.case, args.source), indent=2))
        return 0
    if not args.receipt:
        parser.error("check requires --receipt")
    try:
        result = validate(json.loads(args.receipt.read_text()), args.source,
                          args.evidence_root or args.receipt.parent)
        if args.case and result.get("case") != args.case:
            result["status"] = "INCOMPLETE"
            result["problems"].append("receipt does not match requested case")
    except (OSError, ValueError, TypeError) as error:
        result = {"status": "INCOMPLETE", "problems": [type(error).__name__]}
    print(json.dumps(result, indent=2))
    return 1 if result["status"] == "INCOMPLETE" else 0


if __name__ == "__main__":
    raise SystemExit(main())
