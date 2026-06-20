# 131 — Notification-tap opens a STALE 1:1 conversation (missing the just-received message)

Status: **PLANNED** (2026-06-19). TDD-first. **No DB migration.** Dart-only, screen-level.

## Reported symptom (device)
Receiving a 1:1 message from a contact ("Hashkobly"), tapping the OS notification opens the
conversation showing the history **as it was when the user last sent** — i.e. the just-received reply
is **absent**. Backing out and re-entering the same chat from the orbit screen shows the reply. So the
message is not lost; it simply isn't on screen on the notification-tap entry.

## What the investigation established (8-agent graph trace, adversarially verified)

Both entry paths build a **fresh** `ConversationWired` with **no** `initialMessages` and both read the
DB via the same one-shot path — so this is **NOT** a stale screen instance and **NOT** a stale
snapshot passed in the route. It is an **ordering / no-recovery** bug:

1. **The 1:1 notification branch never drains the relay inbox.** `_handleNotificationRouteTarget`'s
   `case NotificationRouteTargetKind.conversation:` (`lib/main.dart:3885-3900`) only loads the contact
   and calls `_openConversationForContact` (`lib/main.dart:3957-3985`). It does **not** pass / trigger
   `drainOfflineInbox`. (The **post** branch does — `lib/main.dart:3772-3776` via
   `PostNotificationOpenCoordinator` which `unawaited(drainOfflineInbox())` then waits to observe the
   post — `lib/features/posts/application/post_notification_open_coordinator.dart:56-57`. The **group**
   branch's `drainOfflineInbox` — `lib/main.dart:3797` — is only a *fallback to recover a missing
   group/membership* inside `resolveGroupNotificationRouteTarget`, NOT a per-message pre-fetch.)

2. **`ConversationWired` does a single DB read with no re-fetch on entry/resume.**
   `initState` (`conversation_wired.dart:475-531`) takes the `initialMessages == null` branch ⇒
   `_loadInitialPage().then((_) => _markAsRead())` (`:522-523`). `_loadInitialPage`
   (`:1120-1161`) calls `loadConversationPage` → `messageRepo.getMessagesPage`
   (`load_conversation_use_case.dart:63`) — a **pure DB read**, no drain, no cache. The State class is
   `_ConversationWiredState extends State<ConversationWired>` (`:270`) — **no `WidgetsBindingObserver`,
   no `didChangeAppLifecycleState`**, so nothing re-reads the DB after the one-shot load.

3. **The live incoming channel has no replay.** `_startListeningForMessages` (`:1362-1382`) subscribes
   to `chatMessageListener.incomingMessageStream` (a `StreamController.broadcast()` with **no replay
   buffer** — `chat_message_listener.dart:95,119`). `ChatMessageListener` persists-then-emits, so any
   emit that fires **before** the screen's subscription is established is lost forever.

4. **The durable repo-change channel deliberately ignores incoming inserts.**
   `saveMessage` emits **every** save (incoming included) on `messageChanges`
   (`message_repository_impl.dart:141`), but the screen's `_startListeningForOutgoingMessageChanges`
   filter (`conversation_wired.dart:1392-1398`) is `!message.isIncoming && _shouldRefresh... ||
   message.isDeleted` — it **drops incoming inserts**. So the repo-change stream cannot rescue a
   missed incoming message either.

5. **The message actually lands via the slow async app-resume drain.**
   `didChangeAppLifecycleState → resumed → _onResumed → handleAppResumed`
   (`lib/main.dart:4079-4091,4161-4188`; `handle_app_resumed.dart:188`) awaits
   `p2pService.drainOfflineInbox()`, which decrypts + persists the relay message **after** the screen
   already DB-read the old state. Re-entering from orbit (`orbit_wired.dart:1690-1714`, also no
   `initialMessages`) does a **fresh** `_loadInitialPage` that now reads the persisted row ⇒ message
   appears. That is why orbit re-entry "works" — it masks the bug.

### Net root cause
On notification tap the conversation screen DB-reads **before** the relay message is persisted, and it
has **no recovery** (no entry/resume re-fetch; live stream has no replay; repo-change stream ignores
incoming). The message shows up only on the *next* fresh DB read (orbit re-entry), seconds later.

