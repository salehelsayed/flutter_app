# INTEGRATE-UP-009 Worktree-to-Main Integration Contract

Status: blocked_external_fixture

Source of truth:
- Source worktree: `/Users/I560101/Project-Sat/mknoon-2/worktrees/full-rules-pipeline`
- Historical source plan: `/Users/I560101/Project-Sat/mknoon-2/worktrees/full-rules-pipeline/Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_full_with_rules-session-UP-009-plan.md`
- Source row: `UP-009` / Username and sender identity render consistently after re-add
- Row-owned source anchors:
  - `lib/features/groups/application/handle_incoming_group_message_use_case.dart`: post-re-add inbound sender identity prefers current member username when stale wire usernames arrive after the latest removal cutoff.
  - `lib/features/groups/presentation/group_sender_display_name.dart`: existing current-main display helper accepts `preferMemberName`.
  - `lib/features/groups/presentation/screens/group_conversation_screen.dart` and `lib/features/groups/presentation/screens/group_conversation_wired.dart`: existing current-main rendering passes current members to sender label resolution.
  - `test/features/groups/presentation/group_conversation_screen_test.dart`: widget proof for re-added sender label precedence.
  - `test/features/groups/integration/group_messaging_smoke_test.dart`: fake-network proof for stale wire username after re-add.
  - `integration_test/group_multi_party_device_real_harness.dart`, `integration_test/scripts/group_multi_party_device_criteria.dart`, and `test/integration/group_multi_party_device_criteria_test.dart`: `up009ReaddSenderIdentityProof` on `private_timeline_truth`.

Imported delta:
- Kept already-present current-main display-helper and conversation-screen member plumbing unchanged.
- Added the missing receive-path guard so inbound post-re-add messages from a current member use the current member username instead of overwriting it with stale or blank wire usernames after the latest sender-removal cutoff.
- Added the row-owned widget proof that a re-added sender label prefers current member identity over a stale wire username.
- Added the row-owned fake-network proof that stale wire sender metadata after re-add still renders the current member label.
- Added `up009ReaddSenderIdentityProof` live-harness emission and criteria validation for `private_timeline_truth`, including stale rendered-label rejection checks.

Out of scope:
- No original source worktree plan recreation or rerun.
- No unrelated source-worktree changes, source-doc rewrites, COMPLETE_1 doc updates, Android, physical iOS, notification rows, share-target rows, media/reaction rows, security/privacy rows, or adjacent UP rows.
- No attempt to repair the shared `private_timeline_truth` live fixture or ML-015 self-removal/rejoin path in this row.

Verification evidence:
- `dart format --set-exit-if-changed lib/features/groups/application/handle_incoming_group_message_use_case.dart test/features/groups/presentation/group_conversation_screen_test.dart test/features/groups/integration/group_messaging_smoke_test.dart integration_test/group_multi_party_device_real_harness.dart integration_test/scripts/group_multi_party_device_criteria.dart test/integration/group_multi_party_device_criteria_test.dart` - pass with 0 changed.
- `flutter test --no-pub test/features/groups/presentation/group_conversation_screen_test.dart --plain-name "UP-009"` - pass.
- `flutter test --no-pub test/features/groups/integration/group_messaging_smoke_test.dart --plain-name "UP-009"` - initially failed with `Old Charlie` rendered instead of `Readded Charlie`; after importing the row-owned receive-path guard, rerun passed.
- `flutter test --no-pub test/integration/group_multi_party_device_criteria_test.dart --plain-name "UP-009"` - pass.
- `flutter test --no-pub test/integration/group_multi_party_device_criteria_test.dart --plain-name "private_timeline_truth"` - pass.
- `flutter analyze --no-pub lib/features/groups/application/handle_incoming_group_message_use_case.dart test/features/groups/presentation/group_conversation_screen_test.dart test/features/groups/integration/group_messaging_smoke_test.dart integration_test/group_multi_party_device_real_harness.dart integration_test/scripts/group_multi_party_device_criteria.dart test/integration/group_multi_party_device_criteria_test.dart` - pass, `No issues found!`.
- Required iOS 26.2 `private_timeline_truth` live proof failed before UP-009 verdict: run `1779326806744`, shared dir `/var/folders/nd/_55d26s936d0fb_5l9s00t980000gn/T/group_multi_party_private_timeline_truth_TQIlp4`, Alice `5A9A8286-001B-4BF1-8F40-5A3AB8BF8FE3`, Bob `279B82AE-2BB9-4924-9AAE-581870ED3FA9`, Charlie `116B4AF6-C1A9-4F36-B929-0A7130B5E83C`. Charlie repeatedly skipped offline inbox decode with `Bad state: Missing group replay key for group 1efc5acd-d204-4562-b994-c4e1caa03754 at epoch 1`, then timed out waiting for self-removal; Bob timed out waiting for `gmp_1779326806744_rejoin_key.json`; Alice timed out waiting for `gmp_1779326806744_charlie_self_removed`; the orchestrator exited with `Bad state: charlie exited with code 1 before writing a verdict`.

Controller status:
- The row is `blocked_external_fixture`. Row-owned host, widget, fake-network, criteria, format, analyzer, and diff evidence passed, but required iOS 26.2 `private_timeline_truth` live proof could not reach UP-009 verdict because the shared self-removal/rejoin fixture failed before the row-owned proof.
- Safe next action is `INTEGRATE-UP-010` after ledger sanity and dirty-state safety checks because UP-010 is route-target notification work that can be inspected independently, while preserving the shared `private_timeline_truth` blocker evidence.
