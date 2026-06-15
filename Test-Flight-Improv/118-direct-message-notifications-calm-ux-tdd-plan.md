# 118 — Live Direct (1:1) Messages Never Notify: Calm Notification TDD Plan

Status: execution-ready
Date: 2026-06-13
Branch: 121-improvements
Source findings: the 1:1 reliability audit (`project_one_to_one_reliability_audit.md`, 2026-06-11) finding "no notifications on live direct msgs", re-verified in source 2026-06-13 by a graph-first notification-routing recon (multi-agent) and a three-lens adversarial critique. Cited line numbers from the original audit had drifted; this plan carries the **current** anchors on `121-improvements`, all re-confirmed this session.
Related plans (do NOT duplicate): `106-group-chat-invited-vs-accepted-message-notifications-session-03-notification-suppression-routing-plan.md` (group FCM/background fallback membership gating — a DIFFERENT suppression surface), `117-one-to-one-media-thumbnail-mime-voice-tdd-plan.md` (house TDD-plan style).

---

## Problem statement

A live direct (1:1) message delivered over the libp2p stream (relay/direct transport) **never raises a local notification** when the recipient's Flutter is live enough to handle it, because the deferred-direct-ack staging redesign routes that message through the recovery callback. Concretely: Go attaches a `confirmNonce` to every incoming direct `chat_message` while `EnableDeferredDirectAck` is on (default `true`, `go-mknoon/.../feature_flags.go:42`), so on the Dart side the incoming chat is staged as entry id `direct:<nonce>` (`lib/core/services/p2p_service_impl.dart:753`) and routed through `_processDurablyStagedDirectChat` (`p2p_service_impl.dart:822-907`), which replays it via the `_replayRecoveredInboxChatMessage` callback at `p2p_service_impl.dart:877`. That callback is wired in `lib/main.dart:1664-1669` with `suppressNotification: true` (the inline closure passes the constant `true` into the local `replayInboxChatMessage` helper at `main.dart:1615-1653`). The listener forwards that flag (`lib/features/conversation/application/chat_message_listener.dart:564`), so `maybeShowNotification` short-circuits at `lib/features/push/application/show_notification_use_case.dart:56-68`, emitting `NOTIFICATION_SUPPRESSED` reason `'recovery_replay'` (literal at `:61`) and returning **before** showing anything.

The recipient still ACKs the sender (`callP2PConfirmDirectMessage(ok:true)` at `p2p_service_impl.dart:852`), so the send shows "delivered" and the message **never stores to the relay inbox**, so **no FCM fires either** — `go-relay-server/inbox.go:758` is the sole 1:1 push trigger and is reached only after an inbox `Store`. The suppression is therefore a **total notification loss** for the live-direct path.

(Correction to the original audit: it cited `main.dart:1583-1587`; that range is account-migration importer code — `MigrationDatabaseActiveImporter` — not the disposition wiring. The real wiring is `main.dart:1664-1675`, verified this session.)

The LAN path already escapes this via a separate `replayLiveLanChatMessage` callback (`main.dart:1670-1675`, `suppressNotification:false`), and direct messages lacking a `confirmNonce` notify via the `_emitIncomingMessage` fallback (`p2p_service_impl.dart:829`). **Backgrounded/suspended recipients are NOT affected** — they cannot ACK within `DirectConfirmTimeout` (2s, `config.go:81`), so the sender's write falls to the unacked → relay-inbox handoff and FCM fires.

The fix must make live direct messages **capable** of notifying while keeping the whole experience CALM: the default stays quiet and well-mannered, with at most one audible tone per conversation per debounce window and genuine recovery/replay still silent.

---

## Part 1 — How other messaging apps architect calm notifications & sounds

A tight synthesis of how Signal / WhatsApp / iMessage / Telegram plus the iOS/Android notification APIs and calm-tech principles handle "loud only when it matters." "Calm" is not one feature; it is the emergent result of layering a delivery tier, a foreground/visible-thread suppression gate, a per-conversation sound throttle, conversation coalescing, mute/DND honoring, and read-state suppression. The loudest possible alert is reserved for exactly the case the user is **not** already looking at and has **not** just been alerted about.

### Borrowed-pattern table

| Pattern | Source (mechanism) | What it does | Our adoption in this plan |
|---|---|---|---|
| Visible-thread suppression: in-app cue, no system notification | Signal `visibleThread` + `notifyInThread`; WhatsApp In-App Notifications; iOS `willPresent` returning `[]` | The conversation you are looking at never fires a banner/sound | **KEPT verbatim** — our existing `viewing_conversation` gate (`show_notification_use_case.dart:75-87`). Live direct must *reach* this gate instead of being short-circuited first. |
| Single tone per conversation per window | Signal `shouldAlert`: `GROUP_THROTTLE=20s`, `STILL_DECRYPTING_INDIVIDUAL_THROTTLE=5s`, in-app floor `MIN_AUDIBLE_PERIOD_MILLIS=2s`; iOS reuse `threadIdentifier`; Android `setOnlyAlertOnce(true)` | First message in a quiet window sounds; the rest update silently | **ADDED** (Phase 4): per-conversation last-audible-tone tracker, 30s window, keyed by `normalizeActiveKey`. The only behavioral addition. |
| Coalesce a burst into one updating notification | Signal per-thread `NotificationIds` + `MessagingStyle.addMessages`; iOS `threadIdentifier`; Android same notification id | N messages from one sender = one card with a count, at most one pop | **KEPT** — `notificationId = contactPeerId.hashCode` already collapses the visual card (`flutter_notification_service.dart:124`); the silent-update variant reuses the SAME id. |
| Throttle hardest during backlog/restore | Signal `decryptionDrained` gating | Catching up on a queue never machine-guns the user | **KEPT + narrowed** (Phase 1): genuine recovery/relay-inbox-drain stays `suppressNotification:true`; the fix narrows that silence to recovery only. |
| Mute is absolute | Signal `breaksThroughMute`/`markAsNotified`; WhatsApp per-chat mute | A muted thread never sounds or shows | **KEPT verbatim** — group `isMuted` gate at `group_message_listener.dart:919-921`, evaluated before any tone rule. |
| Sound is a supplement, never a signal | Apple HIG "use sound to supplement, not carry info"; Calm Tech "can communicate, but doesn't need to speak" | No in-app whoosh/chime; follow-ups silent | **KEPT** — no new audible cue on send; the OS/local notification tone stays the only audible cue. |
| Contentless wake-up push + on-device build; FCM dedup | Signal Wiki wake-up model; our `recent_remote_push` gate | A backgrounded recipient already alerted by FCM is deduped before the live path fires | **KEPT + strengthened** (Phase 2): `consumeRecentRemoteNotificationAnnouncement` (`show_notification_use_case.dart:89-113`). Because the gate is consume-on-read, the live path also **writes** a marker (`markAnnouncement`) so a late FCM isolate suppresses — a live-wins handshake. This is what makes un-silencing live direct *safe*. |
| Delivery tier / channel importance chosen for calm | iOS `UNNotificationInterruptionLevel`; Android channel importance immutable after `createNotificationChannel` | Loud lives on the channel, not the message; silence = a quieter variant | **ADDED** (Phase 3): a silent `NotificationDetails` variant + a separate silent Android channel (channel sound is immutable, so a silent variant needs a new channel id). |

