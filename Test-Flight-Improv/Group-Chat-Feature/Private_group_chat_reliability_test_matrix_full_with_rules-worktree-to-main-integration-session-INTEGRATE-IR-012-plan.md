# INTEGRATE-IR-012 Minimal Integration Contract

Status: accepted

## Source Evidence

- Source row: `IR-012` / `History repair verifies range hash and expected head before inserting messages`.
- Source worktree plan: `/Users/I560101/Project-Sat/mknoon-2/worktrees/full-rules-pipeline/Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_full_with_rules-session-IR-012-plan.md`.
- Source closure state: covered/accepted with direct app and fake-network hash/head repair validation proofs.
- Source proof profile: host-only. Unit, Integration, and Fake Network are required; Smoke and `3-Party E2E` are `N/A`.

This contract is only for importing and verifying the already-closed source row in main. It does not recreate or replace the historical source implementation plan.

## Integration Scope

IR-012 imports only missing row-owned proof artifacts for history repair range hash and expected-head validation before repaired messages are inserted:

- `test/features/groups/application/drain_group_offline_inbox_use_case_test.dart`
  - Added `IR-012 history repair rejects wrong hash and head before fallback insert`.
  - The test proves a bad-hash source inserts none of its supplied messages, a wrong-head source does not complete repair or stop fallback, and the later valid source inserts only the valid repaired range.
- `test/features/groups/integration/group_resume_recovery_test.dart`
  - Added `IR-012 fake-network repair rejects wrong hash and head then restores range before live delivery`.
  - The test proves the same bad-hash and wrong-head rejection through fake-network resume recovery, then verifies valid fallback repair restores ordered messages before later live delivery.

Production code stayed untouched because current main already validates `headMessageId`, response `rangeHash`, and computed range hash before `_applyRepairedHistoryMessages`, records source rejection diagnostics, and continues to later candidate sources.

Out of scope: `IR-010` history-gap parsing, `IR-011` request identity/source validation, `IR-013` unauthorized repair source injection, retention cutoff, relay ACL/privacy, media, UI, notifications, criteria/live harnesses, iOS 26.2 proof, and adjacent replay rows.

## Verification

Passed:

```bash
flutter test --no-pub test/features/groups/application/drain_group_offline_inbox_use_case_test.dart --plain-name 'IR-012'
flutter test --no-pub test/features/groups/integration/group_resume_recovery_test.dart --plain-name 'IR-012'
flutter test --no-pub test/features/groups/application/drain_group_offline_inbox_use_case_test.dart --name 'GI-026|GI-031|GI-032|GI-033|PREREQ-HISTORY-GAP-REPAIR detects|PREREQ-HISTORY-GAP-REPAIR rejects|PREREQ-HISTORY-GAP-REPAIR applies'
flutter test --no-pub test/features/groups/integration/group_resume_recovery_test.dart --plain-name 'PREREQ-HISTORY-GAP-REPAIR fake-network repair rejects bad source then restores range before live delivery'
flutter analyze --no-pub lib/features/groups/application/drain_group_offline_inbox_use_case.dart test/features/groups/application/drain_group_offline_inbox_use_case_test.dart test/features/groups/integration/group_resume_recovery_test.dart
dart format --set-exit-if-changed test/features/groups/application/drain_group_offline_inbox_use_case_test.dart test/features/groups/integration/group_resume_recovery_test.dart
git diff --check
```

Classified residual gates:

```bash
FLUTTER_DEVICE_ID=macos ./scripts/run_test_gates.sh groups
# +214 -3, red only on preserved non-IR-012 residuals BB-007, BB-012, and GM-029

./scripts/run_test_gates.sh completeness-check
# 732/733, red only on unrelated test/shared/fakes/fake_group_pubsub_network_test.dart classification
```

No iOS 26.2 simulator/live proof was run or required because source `3-Party E2E` is `N/A`.

## Closure Verdict

`INTEGRATE-IR-012` is accepted. Main now has row-owned direct and fake-network proofs that history repair rejects wrong range hash and wrong expected head before insertion, continues to a later valid source, and persists only the valid repaired range before accepting later live delivery.
