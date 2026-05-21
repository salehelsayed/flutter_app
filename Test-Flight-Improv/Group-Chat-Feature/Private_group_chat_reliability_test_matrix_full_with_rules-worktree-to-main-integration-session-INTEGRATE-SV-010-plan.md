# INTEGRATE-SV-010 Minimal Integration Contract

Status: accepted

## Scope

Import/reconcile source row `SV-010` from the full-with-rules worktree into main: duplicate message ids from different senders or groups must not overwrite, enrich, duplicate, or silently normalize the already trusted row.

This is standard worktree-to-main integration, not new implementation rollout and not gap closure. The historical source plan remains the source of truth:

`/Users/I560101/Project-Sat/mknoon-2/worktrees/full-rules-pipeline/Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_full_with_rules-session-SV-010-plan.md`

## Reconciliation

- Source status: accepted/covered in the historical worktree.
- Main status before import: partial. Current main already deduped same-id messages and preserved same-sender duplicate replay/self-echo behavior, but did not explicitly reject same-id conflicts from a different sender or group before duplicate enrichment.
- Imported delta: only missing SV-010 row-owned duplicate-message-id conflict guard and row-owned direct/fake-network proof selectors.
- Current-main adaptation: existing same-sender duplicate replay enrichment, media repair, and self-echo reconciliation stayed intact.
- Live proof: not required. Source 3-Party E2E is `N/A`; no iOS 26.2 simulator proof is claimed.

## Imported Artifacts

- `lib/features/groups/application/handle_incoming_group_message_use_case.dart`
  - rejects existing message-id reuse when the persisted row has a different `groupId` or `senderPeerId`.
  - emits `GROUP_HANDLE_INCOMING_MSG_DUPLICATE_ID_CONFLICT_REJECTED`.
- `test/features/groups/application/handle_incoming_group_message_use_case_test.dart`
  - `SV-010 duplicate message id from different sender cannot overwrite valid row`
- `test/features/groups/integration/group_messaging_smoke_test.dart`
  - `SV-010 duplicate message id from different sender preserves trusted row`
- `Test-Flight-Improv/Group-Chat-Feature/test-inventory.md`
- `Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_full_with_rules-worktree-to-main-integration-session-breakdown.md`
- This contract.

## Verification

- PASS: `dart format --set-exit-if-changed lib/features/groups/application/handle_incoming_group_message_use_case.dart test/features/groups/application/handle_incoming_group_message_use_case_test.dart test/features/groups/integration/group_messaging_smoke_test.dart`
- PASS: `flutter test --no-pub test/features/groups/application/handle_incoming_group_message_use_case_test.dart --plain-name "SV-010"`
- PASS: `flutter test --no-pub test/features/groups/integration/group_messaging_smoke_test.dart --plain-name "SV-010"`
- PASS: `dart analyze lib/features/groups/application/handle_incoming_group_message_use_case.dart test/features/groups/application/handle_incoming_group_message_use_case_test.dart test/features/groups/integration/group_messaging_smoke_test.dart`
- PASS: `flutter test --no-pub test/features/groups/application/handle_incoming_group_message_use_case_test.dart --name "DE-005 self echo|deduplicates by messageId|duplicate replay enriches a missing quotedMessageId|duplicate replay with the same messageId ignores a tampered timestamp|duplicate replay with the same messageId ignores conflicting content|duplicate replay saves missing media attachments|duplicate group inbox replay does not resave media|SV-006 replay dedupes"`
- PASS: `flutter test --no-pub test/features/groups/integration/group_messaging_smoke_test.dart --plain-name "SV-006 fake-network replay duplicate and removed-interval delivery stay deduped"`
- PASS: `flutter test --no-pub test/features/groups/integration/group_messaging_smoke_test.dart --plain-name "MS002 live fake-network delivery stores and checks transport binding"`
- PASS: `git diff --check`

## Closure

`INTEGRATE-SV-010` is accepted as host/fake-network-only. Adjacent rows `SV-011` and later remain separate pending integration sessions.
