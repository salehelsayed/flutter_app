# OS-008 Offline Removed Sender Stale Publish Plan

## Session Intake

- breakdown artifact: `Test-Flight-Improv/Group-Chat-Feature/libp2p_group_chat_missing_test_matrix_full_with_rules-session-breakdown.md`
- source matrix: `Test-Flight-Improv/Group-Chat-Feature/libp2p_group_chat_missing_test_matrix_full_with_rules.md`
- source row: `OS-008 | Offline sender removed remotely before reconnect cannot publish stale sends`
- disposition: `needs_code_and_tests`
- execution classification: `implementation-ready`
- local plan fallback: used after the spawned planning attempt no-progressed without leaving a reusable plan

## Current Evidence Hypothesis

The repo already has adjacent local and replay behavior:

- direct send rejects a locally removed sender before persistence or bridge publish
- failed-message retry calls `sendGroupMessage`, so local removal blocks retry publication
- offline inbox replay of self-removal routes through `GroupMessageListener` cleanup, calls `group:leave`, deletes local group state, emits `groupRemovedStream`, and stops later cursor pages
- group resume recovery already proves a removed offline member drains replayed removal, loses group access, and cannot send after resume
- Go PubSub validator rejects removed/non-member senders before forwarding on live PubSub paths

The missing or weak point is the exact queued-failed-send sequence: B queues a failed send while offline, A removes B, B drains the remote removal on reconnect, and B's failed-message retry must not publish or inbox-store the stale queued row after local cleanup. If a focused fake-network regression can cover that ordering, OS-008 can likely close as `Covered` locally while live device/relay proof remains supplemental.

## Scope

Implement only a direct OS-008 regression if needed.

Likely test owner:

- `test/features/groups/integration/group_resume_recovery_test.dart`

Evidence owners:

- `lib/features/groups/application/send_group_message_use_case.dart`
- `lib/features/groups/application/retry_failed_group_messages_use_case.dart`
- `lib/features/groups/application/drain_group_offline_inbox_use_case.dart`
- `lib/features/groups/application/group_message_listener.dart`
- `test/features/groups/application/send_group_message_use_case_test.dart`
- `test/features/groups/application/retry_failed_group_messages_use_case_test.dart`
- `test/features/groups/application/drain_group_offline_inbox_use_case_test.dart`
- `test/features/groups/integration/group_resume_recovery_test.dart`
- `go-mknoon/node/pubsub_test.go`
- `go-mknoon/node/pubsub_key_rotation_grace_test.go`

## Scope Guard

- Do not implement new direct peer sync, anti-entropy, multi-peer repair, or real relay/device fixture setup.
- Do not broaden into OS-003 direct peer sync, OS-006 multi-peer gap repair, OS-009 epoch placeholders, OS-012 real bridge/GossipSub partition proof, or EK scheduled/future-epoch rows.
- Do not relabel a local removed-sender check as live device proof.
- If the queued failed-send after remote-removal sequence cannot be proven with existing fake-network seams, leave OS-008 Partial/Open with exact blocker classes instead of weakening the closure bar.

## Acceptance Criteria

Accept OS-008 as `Covered` only if direct code/test evidence proves:

- B can have a queued failed outgoing group message from before remote removal.
- A's removal of B is replayed to B while B is offline/reconnecting.
- B applies the replayed self-removal before stale retry publication.
- The local group is deleted/unsubscribed after removal replay.
- A retry attempt after removal returns zero retried messages.
- No `group:publish` and no `group:inboxStore` command occurs for the stale queued row after removal replay.
- The stale failed row is not converted to `sent`.

## Evidence Commands

