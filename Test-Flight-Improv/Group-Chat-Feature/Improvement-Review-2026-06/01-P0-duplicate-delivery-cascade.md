> Part of the **[Group Chat Improvement Review](./README.md)** · Priority **P0** · [Findings appendix](./appendix-findings.md)

---

# Kill the duplicate-delivery / stuck-send cascade (doc 102)

**Priority: P0** · Theme owner: group-chat reliability · Source: `Test-Flight-Improv/102-group-image-retry-duplicate-delivery-notifications-media-ux.md` (+ GIRD-001…007 session plans)

> **One-liner:** The June 2026 implementation sessions extend the doc-102 cascade fix from **images** to **plain-text** and **recorded-voice** paths, close the Dart/native timeout asymmetry with retained in-doubt handling, and preserve one logical delivery/notification path in repo-local evidence.

> **Scope correction (verified against code and accepted sessions 2026-06).** Doc 102 and its GIRD-001…007 sessions already fixed the *image* cascade. This theme originally scoped the remaining **text**, **recorded-voice**, timeout, local-status, stuck-sending, and live/replay notification gaps. Those gaps are now accepted in repo-local evidence; the only remaining strict-closure residual is provider-backed APNs/TestFlight background/terminated proof.

---

## What doc 102 / GIRD-001…007 already landed (verified in code)

Crediting the prior work so this theme stays scoped to the residue:

| Already fixed | Evidence |
|---|---|
| A bridge timeout / publish-without-custody no longer false-**fails** — the row is saved in-doubt `status:'pending'` and the send returns *success* | `send_group_message_use_case.dart:897-946` |
| The sender's own message arriving via replay/receipt reconciles the row to `sent`, **including rows already marked `failed`** | `handle_incoming_group_message_use_case.dart:894-988` (`reconciled.status='sent'`) |
| An open conversation **applies** status updates from the message stream (`_applyMessageUpdate`, for *every* group message, not incoming-only) and reloads on resume — so reconciled self-echoes refresh live | `group_conversation_wired.dart:1201-1218`, `:591` |
| Restored-composer id reuse (**media**), recipient media dedupe, relay-inbox idempotency, the "Media unavailable" flash, Android notification display-failure/coalescing | per doc 102 §7, GIRD-002…006 |

**Current closure status (2026-06-04).** The doc-102 media lineage is preserved, and the June improvement-review sessions close the text/voice extension in repo-local direct, simulator, and named-gate evidence. The broad `groups` gate now passes after the follow-up `GCA-004 bridgeError recovery drains inbox after settled materialized invite` fix. `group-real-network-nightly` also passes with `MKNOON_RELAY_ADDRESSES` unset because the gate now falls back to the same default relay addresses hardcoded in the app. Real provider-backed APNs/TestFlight background/terminated proof remains residual-only.

## Acceptance Closure (2026-06-04)

| Area | Accepted closure evidence | Remaining residual |
|------|---------------------------|--------------------|
| Failed text retry | `group_conversation_screen_test.dart`, `group_conversation_wired_test.dart`, and `retry_failed_group_messages_use_case_test.dart` were rerun and passed, proving failed outgoing text-only group rows expose in-place retry and reach same-id retry plumbing. | None in repo-local scope. |
| Restored text continuation | `group_conversation_wired_test.dart`, `send_group_message_use_case_test.dart`, `retry_failed_group_messages_use_case_test.dart`, and `integration_test/group_recovery_e2e_test.dart` command `#8` were rerun and passed, proving unchanged restored text reuses the failed row id/timestamp while edited text remains a new send. | None in repo-local scope. |
| Recorded voice recovery | `retry_failed_group_messages_use_case_test.dart`, `retry_incomplete_group_uploads_use_case_test.dart`, `group_conversation_wired_test.dart`, `group_conversation_wired_bg_task_test.dart`, and `integration_test/group_recovery_e2e_test.dart` command `#8` were rerun and passed, proving uploaded-audio same-id retry, upload-pending retry, durable-prep cleanup, and re-record continuation. | None in repo-local scope. |
| Timeout / in-doubt pending | `bridge_group_helpers_test.dart`, `send_group_message_use_case_test.dart`, DB helper/lifecycle tests, the `transport` named gate, and `integration_test/group_recovery_e2e_test.dart` command `#8` were rerun and passed, proving the 40-second Dart bridge timeout and retained pending retry-payload recovery. | Native early-custody signaling remains out of scope. |
| Local status visibility | `group_message_repository_impl_test.dart`, `group_conversation_wired_test.dart`, and `integration_test/group_recovery_e2e_test.dart` command `#8` were rerun and passed, proving local outgoing status changes reach the open group screen. | None in repo-local scope. |
| Stuck-sending recovery | Migration, DB helper, repository, send/retry/recover use-case, lifecycle, and full migration-chain tests were rerun and passed, proving `last_send_attempt_at` persistence and stuck-sending recovery. | None in repo-local scope. |
| Live/replay notification dedup | `group_message_listener_test.dart`, `handle_incoming_group_message_use_case_test.dart`, `drain_group_offline_inbox_use_case_test.dart`, `group_notification_dedupe_integration_test.dart`, and `foreground_group_push_drain_test.dart` command `#2` were rerun and passed, proving raced live/replay handling emits one row and one notification path. | Real APNs/TestFlight background/terminated proof remains residual-only. |

