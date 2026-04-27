## 1. Title and Type

- Title: Message Send Failure Retry UX
- Issue type: bug
- Output doc path: `Test-Flight-Improv/78-message-send-failure-retry-ux.md`

## 2. Problem Statement

Users need to understand what happened when a 1:1 message fails to send and recover that same message without accidentally sending it twice.

Today, a failed outgoing message can show a red failed indicator and a transient failure message, but the recovery path is unclear for text-only messages. The user-reported workaround is to long-press the failed message, choose Edit, and send again. That makes a normal message-editing action feel like the resend path.

Repo evidence separates the reported duplicate/confusion into two failure modes:

- Composer-restore duplicate path: a failed send restores the same text into the composer while the failed row remains visible and retryable. If the user taps Send from that restored composer state, the app creates a new message ID and a second optimistic row for the same user intent.
- Edit-as-resend wire-semantics path: a failed outgoing message can enter the normal Edit flow. Submitting the edit reuses the original message ID but sends an `actionEdit` payload, while the failed row's earlier non-edit `wireEnvelope` may still be eligible for automatic retry.

In multiple observed cases, the original failed attempt was later retried while the user also sent recovered content, producing duplicate or confusing outgoing-message outcomes.

From the user's perspective, this is a trust bug: the app says the first message failed, provides no obvious recovery path, then may still deliver it while also allowing the user to send another copy.

## 3. Impact Analysis

- Affected users: users sending 1:1 messages during network loss, relay failure, app pause/resume, or contact-offline conditions.
- Trigger moments: active send failure, direct transport failure, relay inbox fallback failure, app pause while a message is still sending, app resume or online transition after a failed send.
- Severity: high for messaging trust because the user can see duplicate outgoing content after trying to recover a failed send.
- Frequency: repo evidence confirms failed rows, auto retry, resume retry, and failed-message UI all exist; observed frequency depends on real network instability.
- Confusion cost: the visible UI currently separates failed media recovery from failed text recovery, and the long-press menu can expose Edit without a dedicated failed-message recovery concept.
- Regression risk: existing reliability docs treat durable optimistic rows, failed/unacked/interrupted retry paths, periodic online retry, and same-row recovery as part of the current 1:1 reliability bar (`Test-Flight-Improv/47-message-reliability-roadmap.md:22-31`, `Test-Flight-Improv/47-message-reliability-roadmap.md:55-57`, `Test-Flight-Improv/19-1to1-message-reliability-closure-reference.md:11-12`, `Test-Flight-Improv/19-1to1-message-reliability-closure-reference.md:46-60`), so UX changes must preserve no-loss recovery while preventing duplicate visible sends.

## 4. Current State

- `lib/features/conversation/presentation/screens/conversation_wired.dart`
  - `_onSend` edit branch checks the current `_editingMessageId`, calls `editChatMessageFn(...)`, clears edit state and draft text, and upserts the returned message when present (`1483-1553`).
  - `_onSend` new-send branch captures a composer snapshot, clears draft/attachments, creates a new optimistic outgoing `ConversationMessage` with a new UUID and status `sending`, and persists it before network send work continues (`1555-1640`).
  - When a send result is not successful, the screen updates the optimistic message to `failed`, shows failure copy such as `Failed to send message. Message saved.`, and calls `_restoreComposerSnapshot(...)` (`1922-1956`).
  - `_restoreComposerSnapshot(...)` restores the previous draft text, attachments, and quote state into the composer, then persists the optimistic message as `failed` (`2051-2068`).
  - `_onRetryFailedMedia(...)` exists and calls `retryFailedMessage(...)`, but it is wired from failed media controls rather than a general failed text path (`1990-2027`).
  - `_onEditMessage(...)` enters edit mode by clearing quote state, storing `_editingMessageId`, and placing the selected message text back into the composer (`1329-1341`).
- `lib/features/conversation/presentation/screens/conversation_screen.dart`
  - Failed media actions are shown only when a failed outgoing message has media and retryable attachments (`453-463`, `525-531`).
  - `_canEditMessage(...)` does not exclude `status == 'failed'`; a failed outgoing text message can be eligible for the normal Edit action when it is the last outgoing message (`712-719`).
  - The long-press context overlay receives Reply, Edit, Copy, and Delete actions; it does not expose a failed-message recovery action (`640-689`).
