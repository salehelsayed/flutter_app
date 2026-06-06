## 1. Title and Type

- Title: Group Failed Message Retry Duplicate Send UX
- Issue type: bug
- Output doc path: `Test-Flight-Improv/108-group-failed-message-retry-duplicate-send-ux.md`
- Revision (2026-06-06): expanded from the narrow "one clear recovery target"
  framing to the requested "tap to queue, auto-send on reconnect, exactly one
  delivered copy" experience. Added Current State facts that were previously
  undocumented (no concurrency guard on the retry path, the `pending`/in-doubt
  stranding behind `BRIDGE_TIMEOUT`, exact-timestamp receiver-dedupe
  brittleness, the `relayReady` connectivity signal, and the existing
  app-resume group recovery pipeline / `GroupRecoveryGate` overlap). This
  remains a spec-only document: it states desired observable behavior, not a
  solution.

## 2. Problem Statement

Users need one failed group message attempt to recover as one message.

Today, when a group text send fails, the failed outgoing bubble can remain visible with Retry while the same text is also available in the composer. If the user taps Retry, taps Send from the restored composer, or taps retry repeatedly during network instability, the same user intent can be sent more than once.

From the user's perspective, this is a trust bug: the app says a message failed, offers multiple recovery paths for the same text, and can later show or deliver duplicate copies after the user was only trying to recover one failed message.

The user's expectation during a connection error is simple: the message they typed should be sent once. Instead, the current experience asks the user to manage recovery manually — it shows a failed bubble with Retry, leaves the same text in the composer, and relies on the user to tap the right control the right number of times. There is no single, calm "the message is queued and will send itself" state. The requested experience is "tap to queue": once the user taps Send, the message is represented once as a queued outgoing item, the composer is cleared, and the message is delivered automatically when connectivity returns — resolving to exactly one delivered copy without the user having to retry by hand.

A related failure of the same goal is the in-doubt path. When a send times out at the bridge but may already have been accepted, the row can be left in a `pending` state that has no visible recovery control and is excluded from the manual failed-message retry. In that case the user is stranded with a message that is neither clearly failed nor clearly delivered, and any later manual re-send of the same text becomes a new, independent delivery. "Recover one attempt as one message" must hold for in-doubt rows too, not only for rows that surface as `failed`.

## 3. Impact Analysis

- Affected users: group chat senders during connection loss, relay failure, topic disconnection, bridge timeout, app pause/resume, or flaky recovery periods.
- Trigger moments: after a failed outgoing group text row appears, when a user sees both a failed bubble and the same text in the composer, or when a retry action is tapped multiple times before the UI visibly settles.
- Severity: high for messaging confidence because duplicate group messages are visible to multiple recipients and make the sender appear to have repeated themselves.
- Frequency: repo evidence confirms group failed rows, inline text retry, restored composer drafts, same-row retry, automatic retry, and receiver dedupe all exist. Real-world frequency depends on network instability and user recovery behavior.
- Confusion cost: the user must infer whether Retry, Send, or both refer to the same failed message. The current visible state can make the same failed text feel like two separate sendable objects.
- Regression risk: existing group reliability work covers same-id retry and inbound duplicate suppression, but a fresh composer send with a new message identity can bypass those safeguards.

## 4. Current State

- `lib/features/groups/presentation/screens/group_conversation_screen.dart`
  - Failed outgoing text-only group rows can expose a Retry action when the user can write, the row is outgoing, the status is `failed`, there is no media, and the text is non-empty (`531-555`).
  - Failed media rows use separate failed-media retry/delete actions, and text rows avoid those media controls (`545-555`).