## Follow-up Sweep (2026-06-04)

- `GCA-004 bridgeError recovery drains inbox after settled materialized invite` is now closed in repo-local evidence. Inline materialized invite acceptance preserves recovery state on bridge/inbox error, while welcome-package retries still roll back to preserve retryability.
- Focused GCA coverage passed: `accept_pending_group_invite_use_case_test.dart --plain-name "GCA-004 join bridgeError with inline invite preserves recovery state"`, `accept_pending_group_invite_use_case_test.dart --plain-name "GCA-004 join bridgeError with inbox failure keeps welcome package retryable"`, and `invite_round_trip_test.dart --plain-name "GCA-004 bridgeError recovery drains inbox after settled materialized invite"`.
- `./scripts/run_test_gates.sh groups` passed after the GCA fix.
- `./scripts/run_test_gates.sh group-real-network-nightly` passed on simulator `5A9A8286-001B-4BF1-8F40-5A3AB8BF8FE3` with `MKNOON_RELAY_ADDRESSES` unset and the app default relay CSV injected by the gate.
- Fixture-backed real-network group recovery passed with the app default relays via `dart run integration_test/scripts/run_group_recovery_e2e.dart -d 5A9A8286-001B-4BF1-8F40-5A3AB8BF8FE3`; the E2E harness schema was brought forward to migration `073`.
- Push release configuration passed `./scripts/check_push_release_gate.sh`. After locating the workspace service-account JSON, the strict credential form also passed via `FIREBASE_SERVICE_ACCOUNT=<workspace service-account JSON> ./scripts/check_push_release_gate.sh --require-service-account`. Provider-backed APNs/TestFlight background/terminated delivery remains the only external proof needed for a strict closed verdict.
- Physical-device provider/APNs foreground proof passed on the physical iPhone named `iPhone`: native logs show notification authorization enabled, APNs token registration, FCM token minting, relay push-token registration, Firebase FCM v1 send success, and native `willPresent` receipt for probe `iphone13-foreground-20260604T113032`. Background attempts are not accepted as closure proof yet because their native receipt context was still `willPresent`, meaning the app was foreground at delivery time.
- Physical-device provider/APNs locked-screen proof passed on the same iPhone: Firebase accepted probe `iphone13-locked2-20260604T113904` as `projects/mknoon-c6e62/messages/1780565944971027`, the user observed the lock-screen notification and tapped it, and device process evidence immediately after the tap showed both the Notification Service Extension and `Runner.app` running. Direct IPA installation is still not a TestFlight substitute: `devicectl` rejects the beta IPA with `Attempted to install a Beta profile without the proper entitlement`; TestFlight itself is installed and was launched for manual app install/update.

---

## Why this matters (user experience)

The original cascade made group senders unsure whether retrying would recover one intended message or create duplicates. The accepted implementation now makes the safe path visible and id-stable for text and recorded voice, keeps ambiguous timeout states recoverable, and preserves one recipient materialization plus one notification path when live delivery and replay/drain overlap.

The remaining evidence limit is deliberately narrower than the original bug: repo-local APNs payload, preview, fallback, foreground-drain, and notification-open behavior is covered, but real provider-backed iOS background/terminated proof still requires provider/device evidence.

---

## Accepted behaviour & evidence

