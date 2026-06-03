> Part of the **[Group Chat Improvement Review](./README.md)** · Priority **P0** · [Findings appendix](./appendix-findings.md)

---

# Kill the duplicate-delivery / stuck-send cascade (doc 102)

**Priority: P0** · Theme owner: group-chat reliability · Source: `Test-Flight-Improv/102-group-image-retry-duplicate-delivery-notifications-media-ux.md` (+ GIRD-001…007 session plans)

> **One-liner:** Extend the doc-102 cascade fix — which landed for **images** — to the **plain-text** and **recorded-voice** paths, close the **root timeout asymmetry** that doc 102 deferred, and prove the end-to-end closure doc 102 left `blocked`.

> **⚠️ Scope correction (verified against code 2026-06).** Doc 102 and its GIRD-001…007 sessions already fixed the *image* cascade and several pieces landed in the live code (credited in the next section). This theme is **not** "the cascade is wide open" — it is the **residue those sessions did not cover**: the same cascade on the **text** path and the **recorded-voice** path (voice rides a separate `_onRecordStop()` flow the doc-102 restored-composer fix never touched, and a re-record produces *different bytes* that no dedup can collapse), the **timeout value** doc 102 explicitly declined to change, and doc 102's own `blocked with evidence` closure. Two earlier draft claims in this doc were over-stated and are corrected below: the open conversation screen *does* apply background status updates, and a bridge timeout no longer false-*fails* a row (it resolves to in-doubt `pending`).

---

## What doc 102 / GIRD-001…007 already landed (verified in code)

Crediting the prior work so this theme stays scoped to the residue:

| Already fixed | Evidence |
|---|---|
| A bridge timeout / publish-without-custody no longer false-**fails** — the row is saved in-doubt `status:'pending'` and the send returns *success* | `send_group_message_use_case.dart:897-946` |
| The sender's own message arriving via replay/receipt reconciles the row to `sent`, **including rows already marked `failed`** | `handle_incoming_group_message_use_case.dart:894-988` (`reconciled.status='sent'`) |
| An open conversation **applies** status updates from the message stream (`_applyMessageUpdate`, for *every* group message, not incoming-only) and reloads on resume — so reconciled self-echoes refresh live | `group_conversation_wired.dart:1201-1218`, `:591` |
| Restored-composer id reuse (**media**), recipient media dedupe, relay-inbox idempotency, the "Media unavailable" flash, Android notification display-failure/coalescing | per doc 102 §7, GIRD-002…006 |

**Not closed, per doc 102's own verdict (§7).** The three-user incident reproduction is `blocked with evidence` — reliability command #49 never ran because the *Dana* simulator stayed `relayState=recovering, circuitAddresses=0, connections=0` across three attempts (incl. reboot) — and the real-APNs iOS path is `residual-only` follow-up. So even the media fix lacks its final end-to-end gate.

---

## Why this matters (user experience)

The cascade is the single most visible reliability failure in group chat, and it is now **closed for images but still reachable for plain text**:

1. A text send shows a clock/error because Flutter gives up at **10s** while native is still finishing (≈15–30s).
2. The message often **did** deliver — flood-publish or relay-inbox custody completed after Flutter stopped waiting (the row is correctly held as in-doubt `pending`).
3. For **text** there is still **no in-place retry button** (1:1 has one; groups don't), so the user's only recovery is to **retype**.
4. A retyped text message mints a **fresh `messageId` + timestamp** (the id-reuse continuation only fires for media), so recipients can't dedupe it — and because it's a brand-new id, the doc-102 same-id reconciliation never repairs it.
5. Recipients receive **two copies** of one intended text message (and, in a narrow window, **two notifications**).

**Recorded voice is the worst variant.** Voice does not go through `_onSend`/`_restoreComposerSnapshot` at all — it rides a separate `_onRecordStop()` path that the doc-102 restored-composer id-reuse fix never touched. For the common case (audio uploaded, publish failed/in-doubt) a failed voice row *does* show the media retry button and resends id-stably, so it is partly covered. But:

- If the **upload itself** stalled (`upload_pending`), tapping retry **no-ops** with a snackbar (`_onRetryFailedMedia` returns early; `retryFailedGroupMessages` skips `upload_pending`) — only the background upload sweep can re-drive it.
- There is **no composer restore** for voice, so the user's instinct is to **re-record**, which mints a fresh `messageId` *and* fresh audio bytes. If the original later delivers, the recipient gets **two voice notes** — and because the bytes differ, **no content-hash dedup can ever collapse them**.

Because recipients dedupe purely on `messageId`, the durable cure is the same as doc 102's for media — **one stable id per intended send** plus a **safe in-place retry** — but applied to **text and voice**, with the root **timeout asymmetry** finally closed so fewer sends enter the in-doubt state at all. The fixes are small-to-medium and each independently weakens the cascade.

---

## Current behaviour & evidence

| Area | Current behaviour | Evidence (file:line) |
|------|-------------------|----------------------|
| Failed text retry (UI) | Group screen only computes `showFailedMediaActions` which **requires `messageMedia.isNotEmpty`**; only `onRetryFailedMedia` / `onDeleteFailedMedia` are wired into `LetterCard`. There is no `onRetryFailedMessage` field on the group screen at all. A failed *text* row renders only an error glyph with no control. | `group_conversation_screen.dart:543-547`, `:582-589`, fields at `:75-76`; `letter_card.dart:530` (error glyph), `:294-314` (supported but null); `grep onRetryFailedMessage lib/features/groups` → **none** |
| 1:1 has the pattern | The 1:1 screen *does* wire `onRetryFailedMessage` for failed text-only rows. Groups are the gap. | `conversation_screen.dart:470-476` (`showFailedTextRetry`), `:538-539` |
| Id-stable retry exists, but media-only | `retryFailedGroupMessage()` re-sends with the original id + timestamp and already supports text-only via `_isTextOnlyRetryPayload`. Its **only** group-wired call site is inside `_onRetryFailedMedia`. | `retry_failed_group_messages_use_case.dart:37-58`, `:94`; `group_conversation_wired.dart:2071` |
| Open screen: refreshes for stream events, **not** for local-only sweeps *(corrected)* | The stream handler applies updates for **every** message in the group via `_applyMessageUpdate` (not incoming-only), and resume triggers `_loadMessages()` — so reconciled self-echoes **do** refresh live (GIRD-002). **Residual:** purely **local** status changes from background sweeps (`recoverStuckSendingGroupMessages`, the `retryFailed*` use cases) write the DB with **no stream emit**, so they aren't reflected on an open screen until the next reconcile/reload. | `group_conversation_wired.dart:1201-1218` (`_applyMessageUpdate`), `:591` (resume reload); status write with no broadcast `group_message_repository_impl.dart:294-297`; sweep does a bare DB update `recover_stuck_sending_group_messages_use_case.dart` |
| Retype is not id-stable **(text)** | `_onSend` uses `messageId = restoredContinuation?.messageId ?? _uuid.v4()` and `now = restoredContinuation?.timestamp ?? DateTime.now()`. The continuation is only tracked for **media** (`snapshot.pendingAttachments.isNotEmpty`); text-only failed sends hit the `else` that **clears** tracking, so a retyped text message gets a fresh id and escapes both recipient dedupe and the doc-102 same-id reconcile. | `group_conversation_wired.dart:1590-1591`, `:2158-2166` |
| Voice is a separate path with **no composer restore** | Recorded voice goes through `_onRecordStop()` (not `_onSend`), which mints a fresh `messageId`/`attachmentId` (`_uuid.v4()`), copies the audio to durable storage, then calls `sendGroupMessage` with that id. On any **pre-send** failure (durable-prep error, upload returns null) it marks the row `failed` and **returns with no restore** — the doc-102 restored-composer id-reuse fix never applies here, so the user re-records → fresh id + different bytes → undedup-able duplicate. | `group_conversation_wired.dart:2982-2983` (fresh ids), `:3032-3063` (durable + persist), `:3138-3155` (send with id), `:3064-3077`,`:3113-3122` (fail → no restore) |
| Failed-voice retry no-ops while upload is pending | A failed voice row shows the **media** retry button (`messageMedia.isNotEmpty` is true for `mediaType:'audio'`), so the common case (upload done, send failed) retries id-stably. But `_onRetryFailedMedia` returns early with a snackbar when any attachment is still `upload_pending`, and `retryFailedGroupMessages` skips `upload_pending` media — so a manual retry **cannot** re-drive a stalled voice upload; only the background `retryIncompleteGroupUploads` sweep can. | `group_conversation_screen.dart:542-547` (media gate), `group_conversation_wired.dart:2038-2070` (upload-pending no-op), `retry_failed_group_messages_use_case.dart` (skips `upload_pending`) |
| Reuse predicate too strict | `_resolveOutgoingMessageId` can reuse an id only when text **and** timestamp match exactly (`_canReuseOutgoingMessageId`). A retype passes a fresh uuid + fresh `DateTime.now()`, so reuse never fires. | `send_group_message_use_case.dart:208-227`, `:230-279` |
| Orphaned in-doubt `pending` | On `reliableTimedOut`/`publishWithoutCustody` the row is saved `status:'pending'` with `inboxRetryPayload = retryPayload`, whose fallback is `prePersistMessage.inboxRetryPayload` — **null** when `buildGroupOfflineReplayEnvelope` threw earlier. No sweep reclaims such a row. | `send_group_message_use_case.dart:881-904`; null path at `:785-817`; sweeps: `dbLoadGroupMessagesWithFailedInboxStore` requires `inbox_retry_payload IS NOT NULL` `group_messages_db_helpers.dart:730-731`, stuck-sweep only `status='sending'` `:700`/`:748-754`, failed-load only `status='failed'` `:713` |
| Timeout budget mismatch — now in-doubt, **not** false-fail *(corrected)* | Flutter `callGroupSendReliable` still defaults to `Duration(seconds: 10)` → returns `BRIDGE_TIMEOUT`; native runs inbox (`InboxTimeout=15s`) and publish (`PubSubTimeout=30s`) **concurrently** (≈30s worst case). GIRD-001 made the 10s timeout resolve to in-doubt `pending` (not `failed`), so it self-heals **when a same-id self-echo/receipt later arrives**. **Residual:** the asymmetry itself remains, and any send that never gets a reconciliation — notably a text retype under a new id — escapes the repair. | `bridge_group_helpers.dart:410`, `:445-456`; `config.go:33`, `:45`; native `pubsub.go` wg.Wait; in-doubt handling `send_group_message_use_case.dart:897-946` |
| Stuck-sweep races in-flight retry | A retry pre-persists `status:'sending'` with the **original (old) timestamp**; `dbTransitionGroupSendingToFailed` flips `sending` rows whose **creation timestamp** is older than 30s. Resume step-3d `recoverStuck` (30s) can flip a retry that is still awaiting the bridge. | `recover_stuck_sending_group_messages_use_case.dart:5` (`kStuckSendingGroupThreshold=30s`); `group_messages_db_helpers.dart:742-756`; retry reuses ts `retry_failed_group_messages_use_case.dart:285` → `send_group_message_use_case.dart:621`,`:819-836`; resume sweep `handle_app_resumed.dart` (step 3d) |
| Live-vs-replay dedup race | `handleReplayEnvelope` calls `_handleMessage` directly, **bypassing** the `asyncMap` serialization that wraps only the live stream. Dedup is non-atomic `getMessage()`-then-`saveMessage()`. Two concurrent handlers for one id can both emit/notify. | `group_message_listener.dart:193-205` (replay path), `:248-249` (live-only serialization); dedup `handle_incoming_group_message_use_case.dart:462-609`; DB merge protects the row only `group_messages_db_helpers.dart:31-38` |

---

## Root cause(s)

1. **No id-stable, in-place text recovery in the group UI.** The id-reuse retry plumbing exists and even supports text, but in the group UI it is reachable only through the media path, so the user's only text recovery is retyping — the duplicate generator. (doc 102 fixed this for media via restored-composer id reuse; text was out of scope.)
1b. **Voice rides a separate, restore-less path.** `_onRecordStop()` is independent of `_onSend`/`_restoreComposerSnapshot`, so the doc-102 id-reuse fix never applies; a stalled voice upload can't be re-driven manually, and a re-record produces fresh id + different bytes that defeat *every* dedup. Voice is the only content type whose duplicate can never be collapsed after the fact.
2. **Local sweep status changes are not broadcast.** Reconciled self-echoes *do* refresh the open screen (GIRD-002), but purely local sweep-driven flips (`recoverStuck`, `retryFailed*`) write the DB with no stream emit, so they can lag on an open screen until the next reconcile/reload.
3. **The root timeout asymmetry was deferred, not fixed.** doc 102 §5 explicitly declined to change the timeout *value*; it mitigated the symptom (don't false-fail; reconcile later). Flutter still abandons at 10s vs native ≈30s, so sends still enter in-doubt limbo, and the ones that never get a same-id reconciliation (text retype) are not repaired.
4. **Recovery sweeps key off the wrong timestamp and don't cover every state.** They use the message *creation* time (not a status-change time), and certain `pending` rows (null retry payload, no self-echo) fall through every sweep.
5. **Receive-side dedup isn't atomic across entry points.** Replay/drain bypasses the live serialization, so the same id can transiently double-emit / double-notify.

---

## Proposed improvements

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

## Test & verification strategy

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
