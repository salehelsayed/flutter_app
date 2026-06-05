## 1. Title and Type

- Title: Group retry duplicate-delivery cascade residuals for text, voice, and APNs proof
- Issue type: bug
- Output doc path: `Test-Flight-Improv/102-group-image-retry-duplicate-delivery-notifications-media-ux.md`

## 1A. June 2026 Closure Lineage

The original doc-102 image/media closure remains the lineage anchor. The June 2026 improvement-review follow-up at `Test-Flight-Improv/Group-Chat-Feature/Improvement-Review-2026-06/01-P0-duplicate-delivery-cascade.md` extends that closure to text retry, restored text same-id continuation, recorded-voice upload/re-record recovery, timeout/pending retry payloads, local outgoing status visibility, stuck-sending attempt timestamps, and live/replay one-notification dedup.

Current accepted repo-local evidence was rerun on 2026-06-04 through the direct suites listed in that follow-up plan, reliability-sim commands `#8` (`integration_test/group_recovery_e2e_test.dart`) and `#2` (`integration_test/foreground_group_push_drain_test.dart`), the `transport` named gate, and the broad `groups` gate triaged to the carried non-owned `GCA-004` residual only. Real provider-backed iOS APNs/TestFlight background/terminated proof remains residual-only.

## 2. Problem Statement

A group sender needs one intended group message to arrive once, even when send confirmation is slow, the app resumes after an interruption, or the sender retries after ambiguous feedback.

The original image/media cascade in this doc is implemented and no longer appears wide open: image retry identity, media loading, relay inbox idempotency, Android notification coalescing, and group reliability simulator closure have repo evidence. The later text/voice extension has also been accepted in repo-local evidence:

- Plain-text failed rows expose in-place same-id retry, and unchanged restored text continuation reuses the failed row id/timestamp.
- Recorded voice retry, upload-pending recovery, durable-prep cleanup, and re-record continuation are covered under one logical id.
- Reliable-send timeout handling and retained in-doubt pending retry payloads are covered by host and transport evidence.
- Local-only status changes reach the open group screen, and stuck-sending recovery keys off a send-attempt timestamp rather than the original message timestamp.
- Live pubsub plus inbox replay/drain converges on one row and one eligible notification path.
- Repo-level iOS notification proof is strong; provider-backed background/terminated APNs proof remains residual.

From the user's perspective, the accepted repo-local behavior is now the intended trust contract: "I sent this once" recovers through one stable logical message rather than encouraging duplicate resend decisions. The remaining proof gap is provider-backed iOS APNs/TestFlight visibility, OS coalescing, tap route, and catch-up outside the repo-local harnesses.

## 3. Impact Analysis

- Affected users: group senders using text, image/media, or recorded voice; group recipients who receive the duplicate rows or notifications.
- Trigger moments: slow `group:sendReliable`, app close/reopen, app resume recovery, a failed text row, a failed voice upload, retyping after an ambiguous send state, re-recording after a voice failure, foreground/background notification delivery, and live plus inbox replay arrival.
- Severity: high for affected group sends because duplicates are visible to multiple recipients and make sender intent unclear.
- Frequency: not quantified, but repo evidence shows common retry, resume, pending, inbox, live pubsub, upload-pending, and notification fallback paths still intersect under unreliable-network conditions.
- Regression cost: the implemented image/media fixes must stay closed while the remaining text/voice paths are brought to the same "one intended send equals one visible message" standard.
- Evidence gap cost: without residual APNs proof, repo tests can validate payload, preview, and routing behavior but cannot prove production/TestFlight background or terminated iOS notification visibility and OS coalescing.

## 4. Current State

- Current closure evidence for the original image/media scope:
  - `Test-Flight-Improv/102-group-image-retry-duplicate-delivery-notifications-media-ux-session-breakdown.md:740` records the latest source classification as `residual-only with explicit APNs provider follow-up`, not the older blocked-at-command-49 state.
  - `Test-Flight-Improv/102-group-image-retry-duplicate-delivery-notifications-media-ux-session-breakdown.md:751` through `:757` classify reliable sender state, same-id replay repair, media retry ownership, recipient media dedupe, relay group inbox idempotency, recoverable media loading, and Android notification behavior as closed.
  - `Test-Flight-Improv/102-group-image-retry-duplicate-delivery-notifications-media-ux-session-breakdown.md:758` through `:759` leave only the provider-backed iOS APNs background/terminated proof as explicit residual follow-up.

