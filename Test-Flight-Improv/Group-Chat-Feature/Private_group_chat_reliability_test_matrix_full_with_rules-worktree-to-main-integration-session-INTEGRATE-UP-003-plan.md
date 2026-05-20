# INTEGRATE-UP-003 Worktree-to-Main Integration Contract

Status: accepted

Source of truth:
- Source worktree: `/Users/I560101/Project-Sat/mknoon-2/worktrees/full-rules-pipeline`
- Historical source plan: `/Users/I560101/Project-Sat/mknoon-2/worktrees/full-rules-pipeline/Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_full_with_rules-session-UP-003-plan.md`
- Source row: `UP-003` / Compose box is enabled only for active members with current key
- Row-owned source anchors:
  - `test/features/groups/application/send_group_message_use_case_test.dart`: active member without current key cannot send until key is installed
  - `test/features/groups/presentation/group_conversation_wired_test.dart`: composer visibility/write capability tracks active membership plus current send key
  - `test/features/groups/integration/group_membership_smoke_test.dart`: removed and pending re-add member send attempts are rejected until current key is installed
  - `integration_test/group_multi_party_device_real_harness.dart`, `integration_test/scripts/group_multi_party_device_criteria.dart`, and `test/integration/group_multi_party_device_criteria_test.dart`: `up003ComposeGateProof` on `private_readd_current`

Imported delta:
- Production compose-gating behavior was already present in current main through active-member and current-send-key checks, so no production code changed.
- Added the row-owned application proof that an active member without a current group key cannot publish and does not write a local message until a current key is installed.
- Added the row-owned widget proof that stale removed callbacks do not publish, removed users see the read-only banner, pending re-add without a current key sees the key-wait banner, and the composer returns after current key installation.
- Added the row-owned fake-network proof that removed and pending re-add states reject send attempts before current key installation, then allow sending at the new epoch.
- Added the row-owned criteria and live-harness proof fields for `up003ComposeGateProof` on `private_readd_current`, requiring removed-state send rejection, pending re-add without-key rejection, no pending local ghost message, active post-key send, and final epoch >= 2.

Out of scope:
- No original source worktree plan recreation or rerun.
- No UP-004 unread-count proof, UP-005 invite state, UP-006 stale banner/system-row proof, notification rows, media/reaction rows, source-doc, COMPLETE_1 doc, Android, physical iOS, production rewrite, or unrelated residual repair.
- The UP-002 `private_timeline_truth` live fixture blocker stayed preserved and was not repaired or hidden by this row.

Verification evidence:
- `dart format --set-exit-if-changed test/features/groups/application/send_group_message_use_case_test.dart test/features/groups/presentation/group_conversation_wired_test.dart test/features/groups/integration/group_membership_smoke_test.dart integration_test/group_multi_party_device_real_harness.dart integration_test/scripts/group_multi_party_device_criteria.dart test/integration/group_multi_party_device_criteria_test.dart` - pass with 0 changed after formatting.
- `flutter test --no-pub test/features/groups/application/send_group_message_use_case_test.dart test/features/groups/presentation/group_conversation_wired_test.dart test/features/groups/integration/group_membership_smoke_test.dart test/integration/group_multi_party_device_criteria_test.dart --plain-name 'UP-003'` - pass.
- `flutter test --no-pub test/integration/group_multi_party_device_criteria_test.dart --plain-name 'private_readd_current'` - pass.
- Scoped `dart analyze test/features/groups/application/send_group_message_use_case_test.dart test/features/groups/presentation/group_conversation_wired_test.dart test/features/groups/integration/group_membership_smoke_test.dart integration_test/group_multi_party_device_real_harness.dart integration_test/scripts/group_multi_party_device_criteria.dart test/integration/group_multi_party_device_criteria_test.dart` - pass, `No issues found!`.
- Scoped `git diff --check` over the touched UP-003 code/test/harness files - pass before doc closure.
- Required iOS 26.2 proof `private_readd_current` passed with run id `1779320829314`, shared dir `/var/folders/nd/_55d26s936d0fb_5l9s00t980000gn/T/group_multi_party_private_readd_current_nhu2AN`, Alice `5A9A8286-001B-4BF1-8F40-5A3AB8BF8FE3`, Bob `279B82AE-2BB9-4924-9AAE-581870ED3FA9`, Charlie `116B4AF6-C1A9-4F36-B929-0A7130B5E83C`, and orchestrator verdict `private_readd_current proof passed: private_readd_current verdicts valid for alice, bob, charlie`.

Controller status:
- The row is accepted. Host, widget, fake-network, criteria, format, analyzer, diff, and required iOS 26.2 live proof evidence passed.
- Safe next action is `INTEGRATE-UP-004` after ledger sanity and dirty-state safety checks. UP-004 shares the `private_timeline_truth` live path already blocked by UP-002, so any UP-004 execution must preserve that blocker evidence while importing only row-owned host/criteria deltas.