- `lib/features/groups/presentation/screens/group_conversation_wired.dart`
  - `_onSend` checks for a restored failed-message continuation before beginning a send (`1726-1745`).
  - A normal send creates a message id and timestamp for optimistic display, and falls back to a new UUID when no continuation is available (`1756-1758`).
  - The composer draft and attachments are cleared during send setup (`1784-1789`).
  - A failed send restores the composer snapshot through `_restoreComposerSnapshot(...)` (`2053-2060`).
  - `_restoreComposerSnapshot(...)` puts the old draft text back into `_draftText`, marks the local row failed, and tracks the failed row as a restored continuation (`2377-2415`).
  - `_onDraftChanged(...)` clears restored continuation tracking when the visible draft text changes from the tracked failed draft (`2077-2083`).
  - `_onRetryFailedMessage(...)` calls the existing failed-message retry path for one row and refreshes the row after the call (`2306-2334`).
  - The wired screen subscribes to `GroupOutgoingLocalMessageChangeSource.outgoingLocalMessageChanges` when the repository provides it, applies single-row status updates, and reloads when the repository reports rows changed (`1358-1395`).
- `lib/features/conversation/presentation/widgets/compose_area.dart`
  - The composer restores `initialText` into the text controller when the parent supplies non-empty text (`131-146`).
  - Pressing Send clears the text controller before calling the parent `onSend` callback (`168-172`).
- `lib/features/groups/application/retry_failed_group_messages_use_case.dart`
  - `retryFailedGroupMessage(...)` targets one failed outgoing row by id (`96-119`).
  - The retry path re-enters group send with the original message id, logical delivery id when present, timestamp, quote, and media context (`281-300`).
- `lib/features/groups/application/send_group_message_use_case.dart`
  - The send path allows reuse of an existing outgoing `sending` or `failed` row only when the requested id, sender, text, quote, and timestamp match (`327-346`, `349-382`).
  - If no logical delivery id is provided, the message id becomes the logical delivery id (`817-840`).
  - Outgoing rows are pre-persisted with status `sending`, retry payload fields, and the resolved logical delivery id before bridge send work proceeds (`949-970`).
- `lib/features/groups/application/handle_incoming_group_message_use_case.dart`
  - Incoming group messages can dedupe by logical delivery id when both the new delivery and an existing row have that identity (`536-570`).
- `lib/core/database/migrations/074_group_message_logical_delivery_id.dart`
  - The logical delivery id column is intentionally nullable and non-unique, so distinct stable-id sends remain representable (`5-8`, `26-30`).
- `lib/features/groups/domain/repositories/group_message_repository.dart` / `group_message_repository_impl.dart`
  - `GroupOutgoingLocalMessageChange` can represent a specific outgoing status update or a broader rows-changed reload signal (`group_message_repository.dart:184-211`).
  - `GroupMessageRepositoryImpl` emits local outgoing status events when an outgoing row changes status through save/update, and emits rows-changed for stuck-sending recovery (`group_message_repository_impl.dart:119-142`, `360-374`).
- Concurrency guard asymmetry between the two recovery paths
  - The composer send path acquires an in-flight guard via `_tryBeginSendFlow()` / `_isSending`, and a second concurrent composer send is rejected while one is running (`group_conversation_wired.dart:325-342`, `1745`).
  - The failed-row retry path `_onRetryFailedMessage(...)` does not acquire that guard, does not disable the Retry control while recovery is in flight, and the retry use case has no in-flight lock keyed by row (`group_conversation_wired.dart:2306-2334`). Repeated rapid Retry taps, or a Retry overlapping a composer Send, can therefore run concurrently for the same failed text.
- In-doubt (`pending`) status behind bridge timeout
  - The send path detects a reliable-send bridge timeout (`send_group_message_use_case.dart:231-234`) and, when the message may already have been accepted, marks the row `pending` rather than `failed`, retaining the inbox retry payload for later recovery (`send_group_message_use_case.dart:1033-1083`).
  - The manual failed-message retry only loads and operates on rows with status `failed` (`retry_failed_group_messages_use_case.dart:115`), so `pending` rows have no manual Retry affordance and are not covered by that path.
  - A separate stuck-`sending` recovery threshold exists at thirty seconds (`recover_stuck_sending_group_messages_use_case.dart:5`), and a separate failed-inbox-store drain targets `sent`/`pending` rows (`retry_failed_group_inbox_stores_use_case.dart`).
