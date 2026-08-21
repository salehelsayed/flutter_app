#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT_DIR"

python3 - <<'PY'
from pathlib import Path

contracts = {
    "TC-393-01": [
        ("test/features/conversation/presentation/screens/conversation_wired_test.dart", "TC-393-01 direct read requires resumed exact tracking"),
        ("test/features/groups/presentation/group_conversation_wired_test.dart", "TC-393-01 group read fails closed on unknown lifecycle or tracker"),
    ],
    "TC-393-02": [
        ("test/core/notifications/app_visibility_route_binding_test.dart", "TC-393-02 exact activation cleanup is generation safe and read independent"),
        ("test/core/bootstrap/production_canonical_direct_projection_composition_test.dart", "TC-393-02 production wires exact generation cancellation"),
    ],
    "TC-393-03": [
        ("test/features/push/application/show_notification_use_case_test.dart", "TC-393-03 compatibility final visibility barrier"),
        ("test/features/push/application/background_push_notification_fallback_test.dart", "TC-393-03 all conversation fallbacks use the final visibility barrier"),
    ],
    "TC-393-04": [
        ("test/features/push/application/background_message_handler_test.dart", "TC-393-04 nondurable final barrier prevents canonical or visible race"),
    ],
    "TC-393-05": [
        ("test/features/push/application/background_storage_deadline_test.dart", "TC-393-05 display eligibility reserves measured native-entry tail without policy bypass"),
    ],
    "TC-393-06": [
        ("scripts/test/one_to_one_first_wake_profile_aot_contract_test.sh", "PASS: TC-393-06 profile-AOT first-wake capture is explicit and fail closed"),
        ("integration_test/one_to_one_reaction_notification_proof_test.dart", "artifact['testCase'], 'TC-393-06'"),
    ],
    "TC-393-07": [
        ("go-relay-server/group_content_push_test.go", "TestInboxStore_StrictGroupReactionWakesSignedAuthorDevice"),
        ("go-relay-server/group_content_push_test.go", "TestInboxStore_StrictGroupReactionBystanderStaysSilentCustody"),
    ],
    "TC-393-08": [
        ("test/integration/group_strict_notification_criteria_test.dart", "TC-393-08 strict notification artifact is fail closed"),
        ("tool/sims/critical_features.json", '"id": "groups.strict_notification_closure"'),
    ],
    "TC-393-09": [
        ("test/core/debug/group_notification_projection_e2e_test.dart", "TC-393-09 accepts only the fixed killed JPEG phase and role"),
        ("integration_test/scripts/group_notification_projection_android_criteria.dart", "groups.killed_group_photo_message"),
    ],
    "TC-393-10": [
        ("integration_test/scripts/group_notification_projection_android_criteria.dart", "groups.group_reaction_photo_semantic_kind"),
        ("integration_test/scripts/group_notification_projection_android_criteria.dart", "groups.group_reaction_video_semantic_kind"),
        ("integration_test/scripts/group_notification_projection_android_criteria.dart", "groups.group_reaction_voice_message_semantic_kind"),
    ],
    "TC-393-11": [
        ("test/tool/sims/sims_manifest_test.dart", "TC-393-11 fixed wake cohort is additive and exact"),
        ("tool/sims/critical_features.json", '"id": "android.production_fcm.fixed_wake"'),
        ("tool/sims/critical_features.json", '"id": "build.android.production_fcm.fixed_wake"'),
    ],
    "TC-393-12": [
        ("test/integration/android_notification_recovery_completion_criteria_test.dart", "TC-393-12 one controlled fixed-wake scenario is fail closed"),
        ("scripts/test/android_notification_recovery_completion_adapter_contract_test.sh", "PASS: TC-393-12 recovery adapter is one fixed-cohort two-transition campaign"),
    ],
    "TC-393-13": [
        ("test/core/bootstrap/production_headless_canonical_recovery_test.dart", "TC-393-13 authenticated direct reaction settles through inbox reconciler"),
        ("integration_test/scripts/capture_1to1_reaction_head_provenance.dart", "? 'TC-393-13'"),
    ],
    "TC-393-14": [
        ("test/features/push/application/background_message_handler_test.dart", "TC-393-14 direct post-show completion cannot be skipped"),
        ("integration_test/scripts/run_1to1_reaction_notification_sims.dart", "args.first != '--validate-g30-diagnostic-report'"),
    ],
    "TC-393-15": [
        ("test/integration/android_app_state_guard_test.dart", "TC-393-15 restore failure retains recovery backup and cannot become PASS"),
        ("scripts/test/plan393_notification_test_contract_census_test.sh", "PASS: TC-393-15 owns", 2),
        ("tool/runtime_roots/runtime_roots.json", '"id": "tooling.android-fixed-wake-recovery"', 2),
    ],
}

errors = []
for row, bindings in contracts.items():
    if not bindings:
        errors.append(f"{row}: no owned contract")
    for binding in bindings:
        path_text, literal = binding[:2]
        expected = binding[2] if len(binding) == 3 else 1
        path = Path(path_text)
        if not path.is_file():
            errors.append(f"{row}: missing {path_text}")
            continue
        count = path.read_text(encoding="utf-8").count(literal)
        if count != expected:
            errors.append(
                f"{row}: expected {expected} occurrence(s) of {literal!r} "
                f"in {path_text}, found {count}"
            )

if set(contracts) != {f"TC-393-{index:02d}" for index in range(1, 16)}:
    errors.append("census does not own exactly TC-393-01 through TC-393-15")

if errors:
    raise SystemExit("FAIL: Plan 393 contract census\n" + "\n".join(errors))

print("PASS: TC-393-15 owns exactly TC-393-01 through TC-393-15")
PY
