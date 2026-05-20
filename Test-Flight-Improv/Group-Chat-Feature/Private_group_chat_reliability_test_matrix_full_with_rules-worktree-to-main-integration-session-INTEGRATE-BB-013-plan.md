Status: accepted

# INTEGRATE-BB-013 Standard Integration Plan

## Planning Progress

- 2026-05-17T05:05:00+02:00 - Inspected source matrix row `BB-013`, source session breakdown row, historical source plan/closure evidence, source test-inventory closure, source commit `2abd3fc9`, current main selector presence, current main test diffs, and COMPLETE_1 timeout-related overlap rows. Decision/blocker: source BB-013 is a tests-only import; main has generic timeout helper behavior but lacks row-named BB-013 selector coverage and caller-state tests. Next action: import only missing row-owned tests/retags.

## Real Scope

This is a standard worktree-to-main integration contract for exactly `INTEGRATE-BB-013` / source row `BB-013`: bridge timeout responses are never interpreted as successful membership or send completion.

The executor must reuse the historical source worktree BB-013 plan and closure as evidence only. Do not recreate, rewrite, or rerun the original source implementation plan. Do not reimplement the row from scratch. Import only missing meaningful BB-013-owned test deltas into main, adapted to current main drift.

In scope:

- Retag or add row-named helper timeout coverage for `group:create`, `group:join`, `group:publish`, `group:updateConfig`, `group:updateKey`, `group:inboxStore`, `group:inboxRetrieve`, and `group:inboxRetrieveCursor`.
- Import caller-state tests proving timeout create/join do not persist local group/member/key state, rejoin timeout counts as error not joined, publish timeout without durable inbox custody remains failed/retryable, update config timeout rolls back optimistic role mutation, update key timeout does not save/promote a new key, inbox store timeout remains retryable/not stored, and inbox retrieve timeout reports drain error.
- Preserve accepted BB-001 through BB-012 changes and COMPLETE_1 timeout/recovery overlap rows.

Out of scope:

- No production code changes unless a test proves a silent-success timeout bug; if that happens, stop and classify `blocked_conflict`.
- Do not copy source matrix, source session breakdown, source test-inventory, or historical source plan docs into main.
- Do not edit COMPLETE_1 docs.
- Do not import BB-014+, BB-015 malformed response handling, re-add/recovery semantics beyond timeout-no-success, native timeout infrastructure, bridge API normalization, device/relay/3-party E2E proof, UI, notifications, media, observability, or broad retry architecture.

## Source Of Truth

- Source row: `/Users/I560101/Project-Sat/mknoon-2/worktrees/full-rules-pipeline/Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_full_with_rules.md` row `BB-013`.
- Source breakdown: `/Users/I560101/Project-Sat/mknoon-2/worktrees/full-rules-pipeline/Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_full_with_rules-session-breakdown.md` session `BB-013`.
- Historical worktree plan/evidence: `/Users/I560101/Project-Sat/mknoon-2/worktrees/full-rules-pipeline/Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_full_with_rules-session-BB-013-plan.md`.
- Source closure evidence: source `test-inventory.md` row `BB-013` and source matrix `BB-013` covered note.
- Source commit evidence: `2abd3fc9` (`BB-013: prove group timeout handling`).
- Main integration controller: `Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_full_with_rules-worktree-to-main-integration-session-breakdown.md`.
- Main compatibility artifact: `Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_COMPLETE_1-session-breakdown.md`.
- Current code and tests in main win over stale prose when they conflict.

## Source Commit And File Evidence

Meaningful source files for integration:

- `test/core/bridge/bridge_group_helpers_test.dart`
- `test/features/groups/application/create_group_use_case_test.dart`
- `test/features/groups/application/join_group_use_case_test.dart`
- `test/features/groups/application/rejoin_group_topics_use_case_test.dart`
- `test/features/groups/application/send_group_message_use_case_test.dart`
- `test/features/groups/application/update_group_member_role_use_case_test.dart`
- `test/features/groups/application/group_key_update_listener_test.dart`
- `test/features/groups/application/retry_failed_group_inbox_stores_use_case_test.dart`
- `test/features/groups/application/drain_group_offline_inbox_use_case_test.dart`

Source docs changed in the worktree commit are historical evidence only and must not be copied.

## Duplicate Presence In Main