- Existing app-resume group recovery pipeline
  - `handleAppResumed(...)` already performs group rejoin and group offline inbox drain under `runWithGroupRecoveryGate(...)` when resume group recovery is enabled (`handle_app_resumed.dart:143-222`).
  - After that rejoin/drain sequence, the resume handler calls `recoverStuckSendingGroupMessagesFn`, `retryIncompleteGroupUploadsFn`, and `retryFailedGroupMessagesFn` in order, then later calls `retryFailedGroupInboxStoresFn` (`handle_app_resumed.dart:266-325`, `511-518`).
  - The existing pipeline means this spec must not claim there is no automatic recovery anywhere. The missing behavior is a send-readiness / reconnect queue owner that coalesces with the resume pipeline and preserves one-attempt / one-copy semantics across relay-ready transitions, resume, and manual nudges.
  - Resume group recovery is feature-gated by `enableResumeGroupRecovery` (`handle_app_resumed.dart:22-25`), so the later implementation must decide whether the new queued-send owner follows that flag, has its own flag, or remains active independently.
- Existing failed-inbox-store retry also owns reaction replay recovery
  - `retryFailedGroupInboxStores(...)` first loads outgoing message rows whose inbox store failed, then uses the remaining limit capacity to drain retryable sender-owned `GroupReactionReplayOutboxEntry` rows when a reaction replay repository is provided (`retry_failed_group_inbox_stores_use_case.dart:20-23`, `55-62`).
  - On successful message-row retry it clears the inbox retry payload, marks the inbox stored, and updates the message status to `sent`, which can emit local outgoing status changes to an open conversation (`retry_failed_group_inbox_stores_use_case.dart:76-86`).
  - The queued-send work must preserve this existing message/reaction ownership boundary: a text-message recovery must not drop, misclassify, or duplicate reaction replay outbox entries while coexisting with the same resume retry pass.
- `GroupRecoveryGate` overlap
  - `GroupRecoveryGate` exposes active recovery depth and is active during resume group rejoin/drain (`group_recovery_gate.dart:3-47`, `handle_app_resumed.dart:148-222`).
  - `GroupConversationWired` observes `groupRecoveryGate.activeDepthListenable` and passes `isRecovering` into the screen (`group_conversation_wired.dart:4242-4271`).
  - `sendGroupMessage(...)` rejects announcement-group sends while group recovery is active with a `group_recovery_pending` outcome (`send_group_message_use_case.dart:691-700`).
  - The current failed-row retry affordance is still controlled mainly by write permission and media availability, so a retry or send-now action may overlap active group recovery unless the later implementation explicitly coalesces or defers it (`group_conversation_wired.dart:4298-4301`, `group_conversation_screen.dart:550-556`).
- Receiver duplicate suppression is identity-narrow
  - Incoming dedupe resolves first by message id, then by logical delivery id (`handle_incoming_group_message_use_case.dart:92-150`, `535-572`), and the message-id-less content fallback requires an exact `(group_id, sender_peer_id, text, timestamp)` match (`existsByContent` in `group_messages_db_helpers.dart`).
  - A recovery that produces a new message id and a new timestamp for the same user intent — which is what a fresh composer Send does once the original row is no longer `sending`/`failed` (`send_group_message_use_case.dart:327-346`) — is not caught by message-id, logical-delivery-id, or content dedupe, so it can be delivered as a genuine second copy.
- Connectivity / relay-ready signal available to a recovery owner
  - `NodeState` exposes `relayReady` and `usabilityReady` (`lib/features/p2p/domain/models/node_state.dart:136-145`), which indicate when relay session and send/inbox capabilities are available. There is currently no explicit consumer that drains queued, failed, or in-doubt outgoing group sends when these transition to ready.