| Area | Accepted behaviour | Rerun evidence |
|------|-------------------|----------------|
| Failed text retry (UI) | Failed outgoing text-only group rows expose in-place retry and route to existing same-id retry plumbing instead of requiring a manual retype. | `flutter test test/features/groups/presentation/group_conversation_screen_test.dart`; `flutter test test/features/groups/presentation/group_conversation_wired_test.dart`; `flutter test test/features/groups/application/retry_failed_group_messages_use_case_test.dart` |
| Restored text resend | Unchanged restored text reuses the failed row id/timestamp; edited text is treated as a new intentional send. | `group_conversation_wired_test.dart`; `send_group_message_use_case_test.dart`; `retry_failed_group_messages_use_case_test.dart`; reliability-sim `group_recovery_e2e_test.dart` command `#8` |
| Recorded voice retry/re-record | Uploaded audio retries under the same message id, upload-pending voice can be re-driven, durable-prep failures do not leave empty retry-less rows, and re-record continuation stays tied to the failed logical send. | `retry_failed_group_messages_use_case_test.dart`; `retry_incomplete_group_uploads_use_case_test.dart`; `group_conversation_wired_test.dart`; `group_conversation_wired_bg_task_test.dart`; reliability-sim `group_recovery_e2e_test.dart` command `#8` |
| Timeout / pending recovery | Dart waits long enough for native reliable-send work, while retained in-doubt pending handling persists retry payloads for recovery. | `bridge_group_helpers_test.dart`; `send_group_message_use_case_test.dart`; DB helper/lifecycle suites; named `transport` gate |
| Local status visibility | Local outgoing status changes are broadcast to the open group screen so recovery does not invite duplicate resends. | `group_message_repository_impl_test.dart`; `group_conversation_wired_test.dart`; reliability-sim `group_recovery_e2e_test.dart` command `#8` |
| Stuck-sending timestamp | `last_send_attempt_at` distinguishes old message creation time from a fresh retry attempt and prevents in-flight retries from being flipped back to failed by resume recovery. | migration `073`, DB helper, repository, send/retry/recover use-case, lifecycle, and full migration-chain suites |
| Live/replay dedup | Live pubsub, inbox replay, and drain converge on one row and one eligible notification path for the same logical group message. | `group_message_listener_test.dart`; `handle_incoming_group_message_use_case_test.dart`; `drain_group_offline_inbox_use_case_test.dart`; `group_notification_dedupe_integration_test.dart`; reliability-sim `foreground_group_push_drain_test.dart` command `#2` |

---

## Root cause(s) addressed by accepted sessions

The following root-cause list is retained as historical implementation context. The accepted evidence above is the current closure source of truth.