### Adversarial correction folded in (do not re-introduce)
- The original theory said "post AND group both drain to surface the message." **False for group** —
  the group drain is a missing-group recovery fallback, not a per-message pre-fetch. Only **post** is a
  genuine drain-then-observe. Model the 1:1 recovery on the **post** pattern (or do it screen-side),
  not on the group path.
- The no-replay stream is a **narrow** pre-subscribe race, not a deterministic drop: the subscription
  is attached **synchronously** in `initState` (`:525`) before the async `_loadInitialPage` resolves,
  and `_onIncomingMessage` (`:1438`) DOES upsert a live emit. So when the drain completes **after** the
  screen subscribed and is still open, the message appears live with no fix. The fix must therefore
  guarantee a **DB re-read after the drain**, which is robust regardless of stream timing.

## Design — screen-level self-heal (preferred), no migration

`ConversationWired` already receives `p2pService` (`conversation_wired.dart` ctor; passed at
`main.dart:3969`) and `notificationTappedAt` (`:223`). The fix lives in the screen so it covers **all**
entry paths and app-resume, and is deterministically widget-testable.

Two complementary mechanisms:

### Fix A — drain + re-fetch on notification-tap entry (closes the reported case)
- In `initState`, after the initial load + live subscription are wired, if
  `widget.notificationTappedAt != null`, kick a **bounded, non-blocking** recovery:
  `unawaited(_drainAndReloadOnce())`.
- `_drainAndReloadOnce()`:
  1. `await widget.p2pService.drainOfflineInbox()` (idempotent; first-page-fast variant — NOT
     `drainOfflineInboxFully`).
  2. if `mounted`, `await _loadInitialPage()` again (idempotent — `_loadInitialPage` upserts via
     `_upsertMessageById` and merges with current state, so re-running only **adds** the now-persisted
     message; it does not duplicate or clobber paginated older messages).
  3. emit a `CONV_FL_NOTIF_DRAIN_REFETCH` flow breadcrumb (count delta) for device verification.
- Guard against overlap with a `bool _drainReloadInFlight` so resume + entry don't double-run.

### Fix B — drain + re-fetch on app-resume while the screen is open (closes the general case)
- Make `_ConversationWiredState` `with WidgetsBindingObserver`; `addObserver(this)` in `initState`,
  `removeObserver(this)` in `dispose`.
- `didChangeAppLifecycleState(AppLifecycleState.resumed)` ⇒ `unawaited(_drainAndReloadOnce())` (same
  guarded helper). This handles "app was foreground on the chat, backgrounded, a message arrived,
  resumed" — today that also relies on the no-replay stream.

### Fix C (defense-in-depth, low-risk) — let the repo-change stream rescue incoming inserts
- Broaden `_startListeningForOutgoingMessageChanges`'s filter to also accept **incoming** inserts for
  this contact (`message.isIncoming && message.contactPeerId == _contact.peerId`) and upsert them.
  Because `saveMessage` already emits incoming saves (`message_repository_impl.dart:141`), a message
  persisted by **any** path (drain, live, retry) while the screen is open now surfaces through the
  durable repo channel even if the broadcast `incomingMessageStream` emit was missed.
- This does not replace A/B (it is still a broadcast with no replay, so it can't rescue a pre-subscribe
  emit), but it removes the asymmetry where outgoing changes refresh live and incoming ones don't, and
  it is the cheapest extra safety net. Keep it **behavior-additive** (upsert only; never remove).

> **Decision:** ship A + B (the load-bearing recovery) and C (cheap safety net). Do NOT add a drain to
> `main.dart`'s conversation branch as the primary mechanism — the screen-level drain is strictly more
> general (covers orbit entry + resume too) and is widget-testable without booting the app shell. (An
> optional `main.dart` drain on the conversation branch is listed as OQ-1; the screen fix makes it
> redundant.)

## TDD tasks (RED → GREEN, mutation-verified)

Test home: `test/features/conversation/presentation/screens/conversation_wired_test.dart` (exists).
Use a fake `P2PService` whose `drainOfflineInbox()` is the seam that, when called, makes a new message
visible to the fake `MessageRepository.getMessagesPage` (i.e. the fake "persists on drain"). Inject via
the existing ConversationWired test harness. **Synchronous teardown only** (see
`feedback_testwidgets_sync_io_only`).