- Existing tests and adjacent docs:
  - `test/features/groups/presentation/group_conversation_screen_test.dart` already verifies failed outgoing text-only rows show a Retry action and that failed media rows keep media retry/delete controls (`1560-1617`).
  - `test/features/groups/presentation/group_conversation_wired_test.dart` currently verifies a failed publish shows a failed message and keeps the draft in the composer (`5887-5918`).
  - `test/features/groups/domain/repositories/group_message_repository_impl_test.dart` already verifies local outgoing status events for save/update status and rows-changed events for bulk row changes (`337-382`, `463-502`).
  - `test/core/lifecycle/handle_app_resumed_group_recovery_test.dart` already verifies the resume order `rejoin -> drain -> recoverStuck -> retryUploads -> retryFailed -> retryInbox`, a failed/pending background send resume path, the `enableResumeGroupRecovery` disabled path, and `GroupRecoveryGate` blocking certain group mutations while recovery is active (`1190-1344`, `1348-1378`, `1508-1535`).
  - `Test-Flight-Improv/78-message-send-failure-retry-ux.md` records the analogous 1:1 failed-send duplicate problem and accepted recovery behavior for 1:1 messaging, but it explicitly excludes group chat scope.
  - `Test-Flight-Improv/Group-Chat-Feature/Improvement-Review-2026-06/01-P0-duplicate-delivery-cascade-session-text-retry-ui-plan.md` covers exposing group text retry, but its accepted scope does not include end-to-end duplicate-delivery closure for the group journey.

## 5. Scope Clarification

- In scope:
  - Group text-message send failures where the failed outgoing row remains visible.
  - The user-visible relationship between the failed bubble, Retry, and the composer after failure.
  - Repeated Retry taps during an unsettled connection.
  - Recovery attempts where Retry and Send are both reachable for the same failed text.
  - Sender-visible and recipient-visible proof that one failed attempt settles to at most one delivered group message.
  - Preservation of existing failed media retry/delete behavior.
  - Preservation of automatic failed-message retry and same-id/logical-delivery dedupe expectations.
  - Recommended behavior: after a text-only failed group message is visible as a failed row, the user should have one clear recovery target for that failed attempt. The composer should not present the same failed text as an independent second send opportunity unless the final observed result still resolves to the original failed attempt as one visible message.
  - Recommended behavior: retry actions should not appear to accept repeated independent recoveries for the same failed row while recovery is already unsettled.
  - Group text sends attempted during a connection error, where there is no live transport at send time.
  - Recovery of in-doubt (`pending`) outgoing rows, so a timed-out-but-possibly-accepted send is not stranded without a recovery path.
  - Automatic recovery: an outgoing group text that could not be delivered at send time is delivered automatically when connectivity / relay readiness returns, without the user having to tap Retry by hand.
  - Concurrency safety of recovery: repeated Retry taps, a Retry overlapping a composer Send, and an automatic recovery overlapping a manual one all resolve to a single delivered copy.
  - Coexistence with the existing app-resume group recovery pipeline: queued-send recovery, resume `retryFailedGroupMessages`, resume `retryFailedGroupInboxStores`, stuck-sending recovery, and manual retry/send-now nudges must all converge on the same attempt identity when they target the same user intent.
  - Behavior while `GroupRecoveryGate` is active, including whether a visible recovery action waits, disables, shows in-progress state, or coalesces, provided it never creates a second independent attempt.
  - Feature-flag behavior for automatic queued-send recovery relative to the existing `enableResumeGroupRecovery` flag or any new feature flag chosen later.
  - Open-conversation visibility of queued/retry state through the existing local outgoing row-change mechanism, so an already-open group conversation observes the one queued attempt settling without requiring a duplicate row or stale status.
  - Recommended behavior ("tap to queue"): when the user taps Send and the message cannot be delivered immediately, the message is represented exactly once as a queued/in-progress outgoing item, the composer is cleared (no restored draft acting as a second send opportunity), and the message is delivered automatically when the connection is restored, resolving to exactly one sender-visible and one recipient-visible copy.
  - Recommended behavior: a manual Retry, where offered, behaves as an idempotent "send now" nudge for the already-queued attempt rather than as a new send, and reflects an in-progress state instead of inviting repeated independent recoveries.