- `lib/features/conversation/presentation/widgets/letter_card.dart`
  - Failed messages render `Icons.error_outline_rounded`, red status color, and semantic status `failed` (`491-517`).
  - Retry/Delete controls are built for failed media actions when callbacks are present (`286-315`).
- `lib/features/conversation/presentation/widgets/message_context_overlay.dart`
  - The visible context actions are Reply, Edit, Copy, and Delete (`279-307`).
- `lib/features/conversation/application/send_chat_message_use_case.dart`
  - When a `messageId` already exists, the send use case persists the `wireEnvelope` before risky transport work so the row can be retried (`292-298`).
  - Edit sends require an existing `messageId`, `timestamp`, and `createdAt`, then build a payload with `actionEdit` and `editedAt` (`163-209`).
  - If inbox fallback also fails, the use case persists a failed outgoing message with `status: 'failed'` and the `wireEnvelope` (`589-598`).
  - `editChatMessage(...)` reuses the original message ID and timestamp but sends with `actionEdit` (`632-664`), which is edit wire semantics rather than normal first-delivery semantics.
- `lib/features/conversation/application/retry_failed_messages_use_case.dart`
  - `retryFailedMessages(...)` loads failed outgoing rows and retries them (`20-52`).
  - `retryFailedMessage(...)` targets one failed outgoing row by ID (`55-81`).
  - Retry prefers an existing `wireEnvelope` and marks the same row delivered on successful inbox store (`188-231`).
  - Fallback retry re-enters `sendChatMessage(...)` using the original failed row's message ID and timestamp (`283-297`).
- `lib/features/conversation/application/retry_unacked_messages_use_case.dart`
  - `retryUnackedMessages(...)` loads outgoing messages stuck in `sent` with a persisted `wireEnvelope`, using a 60-second age threshold (`15-45`).
  - This path stores the persisted envelope in the relay inbox without direct send, re-encryption, or media rebuild (`7-12`, `105-127`).
  - Successful unacked retry marks the same row `delivered`, sets transport to `inbox`, and clears the `wireEnvelope` (`110-119`).
  - This is a separate automatic recovery path from failed-row retry, so it can overlap with user-visible recovery when a message has reached `sent` but has not been acknowledged.
- Lifecycle and automatic retry:
  - `lib/core/services/pending_message_retrier.dart` automatically retries failed outgoing messages and then unacked outgoing messages after online transitions, with a 5-second reconnect debounce and a 5-minute periodic online cadence (`14-22`, `162-170`, `282-292`, `399-417`).
  - `lib/core/lifecycle/handle_app_resumed.dart` retries failed messages on resume (`429-443`).
  - `lib/core/lifecycle/handle_app_resumed.dart` also retries sent-but-unacked messages on resume (`446-459`).
  - `lib/core/lifecycle/handle_app_paused.dart` transitions outgoing `sending` messages to `failed` locally so retry can pick them up later (`17-21`, `54-70`).
  - The pause transition is local DB work only and does not know whether an in-flight payload already reached the recipient before the sender's local row settled (`17-21`, `54-70`).
- Unacked query shape:
  - `lib/features/conversation/domain/repositories/message_repository.dart` defines unacked outgoing messages as `status='sent'` rows with non-null `wire_envelope` used by the unacked retry service (`77-83`).
  - `lib/core/database/helpers/messages_db_helpers.dart` loads those rows where `status = 'sent'`, `is_incoming = 0`, `wire_envelope IS NOT NULL`, and the timestamp is older than the cutoff (`580-604`).
- Same-ID duplicate protection exists, but it does not protect a newly composed second send:
  - `lib/features/conversation/application/handle_incoming_chat_message_use_case.dart` drops same-ID non-edit duplicates (`190-210`).
  - When an `actionEdit` payload arrives before the original, the receiver returns `editMissingOriginal`, stores a hidden placeholder, and later materializes the original using the edited text when the non-edit original arrives (`211-223`, `400-419`).
  - When an edit arrives after the original, the receiver updates the existing row in place if the edit is authorized and fresh (`225-256`, `292-302`).
  - `go-relay-server/backend_memory.go` skips storing duplicate relay inbox messages when the same message ID can be extracted (`120-126`).
  - `go-relay-server/inbox_dedup_test.go` verifies duplicate stores with the same plaintext and encrypted v2 message IDs remain one stored message (`20-36`, `86-96`).
