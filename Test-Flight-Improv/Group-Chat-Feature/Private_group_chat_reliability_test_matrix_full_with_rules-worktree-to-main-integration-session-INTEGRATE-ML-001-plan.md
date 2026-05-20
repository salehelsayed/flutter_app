# INTEGRATE-ML-001 Worktree-To-Main Integration Contract

Status: accepted

## Row Contract

- Source row: `ML-001`
- Scenario: Create a private group with A, B, and C and converge on the same active membership.
- Active mode: standard integration.
- This is import/reconcile/verify work only. It is not gap-closure mode and not a new implementation rollout.
- Reuse the original worktree implementation plan and closure evidence as historical source-of-truth; do not recreate, rewrite, or rerun that implementation plan.

## Historical Evidence To Reuse

- Source matrix row: `/Users/I560101/Project-Sat/mknoon-2/worktrees/full-rules-pipeline/Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_full_with_rules.md`
- Source row plan/evidence: `/Users/I560101/Project-Sat/mknoon-2/worktrees/full-rules-pipeline/Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_full_with_rules-session-ML-001-plan.md`
- Source closure status: accepted.
- Source focused evidence:
  - `flutter test --plain-name "ML-001" test/features/groups/integration/group_membership_smoke_test.dart`
  - `flutter test test/integration/group_multi_party_device_criteria_test.dart`
  - `flutter test test/features/groups/integration/group_membership_smoke_test.dart test/integration/group_multi_party_device_criteria_test.dart test/features/groups/application/create_group_with_members_use_case_test.dart test/features/groups/application/group_invite_listener_test.dart`
  - `FLUTTER_DEVICE_ID=macos ./scripts/run_test_gates.sh groups`
  - `./scripts/run_test_gates.sh completeness-check`
  - historical iOS 26.2 three-device `private_abc_create` proof.

## Exact Worktree Changed-File Inventory

Meaningful row-owned files from the historical ML-001 plan:

- `test/features/groups/integration/group_membership_smoke_test.dart`
- `integration_test/scripts/group_multi_party_device_criteria.dart`
- `test/integration/group_multi_party_device_criteria_test.dart`
- `integration_test/group_multi_party_device_real_harness.dart`

Source docs are evidence only and must not be copied as implementation output.

## Main Compatibility And Duplicate Check

- Main does not contain the ML-001 smoke selector `ML-001`.
- Main does not contain the `private_abc_create` device scenario or `ml001CreateInviteProof` criteria fields.
- Main has overlapping generic GM/GE multi-party coverage in the same criteria and harness files; preserve that work and import only the ML-001 private A/B/C create path.
- COMPLETE_1 overlap rows to preserve while importing: `GM-001`, `GM-010`, `GM-029`, `GP-008`, `GI-025`, `GE-017`, `GE-020`, plus adjacent private-group membership rows that share the harness surface.
- Source smoke selector includes `KE-001` in its name because initial epoch 1 is asserted. This integration session may import that assertion as part of ML-001 evidence but must not close `INTEGRATE-KE-001`.

## Integration Actions

1. Inspect the source row entry, historical plan, closure evidence, and main COMPLETE_1 overlaps before editing.
2. Import only the missing ML-001-owned smoke test, criteria validation, criteria fixtures/tests, and `private_abc_create` harness path.
3. Do not import adjacent ML-002, ML-003, KE, PL, NW, RA, media, notification, or security rows.
4. Do not duplicate existing GM/GE helpers or broader harness behavior already present in main.
5. If a same-file conflict appears, map the affected worktree row and COMPLETE_1/main row before resolving.

## Verification Contract

Required before acceptance:

- `flutter test --no-pub test/features/groups/integration/group_membership_smoke_test.dart --plain-name "ML-001"`
- `flutter test --no-pub test/integration/group_multi_party_device_criteria_test.dart --plain-name "private A/B/C create"`
- affected main/COMPLETE_1 criteria and harness tests for scenario requirements and existing GM/GE criteria behavior.
- formatting and row-scoped `git diff --check`.

Device proof handling:

- Check current device-fixture availability before claiming live `private_abc_create` proof in main.
- If the required three-device fixture is unavailable, record the live proof as an external fixture blocker rather than overclaiming. Host-side imported tests may still be recorded as passing evidence.

## Final Status Rule

Mark this session exactly one of:

- `accepted` when the ML-001 delta is imported or verified already present and all required available tests pass, including live fixture proof when available.
- `skipped_already_present` only if the exact ML-001 smoke selector, criteria proof, and harness path are already present in main with evidence.
- `blocked_conflict` if row-owned ML-001 changes conflict with named main/COMPLETE_1 row contracts.
- `blocked_external_fixture` if the only remaining blocker is unavailable live device/relay fixture proof.

## Integration Result

- Final status: `accepted`.
- Imported only the missing ML-001-owned private A/B/C create path into main:
  - `test/features/groups/integration/group_membership_smoke_test.dart`
  - `integration_test/scripts/group_multi_party_device_criteria.dart`
  - `test/integration/group_multi_party_device_criteria_test.dart`
  - `integration_test/group_multi_party_device_real_harness.dart`
  - `integration_test/scripts/run_group_multi_party_device_real.dart`
- The runner entry is a minimal integration-only addition so the row-owned `private_abc_create` live proof can be invoked from main.
- Skipped duplicate/broader work: existing GM/GE criteria and harness behavior was preserved; no adjacent ML-002, ML-003, KE, PL, NW, RA, media, notification, security, or source documentation work was imported.
- Conflict status: none found after preserving COMPLETE_1/main overlap rows and prior accepted BB rows.

## Acceptance Evidence

- `flutter test --no-pub test/features/groups/integration/group_membership_smoke_test.dart --plain-name "ML-001"` PASS (`+1`).
- `flutter test --no-pub test/integration/group_multi_party_device_criteria_test.dart --plain-name "private A/B/C create"` PASS (`+2`).
- `flutter test --no-pub test/integration/group_multi_party_device_criteria_test.dart` PASS (`+200`).
- `flutter test --no-pub test/features/groups/integration/group_membership_smoke_test.dart --plain-name "IJ010"` PASS (`+1`).
- `dart analyze test/features/groups/integration/group_membership_smoke_test.dart integration_test/scripts/group_multi_party_device_criteria.dart test/integration/group_multi_party_device_criteria_test.dart integration_test/group_multi_party_device_real_harness.dart integration_test/scripts/run_group_multi_party_device_real.dart` PASS (`No issues found!`).
- `dart format --set-exit-if-changed test/features/groups/integration/group_membership_smoke_test.dart integration_test/scripts/group_multi_party_device_criteria.dart test/integration/group_multi_party_device_criteria_test.dart integration_test/group_multi_party_device_real_harness.dart integration_test/scripts/run_group_multi_party_device_real.dart` PASS (`0 changed`).
- `dart run integration_test/scripts/run_group_multi_party_device_real.dart --scenario private_abc_create --list-scenarios` PASS and listed `private_abc_create`.
- `FLUTTER_DEVICE_ID=macos ./scripts/run_test_gates.sh groups` PASS (`+168`).
- iOS 26.2 three-device live proof PASS:
  - Scenario: `private_abc_create`.
  - Run id: `1778990166558`.
  - Verdict directory: `/var/folders/nd/_55d26s936d0fb_5l9s00t980000gn/T/group_multi_party_private_abc_create_kxWDE7`.
  - Final proof line: `private_abc_create proof passed: private_abc_create verdicts valid for alice, bob, charlie`.
  - Alice, Bob, and Charlie verdicts all reported key epoch `1`, topic `/mknoon/group/ae4094ab-ce8f-4291-b963-96ff99d405ae`, matching active member peer ids, matching config hash `ba620583bf0b75af45111aa169208079cbd3c273307082e37922477031f95681`, and row-specific `ml001CreateInviteProof` fields.

## Non-Row Residual

- `./scripts/run_test_gates.sh completeness-check` failed because `test/shared/fakes/fake_group_pubsub_network_test.dart` is currently unclassified (`732/733 test files classified`). That file is unrelated to ML-001 and was not modified by this row.