- Non-goals:
  - No change to the group wire envelope/protocol or to relay-side dedupe semantics; the single-copy guarantee for one user intent must hold from the client side regardless of relay behavior.
  - No database uniqueness mandate for logical delivery id.
  - No changes to group membership, key rotation, invite recovery, or notification routing scope.
  - No changes to group reaction semantics or reaction replay UX; reaction replay is mentioned only because it shares the existing `retryFailedGroupInboxStores(...)` pass that queued-message recovery must not regress.
  - No new failed text delete requirement.
  - No claim about copy, icon, control placement, animation, or exact visual styling.
  - No requirement to remove the existing media failure affordances.
- Accepted ambiguities for the later implementation pass:
  - The exact UI presentation of the failed row recovery state remains open.
  - The later pass should decide how restored quote text, restored media, and voice-message failures align with the text-only behavior without broadening this spec.
  - The later pass should decide how to represent transient retry-in-progress state in the UI, provided the observable behavior remains single-attempt recovery.
  - The exact visual presentation of the queued/offline state and whether a manual "send now" control is offered alongside automatic recovery remain open, provided the observable behavior is single-copy delivery.
  - The exact triggers and timing of automatic recovery (for example, which readiness signal it keys on and any backoff) remain open, provided one queued or in-doubt attempt resolves to one delivered copy and does not deliver duplicates on repeated readiness transitions.
  - The later pass should decide the precise relationship between queued-send recovery and the existing resume group recovery feature flag, provided disabled/enabled behavior is explicit and testable.

## 6. Test Cases

### Happy Path

- When a group text message fails to send, the conversation shows exactly one failed outgoing row for that attempt.
- The failed row exposes a clear recovery path for the failed attempt when the user can write.
- The composer does not leave the user with an obvious second independent Send path for the same failed text while the failed row is also retryable.
- When connectivity returns and the user retries the failed row, the original failed row settles to sent or delivered and no second outgoing text copy appears.
- Recipients observe one delivered group message for the recovered failed text.

### Edge Cases

- If the user taps Retry multiple times rapidly on the same failed group text row, the sender and recipients still observe at most one recovered message for that failed attempt.
- If the user taps Retry and then taps Send from any restored composer state for the same failed text, the final group history contains one outgoing message for that attempt.
- If a failed text row is retried while automatic failed-message retry is also eligible, the sender and recipients observe one recovered message.
- If a failed text row included quote context, recovery does not create duplicate quoted messages or leave a stale quote draft that can send the same failed attempt again.
- If a failed text row is in a read-only or dissolved group state, recovery controls and composer behavior do not invite a send that the user cannot complete.
- If retry still fails because connectivity is unavailable, the failed row remains recoverable and the composer does not create an extra copy of the same failed text.
- If a message was already accepted by the group inbox or live publish but the local UI later shows an unsettled or failed state, user-visible recovery does not create a second recipient-visible message.
- If `GroupRecoveryGate` is active while the user tries to recover a queued or failed group text, the UI does not create a fresh independent attempt; it either defers, coalesces, or shows an in-progress state for the existing attempt.
- If the group is an announcement group and send is blocked with `group_recovery_pending`, the queued/retry UX remains understandable and does not restore the same text as an independent duplicate send opportunity.

### Queue And Auto-Send Recovery

