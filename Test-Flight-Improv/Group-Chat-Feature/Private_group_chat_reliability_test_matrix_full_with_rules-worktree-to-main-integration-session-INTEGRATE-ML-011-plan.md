Status: skipped_already_present
Acceptance Status: skipped_already_present
Mode: standard worktree-to-main integration, not gap-closure
Source row: `ML-011 | Duplicate remove is idempotent and does not revoke a later re-add`
Integration row: `INTEGRATE-ML-011`

# INTEGRATE-ML-011 Worktree-to-Main Integration Plan

## Planning Evidence

- 2026-05-18 09:47 CEST - Started after `INTEGRATE-ML-010` reached `accepted` and the integration breakdown safe next action became `INTEGRATE-ML-011`.
- Source ML-011 is `Covered`/`accepted` in the worktree by `Private_group_chat_reliability_test_matrix_full_with_rules-session-ML-011-plan.md`.
- Source contract: duplicate remove handling is idempotent and must not revoke a later re-add; after a stale or duplicate remove arrives after a newer add/re-add, Bob and the other roles keep Charlie active exactly once, bridge validator/config state still includes Charlie, messaging after the newer membership state succeeds, and removed-window plaintext remains excluded.
- Source touched-file inventory from the historical row plan/evidence: `test/features/groups/application/group_message_listener_test.dart`; `test/features/groups/integration/group_membership_smoke_test.dart`; `test/integration/group_multi_party_device_criteria_test.dart`; `integration_test/scripts/group_multi_party_device_criteria.dart`; `integration_test/scripts/run_group_multi_party_device_real.dart`; `integration_test/group_multi_party_device_real_harness.dart`. No production source file touch is recorded for source ML-011.
- Current-main classification: source literals `ML-011`, `ml011DuplicateRemoveProof`, and `private_duplicate_remove` are not present. The meaningful behavior is already present in main through accepted COMPLETE_1-equivalent rows `GM-012` and `GM-009`. `GM-012` proves stale remove after newer re-add is ignored and Charlie remains active exactly once with matching config state; `GM-009` preserves duplicate same-event remove idempotence and non-duplication.
- Integration decision: `skipped_already_present`. No source `private_duplicate_remove` test/harness labels were imported because they would duplicate existing COMPLETE_1/main coverage without adding a missing row-owned behavior.

## Execution Evidence

- 2026-05-18 10:10 CEST - No code, production, test, criteria, runner, or harness files were modified for ML-011.
- Verification confirmed the already-present behavior using current main preservation selectors:
  - `flutter test --no-pub test/features/groups/application/group_message_listener_test.dart --plain-name 'GM-012'` passed `+1`.
  - `flutter test --no-pub test/features/groups/integration/group_membership_smoke_test.dart --plain-name 'GM-012 add then stale remove arrives out of order'` passed `+1`.
  - `flutter test --no-pub test/integration/group_multi_party_device_criteria_test.dart --plain-name 'GM-012'` passed `+7`.
  - `flutter test --no-pub test/features/groups/integration/group_membership_smoke_test.dart --plain-name 'GM-009 removes C twice idempotently, rotates at most once, and preserves A/B delivery'` passed `+1`.
  - `flutter test --no-pub test/integration/group_multi_party_device_criteria_test.dart --plain-name 'GM-009'` passed `+5`.
  - `dart run integration_test/scripts/run_group_multi_party_device_real.dart --scenario gm012 --list-scenarios` listed `gm012`.
  - `dart analyze integration_test/group_multi_party_device_real_harness.dart integration_test/scripts/group_multi_party_device_criteria.dart integration_test/scripts/run_group_multi_party_device_real.dart` reported `No issues found!`.
  - `git diff --check` passed before doc updates.
