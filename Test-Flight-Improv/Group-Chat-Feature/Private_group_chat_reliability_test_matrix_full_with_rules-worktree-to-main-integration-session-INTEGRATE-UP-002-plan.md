# INTEGRATE-UP-002 Worktree-to-Main Integration Contract

Status: blocked_external_fixture

Source of truth:
- Source worktree: `/Users/I560101/Project-Sat/mknoon-2/worktrees/full-rules-pipeline`
- Historical source plan: `/Users/I560101/Project-Sat/mknoon-2/worktrees/full-rules-pipeline/Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_full_with_rules-session-UP-002-plan.md`
- Source row: `UP-002` / Timeline shows durable add, remove, and re-add events
- Row-owned source anchors:
  - `test/features/groups/application/group_membership_timeline_message_test.dart`: readable durable add/remove/re-add timeline event builders
  - `test/features/groups/integration/group_membership_smoke_test.dart`: `UP-002 timeline shows durable add remove and re-add events after reopen`
  - `integration_test/group_multi_party_device_real_harness.dart`, `integration_test/scripts/group_multi_party_device_criteria.dart`, and `test/integration/group_multi_party_device_criteria_test.dart`: `up002DurableTimelineProof` on `private_timeline_truth`

Imported delta:
- Added the row-owned application proof that membership add/remove timeline messages are readable, stable, ordered, delivered/incoming, and durable across re-add.
- Added the row-owned fake-network proof that Alice, Bob, and Charlie retain durable add, remove, and re-add timeline rows after listener restart/reopen, with final membership Alice/Bob/Charlie.
- Added the row-owned criteria and live-harness proof fields for `up002DurableTimelineProof` on `private_timeline_truth`, requiring two add timeline events around one removal event, final epoch convergence, and final member-list/timeline consistency.

Out of scope:
- No original source worktree plan recreation or rerun.
- No UP-003 compose gating, UP-004 unread-count proof, UP-005 invite state, UP-006 banner/system-row stale-state proof, notification rows, media/reaction rows, source-doc, COMPLETE_1 doc, Android, physical iOS, production rewrite, or unrelated residual repair.
- Source UP-006 timeline-message assertions and later `private_timeline_truth` proof fields were not imported during this row.

Verification evidence:
- `dart format --set-exit-if-changed test/features/groups/application/group_membership_timeline_message_test.dart test/features/groups/integration/group_membership_smoke_test.dart integration_test/group_multi_party_device_real_harness.dart integration_test/scripts/group_multi_party_device_criteria.dart test/integration/group_multi_party_device_criteria_test.dart` - pass with 0 changed after formatting.
- `flutter test --no-pub test/features/groups/application/group_membership_timeline_message_test.dart --plain-name "UP-002 builds readable durable add remove and re-add timeline events"` - pass.
- `flutter test --no-pub test/features/groups/integration/group_membership_smoke_test.dart --plain-name "UP-002 timeline shows durable add remove and re-add events after reopen"` - pass.
- `flutter test --no-pub test/integration/group_multi_party_device_criteria_test.dart --plain-name "UP-002"` - pass.
- `flutter test --no-pub test/integration/group_multi_party_device_criteria_test.dart --plain-name "private_timeline_truth"` - pass.
- `flutter test --no-pub test/features/groups/integration/group_membership_smoke_test.dart --plain-name "GM-024"` - pass.
- Scoped `dart analyze test/features/groups/application/group_membership_timeline_message_test.dart test/features/groups/integration/group_membership_smoke_test.dart integration_test/group_multi_party_device_real_harness.dart integration_test/scripts/group_multi_party_device_criteria.dart test/integration/group_multi_party_device_criteria_test.dart` - pass, `No issues found!`.
- Scoped `git diff --check` over the touched UP-002 code/test/harness files - pass before doc closure.

Live proof blocker:
- Required current iOS 26.2 proof `private_timeline_truth` failed twice before any UP-002 proof map could be emitted.
- First current-main run `1779318990228`, shared dir `/var/folders/nd/_55d26s936d0fb_5l9s00t980000gn/T/group_multi_party_private_timeline_truth_n9VBNV`, used Alice `5A9A8286-001B-4BF1-8F40-5A3AB8BF8FE3`, Bob `279B82AE-2BB9-4924-9AAE-581870ED3FA9`, and Charlie `116B4AF6-C1A9-4F36-B929-0A7130B5E83C`. Charlie timed out in the existing `_waitForSelfRemoval` path; Bob timed out waiting for `gmp_1779318990228_rejoin_key.json`; Alice timed out waiting for `gmp_1779318990228_charlie_self_removed`; orchestrator exited before verdict.
- Retry run `1779319473323`, shared dir `/var/folders/nd/_55d26s936d0fb_5l9s00t980000gn/T/group_multi_party_private_timeline_truth_Ajm5fk`, used Alice `5A9A8286-001B-4BF1-8F40-5A3AB8BF8FE3`, Bob `279B82AE-2BB9-4924-9AAE-581870ED3FA9`, and spare iOS 26.2 Charlie `CD5929A6-EA0A-421D-A6D3-55BD707E0F76`. It reproduced the same blocker: Charlie timed out in `_waitForSelfRemoval`, Bob timed out waiting for `gmp_1779319473323_rejoin_key.json`, Alice timed out waiting for `gmp_1779319473323_charlie_self_removed`, and orchestrator exited before verdict.

Controller status:
- Host, fake-network, criteria, format, analyzer, diff, and GM-024 preservation evidence passed.
- The row remains `blocked_external_fixture` because the required live proof is blocked in the pre-existing `private_timeline_truth` / ML-015 self-removal and rejoin handoff path before UP-002's imported assertion fields execute.
- Safe next action is `INTEGRATE-UP-003` because lookahead scouts and controller disk checks show UP-003 uses `private_readd_current` and is dependency-independent from the blocked `private_timeline_truth` path. `INTEGRATE-UP-004` shares `private_timeline_truth` and must preserve the UP-002 blocker evidence before execution.