- When the user taps Send on a group text while there is no usable transport (airplane mode, no relay, topic disconnected), the conversation shows exactly one queued/in-progress outgoing row for that text and the composer is left empty, with no copy of the same text remaining as a separate send opportunity.
- When connectivity / relay readiness returns, a queued group text is delivered automatically without any further user tap, the queued row settles to sent or delivered, and recipients observe exactly one copy.
- When several distinct group texts are composed and sent while offline, each is queued once and, after reconnect, each is delivered exactly once with no duplicates and no dropped messages; their relative order is preserved as observed by recipients.
- When a queued or in-doubt group text is still unsent and the app is backgrounded, killed, and relaunched, the message is still represented once and is delivered exactly once after connectivity returns following relaunch.
- When an in-doubt (`pending`) row exists because a send timed out but may have been accepted, the user is not stranded: the attempt either settles on its own to a single delivered copy or offers a recovery path that still resolves to a single delivered copy, and it never produces a second recipient-visible message.
- When automatic recovery and a user-initiated recovery for the same queued/in-doubt attempt occur at nearly the same time, recipients still observe exactly one copy.
- When readiness signals flap (relay becomes ready, drops, and becomes ready again) while an attempt is queued, automatic recovery delivers the attempt exactly once and does not emit a copy per readiness transition.
- When the user taps a "send now" control (if one is offered) on an already-queued attempt, it does not create a second attempt; recipients still observe exactly one copy.
- When app resume begins while a queued or failed group text is also eligible for relay-ready auto-send, the resume recovery pipeline and relay-ready recovery owner coalesce on the same attempt and recipients still observe exactly one copy.
- When `enableResumeGroupRecovery` is disabled, the automatic queued-send behavior is either explicitly disabled with it or explicitly governed by a separate tested flag; there is no ambiguous half-enabled state that can strand or duplicate the queued attempt.
- When the sender already has the group conversation open, repository-local status or rows-changed signals update the existing queued/retrying row in place; the user does not need to leave and re-enter the conversation to see the settled state, and no duplicate local row appears.

### Regressions To Preserve

- Failed outgoing media rows continue to expose existing media retry/delete behavior.
- Failed text rows continue to avoid failed-media retry/delete controls.
- Same-id retry continues to update the original failed row rather than creating a new row.
- Receiver-side message-id and logical-delivery duplicate suppression remain observable for replayed deliveries.
- Distinct intentional messages with the same text remain possible when the user composes them as separate messages after the failed-attempt recovery has settled.
- Successful timeout-plus-inbox custody still clears the composer and does not show a failed row.
- Existing 1:1 failed-send retry behavior remains unaffected.
- Existing resume group recovery order remains intact: group rejoin/drain, stuck-sending recovery, incomplete group media upload retry, failed group message retry, and failed group inbox-store retry still run in the established sequence.
- Existing group reaction replay outbox retry behavior remains intact when `retryFailedGroupInboxStores(...)` runs; queued text-message recovery does not drop reaction replay rows, mark them with message statuses, or count them as duplicate message sends.
- Existing outgoing local status / rows-changed events remain usable by open group conversations for status updates and reloads.
- Existing `GroupRecoveryGate` protections for group recovery remain intact; the new queued-send recovery does not allow blocked membership, metadata, or announcement send behavior to bypass active recovery.

### Bug Regression

- A failed group text message, followed by Retry and/or Send attempts for the same visible failed text, must not result in two outgoing rows or two recipient-visible deliveries for that failed attempt.
- A rapid multi-tap on Retry for one failed group text row must not produce multiple sender-visible recovery outcomes or multiple recipient-visible group messages.
- A failed group text row that remains eligible for automatic retry must not produce a duplicate if the user manually recovers it at nearly the same time.
- A restored composer draft from a failed group text message must not become a new independent delivery while the original failed row remains retryable.
- A queued or failed group text must not be sent once by relay-ready recovery and again by app-resume `retryFailedGroupMessages` / `retryFailedGroupInboxStores`.

### Acceptance Evidence

- TDD evidence is required: the later implementation must first establish a failing or reproducing evidence path for the duplicate-send bug and the recommended single-recovery behavior, then show the same evidence passing after the change.
- Required `unit` evidence:
  - Same-attempt retry identity remains stable for failed text recovery.
  - Repeated recovery attempts for one failed text row resolve as one observable recovery outcome.
  - Distinct intentional same-text messages remain representable after the failed-attempt recovery has settled.
  - Concurrent recovery attempts for one attempt (overlapping manual taps, or manual overlapping automatic) coalesce to a single send.
  - An in-doubt (`pending`) attempt is recoverable rather than stranded, and recovery resolves to a single delivered copy.
  - A send attempted with no usable transport produces exactly one queued representation and clears the composer of the same text.
  - A queued attempt keeps one stable attempt identity while being observed by manual retry, relay-ready auto-send, and resume retry code paths.
  - Feature-flag behavior for queued recovery versus `enableResumeGroupRecovery` is explicit and covered.
  - Outgoing local status or rows-changed signals are emitted for queued/retry state transitions that an open group conversation must observe.