- Reusable prior test and gate evidence:
  - `Test-Flight-Improv/102-group-image-retry-duplicate-delivery-notifications-media-ux-session-breakdown.md:154` through `:159` records accepted RED/GREEN evidence for `GIRD-001` through `GIRD-006`; those tests should be reused as preservation evidence when later residual work touches the same sender-state, media retry, recipient dedupe, relay, media-loading, or notification behavior.
  - `Test-Flight-Improv/102-group-image-retry-duplicate-delivery-notifications-media-ux-session-breakdown.md:117` records final host coverage: broad feature host coverage, the named groups gate, and completeness classification all passed during `GIRD-007`.
  - `Test-Flight-Improv/102-group-image-retry-duplicate-delivery-notifications-media-ux-session-breakdown.md:119` through `:120` records the full group reliability simulator scope passing after environment/harness blockers were classified and fixed.
  - `Test-Flight-Improv/102-group-image-retry-duplicate-delivery-notifications-media-ux-session-breakdown.md:745` through `:747` records that no group reliability blocker remains; the remaining device-context item is only the provider-backed APNs proof.
  - Existing tests with reusable value include reliable in-doubt sender tests (`test/features/groups/application/send_group_message_use_case_test.dart:5872`), same-id failed-row replay repair (`test/features/groups/application/handle_incoming_group_message_use_case_test.dart:659`), restored image composer retry and upload-pending media feedback (`test/features/groups/presentation/group_conversation_wired_test.dart:6157`, `:6269`, `:6343`), recipient reminted-image dedupe (`test/features/groups/application/handle_incoming_group_message_use_case_test.dart:2282`; `test/features/groups/application/group_message_listener_test.dart:10940`), recoverable media-loading UI (`test/features/groups/presentation/group_conversation_wired_test.dart:3109`, `:3277`), and group notification fallback/open routing tests (`test/features/push/application/background_message_handler_test.dart:228`, `:322`; `test/features/push/application/chat_and_group_push_open_flow_test.dart:104`).

- June 2026 accepted text/voice extension state:
  - Failed text retry UI and same-id application retry are covered by `test/features/groups/presentation/group_conversation_screen_test.dart`, `test/features/groups/presentation/group_conversation_wired_test.dart`, and `test/features/groups/application/retry_failed_group_messages_use_case_test.dart`.
  - Restored text continuation id/timestamp reuse is covered by `group_conversation_wired_test.dart`, `send_group_message_use_case_test.dart`, `retry_failed_group_messages_use_case_test.dart`, and `integration_test/group_recovery_e2e_test.dart`.
  - Recorded voice uploaded-audio retry, upload-pending retry, durable-prep cleanup, and re-record continuation are covered by `retry_failed_group_messages_use_case_test.dart`, `retry_incomplete_group_uploads_use_case_test.dart`, `group_conversation_wired_test.dart`, `group_conversation_wired_bg_task_test.dart`, and `integration_test/group_recovery_e2e_test.dart`.
  - Timeout/pending retry-payload recovery is covered by `bridge_group_helpers_test.dart`, `send_group_message_use_case_test.dart`, DB helper/lifecycle suites, the `transport` named gate, and `integration_test/group_recovery_e2e_test.dart`.
  - Local outgoing status visibility is covered by `group_message_repository_impl_test.dart`, `group_conversation_wired_test.dart`, and `integration_test/group_recovery_e2e_test.dart`.
  - `last_send_attempt_at` stuck-sending recovery is covered by migration `073`, DB helper, repository, send/retry/recover use-case, lifecycle, and full migration-chain tests.
  - Live/replay/drain one-materialization and one-notification behavior is covered by `group_message_listener_test.dart`, `handle_incoming_group_message_use_case_test.dart`, `drain_group_offline_inbox_use_case_test.dart`, `group_notification_dedupe_integration_test.dart`, and `foreground_group_push_drain_test.dart`.

- Current residuals:
  - Real background/terminated provider APNs delivery, OS coalescing, tap route, and catch-up remain residual-only until provider/device evidence exists.
  - The broad `groups` gate has a carried non-owned residual in `test/features/groups/integration/invite_round_trip_test.dart`, `GCA-004 bridgeError recovery drains inbox after settled materialized invite`, assertion at `invite_round_trip_test.dart:2930`, `Expected: not null`, `Actual: <null>`.
  - `group-real-network-nightly` remains fixture-backed release/nightly evidence and is not an implementation-scope blocker when relay/device fixtures are not configured.

## 5. Scope Clarification