### Calm principles distilled (the rules this plan obeys)

1. Don't double-alert the chat the user is already looking at (visible-thread suppression).
2. Debounce **sound**, not delivery: keep updating the notification but go silent inside a per-conversation window; first-after-quiet sounds.
3. Throttle per conversation, never globally — a quiet conversation always gets its first alert.
4. Throttle hardest during backlog/restore drains.
5. Coalesce by conversation at a stable notification id — never one notification per message.
6. Mute means mute, evaluated before any sound rule.
7. Sound supplements; never rely on it to convey content.

### Citations

- Signal-Android `DefaultMessageNotifier.kt` (visibleThread, `MIN_AUDIBLE_PERIOD_MILLIS=2s`, ShortcutBadger): https://github.com/signalapp/Signal-Android/blob/main/app/src/main/java/org/thoughtcrime/securesms/notifications/v2/DefaultMessageNotifier.kt
- Signal-Android `NotificationFactory.kt` (`shouldAlert` `GROUP_THROTTLE=20s`/`STILL_DECRYPTING_INDIVIDUAL_THROTTLE=5s`, `setOnlyAlertOnce`, `GROUP_ALERT_CHILDREN`): https://github.com/signalapp/Signal-Android/blob/main/app/src/main/java/org/thoughtcrime/securesms/notifications/v2/NotificationFactory.kt
- Signal-Android `NotificationStateProvider.kt` (MUTE_FILTERED/`breaksThroughMute`/`markAsNotified`): https://github.com/signalapp/Signal-Android/blob/main/app/src/main/java/org/thoughtcrime/securesms/notifications/v2/NotificationStateProvider.kt
- Signal Wiki — Message delivery (contentless wake-up push): https://signal.miraheze.org/wiki/Message_delivery
- WhatsApp Help Center — manage notifications / conversation tones / mute: https://faq.whatsapp.com/797069521522888 , https://faq.whatsapp.com/1790056918005220 , https://faq.whatsapp.com/694350718331007
- Apple Developer — `UNNotificationInterruptionLevel`, `UNNotificationContent.threadIdentifier`, `UNNotificationSound`, `willPresent` / `UNNotificationPresentationOptions`, provisional auth: https://developer.apple.com/documentation/usernotifications
- Apple HIG — Managing notifications (don't repeat, foreground-graceful, sound supplements): https://developer.apple.com/design/human-interface-guidelines/notifications
- Android Developers — Notification channels & importance (immutable after create), `setOnlyAlertOnce`, grouping/`GROUP_ALERT_SUMMARY`, MessagingStyle: https://developer.android.com/develop/ui/views/notifications/channels , https://developer.android.com/develop/ui/views/notifications/build-notification , https://developer.android.com/develop/ui/views/notifications/group
- Telegram Blog / TDLib — per-chat sounds, mute, delay-before-show to allow read-elsewhere: https://telegram.org/blog/notifications-bots , https://core.telegram.org/tdlib/notification-api/
- Amber Case — Principles of Calm Technology: https://www.caseorganic.com/post/principles-of-calm-technology
- Nielsen Norman Group — Designing Useful Smart Home Notifications (tier by urgency, alert fatigue): https://www.nngroup.com/articles/smart-home-notifications/
- flutter_local_notifications — `AndroidNotificationDetails` (`importance`, `onlyAlertOnce`, `groupKey`, `playSound`), `DarwinNotificationDetails` (`presentSound`, `interruptionLevel`, `threadIdentifier`): https://pub.dev/packages/flutter_local_notifications

---

## Part 2 — Target behavior for this app (calm policy)

Single notification gate: `maybeShowNotification` (`show_notification_use_case.dart:42`). Two `ActiveConversationTracker` instances (direct + group). The fix makes live direct **capable** of notifying; everything else is suppression-rule plumbing and one calm addition (the sound debounce).

### Decision table (situation → notification? sound? rationale)

| Situation | Notification? | Sound/vibration? | Rationale (gate) |
|---|---|---|---|
| Viewing the exact conversation (resumed + `tracker.isViewing`) | No | No | Inline letter-card is the surface. **KEPT** `viewing_conversation` (`:75-87`). |
| Genuine recovery/replay-after-restart (relay-inbox drain, post-restore catch-up) | No | No | Backlog must not machine-gun. **KEPT** `recovery_replay` short-circuit (`:56-68`), narrowed to recovery only. |
| Same message already alerted by recent FCM push (`consumeRecentRemoteNotificationAnnouncement` true) | No | No | FCM dedup. **KEPT** `recent_remote_push` (`:89-113`). Makes un-silencing live direct safe. |
| Muted group (`group.isMuted`) | No | No | Mute is absolute, evaluated first. **KEPT** (`group_message_listener.dart:919-921`). |
| **Live direct (1:1), resumed but on another screen, first in window** | **Yes** | **Yes (default tone)** | **THE FIX** — live direct joins the alertable set. First-after-quiet sounds. |
| Live direct (1:1), resumed but on another screen, within window | Yes (updated silently) | No | Per-conversation tone debounce; burst = one pop. |
| Live direct (1:1) that needed a RETRY (first replay was retryable, then swept) | Yes | Per debounce | **FIX EXTENSION** — the recovery sweep must keep `direct:`/`lan:` entries notify-capable (see retry-path fix). |
| Live direct (1:1), backgrounded | Yes (via FCM) | Per FCM | **UNCHANGED** — unacked→relay-inbox handoff fires FCM (`inbox.go:758`); `recent_remote_push` dedup + live-wins marker prevent a double. |
| Live LAN direct (entry id `lan:`) | Yes | Per debounce | **UNCHANGED** — already uses `replayLiveLanChatMessage` (`suppress:false`). The fix mirrors this exact pattern. |
| Live group, not viewing, first in window | Yes | Yes | Already notifies; gains the same per-conversation debounce. |

### Sound debounce policy

- **At most one audible cue per conversation per debounce window (proposed 30s).** The FIRST live (non-recovery, non-viewing, non-deduped, non-muted) message after a quiet window plays the device default tone; every subsequent message for that conversation within the window updates the notification **silently** (Android `onlyAlertOnce` + reuse `notificationId`; iOS reuse `threadIdentifier`).
- **Per conversation, never global** — keyed by `ActiveConversationTracker.normalizeActiveKey` (`contactPeerId` for direct, `group:<id>` for group, after stripping the `|message:<id>` suffix the group listener appends). A quiet conversation is never starved of its first alert.
- **Window keyed to last-audible-tone-at, resets only after silence** — it does NOT extend on silent updates, so one tone fires roughly every 30s of continuous activity and immediately again after a lull. (30s aligns with the existing `recentRemoteNotificationTtl = 30s` in `recent_remote_notification_gate.dart:6` — a deliberate match, see OQ-1.)
- **Vibration follows sound** — the silent variant disables vibration (Android silent channel `playSound:false`, no vibration; iOS `presentSound:false`).
- **Mute and FCM-dedup are evaluated before the tone rule** — a muted or already-FCM-alerted message neither sounds nor shows regardless of the window. The tone tracker is consulted ONLY after all suppression gates pass, so a muted/deduped/viewed message never touches `shouldPlayTone`.
- **No new audible cue on send; no in-app whoosh/chime** — the OS/local notification tone stays the only audible cue.

### Explicit rule separating genuine recovery/replay from live receive

The distinction is **routing**, and it is made on TWO axes — the staging entry-id prefix AND the recoverable-status of the entry. This precision matters because the two paths use different mechanisms:

- **LIVE** = a freshly-staged-and-immediately-replayed direct message (entry id `direct:<nonce>` via `_processDurablyStagedDirectChat`) OR LAN (`lan:<nonce>` via `_replayDurablyStagedLanChat`). → Replays through a **notify-capable** callback (`suppressNotification:false`). Falls through to `viewing_conversation` + `recent_remote_push` + the new tone debounce.
- **RECOVERY** = the startup/relay-inbox drain sweep `_replayStagedInboxEntries` (`p2p_service_impl.dart:960`). **IMPORTANT mechanism note:** this sweep does NOT route by entry-id prefix — it dispatches purely on `entry.messageType == 'chat_message'` (`p2p_service_impl.dart:976`) over whatever `getRecoverableEntries()` returns. A genuine relay-inbox-recovered entry (no `direct:`/`lan:` prefix) is true recovery and **KEEPS** `suppressNotification:true`.
- **THE RETRY EDGE (must be handled, not assumed away):** a once-LIVE `direct:<nonce>` entry whose first `_processDurablyStagedDirectChat` replay returns `retryable` (real paths: `unknown_sender_intro_pending` at `main.dart:1641-1648`, generic `processing_error` at `p2p_service_impl.dart:891`) is left in the staging repo as a RECOVERABLE entry. On the next resume/reconnect, `_drainOfflineInboxDurably` calls `_replayStagedInboxEntries()` with no entryId filter, and that prefix-blind sweep would route the retried `direct:` entry through the SILENT recovery callback — silently dropping a message the recipient was **live** for when it first arrived. The fix MUST therefore make the sweep prefix-aware (route `direct:`/`lan:`-prefixed recoverable entries through the notify-capable callbacks). See Phase 1B.

So the original "the prefixes already separate everything, no staging change needed" framing is WRONG for the retry case. The prefixes exist (`direct:` at `:753`, `lan:` at `:789`), but the recovery sweep is prefix-blind today, so a small sweep-routing change IS needed to keep retried-but-live messages notify-capable.

---

## Part 3 — TDD implementation plan (ordered phases)

Every phase is test-then-code (RED → GREEN → refactor) UNLESS explicitly labeled a VERIFICATION/CHARACTERIZATION phase (where the expected result is that the test passes against unchanged production code — a real failure there is the signal a fix is scoped). Tests mirror `lib/` under `test/`.

> Note on the dropped Phase 0: the previous draft proposed extracting the `main.dart` disposition closures into a standalone `buildInboxChatReplayDispositions` helper with its own test. That is removed. `replayInboxChatMessage` (`main.dart:1615-1653`) is ALREADY a named, self-contained local function; the closures at `:1664-1675` are 4-line wrappers whose only "logic" is hardcoding one boolean. There is no disposition logic to extract — testing a wrapper that forwards a constant is testing-the-mock, not red-first behavior. The genuine seam (does `_processDurablyStagedDirectChat` call the `suppress:false` callback?) is covered by the Phase 1 `p2p_service_impl` unit test with spy callbacks, and the `main.dart` wiring (an integration concern) is exercised by the Phase 6 integration test. The third closure is just added inline alongside the existing two.

### Phase 1 (ROOT-CAUSE): route live direct through a notify-capable callback

Goal: stop `_processDurablyStagedDirectChat` from using the suppressing recovery callback. Add a third callback `_replayLiveDirectChatMessage` (`suppressNotification:false`), wire it hard (non-null) in production, and reserve `_replayRecoveredInboxChatMessage` for the recovery sweep only.

RED tests (write first):
- `test/core/services/p2p_service_impl_direct_notify_test.dart` (create, or extend the existing staging test) — seam: `P2PServiceImpl._handleMessageReceived` → `_processDurablyStagedDirectChat`. Inject spy `replayRecoveredInboxChatMessage`, `replayLiveLanChatMessage`, and the new `replayLiveDirectChatMessage`; feed an incoming `chat_message` with a non-empty `confirmNonce` (entry id `direct:<nonce>`). Assert: the **live-direct** spy runs (with `stagedEntryId` `direct:...`), the **recovered** spy does NOT run, and the entry is still staged + the sender is confirmed (`callP2PConfirmDirectMessage(ok:true)` recorded on the fake bridge). **Fails today**: `_processDurablyStagedDirectChat:877` calls `_replayRecoveredInboxChatMessage`.
- *genuine recovery sweep still uses the suppressing callback* — feed a NON-prefixed relay-inbox-recovered staged entry (no `direct:`/`lan:` prefix) through `_replayStagedInboxEntries` and assert the **recovered** spy runs (not live-direct). **Passes today**, guards the narrowing.
- *no `?? recovery` fallback for direct* — assert that the `direct:` path never silently falls back to the recovery callback. Wire `_replayLiveDirectChatMessage` non-null in production; the test verifies that when only the recovery + lan callbacks are present and a `direct:` entry arrives, the code does NOT take the recovery callback (it routes to the dedicated direct callback, or — if that is genuinely null in an alternate entrypoint — emits the un-staged `_emitIncomingMessage` fallback, NOT the suppressing recovery callback). Guards the LAN-pattern re-suppression risk (see Risks).

GREEN production change:
- `lib/core/services/p2p_service_impl.dart:76-80`: add `final ReplayRecoveredInboxChatMessage? _replayLiveDirectChatMessage;` (alongside `_replayLiveLanChatMessage` at `:77`).
- `lib/core/services/p2p_service_impl.dart:216-237` (constructor): add param `ReplayRecoveredInboxChatMessage? replayLiveDirectChatMessage` next to `replayLiveLanChatMessage` (currently `:224`) and the initializer `_replayLiveDirectChatMessage = replayLiveDirectChatMessage` next to `:234`.
- `lib/core/services/p2p_service_impl.dart:822-907` (`_processDurablyStagedDirectChat`): replace the `_replayRecoveredInboxChatMessage` resolution at `:827` and the call at `:877` with `_replayLiveDirectChatMessage`. The staging/confirm flow at `:833-873` is unchanged. Prefer a **hard non-null** wiring — do NOT copy `_replayDurablyStagedLanChat`'s `?? recovery` idiom at `:915`. Keep `_replayStagedInboxEntries` (`:978`) on `_replayRecoveredInboxChatMessage` for now (the retry-aware sweep change is Phase 1B).
- `lib/main.dart:1664-1675`: add a THIRD inline closure identical to the LAN one, passing `suppressNotification:false`:
  ```dart
  replayLiveDirectChatMessage: (message, {String? stagedEntryId}) =>
      replayInboxChatMessage(
        message,
        suppressNotification: false,
        stagedEntryId: stagedEntryId,
      ),
  ```
  No new file, no helper.

Refactor notes: the typedef `ReplayRecoveredInboxChatMessage` (`p2p_service_impl.dart:45-49`) is reused for all three callbacks — no new type. The field comment may clarify "live direct vs recovery"; do not rename the typedef (avoid churn).

### Phase 1B (RETRY-PATH): keep retried `direct:`/`lan:` entries notify-capable on the recovery sweep

Goal: close the silent-loss-returns hole — a once-live `direct:` (or `lan:`) entry that fell to `retryable` and is later swept must replay through the notify-capable callback, not the silent recovery callback.

RED tests (write first), in `test/core/services/p2p_service_impl_direct_notify_test.dart`:
- *retried live-direct entry stays notify-capable on sweep* — stage a `direct:<nonce>` entry, force its first `_processDurablyStagedDirectChat` live replay to return/throw retryable (so it is `markRetryable`'d, `:891`), then invoke the unfiltered `_replayStagedInboxEntries()`. Assert the **live-direct** spy runs for that entry (NOT the recovered spy) and the notification is NOT suppressed for it. **Fails today**: the sweep at `:976` is prefix-blind and routes every `chat_message` through `_replayRecoveredInboxChatMessage`.
- *retried live-lan entry stays notify-capable on sweep* — same shape for `lan:<nonce>` → routes through `_replayLiveLanChatMessage`.
- *genuine relay-recovered entry still silent on sweep* — a non-prefixed recoverable entry still routes through `_replayRecoveredInboxChatMessage` (regression guard, passes after the change).

GREEN production change:
- `lib/core/services/p2p_service_impl.dart:960-1005` (`_replayStagedInboxEntries`): for `entry.messageType == 'chat_message'`, branch on the entry-id prefix — `entry.entryId.startsWith('direct:')` → `_replayLiveDirectChatMessage`; `entry.entryId.startsWith('lan:')` → `_replayLiveLanChatMessage`; otherwise (true relay-inbox recovery) → `_replayRecoveredInboxChatMessage`. Fall back to `_replayRecoveredInboxChatMessage` only when the matching live callback is null. Keep the `_applyRecoveredInboxOutcome` accounting unchanged.

Refactor notes: this is the one genuine staging-routing change the original "no staging-contract change needed" claim missed. Keep it minimal: only the callback selection branches; the sweep's iteration/timing/accounting is untouched.

Owner caveat (flagged in OQ-7): a retried message re-swept after a *very long* offline gap is arguably "catch-up" and could legitimately be silent. The DEFAULT chosen here is **notify**, because the recipient was live when the message first arrived; do not let it fall silent by omission. If the owner wants an age cutoff, that is an additive follow-up.

### Phase 2 (GATE CONTRACT LOCK + DEDUP HANDSHAKE): pin the gate behavior the routing change relies on

Goal: lock the gate contract that Phase 1's routing change must preserve, and close the reverse-FCM double-alert race with a live-wins marker handshake.

> These first two sub-tests are GREEN today and exist to PIN the contract (regression guards), NOT as red-first steps — the already-passing equivalent lives at `show_notification_use_case_test.dart:302-317`. They are labeled as contract locks, not RED.

Contract-lock tests (green today, kept as regression guards):
- *live direct notifies when resumed-but-not-viewing* — `maybeShowNotification` with `suppressNotification:false`, `resumed`, not viewing, no dedup → `showMessageNotification` called once. (Equivalent to existing `:302-317`; keep one canonical copy, do not duplicate.)
- *recovery replay still silent* — `suppressNotification:true` → `showMessageNotification` NOT called, `NOTIFICATION_SUPPRESSED` reason `recovery_replay` emitted.

RED tests (write first — these genuinely fail today):
- *reason literal is parameterizable* — add an optional `String suppressionReason = 'recovery_replay'` param to `maybeShowNotification`; assert a caller can emit a DIFFERENT reason and the emitted `NOTIFICATION_SUPPRESSED.reason` matches the param. **Fails today** (param does not exist). This prevents a future caller from mislabeling a live message as recovery.
- *live path writes a dedup marker (live-wins handshake)* — inject a real `RecentRemoteNotificationGate` (temp file). Call `maybeShowNotification` for a live direct message (resumed, not viewing, `messageId: m1`) → assert `showMessageNotification` fired AND a marker for `(payload|m1)` is now present (`markAnnouncement` was called after showing). Then simulate the FCM-isolate path consuming `(payload|m1)` via `consumeIfRecentAnnouncement` → assert it returns true (so the late FCM would suppress). **Fails today**: the live path never marks, so a late FCM finds nothing to consume and shows a SECOND notification.

GREEN production change:
- `show_notification_use_case.dart:56-68`: parameterize the hardcoded `'recovery_replay'` literal at `:61` via the new optional `suppressionReason` param (default preserves today's value).
- `show_notification_use_case.dart` (after the successful `showMessageNotification` at `:115-120`): when a gate object is wired AND the message has a `messageId`, call `markAnnouncement(payload: routePayload ?? contactPeerId, messageId: messageId)` so a later FCM-isolate `consumeIfRecentAnnouncement` for the same `messageId` suppresses. Thread the gate's `markAnnouncement` in as an optional injected callback (mirroring the existing `consumeRecentRemoteNotificationAnnouncement` injection at `:52-53`) so the unit test can spy it and existing callers default to no-op. No added latency (the resumed path has no guard-delay sleep — `:90-93` only sleeps when NOT resumed).

Refactor notes: keep `maybeShowNotification` a pure async function with all collaborators injected. Keep the dedup gate keyed by `messageId` (`message:<payload>|<messageId>`, `recent_remote_notification_gate.dart:182-183`); do not weaken the key.

### Phase 3 (SILENT-VARIANT): a no-sound notification variant + silent channel

Goal: give `maybeShowNotification` a way to request a no-sound update so the debounce (Phase 4) can show-without-sounding. Android channel sound is immutable after `createNotificationChannel`, so silence requires a separate silent channel id, not a mutation of `mknoon_messages`.

RED tests (write first):
- `test/core/notifications/flutter_notification_service_test.dart` (extend) — seam: `NotificationService.showMessageNotification(..., bool silent = false)`. Assert that with `silent:true` the service uses the silent `NotificationDetails` (no sound) and **reuses the per-conversation `notificationId = contactPeerId.hashCode`** (`flutter_notification_service.dart:124`); with `silent:false` it uses the existing high-importance details. Use a fake `FlutterLocalNotificationsPlugin` recording `show(...)` notification id + channel id + details. **Fails today**: no `silent` param.
- *notification id is per-conversation and stable across a burst, for BOTH direct and group* — call `showMessageNotification` twice for the same `contactPeerId` ('peer-1') with different `payload` (different per-message routePayload), assert SAME notification id both times; then twice for `contactPeerId:'group:g1'` with two different `routePayload` values that embed different `messageId`s, assert SAME notification id both times. This proves the burst coalesces into one card and the per-message `messageId` in `routePayload` does NOT leak into the id. **Guards** the group-vs-direct id-parity hazard: `showMessageNotification` MUST key the id off `contactPeerId.hashCode` (`:124`), never off `(payload).hashCode` (the strategy `showNotification` uses at `:155`).
- `test/core/notifications/local_notification_support_test.dart` (**extend** — this file already exists) — assert `ensureMknoonNotificationChannel` creates BOTH channels (`mknoon_messages` high + `mknoon_messages_silent` low/`playSound:false`), and that `mknoonMessagesSilentNotificationDetails` has Android `playSound:false` (no vibration) + iOS `presentSound:false`. **Fails today**: only one channel/details exists.

GREEN production change:
- `lib/core/notifications/local_notification_support.dart`: near the existing channel const (`mknoonMessagesChannel` at `:7-12`), add `const mknoonMessagesSilentChannelId = 'mknoon_messages_silent';` + a second `AndroidNotificationChannel` at `Importance.low`. Near the existing `mknoonMessagesNotificationDetails` (`:14-28`), add `const mknoonMessagesSilentNotificationDetails` (Android `playSound:false`, no vibration; iOS `presentSound:false`, keep `presentAlert:true`/`presentBadge:true`). Do NOT mutate the existing high channel/details. `ensureMknoonNotificationChannel` (`:30-38`) creates BOTH channels.
- `lib/core/notifications/notification_service.dart`: add `bool silent = false` (additive optional-with-default) to `showMessageNotification`. **Per project memory "implements has no default bodies": update EVERY `implements`-based fake** in the suite or the test build breaks.
- `lib/core/notifications/flutter_notification_service.dart:116-146`: map `silent` → the silent `NotificationDetails`; keep `notificationId = contactPeerId.hashCode` (`:124`) so the OS updates in place. (On iOS, the silent details + reused notification id / threadIdentifier achieve the silent replace.)

Refactor notes: accept the minor UX cost of two channels visible in Android system settings (documented in Risks / OQ-2). Alternative (`onlyAlertOnce` on the single high channel) is the lower-blast-radius v1 fallback — see OQ-2.

### Phase 4 (DEBOUNCE): per-conversation single-tone-per-window policy

Goal: at most one audible tone per conversation per 30s window; subsequent live messages show silently; first-after-quiet sounds. Applies to BOTH direct and group, keyed by `normalizeActiveKey`.

RED tests (write first):
- `test/core/notifications/notification_tone_tracker_test.dart` (create) — seam: a new plain in-memory class `NotificationToneTracker({DateTime Function() clock, Duration window})` with `bool shouldPlayTone(String conversationKey)` (returns true and records the timestamp on first/after-window; false within window). Assert: first call true; immediate second call false; call after `window+1` true again; different conversation key always gets its own first true. **Key-normalization assertions:** the tracker normalizes its input via `ActiveConversationTracker.normalizeActiveKey` so that a group `routePayload` that is ALREADY `group:<id>` and one carrying a `|message:<id>` suffix both collapse to the SAME key — prove two group inputs `group:g1` and `group:g1|message:abc` bucket together (second is silent within window). Injectable clock makes it deterministic.
- `test/features/push/application/show_notification_use_case_test.dart` — *debounce drives silent vs audible, on the STABLE conversation key*: inject the tone tracker + clock into `maybeShowNotification`. Compute the conversation key ONCE (see GREEN) and use it for BOTH `isViewing` and `shouldPlayTone`. First live message → `showMessageNotification(silent:false)`; second within window → `showMessageNotification(silent:true)`. Assert the tone-window key equals the key the suppression gate uses (both via `normalizeActiveKey` on the same input). Assert mute/FCM-dedup/viewing still short-circuit BEFORE the tone decision (a muted/deduped/viewed message never reaches `shouldPlayTone`).
- *group burst is single-tone (key parity with direct)* — two group calls with the SAME `contactPeerId:'group:g1'` but DIFFERENT `routePayload` (different embedded `messageId`): first → `silent:false`, second within window → `silent:true`. **This is the regression guard against the tone-key leak**: the tone key MUST be `normalizeActiveKey(contactPeerId)` (yielding `group:g1`), NOT `routePayload` (which embeds the per-message id and would make every group message sound).

GREEN production change:
- New file `lib/core/notifications/notification_tone_tracker.dart`: the in-memory tracker (mirrors `ActiveConversationTracker` pattern, injectable clock, default 30s window). `shouldPlayTone` normalizes its key argument with `ActiveConversationTracker.normalizeActiveKey`.
- `show_notification_use_case.dart`: inject `NotificationToneTracker? toneTracker`. Compute `final conversationKey = ActiveConversationTracker.normalizeActiveKey(contactPeerId);` ONCE near the top and reuse it for the `isViewing` evaluation and the tone decision. After all suppression gates pass, compute `final silent = toneTracker != null && !toneTracker.shouldPlayTone(conversationKey);` and pass `silent:` to `showMessageNotification`. The tone key is `conversationKey` — NOT `routePayload`. When `toneTracker == null` (existing callers/tests not wired), behavior is unchanged (audible).
- DI: construct one shared `NotificationToneTracker` in `main.dart` and thread it to both listeners (one tracker, both direct + group keys, since the normalized keys are disjoint).

Refactor notes: thread the tracker via the two call sites — `chat_message_listener.dart:554-575` (direct; note: no `routePayload` here, so the key is `contactPeerId` verbatim) and `group_message_listener.dart:922-942` (group; `routePayload` carries `|message:<id>`, but the tone key is derived from `contactPeerId:'group:<id>'`, so it is already correct). No logic change at the call sites beyond passing the collaborator; group keeps its `isMuted` gate (`:919-921`), direct keeps its corrected `suppressNotification:false`.

### Phase 5 (VERIFICATION — dedup race characterization): live-then-FCM same-messageId does not double-notify

> **VERIFICATION/CHARACTERIZATION phase, not RED→GREEN.** Expected result: these tests PASS against the Phase 1+2 code with no further production change. If any fails, that failure is the signal a real fix is needed (scope it only then). Do not try to make a passing test go red.

Tests (write to characterize/lock):
- *live direct then FCM drain, same messageId* — call `maybeShowNotification` for a live direct message (notify shown + marker written by the Phase-2 handshake), then simulate the relay-inbox FCM drain of the SAME `messageId` → assert the second call is suppressed with reason `recent_remote_push` (the marker is consumed). Uses the real `RecentRemoteNotificationGate` semantics (keyed `message:<payload>|<id>`).
- *FCM then live direct, same messageId (the more common ordering)* — FCM path marks `(payload|m1)` first; the later live direct path consumes it → suppressed `recent_remote_push`. (Confirms the existing gate already covers the FCM-first ordering; the Phase-2 marker covers the live-first ordering.)
- *resumed-but-not-viewing has zero guard delay* — assert that when `lifecycleState == resumed`, `backgroundDuplicateGuardDelay` is NOT slept (current behavior, `:90-93`). The live-wins marker (Phase 2), not a delay, is what closes the live-first race.

GREEN production change: none expected (Phase 2 already added the marker handshake). If a residual double survives both orderings, the minimal fix is a small consult-gate-then-show on the resumed live path; scope only if a test demands it.

### Phase 6 (INTEGRATION): end-to-end live-direct notify + debounce + ack coexistence

Goal: the unit seams cannot prove the full bridge→staging→confirm→listener→gate→service wiring (including the `main.dart` closure wiring) nor the burst-coalescing in place. Add narrow integration coverage.

RED tests (write first):
- `test/integration/live_direct_notification_integration_test.dart` (create) — wire a real `P2PServiceImpl` with the three replay callbacks (the inline-wired closures, or a small test harness mirroring `main.dart:1664-1675`), a fake `Bridge` that **records `callP2PConfirmDirectMessage` calls**, a `FakeNotificationService`, real `ActiveConversationTracker` (not viewing), real `RecentRemoteNotificationGate` (temp dir), real `NotificationToneTracker`. Feed an incoming `chat_message` with a `confirmNonce`. Assert ALL of:
  1. exactly one `showMessageNotification(silent:false)` fired for the first message, AND
  2. the sender was confirmed `ok:true` for that nonce (notify and ack coexist on the live path — guards against the fix accidentally moving the confirm off the live path);
  3. a second message in the same conversation within the window → `showMessageNotification(silent:true)` (burst coalesces, one tone);
  4. a genuine relay-recovered (non-`direct:`/non-`lan:`) sweep entry → no show.
- `test/integration/...` retry sub-case (or extend above): a `direct:` entry forced retryable then swept via `_replayStagedInboxEntries()` → still shows (notify-capable), proving Phase 1B end-to-end.
- Reuse the existing `integration_test/notification_sound_smoke_*` harness convention if a device/simulator smoke is added (S-row for live-direct first-tone + within-window silent). Keep it path-addressable per house style.

GREEN/refactor: no new production beyond Phases 1–4; the integration test is the proof the pieces compose.

### Phase 7 (VERIFICATION — FCM/background coverage): confirm the background path is uncorrupted

> **VERIFICATION/CHARACTERIZATION phase, not RED→GREEN.** Expected result: PASS against the Phase 1–4 code with no production change unless a regression surfaces.

Tests (write to verify):
- `test/features/push/application/background_message_handler_test.dart` (extend) — assert the background FCM fallback still shows via `mknoonMessagesNotificationDetails` (audible) for a backgrounded direct message, unaffected by the new live-direct callback or tone tracker. The in-memory `NotificationToneTracker` does NOT exist in the FCM background isolate, so background notifications are NOT debounced by it (documented limitation, OQ-4).
- *no double on resumed live + background FCM* — re-affirm Phase 2/5's dedup across the two isolates (the `RecentRemoteNotificationGate` is file-backed and shared; the iOS NSE `AppGroupPushDedupeStore` is separate — documented).
- *background burst coalescing characterization* — verify the background FCM handler's notification id is per-conversation (a suspended burst from one sender → one card, not N) and uses `onlyAlertOnce`. Inspect `background_message_handler.dart` notificationId source. If it is per-message rather than per-conversation, that is a PRE-EXISTING calm bug — flag it for the owner in OQ-4 (out of scope for this fix, but worth a one-line note) rather than silently implying background is already calm.

GREEN production change: none unless a regression surfaces. Explicitly **do not** add a persisted last-tone timestamp for background in v1 (background is rarer and already FCM-deduped) — see OQ-4.

---

## Mandatory landing order & dependencies

```
Phase 1  (route live direct)                 ← THE FIX. Adds the third callback + non-null wiring.
   ├─> Phase 1B (retry-path sweep routing)    ← HARD-depends on 1 (needs the live callbacks to route to)
   └─> Phase 2  (gate contract lock + dedup handshake) ← lands with/after 1
        └─> Phase 5 (dedup-race verification)  ← VERIFY; depends on 1 + 2
Phase 3  (silent variant + channel)           ← independent; can land in parallel with 1/1B/2
   └─> Phase 4 (tone debounce)                ← HARD-depends on 3 (needs silent:) + 1 (live path exists)
        └─> Phase 7 (FCM/background verify)    ← VERIFY; depends on 1 + 4
             └─> Phase 6 (integration)         ← depends on ALL above
```

- **Phase 1 is the bug fix; Phase 1B closes the retry-path silent-loss hole; Phase 2 closes the reverse-FCM double.** Phases 1 + 1B + 2 (+ Phase 5 verification) alone close the "no notification for live direct" defect WITHOUT re-introducing loss on retry or a double on the FCM race. Phases 3–4 add the calm sound budget; Phases 6–7 verify and prove end-to-end.
- Phase 3 has no dependency on 1/1B/2 and may interleave; Phase 4 cannot start until both 3 and 1 are green.
- Minimum landing to fix the bug while staying calm-by-default: **1 → 1B → 2 → 5 (verify)**. If the owner wants the debounce in the same change set, add **3 → 4 → 7 (verify) → 6**.

---

## Risks & regressions to guard

- **Re-introducing the bug via a `?? recovery` fallback.** `_replayDurablyStagedLanChat` uses `_replayLiveLanChatMessage ?? _replayRecoveredInboxChatMessage` (`p2p_service_impl.dart:915`). If the new direct path copies that idiom and `_replayLiveDirectChatMessage` is ever null, live direct silently reverts to the suppressing callback. **Mitigation**: wire live-direct hard (non-null) in production; Phase 1 includes a test that fails if the recovery callback is taken for a `direct:` entry.
- **Retry-path silent loss (the subtle one).** The recovery sweep `_replayStagedInboxEntries` is prefix-blind (routes on `messageType` only, `:976`), so a once-live `direct:`/`lan:` entry that fell to `retryable` would be re-suppressed when swept. **Mitigation**: Phase 1B makes the sweep prefix-aware + the retry-then-sweep regression test.
- **Reverse FCM double-alert (consume-on-read gate).** `consumeIfRecentAnnouncement` REMOVES the marker (`recent_remote_notification_gate.dart:81-89`), and the resumed path has NO guard delay (`:90-93` only sleeps when NOT resumed). So a live-first ordering (live shows, then a late FCM isolate shows with nothing to consume) yields two alerts. **Mitigation**: Phase 2's live-wins handshake — the live path WRITES `markAnnouncement(payload, messageId)` after showing, so a late FCM `consumeIfRecentAnnouncement` finds-and-suppresses. Phase 5 verifies BOTH orderings. Do NOT ship "observe it on device" as the only mitigation.
- **Group/direct notification-id parity.** Silent coalescing requires the OS notification id be per-conversation for BOTH. `showMessageNotification` keys on `contactPeerId.hashCode` (`:124`) — stable for direct (`contactPeerId`) and group (`group:<id>`), even though `routePayload` embeds a per-message `messageId`. The id MUST NOT switch to `(payload).hashCode` (the `showNotification` strategy at `:155`), or each group message gets a unique id and the burst does not coalesce. **Mitigation**: Phase 3 asserts a group burst (different routePayload, same groupId) yields the SAME id for both variants.
- **Tone-key leak for group.** Keying the tone window on `routePayload` would make every group message sound (the payload embeds a unique `messageId`). **Mitigation**: Phase 4 keys the tracker on `normalizeActiveKey(contactPeerId)` ONLY, with a regression test that two group messages with different routePayloads but the same groupId bucket together (second is silent).
- **Android channel immutability.** The silent variant MUST be a new channel id (`mknoon_messages_silent`) — mutating the existing high channel is a no-op. Cost: two channels visible in Android system settings. **Mitigation**: documented; OQ-2 offers the lower-blast-radius `onlyAlertOnce`-only alternative.
- **Group path untouched except for the shared debounce.** The fix changes only the direct routing + the sweep prefix-routing + adds a shared tone tracker. Group `isMuted` (`:919-921`), `backgroundDuplicateGuardDelay: Duration.zero` (`:941`), and the group FCM/membership suppression (doc 106) MUST stay unchanged. **Mitigation**: Phase 4 asserts group keeps its mute gate; run the groups gate to prove no regression.
- **Recovery replay still silent.** The narrowing must not accidentally un-silence the GENUINE relay-inbox drain. **Mitigation**: Phase 1 + 1B assert non-prefixed recoverable entries still use the suppressing callback.
- **Fake/interface breakage.** Adding `silent` to `NotificationService.showMessageNotification` breaks all `implements`-based fakes (project memory "implements has no default bodies"). **Mitigation**: additive optional-with-default param + update every fake in the same change.
- **iOS NSE vs Dart gate are separate processes.** The tone debounce lives in the in-memory Dart tracker and does NOT survive the FCM background isolate / iOS NSE (`AppGroupPushDedupeStore`). Background notifications are not debounced in v1. **Mitigation**: accepted for v1 (background is FCM-deduped); OQ-4 covers persistence + the background-burst coalescing check.
- **confirm-nonce assumption.** The fix only changes live direct messages that carry a `confirmNonce`. Direct messages without one already notify via `_emitIncomingMessage` (`:829`). **Mitigation**: verify no path double-fires after the change (Phase 5 + integration).
- **Scope creep.** Per-1:1 mute, global DND/quiet-hours, OS badge counts, communication notifications (`INSendMessageIntent`), iOS provisional auth, threadIdentifier grouping are attractive but NOT required to fix this bug. **Mitigation**: explicitly deferred (OQ-6); keep the change minimal.

---

## Device / manual evidence checklist (iPhone13 / Pixel6)

Per project memory: iPhone13 `00008110-…` (use `--profile`/AOT — debug JIT crashes on iOS 26.5), Pixel6 `21071FDF600CSC`.

1. **Live direct notify, resumed-not-viewing** — A on another screen (feed/orbit), B sends a 1:1 message over relay/direct (NOT LAN). A gets ONE notification with sound. Verify on both Pixel6 and iPhone13.
2. **Burst debounce** — B sends 3 messages within 30s while A is on another screen. A sees ONE updating notification card and hears AT MOST ONE tone (silent updates after). Verify the count/preview reflects the latest message.
3. **First-after-quiet sounds again** — wait >30s of silence, B sends again → tone plays. Confirms window resets.
4. **Viewing suppression intact** — A open in B's conversation, B sends → inline card only, NO banner, NO sound.
5. **Recovery stays silent** — kill A, B sends several while A is dead, relaunch A → backlog drains with NO notification storm (recovery_replay silent).
6. **Retried-but-live still notifies** — induce a transient first-replay failure (e.g. intro still resolving) for a live direct message, then trigger the sweep (resume/reconnect) → A still gets the notification (not silently dropped). FLOW: confirm the `direct:` entry routed through the live-direct callback on the sweep.
7. **Backgrounded recipient unchanged + no double** — A fully backgrounded/suspended, B sends → A gets the FCM notification; on resume the live path does NOT double-notify (live-wins marker + recent_remote_push dedup). Watch for a brief double on iOS (NSE vs Dart gate — Risk).
8. **LAN unchanged** — A and B on same Wi-Fi (LAN path), B sends → A notifies as before.
9. **Group unaffected** — group message to A (not viewing, not muted) → notifies with the same debounce; a MUTED group → no notification, no sound.
10. **Android channels** — confirm `Messages` + `Messages (silent)` both appear in Pixel6 system notification settings and the silent variant truly plays no sound/vibration.

Capture FLOW logs for `NOTIFICATION_SUPPRESSED` reasons (`recovery_replay` / `viewing_conversation` / `recent_remote_push`), `NOTIFICATION_SHOWN`, and `P2P_SERVICE_DIRECT_STAGED_CHAT_COMMITTED` to confirm routing.

---

## Open questions for the owner

1. **OQ-1 (window length).** 30s proposed (matches the existing `recentRemoteNotificationTtl`; Signal: 20s groups / 5s individual-while-draining / 2s in-app floor). Should 1:1 and group differ (Signal tiers them), and is 30s right for this app's volume? Default chosen: uniform 30s.
2. **OQ-2 (silent mechanism).** Separate low-importance Android channel (cleaner OS semantics, a second visible channel) vs `onlyAlertOnce` on the existing high channel (no extra channel, but channel stays "high")? The latter is lower blast-radius for v1.
3. **OQ-3 (confirm-nonce coverage).** Does every live direct 1:1 message in production carry a `confirmNonce` (deferred-ack always-on), or are there transport conditions where it does not? Bounds how many live direct messages the fix un-silences.
4. **OQ-4 (background debounce + background burst).** Should the tone debounce survive the FCM background isolate (persisted last-tone timestamp in DB/secure store) for true cross-state calm, or is foreground/live-only acceptable for v1 (background already FCM-deduped)? Separately: is the background FCM handler's notification id per-conversation today (so a suspended burst coalesces)? If per-message, that is a pre-existing calm gap to schedule.
5. **OQ-5 (foreground-anywhere policy).** Is resumed-but-not-viewing the right place to ALWAYS allow a (debounced) tone, or should foreground-anywhere be silent-banner-only like Telegram In-App Sounds off? Owner intent ("minimal, well-mannered, like a polished messaging app") leans toward tone-allowed-but-debounced, banner shown — confirm.
6. **OQ-6 (out-of-scope confirmation).** Per-1:1 mute, global DND/quiet-hours, OS badge management, `threadIdentifier`/communication-notification grouping, and iOS provisional auth are deferred to a follow-up and NOT part of this bug fix — confirm the owner agrees to keep this change minimal.
7. **OQ-7 (retry-sweep age cutoff).** A `direct:`/`lan:` entry retried then swept after a *long* offline gap is treated as LIVE (notifies) by default. Should there be an age cutoff beyond which a retried entry is treated as catch-up (silent)? Default: no cutoff (notify), because the recipient was live at first arrival.

---

## Closure bar

Closed only when ALL hold:

- Every red-first test above is written first, fails for the intended reason, then passes after the minimal implementation. (Phases 5 and 7 are VERIFICATION phases: their tests are expected to pass against the Phase 1–4 code; a failure there is the signal to scope a fix, not a red-first step.)
- A live direct (1:1) deferred-ack message (carrying a `confirmNonce`), with the recipient resumed-but-not-viewing and not FCM-deduped, raises exactly ONE local notification with the default tone — verified at the `maybeShowNotification` seam AND in the `p2p_service_impl` routing test AND in the integration test (which also asserts the sender was still confirmed `ok:true`).
- A live direct/LAN message that needed a RETRY and is later swept still notifies (Phase 1B), not silently dropped.
- A genuine relay-inbox-drain replay (non-`direct:`/non-`lan:` recoverable entry) stays silent (`recovery_replay`), verified by the recovery-sweep test.
- A burst from one conversation within the window produces one card and at most one audible tone (Phase 4 unit + integration), keyed identically for direct and group, and the window resets after silence.
- The live-then-FCM AND FCM-then-live same-`messageId` sequences do not double-notify (Phase 2 marker handshake + Phase 5 verification).
- Group mute, group FCM/membership suppression (doc 106), the group notification-id coalescing, and the backgrounded-recipient FCM path are all unchanged/verified (Phase 7 + groups gate).
- All `implements`-based `NotificationService` fakes updated for the additive `silent` param; the host test build is green.
- 1:1 Reliability host gate + push suite + groups gate green; `graphify update .` run.

---

## Implementation closure log (2026-06-13)

IMPLEMENTED on `121-improvements` (uncommitted), all 7 phases RED→GREEN (Phases 5/7 verification-pass-only). TDD: each behavioral RED was observed first (Phase 1 no-fallback assertion-RED proving direct→recovery suppression; Phase 1B sweep prefix-blindness; Phase 2/3/4 new-API compile-REDs), then GREEN.

**Production changes**
- `lib/core/services/p2p_service_impl.dart` — added `_replayLiveDirectChatMessage` field + ctor param + initializer; `_processDurablyStagedDirectChat` resolves/calls it with a HARD non-null bail-to-`_emitIncomingMessage` (NO `?? recovery`); `_replayStagedInboxEntries` chat branch made prefix-aware (`direct:`→live-direct, `lan:`→live-lan with `?? recovery`, else→recovery).
- `lib/main.dart` — 3rd `replayLiveDirectChatMessage:` closure (suppress:false) mirroring LAN; one shared `NotificationToneTracker` threaded to both listeners.
- `lib/features/push/application/show_notification_use_case.dart` — `suppressionReason` param (default `'recovery_replay'`); `markRecentRemoteNotificationAnnouncement` live-wins marker (after show, when `messageId!=null`); `NotificationToneTracker? toneTracker` → `silent` derivation; `conversationKey` computed once.
- `lib/core/notifications/local_notification_support.dart` — `mknoon_messages_silent` channel + `mknoonMessagesSilentNotificationDetails`; `ensureMknoonNotificationChannel` creates both.
- `lib/core/notifications/notification_service.dart` + `flutter_notification_service.dart` — additive `bool silent=false`; silent details selection; id stays `contactPeerId.hashCode`.
- `lib/core/notifications/notification_tone_tracker.dart` — NEW per-conversation 30s tone tracker (injectable clock, `normalizeActiveKey`).
- `lib/features/conversation/application/chat_message_listener.dart` — tone tracker field + threaded; live-wins markAnnouncement closure.
- `lib/features/groups/application/group_message_listener.dart` — tone tracker field + threaded; **no markAnnouncement** (see deviation).
- 4 `implements NotificationService` updated for `silent` (FlutterNotificationService + FakeNotificationService + alice/bob harness fakes; bob forwards `silent` to `_inner`).

**Tests** (all RED-first then GREEN, except verification phases): `p2p_service_impl_test.dart` (Phase 1 no-fallback + 2 updated direct tests + Phase 1B sweep group); `show_notification_use_case_test.dart` (Phase 2 reason/marker + Phase 4 debounce + Phase 5 dedup-race verification); `flutter_notification_service_test.dart` + `local_notification_support_test.dart` (silent variant/channel); `notification_tone_tracker_test.dart` (new); `background_message_handler_test.dart` (Phase 7 verification); `test/integration/live_direct_notification_integration_test.dart` (new Phase 6).

**Deviation (OQ-6-aligned)**: the live-wins `markAnnouncement` was threaded into the DIRECT (chat) listener only, NOT the group listener. The plan Risk "group path untouched except for the shared debounce" governs; group FCM dedup already runs via the background handler's `markVisibleRemoteAnnouncement`. Group gets only the tone-tracker debounce.

**Gates**: p2p_service_impl 409 ✓, notifications-core 14 ✓, show_notification_use_case ~40 ✓, background_message_handler 15 ✓, integration live-direct 4 ✓, **groups 2016/2016 (`flutter test -j 1`)** ✓, 0 new analyze issues, `graphify update .` + arch refresh run. PRE-EXISTING failures (NOT 118; deterministic under `-j 1`; concurrent in-flight 114/115/116 + device-criteria work, production files modified on-branch but untouched by 118): `retry_unacked_messages_null_guard` / `rapid_lock_unlock` / `relay_down_degradation` (`'delivered'` vs `'inboxed'` = 115 custody) + `group_multi_party_device_criteria` GM-016/ML-018 proof verdicts. NOTE: full groups/notification sweeps are flaky under PARALLEL `flutter test` due to a PRE-EXISTING shared-global-gate-file (`recentRemoteNotificationGate` default path) race across isolates — `-j 1` is deterministic-green.

**Device evidence captured 2026-06-13** (`pixel.log` / `iphone-13.log` at repo root; iPhone13 on `--profile`, no JIT crash):
- **1:1 — Pixel6 recipient over RELAY (the previously-broken path)**: 9× `NOTIFICATION_SHOWN` for peer `12D3KooWRX` (transport 15 relay / 2 wifi). Tone-debounce timeline is textbook — tones at 19:03:46 / 19:07:21 / 19:07:53, then a 5-message burst 19:07:55→19:08:18 all `"silent":true`, then a tone again at 19:11:58 after the quiet gap (proves scenarios 1+2+3). 12× `P2P_SERVICE_DIRECT_STAGED_CHAT_COMMITTED` + 12× `…CONFIRM_SUCCESS` (notify + sender-ack coexist). 15× `recovery_replay` (backlog/relaunch drains stayed silent — scenario 5). 5× `viewing_conversation` (scenario 4).
- **Group — iPhone13 recipient**: 2× `NOTIFICATION_SHOWN` for `group:4f18` (audible, >30s apart), 5× `viewing_conversation`. Group shares the debounce tracker.
- Confirmed: scenarios 1,2,3,4,5,9. Not exercised in these runs: #6 retried-but-live sweep, #7 backgrounded+FCM no-double (Firebase was `SERVICE_NOT_AVAILABLE` on the Pixel), #8 LAN-path, #10 Android channels-visible UI check. Benign environmental noise only (Pixel FCM-token errors, iPhone relay/inbox TimeoutExceptions) — no crash, no notification regression.

**Still pending**: device scenarios #6/#7/#8/#10 (optional) and owner answers to OQ-1..OQ-7.