- Required `integration` evidence:
  - The group conversation UI, composer state, repository rows, retry use case, and group send path together recover a failed text row as one sender-visible message.
  - A Retry-plus-Send sequence for the same failed text settles as one sender-visible and one recipient-visible message.
  - Automatic failed-message retry racing with user-visible retry settles as one sender-visible and one recipient-visible message.
  - A group text sent with no usable transport is queued once, then delivered automatically on reconnect as one sender-visible and one recipient-visible message with no further user tap.
  - An in-doubt (`pending`) attempt that may already have been accepted recovers to one recipient-visible message and is never delivered twice.
  - Multiple distinct texts queued while offline are each delivered exactly once after reconnect, in order, with none dropped or duplicated.
  - App-resume group recovery racing with relay-ready queued-send recovery still produces one sender-visible row and one recipient-visible delivery for the same attempt.
  - Active `GroupRecoveryGate` behavior is covered for manual recovery and announcement-group send blocking so recovery cannot create a second attempt while group state is resynchronizing.
  - `retryFailedGroupInboxStores(...)` still drains eligible message inbox-store rows and retryable reaction replay rows according to its existing message-first ownership model after queued-send recovery is introduced.
  - An already-open group conversation observes queued, retrying, sent, delivered, and failed status changes through the repository-local change path without duplicate rows or stale composer recovery state.
- Required `smoke` evidence:
  - A normal group send still succeeds.
  - A failed group text send remains understandable and recoverable after transient connection loss.
  - Existing failed media retry/delete behavior remains visible and functional.
- Required `simulator` evidence:
  - The group failed-send recovery journey remains single-copy across mobile lifecycle conditions such as pause/resume or reconnect where automatic retry may also run.
  - At least one multi-user group journey observes the sender and recipient histories after recovery and confirms one delivered copy for the failed attempt.
  - A "send while offline, then reconnect" journey shows the message queued once, auto-delivered after connectivity returns with no manual retry, and confirmed as one copy in both sender and recipient histories.

Existing coverage partially supports these requirements, but current evidence does not yet prove the key duplicate-send paths:

- Existing screen tests cover failed text retry visibility and failed-media preservation.
- Existing wired tests cover failed publish visibility and currently expect the failed text to remain in the composer. Under the "tap to queue" behavior the composer is cleared instead, so this expectation is an intended behavior change to update, not a regression to preserve.
- Existing repository tests cover status and rows-changed event emission, but not a queued-send recovery journey observed by a live `GroupConversationWired` instance.
- Existing lifecycle tests cover the resume recovery order, failed/pending background recovery hooks, `enableResumeGroupRecovery` disabled behavior, and `GroupRecoveryGate` blocking for some group mutations. They do not prove queued-send idempotency across relay-ready auto-send, resume retry, and manual retry for the same group message attempt.
- Existing retry-use-case coverage supports same-row retry and failed inbox-store retry, but not the combined user journey where Retry, restored composer Send, app-resume retry, reaction replay ownership, and relay-ready automatic recovery can overlap.
- No existing coverage proves: a send-while-offline attempt is queued once and auto-delivered exactly once on reconnect; an in-doubt (`pending`) attempt is recoverable rather than stranded and never delivered twice; rapid Retry taps or Retry-overlapping-Send are guarded so they cannot start concurrent recoveries; app-resume retry and relay-ready recovery coalesce for the same attempt; queued-send recovery preserves reaction replay retry ownership; open conversations observe queued/retry state through local row-change events; or that repeated relay-readiness transitions do not each emit a copy of a queued attempt.

## 7. Final Closure Status

Final program verdict: `closed`

Verdict date: 2026-06-06 17:26 CEST

Report 108 is closed by the GFR-001 through GFR-005 rollout. The original
"current evidence does not yet prove" section above is retained as the
pre-rollout baseline; the final accepted evidence below supersedes it for
maintenance-time decisions.

### Accepted Behavior