- **T1 (Fix A, RED first):** Build `ConversationWired` with `notificationTappedAt: <now>` over a fake
  repo whose first `getMessagesPage` returns the OLD page and whose `drainOfflineInbox` flips the fake
  to also return the new message. Pump. Assert: (a) `drainOfflineInbox` was called exactly once;
  (b) after settle, the new message is rendered. Mutation: remove the `notificationTappedAt` guard →
  assert the drain-refetch still NOT triggered when `notificationTappedAt == null` (separates A from B).
- **T2 (Fix A negative):** Build with `notificationTappedAt: null` (orbit entry) and assert
  `_drainAndReloadOnce` is NOT auto-invoked on entry (no spurious drain on every open). (Resume still
  can — covered by T3.)
- **T3 (Fix B, RED first):** Build the screen (open), then drive
  `WidgetsBinding.instance.handleAppLifecycleStateChanged(AppLifecycleState.resumed)` (or call the
  observer). Assert drain called and the new message appears after settle. Mutation: drop the observer
  registration → test goes red.
- **T4 (overlap guard):** Trigger entry-drain and a resume in quick succession; assert
  `drainOfflineInbox` is not run concurrently more than the guard allows (e.g. at most one in-flight),
  and no duplicate rows (`_upsertMessageById` idempotency).
- **T5 (Fix C, RED first):** With the screen open, emit an **incoming** message on the fake repo's
  `messageChanges` (not on `incomingMessageStream`). Assert it is rendered (today it is dropped).
  Mutation: revert the filter broadening → test goes red.
- **T6 (regression locks):** existing `conversation_wired_test.dart` /
  `conversation_wired_sending_to_failed_test.dart` stay green (outgoing status refresh, send→failed,
  pagination unaffected by the re-fetch).

## Invariants
- **INV-131-1:** `_loadInitialPage` is idempotent — re-running it never duplicates a row and never
  drops already-loaded older (paginated) messages (upsert-merge only).
- **INV-131-2:** No unconditional drain on every conversation open — drain-refetch fires only on
  notification-tap entry (A) or app-resume (B); plain orbit entry does a single DB read as today
  (avoids extra relay traffic on every tap).
- **INV-131-3:** Recovery is non-blocking — the screen renders the cached page immediately; the new
  message pops in when the drain completes (no blank-screen-while-draining).
- **INV-131-4:** Behavior-additive only — incoming repo-change handling upserts, never removes; read
  marking still runs after the message appears (`_markAsRead`).
- **INV-131-5:** `removeObserver` is called in `dispose` (no leaked lifecycle observer; no setState
  after unmount — every async continuation checks `mounted`).

## Gates
- `flutter test test/features/conversation/` green; `flutter analyze` 0 new issues.
- (Optional integration) extend `integration_test/notification_open_during_other_chat_harness.dart` /
  `notification_open_ui_smoke_test.dart` to assert the post-drain message appears on a notification-tap
  open over a fake-drain that persists.
- **Device acceptance:** on two phones, send A→B while B's app is backgrounded on a DIFFERENT screen
  (or this chat), have B tap the notification, and confirm the new message is on screen without a
  back-and-re-enter; `idevicesyslog -m CONV_FL_NOTIF_DRAIN_REFETCH` shows the recovery firing.

## Open questions
- **OQ-1:** Also add `unawaited(widget.p2pService.drainOfflineInbox())` in `main.dart`'s conversation
  branch for promptness (drain starts ~one frame earlier)? With the screen fix it is redundant; skip
  unless device timing shows a visible lag. Default: **skip** (one mechanism, one test surface).
- **OQ-2:** Should resume-drain use `drainOfflineInboxFully` (all pages) instead of first-page-fast?
  Default **no** — first page is what the screen shows; full drain is the app-resume job's concern.
- **OQ-3:** Does `drainOfflineInbox` already run via `handleAppResumed` on every resume at the app
  level (`main.dart:4175`)? Yes — so Fix B's drain is partially redundant with the app-level drain, but
  the **re-fetch** is the missing half; keep the screen-side drain for ordering certainty + so the
  widget test is self-contained.

## Rollback
Revert `conversation_wired.dart` (all changes are additive recovery). Zero data risk (no migration, no
write-path change).

## Out of scope
- Group conversation parity (`GroupConversationWired`) — same class of fix may apply but is a separate
  finding; this plan is 1:1 only.
- The relay/transport timing of when offline messages are fetched (handled by `handleAppResumed`).
- Issue 1 (delivered message stuck on the amber pending clock) — separate plan **132**.
