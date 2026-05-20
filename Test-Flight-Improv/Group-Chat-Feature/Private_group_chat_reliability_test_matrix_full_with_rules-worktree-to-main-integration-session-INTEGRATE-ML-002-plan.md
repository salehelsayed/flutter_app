# INTEGRATE-ML-002 Worktree-To-Main Integration Contract

Status: accepted

## Row Contract

- Source row: `ML-002`
- Scenario: Add an online member and prove immediate live delivery.
- Active mode: standard integration.
- This is import/reconcile/verify work only. It is not gap-closure mode and not a new implementation rollout.
- Reuse the original worktree implementation plan and closure evidence as historical source-of-truth; do not recreate, rewrite, or rerun that implementation plan.

## Historical Evidence To Reuse

- Source matrix row: `/Users/I560101/Project-Sat/mknoon-2/worktrees/full-rules-pipeline/Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_full_with_rules.md`
- Source row plan/evidence: `/Users/I560101/Project-Sat/mknoon-2/worktrees/full-rules-pipeline/Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_full_with_rules-session-ML-002-plan.md`
- Source closure status: accepted.
- Source focused evidence:
  - `flutter test --plain-name "ML-002" test/features/groups/integration/group_messaging_smoke_test.dart`
  - `flutter test --plain-name "ML-002" test/integration/group_multi_party_device_criteria_test.dart`
  - `flutter test test/integration/group_multi_party_device_criteria_test.dart test/integration/group_multi_party_device_discovery_test.dart`
  - direct supporting group suites covering add/member invite/listener/membership smoke behavior
  - `FLUTTER_DEVICE_ID=macos ./scripts/run_test_gates.sh groups`
  - `./scripts/run_test_gates.sh completeness-check`
  - historical exact-relay iOS 26.2 four-device `private_online_add` proof.

## Exact Worktree Changed-File Inventory

Meaningful ML-002 row-owned files from the historical plan:

- `test/features/groups/integration/group_messaging_smoke_test.dart`
- `integration_test/group_multi_party_device_real_harness.dart`
- `integration_test/scripts/group_multi_party_device_criteria.dart`
- `test/integration/group_multi_party_device_criteria_test.dart`

Integration-only invocation support needed in main:

- `integration_test/scripts/run_group_multi_party_device_real.dart`

Source matrix, source breakdown, and source test-inventory edits are historical evidence only and must not be copied as implementation output.

## Main Compatibility And Duplicate Check

- Main does not contain the ML-002 smoke selector `ML-002`.
- Main does not contain the `private_online_add` scenario requirement, `ml002OnlineAddProof`, or Bob-to-Dana no-drain proof checks.
- Main has overlapping COMPLETE_1 row `GM-002` online-add coverage in `group_messaging_smoke_test.dart`, `group_multi_party_device_real_harness.dart`, and criteria tests. Preserve GM-002 as supporting context; do not duplicate or relabel it as ML-002.
- Main already contains ML-001 `private_abc_create` proof fields and runner support. Preserve that row and add only the ML-002 private online-add path.
- COMPLETE_1 overlap rows to preserve while importing: `GM-002`, `GM-003`, `GE-016`, `GP-028`, and the already accepted worktree `ML-001` plus `BB-001` through `BB-016`.

## Integration Actions

1. Inspect the source row entry, historical plan, closure evidence, and COMPLETE_1 overlaps before editing.
2. Import only the missing ML-002-owned host smoke proof, `private_online_add` scenario requirement, criteria accept/reject tests, criteria proof validation, harness proof fields, and minimal runner scenario entry.
3. Preserve existing GM-002 harness behavior; the ML-002 path may reuse GM-002 setup but must emit row-specific proof and require Bob post-join delivery to Dana without offline drain.
4. Do not import adjacent ML-003, ML-005, GM, DE, KE, PL, NW, RA, media, notification, security, or broader lifecycle changes.
5. If a same-file conflict appears, map the affected worktree row and COMPLETE_1/main row before resolving.

## Verification Contract

Required before acceptance:

- `flutter test --no-pub test/features/groups/integration/group_messaging_smoke_test.dart --plain-name "ML-002"`
- `flutter test --no-pub test/integration/group_multi_party_device_criteria_test.dart --plain-name "ML-002"`
- affected main/COMPLETE_1 preservation tests for `GM-002` criteria/smoke behavior.
- `dart analyze` for the touched Dart files.
- `dart format --set-exit-if-changed` for the touched Dart files.
- `FLUTTER_DEVICE_ID=macos ./scripts/run_test_gates.sh groups`
- row-scoped `git diff --check`.

Device proof handling:

- Check current four-device iOS simulator/relay availability before claiming live `private_online_add` proof in main.
- If the required four-device fixture is unavailable, record the live proof as an external fixture blocker rather than overclaiming. Host-side imported tests may still be recorded as passing evidence.