- Fresh iOS 26.2 live preservation proof passed for `gm012` with run id `1779088954770`, shared dir `/var/folders/nd/_55d26s936d0fb_5l9s00t980000gn/T/group_multi_party_gm012_wSbQ0T`, and orchestrator verdict `/var/folders/nd/_55d26s936d0fb_5l9s00t980000gn/T/group_multi_party_gm012_wSbQ0T/gmp_1779088954770_gm012_orchestrator_verdict.json`.
- Live proof details: orchestrator detail was `gm012 verdicts valid for alice, bob, charlie`; Alice, Bob, and Charlie recorded final `keyEpoch=2`, matching group id `15f66390-f579-494f-a034-115b6c8b0d94`, and matching `groupConfigStateHash=2f06159e092c21f2016c76f0cdb1c5757ff684b490fd3c01faf14c3358be6276`. All roles recorded `deliveredStaleRemoveVersion2=true`, `staleRemoveIgnored=true`, `memberListIncludesCharlie=true`, `validatorConfigIncludesCharlie=true`, `charlieMemberRowCount=1`, and `charlieActiveDeviceBindingCount=1`; Charlie recorded `groupPresentAfterStaleRemove=true`, `currentMemberAfterStaleRemove=true`, `postReaddPublishAccepted=true`, `hasStaleEpochAfterStaleRemove=false`, and `removedWindowPlaintextCount=0`.

## Scope

Allowed ML-011 integration action was limited to verifying whether the source row's meaningful behavior was already present in main and documenting the result.

Already-present and not duplicated: source duplicate-remove/stale-remove-after-readd behavior, exact Charlie single-row membership convergence, config/validator compatibility, and post-readd messaging proof through `GM-012` plus duplicate same-event remove idempotence through `GM-009`.

Out of scope: importing `private_duplicate_remove`, adding `ML-011` labels, adding `ml011DuplicateRemoveProof`, modifying production/test/harness files, source worktree docs, source matrix docs, COMPLETE_1 docs, `ML-012+`, concurrent admin edits, history, media, notification, key epoch policy, UI, and broader lifecycle cleanup.

## Required Verification

Focused already-present and overlap checks:

```bash
flutter test --no-pub test/features/groups/application/group_message_listener_test.dart --plain-name 'GM-012'
flutter test --no-pub test/features/groups/integration/group_membership_smoke_test.dart --plain-name 'GM-012 add then stale remove arrives out of order'
flutter test --no-pub test/integration/group_multi_party_device_criteria_test.dart --plain-name 'GM-012'
flutter test --no-pub test/features/groups/integration/group_membership_smoke_test.dart --plain-name 'GM-009 removes C twice idempotently, rotates at most once, and preserves A/B delivery'
flutter test --no-pub test/integration/group_multi_party_device_criteria_test.dart --plain-name 'GM-009'
dart run integration_test/scripts/run_group_multi_party_device_real.dart --scenario gm012 --list-scenarios
dart analyze integration_test/group_multi_party_device_real_harness.dart integration_test/scripts/group_multi_party_device_criteria.dart integration_test/scripts/run_group_multi_party_device_real.dart
git diff --check
```

Live preservation proof:

```bash
MKNOON_RELAY_ADDRESSES='/dns/mknoun.xyz/tcp/4001/wss/p2p/12D3KooWGMYMmN1RGUYjWaSV6P3XtnBjwnosnJGNMnttfVCRnd6g,/dns/mknoun.xyz/udp/4002/quic-v1/p2p/12D3KooWGMYMmN1RGUYjWaSV6P3XtnBjwnosnJGNMnttfVCRnd6g' dart run integration_test/scripts/run_group_multi_party_device_real.dart --scenario gm012 -d 5A9A8286-001B-4BF1-8F40-5A3AB8BF8FE3,279B82AE-2BB9-4924-9AAE-581870ED3FA9,116B4AF6-C1A9-4F36-B929-0A7130B5E83C
```

## Final Verdict

Skipped as already present for INTEGRATE-ML-011 only.

Structural blockers remaining: none.

Accepted row-owned delta: none. The source row's meaningful behavior is already covered by current-main `GM-012` plus `GM-009`; importing source literals would duplicate existing coverage.

Accepted differences intentionally left unchanged: no `private_duplicate_remove` scenario, no `ML-011` row labels, and no `ml011DuplicateRemoveProof` were added. Source worktree docs, source matrix docs, COMPLETE_1 docs, production/test/harness files, `ML-012+`, concurrent admin edits, history, media, notification, key epoch, UI, and broader lifecycle work remain out of scope.

Next action: resume the pipeline at INTEGRATE-ML-012.