- One group text user intent is represented by one stable outgoing attempt
  across failed, queued, retrying, pending/in-doubt, sent, and delivered states.
- Manual Retry, repeated Retry taps, Retry overlapping composer Send, relay-ready
  auto recovery, and app-resume recovery coalesce on the same attempt instead of
  creating an independent second send.
- A no-usable-transport send becomes one queued/in-progress row, clears the
  composer for that text, and auto-recovers on reconnect without a second
  recipient-visible copy.
- In-doubt `pending` rows are recoverable through the same stable-attempt path
  and are not stranded outside manual or automatic recovery.
- Open group conversations observe queued, retrying, failed, sent, and delivered
  state transitions in place without resurrecting the same text as a duplicate
  composer send opportunity.
- Failed media retry/delete behavior, text-row media-control separation,
  distinct intentional same-text sends after settlement, receiver
  message-id/logical-delivery dedupe, resume recovery ordering,
  `GroupRecoveryGate` protections, and reaction replay retry ownership remain
  preserved.

### Accepted Evidence

- GFR-001 accepted the stable attempt contract: same-row failed retry, pending
  retry eligibility, logical delivery identity preservation, receiver duplicate
  suppression, and distinct intentional same-text sends.
- GFR-002 accepted queued auto-send and readiness coalescing, including
  relay-ready/app-resume overlap and the explicit follow-up that whole-journey
  simulator acceptance belonged to GFR-004.
- GFR-003 closed the open-conversation UX: duplicate composer recovery was
  removed for the failed text path, row-scoped retry in-flight state suppresses
  repeated independent attempts, failed media behavior remains intact, and local
  status updates settle the existing row.
- GFR-004 accepted host, named-gate, and simulator evidence. The required
  simulator list passed, `private_relay_reconnect_group_recovery` passed on run
  `1780758396971`, and `private_background_resume_group_delivery` passed on run
  `1780758894898`. In both scenarios Alice, Bob, and Charlie ran migration
  `074_group_message_logical_delivery_id` with no missing-column failure. Alice
  published the target missed/background messages with
  `deliveryMode:"live_and_inbox"`, `expectedRecipientCount:2`, and
  `inboxStored:true`; Bob wrote the required received-proof JSONs with
  `liveOnly:false`, `usedOfflineDrain:true`, and `persistedCount:1`; all
  Alice/Bob/Charlie role verdict JSONs and both orchestrator verdict JSONs were
  written and accepted.
- Final hygiene for the rollout is recorded in the session breakdown and GFR
  plans, including focused/direct tests, `groups`, selected-device `transport`,
  selected-device `baseline`, `completeness-check`, graph refresh, simulator
  proof, and whitespace checks.

### Accepted Differences

- This closure is a client-side group text send/retry/recovery guarantee for
  one user intent, not a relay-side uniqueness guarantee and not a
  per-recipient ACK or read-receipt claim.
- The simulator evidence uses the existing group lifecycle scenarios plus the
  GFR-001 through GFR-003 host acceptance contract; no separate new
  `private_group_failed_retry_single_copy` scenario is required for this
  closure unless a future regression proves the accepted scenarios no longer
  cover the lifecycle risk.
- The existing group status vocabulary remains receipt-less: `sent` means the
  sender pipeline is durably closed under current group semantics, not that
  every member has acknowledged the message.

### Residual-Only Items

No Report 108 product residual remains. Broader provider/device-lab confidence
can still be run as release confidence, but it is not a blocker for this
repo-owned closure unless it exposes a real duplicate-send regression.

### Reopen Rules

Reopen Report 108 only if a current group text recovery path again creates a
second sender-visible row or second recipient-visible delivery for one failed,
queued, retrying, pending, or auto-recovered user intent; if a queued/no-usable
transport group text no longer auto-recovers exactly once; if pending rows are
again stranded outside recovery; if open conversation recovery restores the same
failed text as an independent composer send opportunity; if receiver
message-id/logical-delivery dedupe regresses; or if the accepted GFR-004
simulator lifecycle proof stops writing the required Bob received-proof and role
verdict artifacts for the target messages.