## Integration Result

Verdict: `accepted`

ML-002 was imported as a row-owned integration delta into main. The original worktree implementation plan and closure evidence remained historical source-of-truth only; no original plan was recreated, rewritten, or rerun.

Accepted files:

- `test/features/groups/integration/group_messaging_smoke_test.dart`
- `integration_test/scripts/group_multi_party_device_criteria.dart`
- `test/integration/group_multi_party_device_criteria_test.dart`
- `integration_test/group_multi_party_device_real_harness.dart`
- `integration_test/scripts/run_group_multi_party_device_real.dart`
- `Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_full_with_rules-worktree-to-main-integration-session-INTEGRATE-ML-002-plan.md`

Skipped duplicate or out-of-row work:

- Source worktree matrix, source breakdown, source test-inventory edits, and source closure docs were not copied.
- COMPLETE_1 documentation was not modified.
- Existing GM-002 online-add coverage was preserved as overlap support and was not duplicated or relabeled.
- Existing BB-001 through BB-016 and ML-001 integration work was preserved.
- No ML-003, ML-005, GM, DE, KE, PL, NW, RA, media, notification, security, or broader membership-lifecycle work was imported.

## Acceptance Evidence

- `dart format --set-exit-if-changed test/features/groups/integration/group_messaging_smoke_test.dart integration_test/scripts/group_multi_party_device_criteria.dart test/integration/group_multi_party_device_criteria_test.dart integration_test/group_multi_party_device_real_harness.dart integration_test/scripts/run_group_multi_party_device_real.dart` PASS (`0 changed`).
- `dart analyze test/features/groups/integration/group_messaging_smoke_test.dart integration_test/scripts/group_multi_party_device_criteria.dart test/integration/group_multi_party_device_criteria_test.dart integration_test/group_multi_party_device_real_harness.dart integration_test/scripts/run_group_multi_party_device_real.dart` PASS (`No issues found!`).
- `flutter test --no-pub test/features/groups/integration/group_messaging_smoke_test.dart --plain-name "ML-002"` PASS (`+1`).
- `flutter test --no-pub test/integration/group_multi_party_device_criteria_test.dart --plain-name "ML-002"` PASS (`+4`).
- `flutter test --no-pub test/features/groups/integration/group_messaging_smoke_test.dart --plain-name "GM-002"` PASS (`+1`).
- `flutter test --no-pub test/integration/group_multi_party_device_criteria_test.dart --plain-name "GM-002"` PASS (`+2`).
- `flutter test --no-pub test/integration/group_multi_party_device_criteria_test.dart` PASS (`+204`).
- `dart run integration_test/scripts/run_group_multi_party_device_real.dart --scenario private_online_add --list-scenarios` PASS; `private_online_add` is listed.
- `FLUTTER_DEVICE_ID=macos ./scripts/run_test_gates.sh groups` PASS (`+169`).
- Four-device iOS 26.2 relay-backed `private_online_add` proof PASS with run id `1778992215502` and shared directory `/var/folders/nd/_55d26s936d0fb_5l9s00t980000gn/T/group_multi_party_private_online_add_bGgREm`.
- Live proof roles Alice, Bob, Charlie, and Dana agreed on group id `c9b1d1dd-4e51-4c5e-90a7-4a3302ad9acc`, key epoch `1`, active membership, and group config state hash `931610bb005e48876d721c299247dfe0a904526de1c63f0c9a3d8a1e4a4750a1`.
- Dana received Alice and Bob post-join messages exactly once with `liveOnly: true` and `usedOfflineDrain: false`.
- `./scripts/run_test_gates.sh completeness-check` failed only on unrelated/pre-existing unclassified `test/shared/fakes/fake_group_pubsub_network_test.dart`.

## Main Compatibility Notes

- A first live attempt exposed a main harness timestamp split: Alice/Dana hashed the add-member config version while Bob/Charlie hashed a later `members_added` system event timestamp.
- The accepted row-owned compatibility delta publishes ML-002 `members_added` system payloads with Dana's add-member config timestamp so the live proof compares the same effective config version across roles.
- No production files were touched for ML-002.
- No COMPLETE_1 conflict was found; affected GM-002 preservation tests passed.

## Final Status Rule

Mark this session exactly one of:

- `accepted` when the ML-002 delta is imported or verified already present and all required available tests pass, including live fixture proof when available.
- `skipped_already_present` only if the exact ML-002 smoke selector, criteria proof, and harness path are already present in main with evidence.
- `blocked_conflict` if row-owned ML-002 changes conflict with named main/COMPLETE_1 row contracts.
- `blocked_external_fixture` if the only remaining blocker is unavailable live device/relay fixture proof.