Planning searches found no exact `BB-013` selectors in main. Generic timeout helper tests are already present in `bridge_group_helpers_test.dart`; for those, retag existing assertions instead of duplicating tests. Caller-state tests for BB-013 are missing and should be imported narrowly.

## COMPLETE_1 Overlap Rows

Inspect and preserve:

- `GR-003` and `GR-013`: COMPLETE_1 timeout/recovery budget rows. These are native recovery timeout proofs, not BB-013 bridge helper timeout work.
- `GI-021`, `GP-026`, and adjacent drain rows: preserve inbox replay/drain error semantics while adding the BB-013 cursor timeout assertion.

## Tests And Gates To Run

Focused BB-013 proof:

```bash
flutter test --no-pub test/core/bridge/bridge_group_helpers_test.dart --plain-name 'BB-013'
flutter test --no-pub test/features/groups/application/create_group_use_case_test.dart --plain-name 'BB-013'
flutter test --no-pub test/features/groups/application/join_group_use_case_test.dart --plain-name 'BB-013'
flutter test --no-pub test/features/groups/application/rejoin_group_topics_use_case_test.dart --plain-name 'BB-013'
flutter test --no-pub test/features/groups/application/send_group_message_use_case_test.dart --plain-name 'BB-013'
flutter test --no-pub test/features/groups/application/update_group_member_role_use_case_test.dart --plain-name 'BB-013'
flutter test --no-pub test/features/groups/application/group_key_update_listener_test.dart --plain-name 'BB-013'
flutter test --no-pub test/features/groups/application/retry_failed_group_inbox_stores_use_case_test.dart --plain-name 'BB-013'
flutter test --no-pub test/features/groups/application/drain_group_offline_inbox_use_case_test.dart --plain-name 'BB-013'
```

Preservation/backstop:

```bash
flutter test --no-pub test/core/bridge/bridge_group_helpers_test.dart test/core/bridge/go_bridge_client_test.dart test/features/groups/application/create_group_use_case_test.dart test/features/groups/application/join_group_use_case_test.dart test/features/groups/application/rejoin_group_topics_use_case_test.dart test/features/groups/application/send_group_message_use_case_test.dart test/features/groups/application/update_group_member_role_use_case_test.dart test/features/groups/application/group_key_update_listener_test.dart test/features/groups/application/retry_failed_group_inbox_stores_use_case_test.dart test/features/groups/application/drain_group_offline_inbox_use_case_test.dart
(cd go-mknoon && go test ./bridge -run 'TestGroup(Create|JoinTopic|Publish|UpdateConfig|UpdateKey|InboxStore|InboxRetrieve|InboxRetrieveCursor)_' -count=1)
(cd go-mknoon && go test ./node -run 'TestGroupInbox|TestPublishGroupMessage' -count=1)
flutter test --no-pub test/features/groups/integration/group_startup_rejoin_smoke_test.dart
flutter test --no-pub test/features/groups/integration/group_resume_recovery_test.dart
FLUTTER_DEVICE_ID=macos ./scripts/run_test_gates.sh groups
dart format --set-exit-if-changed test/core/bridge/bridge_group_helpers_test.dart test/features/groups/application/create_group_use_case_test.dart test/features/groups/application/join_group_use_case_test.dart test/features/groups/application/rejoin_group_topics_use_case_test.dart test/features/groups/application/send_group_message_use_case_test.dart test/features/groups/application/update_group_member_role_use_case_test.dart test/features/groups/application/group_key_update_listener_test.dart test/features/groups/application/retry_failed_group_inbox_stores_use_case_test.dart test/features/groups/application/drain_group_offline_inbox_use_case_test.dart
git diff --check
```

## Final Status Contract

- `accepted`: missing meaningful BB-013 tests/retags imported and required tests/gates pass.
- `skipped_already_present`: all meaningful BB-013 selector evidence already exists in main.
- `blocked_conflict`: a timeout test proves a production silent-success bug or conflicts with accepted COMPLETE_1 behavior.
- `blocked_external_fixture`: only if a required external fixture unexpectedly blocks closure.

## Execution Progress

