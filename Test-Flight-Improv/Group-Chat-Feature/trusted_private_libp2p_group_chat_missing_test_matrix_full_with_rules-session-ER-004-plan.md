# ER-004 Session Plan - Decryption failure triggers key repair and safe placeholder UI

Status: prerequisite-blocked

## Planning Progress

| timestamp | role | files inspected | decision | next action |
| --- | --- | --- | --- | --- |
| 2026-05-01T09:42:00+02:00 | Local planner completed | ER-004 source matrix row; ordered-session ER-004 row; Go decryption-failure tests; offline inbox placeholder tests; group conversation placeholder UI test; bridge diagnostics test; EK-005 and OS-009 evidence | Current repo evidence covers diagnostics and safe unrecoverable placeholders, but not the full row. Live decryption failures do not create a message placeholder or key-repair lifecycle, and unknown future epochs still lack durable queue/key-sync repair primitives. | Rerun focused evidence and persist ER-004 as `Partial`/prerequisite-blocked. |

## real scope

ER-004 asks for wrong-key, missing-key, future-epoch, and tampered group content to avoid crashes/plaintext rows, trigger key repair where possible, and show a safe placeholder when unrecoverable. Current shipped behavior covers Go diagnostics and offline unrecoverable placeholders, but not a complete live repair path.

## closure bar

ER-004 can be resolved only when:

- live wrong-key and tampered content fail without normal message delivery and surface app diagnostics
- missing/future epoch content enters a durable pending or repair state instead of being only dropped or immediately finalized
- key-sync repair is triggered where recovery is possible, with a completion/finalization lifecycle
- unrecoverable live and offline content surfaces a safe placeholder without plaintext/media leakage
- UI tests prove the user-visible state is truthful across repair pending, repaired, and unrecoverable outcomes

## session classification

`prerequisite-blocked`. This is not only missing assertions around existing code: durable message-level key repair and live placeholder lifecycle primitives are absent.

## Device/Relay Proof Profile

- Profile for this session: host-only Go diagnostics, Flutter bridge diagnostics, offline replay placeholder, and widget placeholder proof.
- Real-network proof is supplemental; the current blocker is missing product/runtime repair primitives.

## files touched

- closure docs only

## exact tests and gates run

- `cd go-mknoon && go test ./node -run 'TestHandleGroupSubscription_EmitsDecryptionFailedEvent$|TestHandleGroupSubscription_EmitsDecryptionFailedEventForTamperedNonce|TestHandleGroupSubscription_EmitsDecryptionFailedEventForTamperedCiphertext|TestGroupTopicValidator_RejectsUnknownFutureEpochBeforeDelivery|TestHandleGroupSubscription_DropsPreviousEpochAfterGraceExpires' -v` passed.
- `flutter test --no-pub test/features/groups/application/drain_group_offline_inbox_use_case_test.dart --plain-name 'future epoch encrypted replay creates one undecryptable placeholder without decrypting'` passed (`+1`).
- `flutter test --no-pub test/features/groups/presentation/group_conversation_screen_test.dart --plain-name 'renders undecryptable epoch placeholders as safe text'` passed (`+1`).
- `flutter test --no-pub test/core/bridge/go_bridge_client_test.dart --plain-name 'group decryption failure push event reaches diagnostics stream without invoking group message callback'` passed (`+1`).
- `git diff --check` must pass after closure docs.

## positive evidence

- Go live wrong-key, tampered nonce, and tampered ciphertext paths emit `group:decryption_failed` and do not emit normal `group_message:received`.
- Go rejects unknown future live epochs before delivery and drops expired previous-epoch traffic without a normal group-message event.
- Flutter bridge forwards `group:decryption_failed` to `groupDiagnosticEventStream` without invoking the group-message callback.
- Offline replay with a missing future key saves one `undecryptable` placeholder, preserves the missing key epoch, never calls `group.decrypt`, and does not expose future plaintext.
- `GroupConversationScreen` renders the undecryptable placeholder as safe generic text and shows no failed-media retry/delete controls for it.

## blocker class

- `missing_live_decryption_failure_placeholder_or_repair_surface`
- `missing_message_key_sync_repair_trigger`
- `missing_durable_future_epoch_pending_queue`
- `missing_repair_completion_or_finalization_lifecycle`

## done criteria for this blocked session

- Source matrix ER-004 remains `Partial` with positive evidence and blockers named directly.
- `test-inventory.md` gets an ER-004 crosswalk row with the fresh evidence.
- Breakdown current-session state, shared prerequisites, session ledger, ordered row, and classification counts record ER-004 as `prerequisite-blocked`.
- No resolved ER-004 claim is made.

## scope guard

Do not invent a partial repair lifecycle in documentation. Future closure needs production support for pending repair, trigger, retry/completion, and final unrecoverable placeholder behavior across live and offline delivery.

## Execution Progress

| timestamp | role | files inspected or changed | decision | next action |
| --- | --- | --- | --- | --- |
| 2026-05-01T09:46:00+02:00 | Local evidence auditor completed | Go decryption/future-epoch diagnostics, Flutter bridge diagnostics, offline future-epoch placeholder, and conversation placeholder UI tests | Blocked. Diagnostics and safe offline placeholder behavior are real, but message key-repair lifecycle and live placeholder surface are missing. | Persist ER-004 as `Partial`/prerequisite-blocked without changing product code. |

## Final Execution Verdict

Blocked on 2026-05-01. ER-004 remains `Partial`: current repo evidence proves no-crash diagnostics and safe offline unrecoverable placeholders, but the row cannot close until live decryption failure and future/missing-key content have a durable key-repair trigger, pending/repair/finalization lifecycle, and safe user-visible placeholder behavior.