- `rg -n "removed.*send|sender.*removed|REMOVED_AFTER_CUTOFF|stale send|retry.*removed|removed offline member drains replayed removal" lib/features/groups test/features/groups go-mknoon/node`
- `flutter test --no-pub test/features/groups/application/send_group_message_use_case_test.dart --plain-name "rejects stale send after local membership removal before persistence"`
- `flutter test --no-pub test/features/groups/application/retry_failed_group_messages_use_case_test.dart --plain-name "does not replay a failed text row after sender was removed locally"`
- `flutter test --no-pub test/features/groups/application/drain_group_offline_inbox_use_case_test.dart --plain-name "replayed self-removal cuts off later queued inbox traffic for that group"`
- `flutter test --no-pub test/features/groups/integration/group_resume_recovery_test.dart --plain-name "removed offline member drains replayed removal, loses group access, and cannot send after resume"`
- new focused OS-008 integration test command
- `cd go-mknoon && go test ./node -run 'TestGroupTopicValidator_(RejectsRemovedSenderPreviousEpochDuringGrace|RejectsUnauthorizedEventFamiliesBeforeForward|RejectsNonMemberMessage|RejectsRemoved)' -v`
- `printenv FLUTTER_DEVICE_ID`
- `printenv MKNOON_RELAY_ADDRESSES`
- `./scripts/run_test_gates.sh completeness-check`
- `git diff --check`

## Session Gates

- focused application and integration commands above
- Go PubSub removed-sender validator slice
- `./scripts/run_test_gates.sh completeness-check`
- `git diff --check`

## Done Criteria

- OS-008 has direct queued-failed-send-after-remote-removal evidence or an exact blocker verdict.
- If covered, source matrix and `test-inventory.md` record OS-008 as Covered with test evidence.
- If blocked, source matrix remains Open/Partial with exact missing primitives.
- Session breakdown ledger records OS-008 truthfully and includes closure evidence.

## Execution Evidence

- Added `removed offline member does not retry queued failed sends after replayed removal` in `test/features/groups/integration/group_resume_recovery_test.dart`.
- The new regression creates a failed outgoing row while Bob is offline, replays the admin removal to Bob through the cursor inbox, verifies Bob applies self-removal and leaves the group, runs `retryFailedGroupMessages`, and asserts no additional `group:publish` or `group:inboxStore` command occurs for the stale queued row.
- Existing local send proof shows a locally removed sender is rejected before persistence or bridge publication.
- Existing retry proof shows failed-message retry reuses `sendGroupMessage` and does not replay after local removal.
- Existing drain proof shows replayed self-removal stops later cursor pages and removes local group state.
- Existing resume-recovery proof shows a removed offline member drains replayed removal, loses group access, and cannot send after resume.
- Go PubSub validator proof shows removed or unauthorized senders are rejected before forwarding.
- `FLUTTER_DEVICE_ID` and `MKNOON_RELAY_ADDRESSES` were unset, so live device/relay proof remains supplemental and fixture-blocked.

## Verification

- `rg -n "removed.*send|sender.*removed|REMOVED_AFTER_CUTOFF|stale send|retry.*removed|removed offline member drains replayed removal|does not retry queued failed sends" lib/features/groups test/features/groups go-mknoon/node`
- `flutter test --no-pub test/features/groups/integration/group_resume_recovery_test.dart --plain-name "removed offline member does not retry queued failed sends after replayed removal"` passed.
- `flutter test --no-pub test/features/groups/application/send_group_message_use_case_test.dart --plain-name "rejects stale send after local membership removal before persistence"` passed.
- `flutter test --no-pub test/features/groups/application/retry_failed_group_messages_use_case_test.dart --plain-name "does not replay a failed text row after sender was removed locally"` passed.
- `flutter test --no-pub test/features/groups/application/drain_group_offline_inbox_use_case_test.dart --plain-name "replayed self-removal cuts off later queued inbox traffic for that group"` passed.
- `flutter test --no-pub test/features/groups/integration/group_resume_recovery_test.dart --plain-name "removed offline member drains replayed removal, loses group access, and cannot send after resume"` passed.
- `cd go-mknoon && go test ./node -run 'TestGroupTopicValidator_(RejectsRemovedSenderPreviousEpochDuringGrace|RejectsUnauthorizedEventFamiliesBeforeForward|RejectsNonMemberMessage|RejectsRemoved)' -v` passed.

## Execution Verdict

`accepted`

OS-008 is Covered by direct fake-network/inbox replay and retry evidence. The row now proves a queued failed outgoing message from before remote removal stays failed after B drains A's replayed removal, B's local group is deleted/unsubscribed, failed-message retry returns zero, and no stale `group:publish` or `group:inboxStore` reaches the bridge after removal. Live relay/device proof remains supplemental fixture coverage for OS-012 or real-network nightly gates, not a blocker for this row's repo-local closure.
