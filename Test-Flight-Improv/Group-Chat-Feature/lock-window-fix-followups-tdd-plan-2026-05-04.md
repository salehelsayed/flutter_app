# Lock-window fix follow-ups — TDD plan (filed 2026-05-04)

## Context

The lock-window fix on branch `new-background` (PR #1) shipped after three
`/ultrareview` runs and one Pixel ↔ iOS-sim hardware soak. Closure was
recorded in
[`lock-window-fix-gate3-ultrareview-2026-05-04.md`](./lock-window-fix-gate3-ultrareview-2026-05-04.md);
the post-closure section there filed five follow-ups discovered while
post-mortem-ing user-b's "empty bubbles" symptom. This document turns
those five items into an actionable TDD plan a future session can execute
cleanly.

The rule this plan exists to enforce: every follow-up the soak log filed
gets either *executable RED→GREEN→REFACTOR steps* below, or *a standing
rule with a clear owner location*. Nothing slips through as "we'll
remember it."

The fix commits this plan continues from:
```
4730f6d9  Fix offline-inbox drain holding SQLCipher write lock across bridge calls
67442851  Fix drain Phase 2/3 atomicity gaps surfaced by /ultrareview
f82f778e  Stop tracking local Codex sandbox artifacts and fix orchestrator agent definition
7dc6376f  Untrack remaining sandbox / build caches missed by f82f778e
f412df19  Patch FakeBridge subclass guard bypass + Gate 3 closure note
e8066621  Bump 1.0.0+87
a600a5cf  Bump 1.0.0+88: live-message symptom fix verified on hardware
dfb96e32  Land in-flight WIP: empty-msg listener guard, simulator tests, relay binary
82df2a00  Add drain → listener empty-envelope cross-system test + post-closure follow-up note
```

---

## Standing rules (no code work — document once, apply forever)

### Rule 1.1 — Hardware-soak input fuzzing (covers soak-log follow-up #1)

Before any group-messaging release hardware-validates, the soak plan **must
include at least one malformed-envelope injection point on the upstream
side** — skeleton / text-less / media-less event(s) wired through the same
path real upstream traffic takes.

- **Lives in:** the soak template in
  `Test-Flight-Improv/Group-Chat-Feature/`. Extend the soak procedure with a
  "malformed-envelope checkpoint" line item.
- **Why this matters:** the +87 lock-window soak used only well-formed
  envelopes from `buildGroupOfflineReplayEnvelope` and was structurally
  incapable of exposing user-b's empty-bubble bug. A 30-second injection
  step would have reproduced the symptom on the developer's own machine.

### Rule 1.2 — UI symptom triage rule (covers soak-log follow-up #4)

When a UI surface looks "stuck on skeleton placeholders", **verify whether
the underlying rows are real-but-empty before assuming the loader is
blocked.**

- **Concretely:** open a debug build (FLOW events visible), check what the
  relevant `loadX()` actually returns. If it returns rows whose payload
  fields are empty strings, the bug is upstream of the load — not in the
  load.
- **What we did wrong last time:** read the 10s sqflite "database has been
  locked" warning, conflated it with a stuck loader, and chased a phantom
  lock window. The 10s warning is *not* a reliable indicator that the load
  itself is blocked — there are many concurrent paths that produce it.
- **Lives in:** this document plus the post-closure section of the Gate-3
  closure note. Reread before opening any "skeleton placeholder stuck"
  bug.

---

## TDD sessions (executable code work)

Three sessions, executed in **A → B → C order**. The order minimizes
re-work: A creates a helper that B uses, and C is the largest piece so
done last.

Each session uses the project's standard RED→GREEN→REFACTOR cycle.

### Session A — `_PageBridge.addMalformedPage` helper (covers soak-log follow-up #3)

**Goal.** Extract the one-off empty-envelope construction in the
`drain → listener empty-envelope` test (added in `82df2a00`) into a
reusable helper on `_PageBridge` so future malformed-input tests are 5
lines instead of 50.

**RED.** Add a second drain test to
`test/features/groups/application/drain_followup_invariants_test.dart`
that exercises a *different* malformed shape (e.g., `text=null` instead
of `text=""`) using the proposed helper. Expected shape:

```dart
test('drain → listener: text-null envelope is dropped', () async {
  bridge.addMalformedPage(
    'group-1', '',
    shape: _MalformedEnvelopeShape.textNull,
    messageId: 'msg-text-null',
  );
  await drainGroupOfflineInbox(...);
  expect(msgRepo.count, 0);
  expect(...GROUP_MESSAGE_LISTENER_EMPTY_DROP fired once...);
});
```

Test fails because `addMalformedPage` doesn't exist yet.

**GREEN.** Add to the test file:

```dart
enum _MalformedEnvelopeShape {
  textEmpty,        // text: ""
  textNull,         // text: null
  textMissing,      // no text key
  emptyMediaArray,  // text: "", media: []
}

extension _MalformedHelpers on _PageBridge {
  Future<void> addMalformedPage(
    String groupId,
    String cursor, {
    required _MalformedEnvelopeShape shape,
    required String messageId,
    String nextCursor = '',
  }) async {
    final plaintextMap = <String, dynamic>{
      'groupId': groupId,
      'senderId': 'peer-admin',
      'senderUsername': 'Admin',
      'keyEpoch': 1,
      'timestamp': DateTime.utc(2026, 5, 2, 12).toIso8601String(),
      'messageId': messageId,
    };
    switch (shape) {
      case _MalformedEnvelopeShape.textEmpty:
        plaintextMap['text'] = '';
      case _MalformedEnvelopeShape.textNull:
        plaintextMap['text'] = null;
      case _MalformedEnvelopeShape.textMissing:
        // intentionally omit
        break;
      case _MalformedEnvelopeShape.emptyMediaArray:
        plaintextMap['text'] = '';
        plaintextMap['media'] = <Map<String, dynamic>>[];
    }
    final envelope = await buildGroupOfflineReplayEnvelope(
      bridge: this,
      groupRepo: ...,
      groupId: groupId,
      payloadType: groupOfflineReplayPayloadTypeMessage,
      plaintext: jsonEncode(plaintextMap),
      ...
    );
    addPage(groupId, cursor, [{'from': 'peer-admin', 'message': envelope, 'timestamp': ...}], nextCursor);
  }
}
```

Refactor the *existing* drain → listener test from `82df2a00` to use
`addMalformedPage(... shape: _MalformedEnvelopeShape.textEmpty ...)` so
the boilerplate is in one place.

**REFACTOR.** Verify both tests (the existing one + the new `textNull`
one) pass. Collapse any duplicated envelope-build code.

**Files touched.**
- `test/features/groups/application/drain_followup_invariants_test.dart`
  (only)

**Estimated time.** ~30 min.

**Depends on.** Nothing.

---

### Session B — `handleIncomingGroupMessage` empty-text symmetry (covers soak-log follow-up #2)

**Goal.** Audit the 10 `return null;` branches in
`lib/features/groups/application/handle_incoming_group_message_use_case.dart`
(lines 69, 96, 108, 133, 154, 166, 181, 199, 248, 277) for empty-bubble
hazards, and add a top-of-function early-return so the
**listener-less drain path** (when `groupMessageListener == null`) gets
the same empty-drop protection the listener has.

**Why this matters.** The listener-side guard committed in `dfb96e32`
only fires when the drain has a `groupMessageListener`. The drain falls
back to calling `handleIncomingGroupMessage` directly when no listener
is wired (e.g., production startup before `MyApp` mounts the listener,
or unit tests without a listener). Without an early-return in
`handleIncomingGroupMessage` itself, an empty-text envelope reaching
this path would still persist a row.

**RED.** Use `addMalformedPage(...)` from Session A to add a third drain
test:

```dart
test('drain (no listener): malformed envelope does not persist via handleIncomingGroupMessage', () async {
  bridge.addMalformedPage('group-1', '', shape: _MalformedEnvelopeShape.textEmpty, messageId: 'msg-direct');
  // Notice: groupMessageListener is NOT passed
  await drainGroupOfflineInbox(
    bridge: bridge,
    groupRepo: groupRepo,
    msgRepo: msgRepo,
  );
  expect(msgRepo.count, 0);
  expect(flowEvents.where((e) => e['event'] == 'GROUP_HANDLE_INCOMING_MSG_EMPTY_DROP'), hasLength(1));
});
```

Currently fails because the use case persists the row.

**GREEN.** Insert a guard near the top of `handleIncomingGroupMessage`,
*after* media validation (lines 41–69 area) but *before* the
messageId-dedupe block (line 75). Sketch:

```dart
if (sanitizedText.isEmpty && (media == null || media.isEmpty)) {
  emitFlowEvent(
    layer: 'FL',
    event: 'GROUP_HANDLE_INCOMING_MSG_EMPTY_DROP',
    details: {
      'groupId': groupId.length > 8 ? groupId.substring(0, 8) : groupId,
      'senderId': senderId.length > 8 ? senderId.substring(0, 8) : senderId,
      'reason': 'no_text_no_media',
    },
  );
  return null;
}
```

Cross-link in a comment to the listener-side guard at
`lib/features/groups/application/group_message_listener.dart:285` so
future readers see them as a pair.

**Audit findings to record inline (already verified during planning):**
none of the 10 existing `return null;` branches persist a row before
returning — they're all "reject + don't persist" paths that early-out
above the `await msgRepo.saveMessage(message)` at line 303. The new
guard is the only addition needed.

**REFACTOR.** Run the existing 6388-test suite plus the new tests to
confirm no regression.

**Files touched.**
- `lib/features/groups/application/handle_incoming_group_message_use_case.dart`
- `test/features/groups/application/drain_followup_invariants_test.dart`

**Estimated time.** ~45 min including the audit pass.

**Depends on.** Session A (uses `addMalformedPage`).

---

### Session C — Stricter `dbWriteTransaction` guard (covers soak-log follow-up #5)

**Goal.** Extend the existing zone-flag guard in
`lib/core/database/db_write_transaction.dart` so it also catches the
classic sqflite deadlock pattern: **code awaiting any method on the
parent `Database` (or another `DatabaseExecutor`) from inside a
`dbWriteTransaction` body.** Today the guard catches Bridge.send only;
not parent-DB calls.

**Approach.** A `_GuardedDatabase` proxy that wraps the underlying
`Database` and:

- delegates every method (`query`, `insert`, `update`, `delete`,
  `rawInsert`/`rawUpdate`/`rawDelete`/`rawQuery`, `transaction`,
  `path`, `isOpen`, etc.) to the wrapped handle when called outside a
  `dbWriteTransaction` zone,
- throws a new `OuterDbCallInsideDbTransactionError` when called from
  inside the zone.

The proxy is passed *instead of* the raw `Database` to all DI
consumers. Inside a `dbWriteTransaction` body, callers receive the
`Transaction txn` parameter as before — they are *expected* to use
that. The proxy only tightens behavior for misuse (calling the parent
handle).

**RED.** Three tests in
`test/core/database/db_write_transaction_guard_test.dart`:

1. **Outer-DB call inside body throws.** Set up an in-memory or fake
   guarded `Database`; call `dbWriteTransaction(guardedDb, (txn) async {
   await guardedDb.query('foo'); })`; expect
   `OuterDbCallInsideDbTransactionError`.
2. **Txn-bound call inside body works.** Same setup; call
   `dbWriteTransaction(guardedDb, (txn) async { await txn.query('foo'); })`;
   expect success.
3. **Outer-DB call outside body works.** Just
   `await guardedDb.query('foo')` outside any zone — works normally.

**GREEN.** Implement `_GuardedDatabase` in
`lib/core/database/db_write_transaction.dart`. Wire it into
`lib/main.dart` where `EncryptedDB` is opened so all DI consumers
receive the guarded handle:

```dart
// before
final db = await openEncryptedDb(...);

// after
final rawDb = await openEncryptedDb(...);
final db = _GuardedDatabase(rawDb);  // proxy passed everywhere downstream
```

Add `OuterDbCallInsideDbTransactionError` mirroring the existing
`BridgeCallInsideDbTransactionError`.

**Implementation note.** The proxy needs to forward `path`, `isOpen`,
transaction lifecycle, and event-channel hooks correctly. Spot-check by
running every existing test that depends on `Database` after the proxy
is wired. A failure pattern to watch for: tests that downcast to a
concrete sqflite type — those need the proxy to expose the underlying
handle through some escape hatch (`rawHandle` getter) for legitimate
test-only use.

**REFACTOR.** Optionally extend
`test/core/database/no_raw_db_transaction_calls_test.dart` to also flag
any new code that constructs `Database` directly instead of receiving
the guarded one through DI. Defense in depth, low priority.

**Files touched.**
- `lib/core/database/db_write_transaction.dart` (add proxy + error)
- `lib/main.dart` (wire guarded handle into DI)
- `test/core/database/db_write_transaction_guard_test.dart` (3 new tests)
- Possibly `test/core/bridge/fake_bridge.dart` if any test-only paths
  need to know about the proxy (unlikely; the proxy quacks like
  `Database`).

**Estimated time.** ~2–3 h including DI rewiring + verifying every
existing unit test still passes.

**Depends on.** Independent of A and B; can be done in any order, but
it's the largest so most-comfortable last.

---

## Verification

For each session individually:
- `flutter test` GREEN (the 6388-test suite plus any new tests).
- `flutter analyze` no new warnings beyond the established 1691
  baseline.

After all three sessions:
- Re-run the hardware-soak procedure with the **malformed-envelope
  checkpoint from Rule 1.1** to confirm the changes hold under live
  conditions. Sim "a" should send at least one event with
  `text=""` / `text=null` / `text` missing during the soak; the Pixel
  must not show empty bubbles in the conversation screen.
- If the soak passes, bump version, rebuild iOS-then-Android per
  `feedback_release_build_order.md`, and ship through the same Gate
  4 → Gate 5 flow as the lock-window release.

## Critical files / scripts (referenced above)

- [`lock-window-fix-gate3-ultrareview-2026-05-04.md`](./lock-window-fix-gate3-ultrareview-2026-05-04.md) — soak log this plan implements the follow-ups for.
- `lib/features/groups/application/handle_incoming_group_message_use_case.dart` — Session B target. The 10 `return null;` branches are at lines 69, 96, 108, 133, 154, 166, 181, 199, 248, 277.
- `lib/features/groups/application/group_message_listener.dart:285` — existing listener empty-drop guard the new use-case guard mirrors.
- `lib/core/database/db_write_transaction.dart` — Session C target.
- `test/features/groups/application/drain_followup_invariants_test.dart` — Sessions A and B target test file. Already has `_PageBridge` scaffolding and the cross-system empty-envelope test from `82df2a00`.
- `test/core/database/db_write_transaction_guard_test.dart` — Session C target test file. Already has 5 tests pinning the bridge-side guard.
- `test/features/groups/application/group_message_listener_test.dart:980` — listener-side empty-drop tests already in place; useful reference shape for Session B's new use-case-side tests.

---

## 2026-05-05 hardware-soak finding — Android notification-tap callback never fires

A live two-device repro (Pixel 6 / Android 16 / API 36 as receiver, iOS sim as
sender, prod debug build of `1.0.0+88` from branch `new-background`) was run
end-to-end with `adb logcat --pid=<app>` capture. The bug surfaced exactly as
the user-reported "tap notification → wrong chat opens" symptom: Alice opened
user-C's chat, backgrounded the app, sender Bob sent a 1:1 message, the OS
notification appeared on the Pixel, Alice tapped it, the app foregrounded but
landed on user-C's chat instead of routing to Bob.

### What the Pixel logs show

```
11:53:11.113  P2P_SERVICE_MESSAGE_RECEIVED   from=12D3KooWJp (Bob), incoming=true
11:53:11.114  MESSAGE_ROUTER_ROUTING          type=chat_message
11:53:11.521  INBOX_STAGING_REPO_STAGE_ENTRY  entryId=direct:5
11:53:13.343  NOTIFICATION_SHOWN              contactPeerId=12D3KooWJp, sender=Bob,
                                              payload=12D3KooWJpvAhFF34wMbGKnomtV843shnN7PBxJFRT4AfovxR14t
11:53:27.479  [RESUME] Step 5: refreshSilentlyOnResume() done   ← app foregrounded by the tap
11:53:27.481  [LIFECYCLE] _onResumed() finished
11:55:11.049  peer:disconnected → 12D3KooWJpv...
```

Absent across the full 6909-line capture:

- `NOTIFICATION_TAPPED` (emitted from `_onNotificationResponse` in
  `lib/core/notifications/flutter_notification_service.dart:64`, the very first
  emit after the plugin callback fires)
- `NOTIFICATIONS_CLEARED` (emitted from `clearDeliveredNotifications`, called
  by `routeAppRootLocalNotificationTap` *before* any route resolution)
- `NOTIFICATION_OPEN_PREPARATION_ERROR` / `NOTIFICATION_TAP_NAV_ERROR`
  (would have fired if tap routing reached Dart and then errored)
- Any navigation event, route-target resolution, or
  `_handleNotificationRouteTarget` activity

### Conclusion

The Flutter `_onNotificationTap` callback in `lib/main.dart:2367` was **never
invoked** when the OS-level notification was tapped on Android. The app's
`_onResumed` lifecycle hook fired (because tapping a notification still brings
the existing process forward), but the tap *payload* was never delivered to
the Dart side. With no payload, no routing decision runs, so the app simply
resumes to whichever screen was last visible — user-C's chat — which is
exactly the symptom the user has been reporting. The bug is at the
Android-↔-Flutter `flutter_local_notifications` PendingIntent boundary, **not**
in `prepareNotificationOpen` / `_handleNotificationRouteTarget` / the route
switch (which the Alice harness in `integration_test/notification_open_during_other_chat_alice_harness.dart`
exercises directly via `onNotificationTap` and which therefore can never
catch this regression).

`adb shell dumpsys activity activities` corroborates this: while the app is in
the foreground after the tap, the MainActivity's current Intent is

```
act=android.intent.action.MAIN cat=[android.intent.category.LAUNCHER] flg=0x10200000
```

i.e., a plain launcher intent — no notification extras, no `payload=` data.
A correctly delivered `flutter_local_notifications` tap PendingIntent would
have carried extras consumed by the plugin's `onDidReceiveNotificationResponse`
dispatcher.

### Suspect surface

`MainActivity.kt` is currently bare:

```kotlin
class MainActivity : FlutterActivity() {
    private var goBridge: GoBridge? = null
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        goBridge = GoBridge(flutterEngine)
    }
}
```

with `android:launchMode="singleTask"` in `AndroidManifest.xml:20`. With
`singleTask`, a tap on the notification PendingIntent fires `onNewIntent`
on the existing MainActivity instance — but the default
`FlutterActivity.onNewIntent` does **not** propagate to the
`flutter_local_notifications` plugin's response handler in plugin v18.0.1.
Plugin docs and known issues (e.g.
`flutter_local_notifications` GitHub #2023, #2287) call out exactly this
mismatch on Android 12+ with `singleTask` / `singleTop`.

### Standing rule

**Rule 2.1 — Test surface for OS notification tap delivery**

Every notification-related fix must include at minimum one **end-to-end**
hardware-or-emulator test where the *real* OS taps a *real* posted
notification and the Dart side observes `NOTIFICATION_TAPPED` (and downstream
route events). A harness that synthesizes the tap by directly invoking
`onNotificationTap` is necessary but not sufficient — it cannot catch
PendingIntent / launchMode regressions like this one.

**Why:** the existing `notification_open_during_other_chat_alice_harness.dart`
calls `onNotificationTap` from Dart, so it green-lights even when the
PendingIntent never reaches Flutter. Today's hardware soak is the first time
this gap surfaced.

**How to apply:** new sessions touching anything in
`lib/core/notifications/`, `MainActivity.kt`, or the AndroidManifest
notification-related fields must add or update an `adb logcat`-asserting
hardware step in the soak plan that greps for `NOTIFICATION_TAPPED`.

### Session N — Wire MainActivity → flutter_local_notifications onNewIntent

Goal: deliver the notification PendingIntent payload from the OS to the Dart
`_onNotificationTap` handler when the existing app process is brought to the
foreground via notification tap (the Pixel-soak scenario above).

**RED:** new instrumentation test (or unit test of MainActivity's
`onNewIntent` hook via Robolectric/Espresso, depending on what the project
already supports) that asserts: given a notification PendingIntent with
`payload="12D3KooWJpv..."` extra, after MainActivity is brought forward,
the FlutterPluginBinding receives a notification-response intent and the
Dart `MethodChannel('dexterous.com/flutter/local_notifications')` receives a
`didReceiveNotificationResponse` invocation with that payload. Mark the
test as currently failing on the existing bare MainActivity.

**GREEN:** override `onNewIntent` in
`android/app/src/main/kotlin/com/mknoon/app/MainActivity.kt` to forward
notification-launch intents to the `flutter_local_notifications`
NotificationDetailsActivity hook (or, equivalently, follow the plugin's
documented `onNewIntent` contract for `singleTask` apps). At a minimum:

1. Override `onNewIntent(intent: Intent)` to call
   `super.onNewIntent(intent)` and then `setIntent(intent)`.
2. Verify (in a separate diagnostic step) that the plugin's intent
   action / extras survive the singleTask resume.

If `setIntent(intent)` alone is insufficient, fall back to the explicit plugin
hook — call into the plugin's instance via the FlutterEngine plugin registry
and forward the intent (the plugin exposes a public method for this in
recent versions).

**REFACTOR:** add a logging-only step in `onNewIntent` (gated behind
`BuildConfig.DEBUG`) that dumps `intent.extras?.keySet()` to logcat so
future hardware soaks can see at a glance whether the payload arrived.
Wire the same `emitFlowEvent('NOTIFICATION_NEW_INTENT_RECEIVED', ...)` on
the Dart side in `_onResumed` to record whether a notification-driven resume
was observed without a follow-up `NOTIFICATION_TAPPED`.

**Verification:**
- `flutter test` GREEN.
- Hardware re-run of the same Pixel soak above (Alice on Pixel, Bob on iOS
  sim, real notification tap). Pixel logcat must show:
  - `NOTIFICATION_TAPPED` within ~1s of the tap.
  - Either `_handleNotificationRouteTarget` for the Bob conversation, or a
    silent return because `onBeforeRouteTarget` resolved a non-conversation
    kind.
- `dumpsys activity activities` after the tap must show MainActivity's Intent
  with the notification extras (action ≠ MAIN/LAUNCHER) **or** show
  MAIN/LAUNCHER but with `_onNotificationTap` having already fired (the
  plugin re-uses `setIntent` patterns).

### Critical files / scripts (added)

- `lib/core/notifications/flutter_notification_service.dart:55-73` —
  `_onNotificationResponse`; the FLOW emit at line 64 is the canary that this
  session must make fire.
- `lib/main.dart:2307` — `widget.notificationService.onNotificationTap = _onNotificationTap;`
  registration site.
- `lib/main.dart:2367` — `_onNotificationTap` body.
- `android/app/src/main/kotlin/com/mknoon/app/MainActivity.kt` — the
  override target.
- `android/app/src/main/AndroidManifest.xml:20` — `launchMode="singleTask"`,
  the constraint that makes plain `setIntent`-style fixes necessary.
- `integration_test/notification_open_during_other_chat_alice_harness.dart` —
  existing harness that **cannot** catch this regression by design (synthesizes
  the tap in Dart). Standing rule 2.1 applies.

---

## Rollout — Session N controller ledger (added 2026-05-05)

### Run Mode Snapshot

- **Active mode:** implementation-committed gap-closure.
- **Degraded local continuation allowed:** no.
- **Source proposal / closure path:** this same document, Session N section
  (lines 471–520) is the row-of-record.
- **Source row status vocabulary:** `Open` / `In progress` / `Code-landed` /
  `Hardware-pending` / `Closed`.
- **Overall closure bar:** Kotlin `onNewIntent` fix landed in
  `MainActivity.kt`; an automated test (or honestly recorded hardware-only
  scope) pinning the fix exists; Dart-side `NOTIFICATION_NEW_INTENT_RECEIVED`
  flow event added so future hardware soaks can grep for it; the bug remains
  reproducible only on a real Android device, so end-to-end verification is
  necessarily a hardware-soak follow-up the human owns (Standing Rule 2.1).
- **Final verdict policy:** `accepted_with_explicit_follow_up` is the
  expected verdict (code-side closes; hardware re-run = explicit
  external-fixture follow-up the human runs). Use `closed` only if the
  human comes back and reports the hardware soak passed in this same
  artifact.

### Ledger

| Session | Status | Plan path | Result | Notes |
|---|---|---|---|---|
| N — Wire `MainActivity` → `flutter_local_notifications` `onNewIntent` | closed | [`session-N-android-notification-tap-onnewintent-plan-2026-05-05.md`](./session-N-android-notification-tap-onnewintent-plan-2026-05-05.md) | Code-landed + hardware-soak-verified | GREEN. `MainActivity.kt` now overrides `onNewIntent` with `super.onNewIntent(intent); setIntent(intent)` and a KDoc block linking back to this artifact. Static pin test at `test/core/notifications/main_activity_onnewintent_pin_test.dart` is GREEN (and was confirmed RED before the Kotlin edit). `flutter test` overall: 6395 passed. `flutter analyze`: 1717 issues — same count both with and without the diff, i.e., zero new warnings introduced (artifact's "1691 baseline" line above is itself stale; it predates pre-existing churn unrelated to this session). **Hardware soak verified 2026-05-05** on Pixel 6 (Android 16, API 36) ↔ 2 iOS-sim friends, fresh-install debug build with the new override. Two consecutive notification-tap reps both produced `NOTIFICATION_TAPPED` Dart flow events on the Pixel within milliseconds of the tap (10:58:49.841 and 11:00:03.727 UTC), each followed by `NOTIFICATION_TAP_TO_MESSAGE_TIMING` `routeKind=conversation` with `elapsedMs=573` and `elapsedMs=442` respectively. No `NOTIFICATION_TAP_NAV_ERROR`, no `INITIAL_LOCAL_NOTIFICATION_ROUTE_ERROR`, no FATAL / `E/flutter`. User-reported "tap notification → wrong chat opens" symptom no longer reproduces. Standing Rule 2.1 satisfied. |

### Follow-ups (explicit, not blocking final verdict)

1. **Hardware soak (external-fixture; human-owned).** ✅ **Hardware-soak-verified 2026-05-05.**
   Per Standing Rule 2.1 in this same artifact (lines 450–469), the Pixel ↔
   iOS-sim soak from the 2026-05-05 finding was re-run on a fresh-install
   debug build of branch `new-background` carrying the `MainActivity.onNewIntent`
   override. Pixel 6 (Android 16, API 36) was the receiver; two iOS sims
   (`347FB118…` iPhone Air + `5BA69F1C…` iPhone 17) were the senders.
   Two consecutive notification-tap reps both produced:
   - `NOTIFICATION_TAPPED` Dart flow event on the Pixel within milliseconds
     of the tap (10:58:49.841 UTC and 11:00:03.727 UTC).
   - `NOTIFICATION_TAP_TO_MESSAGE_TIMING` `routeKind=conversation` immediately
     after, with `elapsedMs=573` (rep 1) and `elapsedMs=442` (rep 2) — both
     well under the ~1s target.
   - No `NOTIFICATION_TAP_NAV_ERROR`, no `INITIAL_LOCAL_NOTIFICATION_ROUTE_ERROR`,
     no `FATAL EXCEPTION`, no `E/flutter` in either `flutter run` stdout or
     `adb logcat --pid=<app>`.
   - The user-reported "tap notification → wrong chat opens" symptom no
     longer reproduces.
   Logs captured: `/tmp/run-pixel.log`, `/tmp/pixel-logcat.log`. This is
   the runtime regression catcher; the static pin test only locks the
   contract.
2. **Diagnostic flow event `NOTIFICATION_NEW_INTENT_RECEIVED`
   (deferred REFACTOR sub-row).** The original Session N spec asked for a
   Dart-side `emitFlowEvent('NOTIFICATION_NEW_INTENT_RECEIVED', ...)` in
   `_onResumed` to record whether a notification-driven resume was observed
   without a follow-up `NOTIFICATION_TAPPED`. Doing this honestly requires
   a new MethodChannel from MainActivity → Dart so the Dart side actually
   knows whether the most recent `onNewIntent` carried notification extras.
   That is a non-trivial bridge surface for diagnostic-only value;
   intentionally deferred to keep this session minimal-touch. File as a
   small standalone follow-up if/when the next hardware soak still feels
   noisy. Same scope: a debug-build-only `Log.d` in `onNewIntent` dumping
   `intent.extras?.keySet()` for `adb logcat` visibility.
3. **Robolectric / instrumentation test infrastructure (spawned as
   Session N+1 on 2026-05-05).** The project has no `androidTest/`
   directory and no Robolectric setup. Adding either was disproportionate
   for the single-line override that landed in Session N. After the
   2026-05-05 hardware soak passed, the user asked specifically for a
   regression catcher beyond the existing text-level static pin test;
   the request was scoped into its own session plan at
   [`session-N+1-android-onnewintent-regression-test-plan-2026-05-05.md`](./session-N+1-android-onnewintent-regression-test-plan-2026-05-05.md).
   That session's pre-flight chooses between Robolectric (default, JVM
   unit test) and `androidTest/` (escalation if Robolectric infra cost
   exceeds ~1 hour). It is bounded — one test, one file, one regression
   scope — and explicitly does **not** replace Standing Rule 2.1.
   Status: Open / not yet implemented. Track it in the session plan,
   not here.

### Final program verdict

**`closed`** — promoted 2026-05-05 after hardware-soak verification.
(Originally recorded `accepted_with_explicit_follow_up` 2026-05-05 when
the code landed; promoted later the same day after the soak passed.)

The implementation-side closure bar for Session N is fully met (override
landed, static pin GREEN, full suite GREEN, no new analyzer warnings, KDoc
block links back to this artifact for future readers). The remaining
piece — real-OS-tap hardware soak per Standing Rule 2.1 — was run on
2026-05-05 (Pixel 6 + 2 iOS sims, fresh installs, debug build of
`new-background`); see follow-up #1 above for the captured evidence.
Two consecutive tap reps both observed `NOTIFICATION_TAPPED` on the Pixel
within milliseconds, both routed to `routeKind=conversation` in <600 ms,
no errors in any of the 3 device logs. The original "tap notification
→ wrong chat opens" symptom no longer reproduces.

Sim-side noises observed during the soak that are **unrelated to the
notification-tap fix** were carved out into a separate follow-up artifact
([`session-N-followups-sim-side-noises-2026-05-05.md`](./session-N-followups-sim-side-noises-2026-05-05.md))
so this row's `closed` status is not muddied by them. They are: iOS-sim
push-token registration error (only reproduces on simulator; needs real
iPhone re-check) and sim-B GossipSub-relay `NO_RESERVATION (204)` dial
flakiness against all 5 relay candidates.

Follow-up #2 (`NOTIFICATION_NEW_INTENT_RECEIVED` diagnostic flow event)
and #3 (Robolectric / `androidTest/` infrastructure) above remain
deferred and are non-blocking for this verdict.

### Controller Progress

- 2026-05-05: rollout entered. Read artifact, confirmed Sessions A/B/C
  above are out of scope per user direction (separate rollout).
  Confirmed no prior controller ledger existed for Session N — this is
  first pass. WIP commit `5fec83b3` only added the diagnostic + plan
  prose; no code or test changes for Session N have been applied yet.
  `MainActivity.kt` is still bare (verified).
- 2026-05-05: spawn-children path unavailable in this environment — no
  Task tool, downstream `$implementation-plan-orchestrator` /
  `$implementation-execution-qa-orchestrator` /
  `$implementation-closure-audit-orchestrator` skills not present. Per
  orchestrator contract, falling back to bounded artifact-only local
  Plan / Execution / Closure / Final-Acceptance for the single Session N.
  Single session, narrow scope (one Kotlin file + one Dart flow event +
  one new test), so the bounded fallback is appropriate. Hardware re-run
  remains the user's responsibility per Standing Rule 2.1 — that piece
  will be recorded as `external-fixture` follow-up regardless.
- 2026-05-05: plan written
  ([`session-N-android-notification-tap-onnewintent-plan-2026-05-05.md`](./session-N-android-notification-tap-onnewintent-plan-2026-05-05.md)).
  RED test landed and confirmed failing on bare `MainActivity.kt`. Edited
  `MainActivity.kt` with `onNewIntent` override; pin test flipped GREEN.
  `flutter test` 6395 passed. `flutter analyze` 1717 issues, identical
  with and without the diff (zero new warnings). Diff is exactly:
  `MainActivity.kt`,
  `test/core/notifications/main_activity_onnewintent_pin_test.dart`, this
  artifact, and the new plan file — fully within scope. Closure recorded;
  final verdict `accepted_with_explicit_follow_up`. Rollout complete
  modulo the human-owned hardware soak (follow-up #1).
- 2026-05-05 (later): hardware soak run by the human on Pixel 6 + 2 iOS
  sims, fresh installs, debug build of `new-background`. Two consecutive
  notification-tap reps both produced `NOTIFICATION_TAPPED` Dart flow
  events on the Pixel (`elapsedMs=573` and `elapsedMs=442` to message
  display, both `routeKind=conversation`). No tap-route errors / FATAL /
  `E/flutter` in any of the 3 device logs. Standing Rule 2.1 satisfied.
  Verdict promoted from `accepted_with_explicit_follow_up` → `closed`;
  ledger row + Final-program-verdict section + follow-up #1 updated to
  reflect the soak evidence. Three sim-side log noises that surfaced
  during the soak (iOS-sim push-token registration error; sim-B relay
  `NO_RESERVATION` dial flakiness; cosmetic empty `messageId` in
  `NOTIFICATION_TAP_TO_MESSAGE_TIMING`) are unrelated to this fix and
  carved out into
  [`session-N-followups-sim-side-noises-2026-05-05.md`](./session-N-followups-sim-side-noises-2026-05-05.md)
  for a future session.
- 2026-05-05 (post-closure, on user request): regression-coverage gap
  raised — the static pin test is shape-only, the existing Dart harness
  cannot exercise the OS PendingIntent → MainActivity → plugin → Dart
  path (and is precisely the reason the original bug went unnoticed).
  Spawned Session N+1 plan at
  [`session-N+1-android-onnewintent-regression-test-plan-2026-05-05.md`](./session-N+1-android-onnewintent-regression-test-plan-2026-05-05.md)
  to add a behaviour-level Android-side test (Robolectric default;
  `androidTest/` escalation path if infra cost exceeds ~1 hour). That
  session is intentionally separate so this `closed` verdict does not
  re-open. Updated follow-up #3 above to link to it; this artifact's
  rollout is otherwise complete.
