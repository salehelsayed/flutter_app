# INTEGRATE-IR-013 Minimal Integration Contract

Status: accepted

## Source Evidence

- Source row: `IR-013` / `Unauthorized repair source cannot inject messages`.
- Source worktree plan: `/Users/I560101/Project-Sat/mknoon-2/worktrees/full-rules-pipeline/Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_full_with_rules-session-IR-013-plan.md`.
- Source closure state: covered/accepted with direct app and fake-network unauthorized repair-source rejection proofs.
- Source proof profile: host-only. Unit, Integration, and Fake Network are required; Smoke and `3-Party E2E` are `N/A`.

This contract is only for importing and verifying the already-closed source row in main. It does not recreate or replace the historical source implementation plan.

## Integration Scope

IR-013 imports only missing row-owned proof artifacts for unauthorized history-repair source rejection:

- `test/features/groups/application/drain_group_offline_inbox_use_case_test.dart`
  - Added `IR-013 unauthorized repair source cannot inject before fallback`.
  - The test proves an unauthorized `peer-rogue` candidate is recorded as attempted but receives no `group:historyRepairRange` request, a forged response claiming `peer-rogue` is rejected on an authorized source request, and the authorized fallback inserts only `ir013-valid-fallback`.
- `test/features/groups/integration/group_resume_recovery_test.dart`
  - Added `IR-013 fake-network unauthorized repair source cannot inject before fallback`.
  - The test proves the same unauthorized candidate skip, forged returned-source rejection, authorized fallback repair, and one-row persistence through the fake-network resume recovery harness.

Production code stayed untouched because current main already records unauthorized candidates as `unauthorized_source`, requests repair only from current authorized member sources, validates returned `sourcePeerId` against the requested source before applying repaired history, and continues to later candidate sources.

Out of scope: `IR-010` history-gap parsing, `IR-011` request identity/source validation, `IR-012` hash/head validation, retention cutoff, relay ACL/privacy, media, UI, notifications, criteria/live harnesses, iOS 26.2 proof, and adjacent replay rows.

## Verification

Passed:

```bash
flutter test --no-pub test/features/groups/application/drain_group_offline_inbox_use_case_test.dart --plain-name 'IR-013'
flutter test --no-pub test/features/groups/integration/group_resume_recovery_test.dart --plain-name 'IR-013'
flutter test --no-pub test/features/groups/application/drain_group_offline_inbox_use_case_test.dart --name 'IR-011|IR-012|GI-031|GI-032|GI-033|PREREQ-HISTORY-GAP-REPAIR'
flutter test --no-pub test/features/groups/integration/group_resume_recovery_test.dart --name 'IR-011|IR-012|PREREQ-HISTORY-GAP-REPAIR'
flutter analyze --no-pub lib/features/groups/application/drain_group_offline_inbox_use_case.dart test/features/groups/application/drain_group_offline_inbox_use_case_test.dart test/features/groups/integration/group_resume_recovery_test.dart
dart format --set-exit-if-changed test/features/groups/application/drain_group_offline_inbox_use_case_test.dart test/features/groups/integration/group_resume_recovery_test.dart
git diff --check
```

Classified residual gates:

```bash
FLUTTER_DEVICE_ID=macos ./scripts/run_test_gates.sh groups
# +215 -3, red only on preserved non-IR-013 residuals BB-007, BB-012, and GM-029

./scripts/run_test_gates.sh completeness-check
# 732/733, red only on unrelated test/shared/fakes/fake_group_pubsub_network_test.dart classification
```

No iOS 26.2 simulator/live proof was run or required because source `3-Party E2E` is `N/A`.

## Closure Verdict

`INTEGRATE-IR-013` is accepted. Main now has row-owned direct and fake-network proofs that an unauthorized repair source cannot receive a history repair request or inject repaired history through a forged response, while a later authorized fallback source still repairs the gap.
