# 186 - Reconnect self-heal latency tightening (FU-185-A)  (Follow-up slice)

Status: IMPLEMENTED + host-verified (2026-07-01); device re-proof pending
Verified: TC-186-01 (use-case olderThan spy), TC-186-02 (reconnect drops gate / periodic keeps 60s), TC-186-04 (real-DB age gate). `pending_message_retrier_test` +28 (all 27 existing preserved incl. the flap-coalescing guard), `retry_unacked_messages_use_case_test` +17, 3 other retrier suites, `handle_app_resumed` (other retryUnacked caller) +10, `1to1` gate +1440 all pass, `flutter analyze` clean (1 pre-existing unrelated warning). core-host-all skipped (its relevant files run directly).
Parent: `185-offline-send-failure-truthfulness-tdd-plan.md` → Follow-ups → FU-185-A
Device evidence: 2026-07-01 Pixel `@pixel` → iPhone-11 capture. On WiFi-restore, the 4 queued offline messages re-inboxed ~20s after reconnect (relay re-dial ~15s + the retrier's 5s debounce), and a message sent <60s before reconnect would wait up to the 5-min periodic (the 60s unacked age gate). A freshly-typed message went out immediately (live send after relay up).

## Problem
An offline-queued (`sent` + wire envelope) message does NOT converge "as soon as we're back online":
1. **5s debounce** — `PendingMessageRetrier._startOnlineTimers` schedules the first post-online retry via `Timer(retryDebounce = 5s)` even on a genuine offline→online reconnect (`pending_message_retrier.dart:226`).
2. **No immediate re-arm on relay-ready** — the too-early resume retry (fires before `circuitAddresses` is back) fails and isn't re-run until the debounce/periodic. (The retrier already waits for `_isOnline` = `circuitAddresses` non-empty, so its trigger is correct; it's just delayed by the debounce.)
3. **60s unacked age gate** — `retryUnackedMessages` hardcodes `getUnackedOutgoingMessages(olderThan: 60s)` (`retry_unacked_messages_use_case.dart:44`), so a message sent <60s before reconnect is skipped by the reconnect pass and waits for the 5-min periodic.

## Fix (as-built — refined during TDD)
1. `retry_unacked_messages_use_case.dart` — add `Duration olderThan = const Duration(seconds: 60)` param (default preserves all callers); thread to `getUnackedOutgoingMessages`.
2. `pending_message_retrier.dart` — the first post-online retry (the `_startOnlineTimers` **debounce** timer) now fires `_retryIfNeeded(unackedOlderThan: Duration.zero)` → the reconnect/cold-start/group-recovery retry **drops the 60s age gate**. The **periodic** timer keeps `_retryIfNeeded()` → default 60s.
3. `_retryIfNeeded({Duration? unackedOlderThan})` → `_retryUnackedMessagesNow(olderThan:)` → `retryUnackedMessages(olderThan:)`.

**TDD-discovered design change (items 1+2 reconsidered):** the original plan was to fire the reconnect retry *immediately* (drop the 5s debounce). Implementing that RED-first tripped the existing preservation test **`debounce cancels previous timer on rapid state changes`** (expected 1 retry, got 3): immediate-fire defeats the debounce's **flap-coalescing** guard, which exists to stop a stampede of relay stores on a flappy network. That guard is worth more than the ~3s the immediate-fire saves — and the *dominant* reconnect delay is the ~15s transport-level relay re-dial (not Dart-fixable), not the 5s debounce. So the debounce is **retained** (item 2's "re-arm on relay-ready" is already provided by the retrier's existing `stateStream` watch → debounce), and the high-value change — **item 3, dropping the 60s age gate on the first post-online retry** (the 5-min worst case → ~5s) — is what ships.

Scope guard: no new retry mechanism; reuse the existing lane. Re-store is idempotent at the receiver (dedup by id), so dropping the age gate on the reconnect pass cannot double-deliver. The periodic pass keeps 60s.

## RED catalog (as-built)
- **TC-186-01** (`retry_unacked_messages_use_case_test.dart`): `retryUnackedMessages(olderThan: Duration.zero)` passes `olderThan == 0` to `getUnackedOutgoingMessages`; the default call passes `60s` (spy on the fake). RED on HEAD: no `olderThan` param (compile). Mutation: drop the passthrough → recorded value wrong → red.
- **TC-186-02** (`pending_message_retrier_test.dart`): after an offline→online reconnect, the **debounced** retry passes `olderThan == Duration.zero`; the **periodic** pass passes `60s` (spy via a no-override retrier + fakeAsync `elapse(defaultRetryDebounce)` then `elapse(defaultPeriodicRetryInterval)`). RED on HEAD (reconnect pass hardcoded 60s). Mutation: revert the `unackedOlderThan: Duration.zero` on the debounce timer → red.
- **TC-186-04** (`messages_db_helpers_test.dart`, real DB): a `sent`+wire_envelope row timestamped 30s ago is EXCLUDED by `dbLoadUnackedOutgoingMessages(olderThan: now-60s)` but INCLUDED by `olderThan: now`. Characterization lock for the gate the fix rides. (DB helper takes a DateTime cutoff; the repo converts Duration→cutoff.)
- Preservation lock kept: **`debounce cancels previous timer on rapid state changes`** stays green (debounce/coalescing retained) — this is the sentinel that reshaped the design.

## Preservation sentinels
- `test/core/services/pending_message_retrier_test.dart` (27 tests — debounce/coalescing/ordering) — cold-start + periodic timing unchanged.
- `retry_unacked_messages_use_case_test.dart` — all pass with the default 60s.
- `./scripts/run_test_gates.sh 1to1` · `core-host-all`.

## Acceptance gates
```bash
flutter test test/core/services/pending_message_retrier_test.dart
flutter test test/features/conversation/application/retry_unacked_messages_use_case_test.dart
flutter test test/core/database/helpers/messages_db_helpers_test.dart
./scripts/run_test_gates.sh core-host-all
./scripts/run_test_gates.sh 1to1
flutter analyze   # 0 new
```

## Device re-proof — PASSED (2026-07-01, Pixel `@pixel` → iPhone-11, 186+slate build)
Message `Fdss`/`0792aa8b`:
- 19:46:42 offline send → `peer_not_found` → kept `sent` (slate snackbar captured, blueGrey[700]).
- 19:47:09 reconnect (`NETWORK_CHANGE_DRAIN_BEGIN`) — message age **~27s** (<60s).
- 19:47:15 **`RETRY_UNACKED_MESSAGES_FOUND count:1`** → `RETRY_UNACKED_MESSAGE_INBOXED` (~6s post-reconnect). **This is the fix:** pre-186 the 60s gate (cutoff = now−60s = 19:46:15) would have EXCLUDED the 19:46:42 message (waits 5-min periodic); post-186 (cutoff = now) INCLUDES it.
- 19:47:24 `CONDITIONAL_TRANSITION inboxed→delivered` → `DELIVERY_RECEIPT_APPLIED` (~15s post-reconnect, bounded by relay re-dial + receipt round-trip), vs ~5 min pre-fix.

Also device-verified: the offline snackbar now renders in **slate blueGrey[700]** (185 color polish), not error-red.
