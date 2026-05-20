# INTEGRATE-PL-009 Worktree-to-Main Integration Contract

Status: accepted

Source of truth:
- Source worktree: `/Users/I560101/Project-Sat/mknoon-2/worktrees/full-rules-pipeline`
- Historical source plan: `/Users/I560101/Project-Sat/mknoon-2/worktrees/full-rules-pipeline/Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_full_with_rules-session-PL-009-plan.md`
- Source row: `PL-009` / Reaction from active member publishes and routes correctly
- Row-owned source anchors:
  - `test/features/groups/application/send_group_reaction_use_case_test.dart`: `PL-009 active member publishes reaction command and stores local reaction once`
  - `test/features/groups/application/handle_incoming_group_reaction_use_case_test.dart`: `PL-009 active sender reaction applies once to the correct message`
  - `test/features/groups/integration/group_reaction_roundtrip_test.dart`: `PL-009 media-free active member reaction reaches Alice and Charlie exactly once`
  - `integration_test/group_multi_device_real_harness.dart`: reaction repository/outbox and live listener reaction stream wiring
  - `integration_test/group_multi_party_device_real_harness.dart`: `private_reaction_roundtrip`
  - `integration_test/scripts/group_multi_party_device_criteria.dart`: `private_reaction_roundtrip` criteria
  - `integration_test/scripts/run_group_multi_party_device_real.dart`: `private_reaction_roundtrip` scenario registration
  - `test/integration/group_multi_party_device_criteria_test.dart`: PL-009 criteria accept/reject selectors

Imported delta:
- Added row-owned app tests proving an active member's reaction publish stores exactly one local reaction and incoming active-sender replay applies exactly once to the target message.
- Added the row-owned fake-network roundtrip proof that Bob reacts to Alice's message and Alice plus Charlie observe exactly one reaction on the correct message.
- Added only the minimal live-harness reaction repository/listener wiring needed for `private_reaction_roundtrip`.
- Added the `private_reaction_roundtrip` runner, live-harness, criteria, and criteria-test coverage proving Alice, Bob, and Charlie verdict evidence includes sender storage, Alice receiver stream/storage, Charlie receiver stream/storage, and exact target-message binding.
- Added fake-network fixture key seeding for the PL-009 selector and adjacent existing reaction-roundtrip selectors so they satisfy current main's group-key bootstrap precondition.

Out of scope:
- No original source worktree plan recreation or rerun.
- No PL-010+ removed-member/re-add reaction rows, media ACL/download rows, upload retry, notifications, privacy, stress, Android, physical iOS, source-doc, COMPLETE_1 doc, or unrelated fixture repair.
- No production reaction path rewrite; current main already routes native `group_reaction:received` into `onGroupReactionReceived` and app listener storage.
- The live proof still emitted the known side-path `GROUP_REACTION_INBOX_STORE_FAILED` for `group:inboxStore` missing `recipientPeerIds`; this contract accepts only PL-009's active live publish/receive/storage route, matching the source row's historical classification.

Verification evidence:
- `flutter test --no-pub test/features/groups/application/send_group_reaction_use_case_test.dart --plain-name "PL-009 active member publishes reaction command and stores local reaction once"` - pass
- `flutter test --no-pub test/features/groups/application/handle_incoming_group_reaction_use_case_test.dart --plain-name "PL-009 active sender reaction applies once to the correct message"` - pass
- `flutter test --no-pub test/features/groups/integration/group_reaction_roundtrip_test.dart --plain-name "PL-009 media-free active member reaction reaches Alice and Charlie exactly once"` - pass after fixture key seeding for the current group-key bootstrap precondition
- `flutter test --no-pub test/integration/group_multi_party_device_criteria_test.dart --plain-name "PL-009 accepts private reaction roundtrip verdicts"` - pass
- `flutter test --no-pub test/integration/group_multi_party_device_criteria_test.dart --plain-name "PL-009 rejects reaction proofs without receiver stream evidence"` - pass
- Preservation selectors passed: `chat member can react`, `announcement member can react`, `non-member is rejected`, `publish failure returns publishFailed`, duplicate add/remove incoming reaction replay, `chat-group reaction roundtrip reaches the original sender through the live listener stream`, and `dissolved chat group blocks later reaction send and does not roundtrip`.
- `dart run integration_test/scripts/run_group_multi_party_device_real.dart --scenario private_reaction_roundtrip --list-scenarios` - pass, lists `private_reaction_roundtrip`.
- `dart format --set-exit-if-changed` over the eight touched Dart files - pass with 0 changed after formatting.
- Scoped `flutter analyze --no-pub` over the eight touched Dart files - pass, `No issues found!`.
- Required iOS 26.2 live proof passed: run id `1779310544911`, shared dir `/var/folders/nd/_55d26s936d0fb_5l9s00t980000gn/T/group_multi_party_private_reaction_roundtrip_gcZ0Nw`, Alice `5A9A8286-001B-4BF1-8F40-5A3AB8BF8FE3`, Bob `279B82AE-2BB9-4924-9AAE-581870ED3FA9`, Charlie `116B4AF6-C1A9-4F36-B929-0A7130B5E83C`, orchestrator verdict `private_reaction_roundtrip proof passed: private_reaction_roundtrip verdicts valid for alice, bob, charlie`.

Controller acceptance evidence:
- Read-only scouts confirmed current main already had the core production reaction routing, while PL-009-specific three-role proof coverage, live scenario, criteria validation, and exact row selectors were missing.
- The controller rechecked the row-owned file inventory before execution and imported only PL-009 reaction deltas, leaving PL-010/PL-011 reaction membership-window scope and later payload/media rows untouched.
- All required focused row tests, affected reaction preservation selectors, scoped maintenance checks, and iOS 26.2 live proof passed.