- Distinct failure mechanisms:
  - Composer-restore recovery creates a new UUID and therefore bypasses same-ID duplicate protection if the user sends from the restored composer while the failed row remains retryable.
  - Edit-as-resend recovery reuses the same message ID, but changes the payload semantics from a non-edit message to `actionEdit`; for a message the recipient has never received, that is not equivalent to first delivery and receiver behavior depends on whether the original, the edit, or automatic replay arrives first.
  - Force-failed-after-delivery recovery reuses the same message ID through automatic retry, but the user-visible failed state can still prompt a new composer send with a different message ID for content the recipient already received.
- Existing tests partially cover the current behavior:
  - `test/features/conversation/presentation/screens/conversation_screen_test.dart` verifies failed outgoing media rows show retry and delete controls, and failed text-only rows do not show failed-media controls (`1571-1645`).
  - `test/features/conversation/presentation/screens/conversation_wired_test.dart` verifies a send returning null marks the optimistic message as failed (`1091-1145`).
  - `test/features/conversation/presentation/screens/conversation_wired_test.dart` verifies send failure after upload restores the quote draft and attachments, including the original composer text (`5070-5171`).
  - `test/features/conversation/application/retry_failed_messages_use_case_test.dart` verifies failed messages can be retried successfully (`240-307`).
  - `test/features/conversation/application/retry_failed_messages_media_test.dart` verifies targeted retry only retries the requested failed row (`478-510`).
  - `test/features/conversation/application/retry_unacked_messages_use_case_test.dart` verifies unacked rows store to inbox, become delivered, clear `wireEnvelope`, and skip inbox store when transport is already `inbox` (`69-109`, `259-297`).
  - `test/features/conversation/application/send_chat_message_use_case_test.dart` verifies `editChatMessage(...)` preserves the original row contract and emits `actionEdit` (`855-891`).
  - `test/features/conversation/application/handle_incoming_chat_message_use_case_test.dart` verifies edit-first hidden placeholders, later materialization, same-ID edit application, unauthorized edit rejection, and stale edit rejection (`472-624`, `626-759`).
  - `test/features/conversation/integration/send_then_lock_delivery_test.dart` verifies a completed delivered send is not overwritten by pause, but that is not the same as a `sending` row force-failed after the recipient already received it (`1039-1068`).
  - `test/features/conversation/integration/two_user_message_exchange_test.dart` verifies a same-ID duplicate injected after receipt does not create a second receiver row (`999-1039`).
  - `test/integration/relay_down_degradation_integration_test.dart` verifies a failed row can heal on online transition as the same row once (`93-155`).
  - `test/core/lifecycle/pause_resume_retry_smoke_test.dart` verifies pause transitions `sending` to `failed` and leaves the row available for retry (`13-68`).

## 5. Scope Clarification

- In scope:
  - The user-visible 1:1 conversation flow after an outgoing message fails to send.
  - Text-only failed outgoing messages as the primary reported failure.
  - Media failed-message recovery parity only where it helps avoid inconsistent user expectations.
  - The relationship between visible failed state, composer state, long-press actions, manual recovery, and automatic retry.
  - Wire semantics for failed-send recovery when the recipient may never have received the original message.
  - Pause/lock races where the sender locally marks an in-flight message failed even though the recipient may already have received that same message ID.
  - Coordination among Path A (`retry_failed_messages`), Path B (`retry_unacked_messages`), and Path C (user-initiated failed-message recovery) for the same message ID or same failed-send attempt.
  - Separate acceptance coverage for the composer-restore duplicate path and the edit-as-resend wire-semantics path.
  - Acceptance behavior that prevents one failed send attempt from producing two visible outgoing messages after recovery.
  - Recovery model for this spec: automatic retry remains preserved, and manual recovery is an allowed user override; both must resolve one canonical failed-send attempt rather than independent sends.
  - Canonical identity expectation: the original failed outgoing bubble and message ID are the visible recovery target. If restored composer text gives the user another send opportunity for the same failed attempt, the final state must still settle that original failed row as the only visible outgoing message for the attempt.
  - Accessibility semantics for the failed state and recovery affordance, so the recovery path is not only visually discoverable.
- Non-goals:
  - No new transport architecture.
  - No relay or receiver dedupe redesign beyond preserving current same-ID behavior.
  - No group chat retry UX scope in this document.
  - No broad edit-message feature redesign outside the failed-send confusion described here.
  - No claim about guaranteed retry while the Dart isolate is fully suspended.
  - No final decision in this spec about exact copy, control placement, or visual treatment.