- In scope:
  - One user-intended group text send remains one visible recipient message across timeout, failed-row retry, retype-after-error, app close/reopen, and resume recovery.
  - One user-intended recorded voice send remains one visible recipient voice note across upload failure, retry, app resume, and re-record-after-error behavior.
  - Sender-visible status for in-doubt, failed, retried, and locally recovered rows remains truthful enough that the UI does not invite avoidable duplicate sends.
  - Recipient-visible rows and notifications stay single-path for one logical group send, including live pubsub plus inbox replay arrival.
  - Every remaining bug-regression case is reproduced red-first in the lowest credible evidence layer before it is treated as fixed; cross-layer failures must include integration or simulator evidence when unit/widget coverage cannot observe the user-visible failure.
  - Existing `GIRD-001` through `GIRD-007` tests and gate evidence are reused as preservation coverage instead of recreated, while new red-first tests are added only for uncovered residual behavior such as text retype duplicates and recorded-voice re-record/upload-pending recovery.
  - Already-implemented image/media retry, recoverable media loading, relay idempotency, Android notification behavior, and group reliability simulator evidence stay closed.
  - iOS repo-level payload, preview/fallback, and notification-open behavior stay covered, while real provider-backed background/terminated APNs proof remains explicit residual acceptance evidence.

- Non-goals:
  - No broad redesign of group chat, media transfer, push notification UX, relay storage, native pubsub, or the message composer.
  - No requirement to collapse genuinely separate successful sends when a user intentionally sends the same text, image, or voice content more than once.
  - No claim that every duplicate symptom is caused by one code path.
  - No product requirement to hide terminal unsafe media or unverifiable content behind an endless loading state.
  - No provider/APNs production infrastructure decision in this spec.

- Accepted ambiguities for later implementation:
  - The exact user-facing copy for failed, pending, retrying, and recovered text/voice rows remains open as long as the observable state does not encourage duplicate sends.
  - The boundary between a user's intentional second send and a continuation of the first ambiguous send remains open as long as tests cover the incident-shaped ambiguity.
  - The exact stale-pending threshold and local status propagation mechanism remain open.
  - The exact concurrency shape for live-plus-replay delivery remains open, but acceptance must prove the user-visible result.
  - The iOS APNs residual can stay classified separately from repo-local notification behavior until a provider-backed evidence path exists.

## 6. Test Cases

Happy path:

- Given User A sends one text message to a group on a healthy connection, then User A sees one sent row and every eligible recipient sees one received row.
- Given User A records and sends one voice note to a group on a healthy connection, then User A sees one sent voice row and every eligible recipient sees one playable voice row.
- Given User A sends one image/media message to a group, then the already-implemented image/media behavior continues to show one logical recipient row, recoverable loading states, and no duplicate notification path.
- Given a recipient receives a group message while backgrounded, then one eligible notification opens the correct group/message context when tapped.
- Given a recipient is already viewing the group, then an incoming group message does not create an unnecessary foreground notification.

Edge cases:

- Given a group text send enters an in-doubt state because Flutter timed out while native delivery may still finish, then the sender does not need to retype to recover and recipients still end with one visible message for the original user intent.
- Given a failed text-only outgoing group row is visible, then the sender has a clear in-place recovery path from that row and the retry preserves one logical recipient-visible message.
- Given User A retypes a failed or pending group text message before the original finally arrives, then recipients do not end with two visible copies for the same user-intended message.
- Given User A closes and reopens the app after an ambiguous text send, then resume recovery does not create or invite a duplicate recipient row.
- Given a voice upload fails after the app has persisted an `upload_pending` voice attachment, then the visible row remains recoverable and retry behavior does not force the sender to re-record.
- Given User A re-records after a failed or ambiguous voice send and the original later arrives, then recipients do not end with two user-visible voice notes for one intended send.
- Given a retried group row keeps an old original timestamp while a retry is currently in flight, then stuck-send recovery does not flip it into a misleading failed state that causes another duplicate retry.
- Given an in-doubt pending row lacks inbox retry data and no same-id replay arrives, then it does not stay forever in an ambiguous state that leaves the sender unsure whether to resend.
- Given the same group message arrives through live pubsub and inbox replay close together, then the recipient timeline emits one row and the notification surface shows at most one eligible notification.
- Given a data-only background group notification fallback cannot be visibly displayed, then later in-app replay is not suppressed as if the user had already seen a notification.
- Given an iOS recipient receives background or terminated group push for same-id and re-minted group image cases through a real provider path, then visible notification, preview/fallback, OS coalescing, tap route, and catch-up are observable.

Regressions to preserve:

- Bug regression: the original image incident remains closed: one image send with transient error, retry, close/reopen, and continuation results in one visible image row per recipient, not three.
- Bug regression: a text send that times out or becomes pending must not become two recipient rows after the sender retypes.
- Bug regression: a failed text-only group row must not render as a dead end that pushes the sender toward a duplicate manual resend.
- Bug regression: a failed upload-pending voice row must not leave the sender with re-recording as the only apparent recovery path.
- Bug regression: live pubsub plus inbox replay must not create duplicate recipient notifications for the same logical group message.
- Bug regression: a notification suppression gate must not record a visible notification when no visible notification was actually shown.
- Preservation/regression: same-message-id incoming replays still dedupe.
- Preservation/regression: distinct intentional sends with distinct user intent still remain visible as separate messages.
- Preservation/regression: terminal unsafe or unverifiable media still renders as unavailable instead of pretending to load.
- Preservation/regression: active-group and muted-group notification suppression remain observable.
- Preservation/regression: notification tap routing for group messages remains observable.
- Preservation/regression: accepted image/media, relay inbox, Android notification, and group reliability evidence remains valid after the text/voice residual work.

Required acceptance evidence layers:

- Red-first TDD evidence:
  - Before any remaining text, voice, timeout, local-status, live/replay, notification, or APNs residual is accepted as fixed, the failing behavior must be reproduced first as an observable bug-regression test or simulator/provider scenario.
  - The first failing evidence must match the user-visible problem, not only an internal helper condition: duplicate recipient rows, missing retry affordance, misleading recovery state, stale visible status, duplicate notification, suppressed visible notification, or missing APNs/tap/catch-up behavior.
  - The fix is accepted only when the same red-first scenario passes, adjacent preservation/regression cases still pass, and the final evidence records which layer reproduced the failure.
  - Prior `GIRD` RED/GREEN tests count as reusable preservation when they match the already-fixed image/media behavior; they do not replace red-first reproduction for a newly scoped text or voice failure unless they already fail on the exact same user-visible behavior.

- Unit evidence:
  - Deterministic classification of text and voice send states from the user's point of view: sent, pending/in-doubt, failed, retrying, recovered, and terminal.
  - Deterministic duplicate handling for same-id replay, retyped text, re-recorded voice, intentional separate sends, and live-plus-replay arrival.
  - Deterministic notification display/suppression boundaries for active group, muted group, recent remote announcement, fallback display failure, and duplicate logical sends.

- Integration evidence:
  - Sender journey spanning text send, ambiguous timeout, failed-row recovery, retype-after-error, app resume, and recipient catch-up.
  - Sender journey spanning voice record, upload-pending failure, retry/recovery, re-record-after-error, app resume, and recipient catch-up.
  - Recipient journey spanning live group delivery, group inbox replay, local notification decision, and notification tap route.
  - Preservation journey proving the closed image/media behavior remains closed.

- Simulator evidence:
  - Multi-user group text and voice scenarios under transient send failure, app close/reopen, and resume recovery, with recipients validating exactly one visible logical message.
  - Foreground/background notification scenarios for one logical group send, including active-group suppression and notification-open routing.
  - Lifecycle coverage where sender recovery and recipient catch-up run after backgrounding or app restart.

- Residual provider-backed iOS APNs evidence:
  - Background and terminated iOS APNs group image notifications for same-id and re-minted-id cases, proving visible notification behavior, NSE preview/fallback, OS coalescing, tap routing, and catch-up.

Reusable existing coverage and remaining gaps:

- Reusable host evidence already proves text-only retry in the application use case, image/media retry ownership, same-id replay repair, recipient media dedupe, relay inbox idempotency, recoverable media loading, Android notification behavior, foreground group push drain, and full group reliability simulator closure.
- Reusable gate evidence from the previous media work should be kept in the acceptance chain: focused `GIRD` host tests for the touched behavior, the named groups host gate, broad feature host coverage when shared group-adjacent code changes, completeness classification when test inventory changes, and group reliability simulator coverage for device-context/lifecycle risk.
- These prior tests should be replayed or extended as preservation evidence; they should not be treated as red-first proof for residual text/voice behavior unless the exact residual failure is already reproduced by one of them.
- Accepted evidence now covers failed text retry UI, unchanged restored text same-id continuation, failed upload-pending voice recovery, re-record continuation, local-only status visibility on an open group screen, stale pending retry-payload recovery, old-timestamp retry protection via `last_send_attempt_at`, and concurrent live-plus-replay one row / one notification behavior.
- Remaining residual evidence: provider-backed iOS APNs background/terminated proof remains residual-only.
- Remaining carried gate residual: broad `groups` may remain red only for the exact non-owned `GCA-004 bridgeError recovery drains inbox after settled materialized invite` failure at `invite_round_trip_test.dart:2930`; that is not doc-102 duplicate-delivery implementation scope.
