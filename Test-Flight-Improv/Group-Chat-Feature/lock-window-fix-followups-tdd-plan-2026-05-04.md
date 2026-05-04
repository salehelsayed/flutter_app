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