- Accepted ambiguities for the later implementation pass:
  - The final UI language and control pattern should be decided later, as long as users do not need to infer that normal Edit is the resend path for a failed message.
  - The later pass should decide how much failed-message recovery parity is needed between text, media, voice, and quoted sends.
  - The later pass should decide whether feed inline replies need a separate spec if they share enough of the same failed-send behavior.
  - The spec acknowledges the existing targeted `retryFailedMessage(messageId:)` path as current-state evidence, but does not require the later implementation to expose that exact function as the user-facing primitive. Acceptance is based on one clear recovery target and one delivered copy.

## 6. Test Cases

Happy path:

- After a text message send fails because the network path is unavailable, the conversation shows exactly one outgoing message for that attempt, with a persistent and understandable failed state after any transient snackbar disappears.
- A user can recover the failed text message from the conversation without using normal Edit as the apparent resend workaround.
- When the user recovers a failed text message after connectivity returns, the original failed outgoing message settles to a sent or delivered state, and no second outgoing copy appears.
- If automatic retry succeeds while the conversation screen is open, the existing failed message updates in place and does not leave the user with an obvious duplicate-send trap.
- Failed media rows keep their currently covered user-visible recovery affordance, and failed text rows do not feel like a less recoverable class of message.

Edge cases:

- If the app pauses while an outgoing message is still sending, the user later sees one failed outgoing message, and resume or online recovery does not create an additional visible message.
- If direct delivery fails and relay inbox fallback fails, the failed state remains understandable and recoverable after the snackbar disappears.
- If a failed text message is also the last outgoing message, long-press behavior must not make a normal edit flow appear to be the only practical way to send the failed content.
- If a user repeatedly attempts recovery during a flaky network period, the conversation must still resolve to at most one visible sent or delivered copy of the original failed attempt.
- If a failed send included quote context or prepared attachments, recovery must not create confusing duplicate quote/attachment composer state alongside a retryable failed row.
- If Path A, Path B, and Path C become eligible around the same message ID or same failed-send attempt, the user and recipient must still observe at most one visible message for that attempt.
- Path A vs Path C race, text: if a failed text row becomes eligible for automatic failed-row retry and the user starts manual recovery within about 5 seconds, the receiver observes exactly one delivered copy and the sender observes one settled outgoing row for that attempt.
- Path B vs Path C race: if a sent-but-unacked row older than 60 seconds is eligible for unacked replay while the user starts manual recovery, the receiver observes exactly one delivered copy and the sender observes one settled outgoing row for that attempt.
- Composer-restore edge case: after a failed send restores the same text into the composer, sending from that restored state must still settle the original failed row as the only visible outgoing message for that failed-send attempt; the composer-restored send cannot become a second independent delivery.
- Edit-as-resend edge case: using normal Edit on a failed outgoing message must not leave the recipient with an edit-only hidden placeholder, stale original content, or ordering-dependent message state for what the sender experiences as recovering a failed send.
- Never-delivered recovery edge case: recovering a message that has not reached the recipient must be observed by the recipient as first delivery of that message, not as an `actionEdit` against a missing original.
- Force-failed-after-delivery edge case: if pause marks a `sending` row as `failed` after the recipient already received the same message ID, resume retry and any user-visible recovery flow must not create another visible message for the same send attempt.

Regressions to preserve:

- Same-ID duplicate suppression on the receiver and relay remains observable: replaying the same failed-row message ID does not create duplicate incoming rows.
- Same-ID relay dedup for encrypted v2 envelopes remains observable for the new recovery flow, not only for legacy envelope replay coverage.
- Automatic retry on online transition and resume remains observable for failed rows that are eligible for retry.
- Automatic unacked retry on online transition and resume remains observable for sent rows with a retryable persisted `wireEnvelope`.
- The 5-minute periodic retry cadence cannot resurrect a message that already settled through user-visible recovery, even hours after the initial failure.
- Existing failed media retry/delete controls remain available for failed outgoing media rows.
- Normal Edit remains available for eligible already-sent messages covered by the existing edit flow.
- Message status semantics remain honest: a message is not shown as delivered unless the existing transport/inbox delivery contract has been met.
- Failed-message status and recovery controls expose accessible semantics equivalent to the visible state and action.

Bug regression:

- If a text send fails, the failed row remains retryable, and the user then tries to recover from the UI before automatic retry completes, the final conversation must not show two outgoing copies of that same failed-send attempt.
- If failed-row retry and user-visible recovery race for a failed text row, the receiver must observe one delivered copy and the sender must observe one settled row.
- If unacked retry and user-visible recovery race for a sent-but-unacked row older than 60 seconds, the receiver must observe one delivered copy and the sender must observe one settled row.
- If a user-visible recovery action, failed-row retry, and unacked retry all have an opportunity to act on the same message ID, the final sender and recipient histories must not contain duplicate visible rows for that message ID or for that single send attempt.
- If composer restoration after failure allows the user to send the same text again, the final sender and recipient histories must not contain both the original failed-row delivery and the new composer-send delivery.
- If a failed message enters the normal Edit flow, submitting it must not turn failed-send recovery into an `actionEdit` delivery whose ordering with the original non-edit envelope produces inconsistent sender and recipient histories.
- If the original message was never delivered to the recipient, failed-send recovery must not produce an `actionEdit` payload as the first recipient-visible representation of that message.
- If a pause/lock event force-fails a row whose payload already reached the recipient, automatic retry may replay the same message ID but the final sender and recipient histories must still contain one visible message for that send attempt, even if the user also tries to recover from the failed UI.
- If a successfully recovered message remains in any periodic-retry query window, later retry sweeps must not recreate a failed state, send another copy, or surface another outgoing row.

Existing coverage and gaps:

- Existing unit, widget, and integration tests cover durable failed-row retry, targeted failed-row retry, failed media controls, pause-to-failed behavior, and online-transition same-row recovery.
- Existing unit tests cover unacked retry in isolation, including successful inbox store, delivered status, `wireEnvelope` clearing, and already-inbox crash recovery.
- Missing acceptance evidence: failed text-only rows do not yet have a direct user-visible recovery test.
- Missing acceptance evidence: no current test covers the composer-restore duplicate path where composer restoration plus automatic retry plus user resend leads to two visible outgoing messages.
- Missing acceptance evidence: no current test covers the edit-as-resend path where a failed outgoing row enters normal edit mode while the original failed-row envelope remains retryable.
- Missing acceptance evidence: no current test asserts that recovery of a never-delivered failed message avoids `actionEdit` wire semantics and is handled as first delivery by the recipient.
- Missing acceptance evidence: no current test covers the force-failed-after-delivery race where pause marks a `sending` row failed after the recipient already received it, then resume retry and user-visible recovery compete.
- Missing acceptance evidence: no current test covers Path A (`retry_failed_messages`) racing Path C (user-initiated recovery) for a failed text row.
- Missing acceptance evidence: no current test covers Path B (`retry_unacked_messages`) racing Path C for a sent-but-unacked row older than 60 seconds.
- Missing acceptance evidence: no current test covers all three of Path A, Path B, and Path C becoming eligible around the same message ID or same failed-send attempt.
- Missing acceptance evidence: no current test proves the new recovery flow stays covered by same-ID relay dedup for encrypted v2 envelopes.
- Missing acceptance evidence: no current test proves periodic retry sweeps cannot resurrect a successfully recovered message later.
- Missing acceptance evidence: no current test covers accessibility semantics for the failed state and recovery affordance.
- Missing acceptance evidence: no current test asserts that failed outgoing text is not recovered through the normal Edit mental model.
- Required acceptance evidence layers:
  - unit: deterministic same-attempt recovery and duplicate-prevention rules where they are user-visible.
  - integration: failed send, recovery, and automatic retry behavior across UI, repository state, and retry services.
  - smoke: the 1:1 send journey after transient network failure remains understandable and produces one visible message.
  - simulator: lifecycle-sensitive pause/resume and reconnect behavior remains observable on a mobile runtime.

## 7. Implementation Evidence

- Status: implemented and accepted on 2026-04-27.
- Failed outgoing text rows now expose direct Retry behavior and no longer use normal Edit as the apparent resend path.
- Same-attempt recovery targets the original failed row and message ID, including unchanged restored composer sends.
- If automatic retry settles the restored failed row before the user taps Send, the composer clears without creating a second outgoing message.
- Never-delivered failed text retry uses first-delivery send semantics, not `actionEdit`.
- Receiver same-ID dedupe remains covered for encrypted v2 retry envelopes.
- Final verification included direct focused suites and `./scripts/run_test_gates.sh 1to1`; see `Test-Flight-Improv/78-message-send-failure-retry-ux-session-breakdown.md` for the full accepted ledger.
