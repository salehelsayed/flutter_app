# INTEGRATE-UP-005 Worktree-to-Main Integration Contract

Status: accepted

Source of truth:
- Source worktree: `/Users/I560101/Project-Sat/mknoon-2/worktrees/full-rules-pipeline`
- Historical source plan: `/Users/I560101/Project-Sat/mknoon-2/worktrees/full-rules-pipeline/Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_full_with_rules-session-UP-005-plan.md`
- Source row: `UP-005` / Pending or failed invite state is visibly different from active member state
- Row-owned source anchors:
  - `test/features/groups/application/create_group_with_members_use_case_test.dart`: create-flow invite delivery attempts keep sent, failed, and joined evidence distinct
  - `test/features/groups/presentation/group_info_wired_test.dart`: Group Info badges distinguish joined, inbox, resend-needed, and cannot-send states
  - `test/features/groups/integration/group_membership_smoke_test.dart`: fake-network invite delivery statuses keep pending, failed, and joined recipients distinct
  - `integration_test/group_invite_status_matrix_harness.dart` and `integration_test/scripts/run_group_invite_status_matrix_sim.dart`: seeded `up005InviteStateProof` display proof with `relayLifecycleProof=false`

Imported delta:
- Production invite-state behavior was already present in current main, so no production code changed.
- Added the row-owned application proof that delivered invitees remain `sent`, failed Dave remains `needsResend`, and no attempt becomes `joined` until explicit joined evidence is recorded.
- Added the row-owned Group Info widget proof that Bob is `Joined`, Charlie is `In their inbox`, Dave is `Resend needed`, Eve is `Cannot send`, non-joined rows do not contain `Joined`, only Dave has resend, and cannot-send detail is visible.
- Added the row-owned fake-network proof that pending delivered recipients, failed recipients, and explicit joined evidence remain distinct, and failed Dave has no joined local group.
- Added strict `up005InviteStateProof` emission and validation to the seeded Group Info display harness/runner.

Out of scope:
- No original source worktree plan recreation or rerun.
- No relay/testpeer lifecycle invite delivery claim; the simulator proof is seeded display-only and records `relayLifecycleProof=false`.
- No unread counts, notifications, share targeting, media, reactions, security/privacy, stress, adjacent UP rows, source-doc, COMPLETE_1 doc, Android, physical iOS, macOS, Chrome, or production UI rewrite.

Verification evidence:
- `dart format --set-exit-if-changed test/features/groups/application/create_group_with_members_use_case_test.dart test/features/groups/presentation/group_info_wired_test.dart test/features/groups/integration/group_membership_smoke_test.dart integration_test/group_invite_status_matrix_harness.dart integration_test/scripts/run_group_invite_status_matrix_sim.dart` - pass with 0 changed.
- `flutter test --no-pub test/features/groups/application/create_group_with_members_use_case_test.dart --plain-name "UP-005"` - pass on serial rerun after an initial parallel native-assets `lipo` race.
- `flutter test --no-pub test/features/groups/presentation/group_info_wired_test.dart --plain-name "UP-005"` - pass.
- `flutter test --no-pub test/features/groups/integration/group_membership_smoke_test.dart --plain-name "UP-005"` - pass on serial rerun after an initial parallel native-assets `lipo` race.
- `flutter analyze --no-pub test/features/groups/application/create_group_with_members_use_case_test.dart test/features/groups/presentation/group_info_wired_test.dart test/features/groups/integration/group_membership_smoke_test.dart integration_test/group_invite_status_matrix_harness.dart integration_test/scripts/run_group_invite_status_matrix_sim.dart` - pass, `No issues found!`.
- `flutter test --no-pub test/features/groups/application/create_group_with_members_use_case_test.dart test/features/groups/presentation/contact_picker_wired_test.dart test/features/groups/presentation/group_info_wired_test.dart test/features/groups/integration/group_membership_smoke_test.dart --plain-name "ML-004"` - pass.
- `flutter test --no-pub test/features/groups/presentation/contact_picker_wired_test.dart --plain-name "GM-036"` - pass.
- `flutter test --no-pub test/features/groups/presentation/group_info_wired_test.dart --plain-name "GM-036"` - pass.
- `flutter test --no-pub test/features/groups/integration/group_membership_smoke_test.dart --plain-name "GM-036"` - pass.
- Scoped `git diff --check` - pass before doc closure.
- Required iOS 26.2 seeded display proof passed: run `1779323319703`, shared dir `/var/folders/nd/_55d26s936d0fb_5l9s00t980000gn/T/group_invite_status_matrix_LMHGyP`, devices creator/Alice `5A9A8286-001B-4BF1-8F40-5A3AB8BF8FE3`, accepted-one/Bob `279B82AE-2BB9-4924-9AAE-581870ED3FA9`, accepted-two/Charlie `116B4AF6-C1A9-4F36-B929-0A7130B5E83C`, pending-unaccepted/Dana `CD5929A6-EA0A-421D-A6D3-55BD707E0F76`, with orchestrator verdict `Group invite status matrix display proof passed`.

Controller status:
- The row is accepted. Host, widget, fake-network, preservation, format, analyzer, diff, and required iOS 26.2 seeded display proof evidence passed.
- Safe next action is `INTEGRATE-UP-006` after ledger sanity and dirty-state safety checks. UP-006 shares the `private_timeline_truth` path currently blocked by UP-002/UP-004, so any UP-006 execution must preserve that blocker evidence.