1. **No id-stable, in-place text recovery in the group UI.** The id-reuse retry plumbing exists and even supports text, but in the group UI it is reachable only through the media path, so the user's only text recovery is retyping — the duplicate generator. (doc 102 fixed this for media via restored-composer id reuse; text was out of scope.)
1b. **Voice rides a separate, restore-less path.** `_onRecordStop()` is independent of `_onSend`/`_restoreComposerSnapshot`, so the doc-102 id-reuse fix never applies; a stalled voice upload can't be re-driven manually, and a re-record produces fresh id + different bytes that defeat *every* dedup. Voice is the only content type whose duplicate can never be collapsed after the fact.
2. **Local sweep status changes are not broadcast.** Reconciled self-echoes *do* refresh the open screen (GIRD-002), but purely local sweep-driven flips (`recoverStuck`, `retryFailed*`) write the DB with no stream emit, so they can lag on an open screen until the next reconcile/reload.
3. **The root timeout asymmetry was deferred, not fixed.** doc 102 §5 explicitly declined to change the timeout *value*; it mitigated the symptom (don't false-fail; reconcile later). Flutter still abandons at 10s vs native ≈30s, so sends still enter in-doubt limbo, and the ones that never get a same-id reconciliation (text retype) are not repaired.
4. **Recovery sweeps key off the wrong timestamp and don't cover every state.** They use the message *creation* time (not a status-change time), and certain `pending` rows (null retry payload, no self-echo) fall through every sweep.
5. **Receive-side dedup isn't atomic across entry points.** Replay/drain bypasses the live serialization, so the same id can transiently double-emit / double-notify.

---

## Proposed improvements (implemented or residualized)

This section is retained as the original implementation checklist. Items 1, 2, 2b, 3, 4, 5, 6, and 7 have been accepted in repo-local evidence by the June 2026 sessions unless explicitly residualized above.

Ordered roughly by impact-per-effort. Items 1–3 break the cascade for the common case; 4–7 close the remaining holes.

### 1. Wire an id-stable in-place retry (and delete) for failed text-only group messages — **small**

- Add fields to `GroupConversationScreen`: `final ValueChanged<String>? onRetryFailedMessage;` (mirror of `conversation_screen.dart`).
- In `_buildMessageList`, compute alongside `showFailedMediaActions`:
  ```dart
  final showFailedTextRetry =
      canWrite &&
      isSent &&
      message.status == 'failed' &&
      messageMedia.isEmpty &&
      message.text.trim().isNotEmpty &&
      onRetryFailedMessage != null;
  ```
- Pass into `LetterCard`:
  ```dart
  onRetryFailedMessage: showFailedTextRetry
      ? () => onRetryFailedMessage!(message.id)
      : null,
  failedMessageActionKeySuffix: message.id,
  ```
  (`LetterCard` already renders this — `letter_card.dart:294-314` — no widget change needed.)
- In `group_conversation_wired.dart`, add `_onRetryFailedMessage(String messageId)` that calls the **existing** `retryFailedGroupMessage(messageId: …)` (reuses original id + timestamp, supports text-only via `_isTextOnlyRetryPayload`), then `_refreshMessageWithHydratedMedia(messageId)` and a snackbar on `retried == 0`. Pass `onRetryFailedMessage: _onRetryFailedMessage` when constructing the screen.
- **No wire/DB/migration impact.** This is the single highest-leverage change: it removes the *incentive* to retype.

### 2. Make restored-composer text resend id-stable — **medium**

Two complementary changes (do both; they reinforce):

- **Track a continuation for text-only failed sends too.** In `_restoreComposerSnapshot` (`group_conversation_wired.dart:2158-2166`), always record `draftText` / `quotedMessageId` / `timestamp` / `messageId` for the failed row — not only when `pendingAttachments.isNotEmpty`. Generalize `_trackRestoredMediaContinuation` (currently the sole writer of `_restoredMediaContinuation`) so the `else` branch records a text continuation instead of clearing it. Then `_onSend`'s existing `restoredContinuation?.messageId ?? _uuid.v4()` / `restoredContinuation?.timestamp ?? …` (line 1590-1591) reuses the original id+timestamp automatically.
- **Belt-and-suspenders:** with item 1 shipped, prefer steering users to the in-place retry over re-enabling free-text resend, so retyping is rarely on the happy path.
- **No wire/DB/migration impact.**

### 2b. Cover the recorded-voice path explicitly — **medium**

Voice can't be "retyped," and a re-record is permanently undedup-able, so it needs a first-class id-stable recovery on its own `_onRecordStop()` path:

- **Lock the common case.** When the audio is uploaded (`downloadStatus == 'done'`) but the publish failed/went in-doubt, the existing media retry button already resends under the same `messageId` via `retryFailedGroupMessage`. Add an explicit voice regression test so this can't silently break.
- **Make "retry" actually re-drive a stalled upload.** When the attachment is `upload_pending`, `_onRetryFailedMedia` currently no-ops with a snackbar (`group_conversation_wired.dart:2038-2070`). Instead, trigger an immediate per-message `retryIncompleteGroupUploads`-style re-upload for that `messageId`, then resend under the same id — so the user isn't forced to re-record.
- **Never silently drop a recording.** On a pre-send durable-prep error (`:3064-3077`) that persists no attachment, either keep the temp file and surface a retry affordance, or remove the empty `failed` row entirely (it has no text and no media, so it shows *neither* retry control and just invites a re-record).
- **If a re-record is genuinely needed, reuse the failed/in-doubt row's id** for that composer session, so a late delivery of the original voice note doesn't materialize as a second bubble on recipients.
- **No wire/DB/migration impact** (reuses the existing media-retry + upload-retry plumbing).

### 3. Align the reliable-send timeout to the native budget — **small**

- Raise `callGroupSendReliable`'s default `timeout` (`bridge_group_helpers.dart:410`) from `10s` to ~**35–40s**, comfortably above the native ≈30s worst case (`PubSubTimeout=30s`, `InboxTimeout=15s` run concurrently — `config.go:33,45`; `pubsub.go` `wg.Wait`). Most slow-but-successful sends then resolve to a real `sent` instead of in-doubt `pending`.
- Keep the in-doubt handling for genuinely slow cases.
- **Optional, larger:** have native emit an early `accepted-custody` signal (inbox stored OR ≥1 topic peer) so Flutter can flip to `sent` before the full pubsub window elapses. This is the cleanest long-term fix but is a native + bridge-contract change; defer behind the timeout bump.
- **No DB/migration impact.** Native change only if the optional custody signal is pursued.

### 4. Broadcast local sweep status flips to the open conversation — **medium**

The open screen already applies status updates that arrive on `groupMessageStream` (incl. reconciled self-echoes — GIRD-002). The residual gap is purely **local** status changes from background sweeps, which write the DB without emitting. Close just that gap:

- Add a lightweight outgoing-status notifier. Preferred: a `Stream<({String messageId, String status})>` exposed by `GroupMessageRepositoryImpl`, emitted from `updateMessageStatus` and `saveMessage` for **outgoing** rows (`group_message_repository_impl.dart:294-297`). `group_conversation_wired` subscribes and calls `_upsertMessage` / `_updateLocalMessageStatus` for the affected id (reusing the existing `_applyMessageUpdate` path).
- **Minimal alternative** (smaller blast radius): after each `PendingMessageRetrier` sweep that changes >0 group rows, emit a single "group rows changed" event the active screen listens to → scoped `_loadMessages()`.
- **No wire/migration impact**; introduces an in-process event stream only.

### 5. Reclaim orphaned in-doubt `pending` rows — **medium**

Scope is narrow but real: a `pending` row with **null `inbox_retry_payload`** (replay-envelope build threw) **and no self-echo**. Today no sweep touches it.

- **Always persist a retry payload for in-doubt rows.** Before giving up in the catch at `send_group_message_use_case.dart:808-817`, fall back to the locally built `inboxPayload` so `inboxRetryPayload` is non-null. This alone lets the existing inbox-store sweep (`dbLoadGroupMessagesWithFailedInboxStore` already includes `status='pending'` — `group_messages_db_helpers.dart:730-731`) pick it up. **This is the cheapest fix and likely sufficient.**
- **Backstop:** add a sweep that transitions long-stale in-doubt `pending` rows (no retry payload, older than N minutes, no echo) → `failed`, so they surface the **new retry button from item 1**. A row that still has a `wireEnvelope` may instead be re-driven via `sendGroupMessage` with the same id.
- **No migration** for the payload-fallback path. The optional stale-pending → failed sweep is logic-only (no schema change).

### 6. Use a status-change timestamp for the stuck-sending sweep — **medium**

- The genuine race: an already-in-flight retrier pass (awaiting the bridge in `retryFailedGroupMessages`) overlapping resume step-3d `recoverStuck` (30s). Because a retry pre-persists `sending` with the **original (old) timestamp**, the sweep flips it back to `failed` mid-flight, the next pass re-sends, and a delivered message can duplicate.
- **Fix:** add a `status_updated_at` (or `last_send_attempt_at`) column to `group_messages`, written whenever `status → 'sending'`. Change `dbTransitionGroupSendingToFailed` (`group_messages_db_helpers.dart:742-756`) to compare against **that** column, not the message `timestamp`.
- **Note:** mirroring the upload path's `_isFreshOutgoingGroupSend` guard would **not** help — that guard also keys off `message.timestamp`, which is already old for a retried row. The dedicated status-change column is the correct mechanism.
- **DB/migration impact:** one nullable column + a migration in `lib/core/database/migrations/` (next version after current v5). Backfill is unnecessary (NULL → treat as eligible / fall back to `timestamp`).

### 7. Make receive-side dedup atomic across live and replay/drain — **medium** (lower priority)

- Route `handleReplayEnvelope` / drain through the **same serialization** as the live path. Either funnel replay through the live `asyncMap` queue, or have `_handleMessage` acquire a **per-`groupId` (or per-`messageId`) lock** (the codebase already has an `_enqueueGroupConfigWork`-style per-group lock to reuse).
- Alternatively make emit + notify idempotent: detect that `dbInsertGroupMessage` hit the UNIQUE conflict-merge branch (`group_messages_db_helpers.dart:31-38`) and skip `_emitGroupMessage` + the local-notification block in that case.
- Practical impact is bounded (the conversation UI already dedups bubbles by id — `group_conversation_wired.dart:2672-2681`); the durable artifact at risk is a **duplicate local notification** in a tight window. Schedule after items 1–6.
- **No wire/DB/migration impact.**

---

## Affected files & components

**UI / wiring**
- `lib/features/groups/presentation/screens/group_conversation_screen.dart` — new `onRetryFailedMessage` field + `showFailedTextRetry` (items 1)
- `lib/features/groups/presentation/screens/group_conversation_wired.dart` — `_onRetryFailedMessage`, text continuation tracking, status-stream subscription (items 1, 2, 4); `_onRetryFailedMedia` upload-pending re-drive + `_onRecordStop` recording-loss handling (item 2b)
- `lib/features/conversation/presentation/widgets/letter_card.dart` — read-only reference; already supports the callback (item 1)

**Application / use cases**
- `lib/features/groups/application/retry_failed_group_messages_use_case.dart` — already supports text-only; new call site only (item 1)
- `lib/features/groups/application/retry_incomplete_group_uploads_use_case.dart` — per-message re-upload trigger for the voice upload-pending retry (item 2b)
- `lib/features/groups/application/send_group_message_use_case.dart` — retry-payload fallback, status-change timestamp on pre-persist (items 5, 6)
- `lib/features/groups/application/recover_stuck_sending_group_messages_use_case.dart` — compare against status-change time (item 6)
- `lib/core/services/pending_message_retrier.dart` — optional "rows changed" event; new stale-pending sweep hook (items 4, 5)

**Domain / data**
- `lib/features/groups/domain/repositories/group_message_repository_impl.dart` — outgoing-status notifier stream (item 4)
- `lib/core/database/helpers/group_messages_db_helpers.dart` — sweep predicates + new column queries (items 5, 6)
- `lib/core/database/migrations/` — new migration for `status_updated_at` (item 6)

**Bridge / native**
- `lib/core/bridge/bridge_group_helpers.dart` — raise reliable-send timeout (item 3)
- `go-mknoon/node/config.go`, `go-mknoon/node/pubsub.go` — only if the optional early-custody signal is pursued (item 3)

**Receive path (lower priority)**
- `lib/features/groups/application/group_message_listener.dart`, `lib/features/groups/application/drain_group_offline_inbox_use_case.dart`, `lib/features/groups/application/handle_incoming_group_message_use_case.dart` (item 7)

---

## Test & verification strategy (accepted evidence recorded)

The strategy below was the implementation target; the acceptance closure table above records the current rerun evidence and remaining residuals.

**Unit tests**
- *Retry id-stability* (items 1, 2): retrying / resending a failed text row calls `sendGroupMessage` with the **original** `messageId` + `timestamp`; assert `_canReuseOutgoingMessageId` returns true and no new uuid is minted.
- *Voice id-stability* (item 2b): a failed voice row with a `done` audio attachment retries via `retryFailedGroupMessage` under the **same** `messageId`; an `upload_pending` voice row's retry triggers a per-message re-upload (not a snackbar no-op) and then resends under the same id; a durable-prep failure leaves no empty/retry-less `failed` row.
- *Status notifier* (item 4): `updateMessageStatus`/`saveMessage` on an outgoing row emits one `(messageId, status)` event; incoming rows emit nothing.
- *Retry-payload fallback* (item 5): when `buildGroupOfflineReplayEnvelope` throws, the in-doubt `pending` row still has a non-null `inbox_retry_payload`; assert `dbLoadGroupMessagesWithFailedInboxStore` returns it.
- *Stuck-sweep timestamp* (item 6): a row pre-persisted `sending` with an old `timestamp` but a **fresh `status_updated_at`** is **not** transitioned to `failed`; one with a stale `status_updated_at` is.
- *Timeout* (item 3): `callGroupSendReliable` no longer returns `BRIDGE_TIMEOUT` before ~35s (fake bridge resolving at 25s yields `sent`).
- *Dedup atomicity* (item 7): drive two concurrent `_handleMessage` calls for one id through `FakeGroupPubSubNetwork`; assert a single `_emitGroupMessage` and a single notification.

**Widget tests**
- `group_conversation_screen` renders a Retry control (`ValueKey('failed-message-retry-<id>')`) for a failed text-only outgoing row and **not** for incoming or non-failed rows; tapping invokes `onRetryFailedMessage(message.id)`.
- An open screen receiving a background `failed → sent` status event updates the rendered status icon without a full reload (item 4).

**Integration harnesses** (`integration_test/`)
- Extend `group_recovery_e2e_test.dart` / `group_recovery_cli_e2e_test.dart` with a **fail-then-retry-in-place** flow for **text and voice** and assert the recipient receives exactly **one** copy (the core duplicate guard). For voice, also cover the **re-record-after-failure** path: confirm a late delivery of the original does not produce a second voice note.
- Use `group_multi_party_device_real_harness.dart` + `scripts/run_group_multi_party_device_real.dart` to reproduce the timeout-induced in-doubt path on a slow link and confirm a single delivered copy after the timeout bump (item 3).
- Reuse the foreground push simulators (`foreground_group_push_drain_test.dart`, `foreground_group_push_simulator_*_harness.dart`) to validate the drain-vs-live dedup (item 7) — exactly one notification.

**Test-Flight-Improv matrices / device matrix**
- Update `Test-Flight-Improv/102-group-image-retry-duplicate-delivery-notifications-media-ux.md` and the GIRD session plans to cover the **text** cascade (currently image-centric).
- Add cases to `Test-Flight-Improv/52-notification-journey-test-matrix.md` for the single-notification guarantee, and to `Test-Flight-Improv/test-gate-definitions.md` for "no duplicate on retry."
- Two-device manual matrix (iPhone13 + Pixel6 per project memory): airplane-mode mid-send → reconnect → in-place retry → assert exactly one bubble + one notification on the peer; repeat with app-foreground status flip (item 4).

---

## Risks, trade-offs & rollout

| Item | Risk / trade-off | Mitigation |
|------|------------------|------------|
| 1 Retry UI | Low. Reuses proven plumbing. | Mirror 1:1 wiring 1:1; guard on `messageMedia.isEmpty` to avoid colliding with media actions. |
| 2 Text continuation | Restored draft might be edited before resend (text no longer matches the original send). | If text changed, treat as a *new* message (fresh id) — only reuse the id when text is unchanged, matching `_canReuseOutgoingMessageId` semantics. |
| 2b Voice | Re-using the id when audio bytes differ means the recipient keeps whichever copy arrived first. | That is the desired outcome — one logical voice note per intended send; surface a clear "resending" state so the user isn't surprised the original (not the re-record) is what landed. |
| 3 Timeout bump | A genuinely dead send now blocks the UI longer before showing failure. | Keep the pre-persist `sending` optimistic row so UI is responsive; only the *final* status resolution waits. Consider the optional early-custody signal later to shorten the happy path. |
| 4 Status stream | New subscription lifecycle; risk of leak / setState-after-dispose. | Cancel in `dispose`; guard `mounted`; scope events to the open `groupId`. |
| 5 Stale-pending sweep | Over-aggressively flipping `pending → failed` could surface false failures. | Conservative threshold (minutes) + require "no self-echo"; prefer the payload-fallback (no state change) as the primary fix. |
| 6 Schema migration | Forward-only column add; old rows have NULL `status_updated_at`. | Treat NULL as "fall back to `timestamp`" so behaviour is unchanged for legacy rows; idempotent migration, additive only. |
| 7 Receive serialization | Per-group lock could slow drain throughput. | Per-`messageId` guard (finer-grained) or idempotent-emit alternative to avoid global serialization. |

**Rollout order:** ship **1 → 2 → 2b → 3** first (they defuse the common-case cascade across text, voice, and media with no schema change and are independently testable), then **4 → 5**, then **6** (carries the only migration), and finally **7**. Each is independently revertable; none changes the on-wire envelope, so there is no cross-version compatibility concern except the local DB migration in item 6.

---

## Effort estimate

| # | Improvement | Effort | New wire/DB/migration |
|---|-------------|--------|------------------------|
| 1 | In-place retry/delete for failed text | **Small** | none |
| 2 | Id-stable restored-composer text resend | **Medium** | none |
| 2b | Cover the recorded-voice path (upload-pending re-drive, recording-loss, id-stable re-record) | **Medium** | none |
| 3 | Align reliable-send timeout (optional native custody signal) | **Small** (native option: Medium) | none (native contract if pursued) |
| 4 | Reflect background status flips on open screen | **Medium** | in-process event stream only |
| 5 | Reclaim orphaned in-doubt `pending` rows | **Medium** (payload-fallback alone: Small) | none |
| 6 | Status-change timestamp for stuck sweep | **Medium** | +1 nullable column + migration |
| 7 | Atomic live/replay dedup | **Medium** | none |

**Aggregate:** ~1 small + 1 small/medium quick win (items 1, 3) delivers the bulk of user-visible relief; full theme is **medium overall**, with a single additive DB migration (item 6) as the only schema change.