- 2026-05-17T05:52:00+02:00 - Imported only the missing meaningful BB-013 test delta into main. Retagged existing helper timeout assertions where main already had the behavior, added the missing `group:updateKey` helper timeout assertion, and added caller-state tests for create, join, rejoin, publish, update config, update key, inbox store, and inbox retrieve timeout handling. No production code was changed.
- 2026-05-17T06:15:00+02:00 - Ran focused BB-013 selectors across all row-owned test files; all passed. Ran affected COMPLETE_1/main overlap tests for drain replay, startup rejoin, resume recovery, Go bridge timeout handling, and Go node inbox/publish behavior; all passed. The broad combined Flutter preservation command failed only on the pre-existing/non-row `GEK003 partial key-update delivery plus immediate post-rotation send repairs stale recipient after later key arrival` selector in `drain_group_offline_inbox_use_case_test.dart`; the same selector failed in isolation with `Expected: not null Actual: <null>`, so it is recorded as residual non-BB-013 evidence and not used to broaden this row.
- 2026-05-17T06:38:00+02:00 - `FLUTTER_DEVICE_ID=macos ./scripts/run_test_gates.sh groups` passed (`+167`), `dart format --set-exit-if-changed` over the nine BB-013 files passed with `0 changed`, and `git diff --check` passed.

## Final Execution Result

Status: `accepted`

Accepted row-owned files:

- `test/core/bridge/bridge_group_helpers_test.dart`
- `test/features/groups/application/create_group_use_case_test.dart`
- `test/features/groups/application/join_group_use_case_test.dart`
- `test/features/groups/application/rejoin_group_topics_use_case_test.dart`
- `test/features/groups/application/send_group_message_use_case_test.dart`
- `test/features/groups/application/update_group_member_role_use_case_test.dart`
- `test/features/groups/application/group_key_update_listener_test.dart`
- `test/features/groups/application/retry_failed_group_inbox_stores_use_case_test.dart`
- `test/features/groups/application/drain_group_offline_inbox_use_case_test.dart`

Verification:

- `flutter test --no-pub test/core/bridge/bridge_group_helpers_test.dart --plain-name 'BB-013'` passed (`+8`).
- `flutter test --no-pub test/features/groups/application/create_group_use_case_test.dart --plain-name 'BB-013'` passed (`+1`).
- `flutter test --no-pub test/features/groups/application/join_group_use_case_test.dart --plain-name 'BB-013'` passed (`+1`).
- `flutter test --no-pub test/features/groups/application/rejoin_group_topics_use_case_test.dart --plain-name 'BB-013'` passed (`+1`).
- `flutter test --no-pub test/features/groups/application/send_group_message_use_case_test.dart --plain-name 'BB-013'` passed (`+1`).
- `flutter test --no-pub test/features/groups/application/update_group_member_role_use_case_test.dart --plain-name 'BB-013'` passed (`+1`).
- `flutter test --no-pub test/features/groups/application/group_key_update_listener_test.dart --plain-name 'BB-013'` passed (`+1`).
- `flutter test --no-pub test/features/groups/application/retry_failed_group_inbox_stores_use_case_test.dart --plain-name 'BB-013'` passed (`+1`).
- `flutter test --no-pub test/features/groups/application/drain_group_offline_inbox_use_case_test.dart --plain-name 'BB-013'` passed (`+1`).
- `(cd go-mknoon && go test ./bridge -run 'TestGroup(Create|JoinTopic|Publish|UpdateConfig|UpdateKey|InboxStore|InboxRetrieve|InboxRetrieveCursor)_' -count=1)` passed.
- `(cd go-mknoon && go test ./node -run 'TestGroupInbox|TestPublishGroupMessage' -count=1)` passed.
- `flutter test --no-pub test/features/groups/application/drain_group_offline_inbox_use_case_test.dart --plain-name 'GI-021'` passed (`+1`).
- `flutter test --no-pub test/features/groups/application/drain_group_offline_inbox_use_case_test.dart --plain-name 'GP-026'` passed (`+1`).
- `flutter test --no-pub test/features/groups/integration/group_startup_rejoin_smoke_test.dart` passed (`+7`).
- `flutter test --no-pub test/features/groups/integration/group_resume_recovery_test.dart` passed (`+45`).
- `FLUTTER_DEVICE_ID=macos ./scripts/run_test_gates.sh groups` passed (`+167`).
- `dart format --set-exit-if-changed` over the nine BB-013 files passed with `0 changed`.
- `git diff --check` passed.

Skipped as already present or out of scope: source docs were not copied; COMPLETE_1 docs were untouched; existing generic timeout helper behavior was reused rather than duplicated; no BB-014+, BB-015 malformed response handling, native timeout infrastructure, device/relay/3-party E2E proof, UI, notification, media, observability, security, or broad recovery work was imported. No conflict was found.
