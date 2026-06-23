# 146 - 1:1 Drain: defer the per-message delivery-receipt send off the replay critical path  (Feature Improvement)

Status: IMPLEMENTED (host-green, reviewed) — 2026-06-23, uncommitted on `new-feed`
Spec: free-text intent (no formal spec) — derived from `Test-Flight-Improv/notification-tap-to-message-load-delay-investigation.md` (the p2p-performance work carved out of plan 145 at `145:69` / `145:292`)

## Planning Progress
| Time | Role | Files inspected | Decision/blocker | Next action |
|---|---|---|---|---|
| 2026-06-23 | Evidence Collector | handle_incoming_chat_message_use_case.dart, send_delivery_receipt_use_case.dart, p2p_service_impl.dart (`_replayStagedInboxEntries`), handle_incoming_chat_message_use_case_test.dart, send_delivery_receipt_use_case_test.dart, scripts/run_test_gates.sh | All anchors verified in working tree; receipt-send is the one clearly off-critical-path awaitable; no DB migration; host-testable via the existing `sendDeliveryReceipt` hook seam | Build matrix |
| 2026-06-23 | Planner | tier-matrix.md, plan-template.md | 7 TCs (unit floor + 1 integration end-to-end); all target files already in `ONE_TO_ONE_TESTS` | Emit plan |
| 2026-06-23 | Reviewer (sufficiency) | sufficiency-checklist.md | zero-empty-cell matrix; each fix mutation-verified; PROD-CRITICAL leg named (TC-07) | — |
| 2026-06-23 | Arbiter | — | host-only closure; device verify = non-blocking follow-up | hand off to execution |

## Execution Progress
| Time | Phase | Files touched | Command/evidence | Decision/blocker | Next |
|---|---|---|---|---|---|
| 2026-06-23 | contract extraction | (read-only) handle_incoming_chat_message_use_case.dart, send_delivery_receipt_use_case.dart, p2p_service_impl.dart `_replayStagedInboxEntries`, inbox_round_trip_test.dart, test_user.dart, fake_p2p_service_integration.dart, p2p_service_impl_test.dart | all anchors verified; all 4 target files in `ONE_TO_ONE_TESTS` | scope confirmed; **TC-07 moved per Stop-If (see below)** | RED |
| 2026-06-23 | RED tests added | handle_incoming_chat_message_use_case_test.dart (+TC-01..06), p2p_service_impl_test.dart (+TC-07) | TC-01/05 timeout RED, TC-07 timeout RED (drain hangs on entry #1 awaited receipt); TC-02/03/04/06 pass on HEAD | RED-first verified for the predicted reason | fix |
| 2026-06-23 | implementation | handle_incoming_chat_message_use_case.dart (`import 'dart:async'` + closure `await`→`unawaited(...catchError...)`) | scoped: 1 prod file, +import only | decision/MINT_SKIPPED kept synchronous; 4 call sites unchanged | GREEN |
| 2026-06-23 | direct GREEN | — | handle test (59) + p2p_service_impl_test + send_delivery_receipt (6) + inbox_round_trip (18) all green | TC-01/05/07 flipped green, locks stayed green | mutation |
| 2026-06-23 | mutation pass | (temp) prod file | A restore-await→TC-01/05/07 re-red; B drop-send→TC-02 re-red; C drop-catchError→TC-03 re-red (unhandled "Bad state: boom" + breadcrumb absent); **D′** schedule-send-despite-skip→TC-04 re-red; E direct/lan-skip→TC-06 re-red | all 7 TCs mutation-verified; **note: plan's TC-04 mutation "compute decision inside deferred future" is NOT observable** (a microtask drains before the awaiting test continuation resumes, so the event is present at assert-time regardless). The genuine catchable lock is "skip schedules NO send" (D′) — TC-04 asserts `receiptIds` empty + MINT_SKIPPED present, both load-bearing | preservation |
| 2026-06-23 | preservation GREEN + named gates | — | `./scripts/run_test_gates.sh 1to1` → **+1120 All tests passed**, 0 regressions | gate green | QA |
| 2026-06-23 | hygiene | — | `flutter analyze` (3 files): 0 NEW issues (3 pre-existing warnings at :271/:491/:497 are outside my edit region; new test ranges clean — switched `__`→`_` wildcard); `git diff --check` clean | clean | QA |
| 2026-06-23 | QA (independent) | — | 3-lens adversarial review workflow (correctness / test-integrity / scope-regression) + per-finding verify | (see Reviewer Findings) | — |

### TC-07 placement deviation (Stop-If honored)
The plan filed TC-07 in `inbox_round_trip_test.dart`. That file's `FakeP2PService.drainOfflineInboxCount` (test/shared/fakes/fake_p2p_service_integration.dart:143) injects each drained message into a stream and yields one turn per entry **without awaiting the handler** — so the receipt-await never gates its drain and the test would pass on HEAD (proving nothing). Per the plan's TC-07 Stop-If, TC-07 was placed in `test/core/services/p2p_service_impl_test.dart`, which drives the **real** `_replayStagedInboxEntries` serial loop with an injected `replayRecoveredInboxChatMessage` that calls the **real** `handleIncomingChatMessage` + a never-completing receipt hook. Confirmed RED-on-HEAD by timeout (drain hangs on entry #1). Both files are in `ONE_TO_ONE_TESTS`, so the `1to1` gate runs it; registration unaffected. The §1/§2 acceptance-gate commands that name `inbox_round_trip_test.dart --plain-name 'without blocking on receipt sends'` instead become `p2p_service_impl_test.dart --plain-name '146 TC-07'`.

## Source Of Truth
- Spec / intent: inline below + `Test-Flight-Improv/notification-tap-to-message-load-delay-investigation.md`
- Gate definitions: `scripts/run_test_gates.sh` (script wins over prose)
- Discovery/registration: `scripts/check_reliability_simulation_discovery.sh` (NOT used — no sim/device rows)
- Numbering / index: `Test-Flight-Improv/00-INDEX.md` (next-free = 146)

## Session Classification
implementation-ready

---

## Exact Problem Statement

When a user taps a 1:1 notification (or the app resumes), the conversation opens on stale history and the relay inbox drain replays the new messages. The drain replays entries **serially** (`p2p_service_impl.dart:1070` `for (final entry in entries)` → `await chatReplay(...)` `:1092`), and inside each replayed message `handleIncomingChatMessage` **awaits a network delivery-receipt send** before the message is considered done (`handle_incoming_chat_message_use_case.dart:510` → closure `maybeSendDeliveryReceipt:93-127` → `await sendDeliveryReceipt(messageId)` `:116`). That send is a real peer round-trip — live `sendMessageWithReply` (`send_delivery_receipt_use_case.dart:109`, **no timeout override**) plus a relay `storeInInbox` fallback (`:131`) — and in the exact notif-tap scenario (sender went offline) the live attempt does not ack, so each message pays the live-attempt latency **plus** a relay store before the loop advances. With N drained messages this is ~N serial receipt round-trips of wall-clock added on top of decrypt+persist, all before the screen reload fires.

The delivery receipt is custody confirmation **to the sender**. The recipient (the user staring at the screen) gains nothing by waiting for it: the message is already durably persisted (`:507`) before the receipt send (`:510`). Nothing downstream consumes the receipt result, its errors are already swallowed+logged (`DELIVERY_RECEIPT_HOOK_ERROR:118-126`), and the receipt is idempotent on the sender (`handleDeliveryReceipt` early-returns on `'delivered'`), so order/duplication of receipts is harmless.

**What must improve:** the per-message delivery-receipt **send** is detached from the replay/critical path (fire-and-forget) so the drain loop — and therefore the screen reload — no longer blocks on receipt network round-trips. The receipt is still sent; just not awaited.

**What must stay unchanged (→ preserved-green sentinels):** the mint **decision** stays per-message and on-path (its inputs `stagedEntryId`+`transport` are message-scoped — `deliveryReceiptMintDecision:42-70`); `DELIVERY_RECEIPT_MINT_SKIPPED` still emits synchronously on a skip; the confirmatory direct/LAN receipt is still **sent** (flag `kConfirmatoryDirectLanReceiptEnabled=true`, the 132 stuck-pending-clock fix — defer, never drop); deferred-send errors are still caught+logged (no unhandled async error); the dup re-mint sites (`:342/:427/:449`) get the same treatment; group delivery receipts (a separate mechanism) are untouched; message persistence, dedupe, edit/delete/reaction handling unchanged.

## Root Cause (verify → refute confirmed)
- **Mechanism (verified in working tree):** `handle_incoming_chat_message_use_case.dart:116` `await sendDeliveryReceipt(messageId)` inside the closure `maybeSendDeliveryReceipt` (`:93-127`); the closure is awaited at the post-persist happy path `:510` (after `saveMessage:507`) and at the three dup re-mint sites `:342`, `:427`, `:449`. The closure is reached once per replayed message through the serial loop `p2p_service_impl.dart:1070/1092`. The send itself (`send_delivery_receipt_use_case.dart:89-163`) does a live `sendMessageWithReply:109` (no `timeoutMs`) + relay `storeInInbox:131` fallback, no retry (D-5).
- **Refute → safe-to-defer (survived):** (a) message is persisted at `:507` BEFORE the send at `:510` — deferring cannot lose the user-visible message; (b) the use case discards the receipt result and already swallows hook errors (`:117-126`) — nothing awaits success; (c) the receipt is idempotent on the sender (`handleDeliveryReceipt` early-returns on `'delivered'`) — fire-and-forget reordering/duplication is harmless; (d) the mint decision (`:95-99`) is a pure function of per-message inputs computed BEFORE the send, so it stays correct when only the send is detached.

Refuted / do-NOT-re-introduce:
- "Just `unawaited(...)` the four call sites" — **rejected**: that would defer the *decision* + the `MINT_SKIPPED` emission too, reorder those events, and risk hoisting a single decision across messages. The fix detaches **only the network send inside the closure**, leaving the decision synchronous and per-message.
- "Suppress the direct/LAN receipt to save the round-trip entirely" — **forbidden**: that re-opens the 132 stuck-pending-clock regression. The flag stays ON; the send is deferred, not dropped.
- "Move the deferral into `main.dart`'s `sendDeliveryReceiptForPeer` wiring" — **rejected**: `main.dart` is not host-importable; the closure in the use case is the testable seam (the test already injects a `sendDeliveryReceipt` hook).

## Real Scope
**In scope:**
- One production change in `handle_incoming_chat_message_use_case.dart`: in the closure `maybeSendDeliveryReceipt`, replace `await sendDeliveryReceipt(messageId)` (`:116`) with a fire-and-forget `unawaited(sendDeliveryReceipt(messageId).catchError(<emit DELIVERY_RECEIPT_HOOK_ERROR>))`. Keep the decision computation (`:95-114`) synchronous/awaited. This single change covers all four call sites (`:342/:427/:449/:510`) because they all route through the closure.
- Ensure `unawaited` is imported (`dart:async`).

**Out of scope (owning work):**
- Parallelizing the per-message **replay** (decrypt fan-out) → plan **147** (`147-1to1-inbox-replay-decrypt-fanout-tdd-plan.md`).
- The non-blocking route + "catching up" affordance + drain telemetry → plan **145**.
- Group delivery receipts (`group_message_receipt.dart` / `group_sync_receipts`) — separate mechanism, unchanged.
- Any change to the mint **decision** truth table, the confirmatory-receipt flag, the relay-store fallback, or the no-retry (D-5) policy.

## Files To Inspect Next
Production: `lib/features/conversation/application/handle_incoming_chat_message_use_case.dart` (closure `maybeSendDeliveryReceipt` 93-127, call sites 342/427/449/510); `lib/features/conversation/application/send_delivery_receipt_use_case.dart` (sender 89-163, decision 42-70 — read-only, NOT edited); `lib/core/services/p2p_service_impl.dart` (`_replayStagedInboxEntries` 1060-1095 — read-only, the loop that benefits).
Direct tests: `test/features/conversation/application/handle_incoming_chat_message_use_case_test.dart` (already injects `sendDeliveryReceipt:` hooks at L743/2020/2044/2053+); `test/features/conversation/application/send_delivery_receipt_use_case_test.dart`.
Integration tests: `test/core/inbox/inbox_round_trip_test.dart`; `test/core/services/p2p_service_impl_test.dart`.
Dependency-only context: `lib/features/conversation/application/chat_message_listener.dart`, `lib/main.dart` (`sendDeliveryReceiptForPeer` wiring — not edited).

## Existing Tests Covering This Area
- `handle_incoming_chat_message_use_case_test.dart` (53 tests) — already injects fake `sendDeliveryReceipt:` hooks (L743/2020/2044/2071+); has a test "invokes sendDeliveryReceipt after durable persist… and re-invokes on duplicate receive" (~L2053). **MISSING:** any assertion that the send is fire-and-forget (does not block the use case). In `ONE_TO_ONE_TESTS` (`run_test_gates.sh:33`).
- `send_delivery_receipt_use_case_test.dart` (6 tests) — covers the sender + mint-decision truth table. No change needed (sender unedited). In `ONE_TO_ONE_TESTS`.
- `inbox_round_trip_test.dart` / `p2p_service_impl_test.dart` — drive the real `_replayStagedInboxEntries` with fakes; the host seam for the end-to-end "drain does not block on receipt sends" proof. Both in `ONE_TO_ONE_TESTS`.

Missing coverage gaps: fire-and-forget contract (use case returns before the receipt send completes); eventual-send preservation; deferred-send error still caught (no unhandled async); decision still synchronous/per-message; dup re-mint sites also deferred; confirmatory direct/LAN still sent; **end-to-end: the drain loop completes even when receipt sends never ack**.
Already in curated family arrays?: ALL target files are in `ONE_TO_ONE_TESTS` — no array edit needed.

---

## RED Test Catalog  (add BEFORE any production code — INV-RED-FIRST)

1. `handle_incoming_chat_message_use_case_test.dart::delivery-receipt send is fire-and-forget — handleIncomingChatMessage returns before the receipt send completes`
   - Tier: unit/application
   - Shape/setup: inject `sendDeliveryReceipt: (_) => Completer<void>().future` (NEVER completes), `transport: 'inbox'` (mint path), a fresh non-duplicate payload. `await handleIncomingChatMessage(...).timeout(const Duration(seconds: 2))`. Assert it returns the success result (the inserted/received `HandleChatMessageResult` value) while the receipt future is still pending, and the hook was invoked exactly once.
   - RED on HEAD because: HEAD awaits `:116`, so the call never completes → `TimeoutException` → test fails.
   - GREEN after fix asserts: returns the success result; hook invoked once; no timeout.
   - Mutation that re-reds: restore `await sendDeliveryReceipt(messageId)` at `:116` → re-red (timeout).

2. `…::deferred delivery receipt is still sent exactly once after persist`
   - Tier: unit/application
   - Shape/setup: inject `sendDeliveryReceipt: (id) async => receiptIds.add(id)`, `transport: 'inbox'`; `await handleIncomingChatMessage(...)`; then `await pumpEventQueue()` (drain microtasks). Assert `receiptIds == [payload.id]`.
   - RED on HEAD because: n/a — passes on HEAD (synchronous fake adds before return). This is the **eventual-send preservation lock**.
   - GREEN after fix asserts: still sent once.
   - Mutation that re-reds: drop the `sendDeliveryReceipt(messageId)` call entirely (no scheduled send) → `receiptIds` empty → re-red.

3. `…::a deferred receipt send that throws is caught and logged, not unhandled`
   - Tier: unit/application
   - Shape/setup: inject `sendDeliveryReceipt: (_) async { throw StateError('boom'); }`, `transport: 'inbox'`; capture flow events via `debugSetFlowEventSink` (SYNC teardown — see [[feedback_testwidgets_sync_io_only]]); `await handleIncomingChatMessage(...)`; `await pumpEventQueue()`. Assert a `DELIVERY_RECEIPT_HOOK_ERROR` event is present AND the test zone reports **no unhandled async error**.
   - RED on HEAD because: n/a — passes on HEAD (awaited try/catch emits the event). This is the **fix-risk lock** (the unawaited future must keep its error handler).
   - GREEN after fix asserts: `DELIVERY_RECEIPT_HOOK_ERROR` present; no unhandled exception.
   - Mutation that re-reds: drop the `.catchError(...)` on the unawaited send → unhandled async error fails the zone / event absent → re-red.

4. `…::mint decision stays synchronous and on-path — skip emits MINT_SKIPPED and schedules no send`
   - Tier: unit/application
   - Shape/setup: `confirmatoryDirectLanEnabled: false`, `transport: null` (non-inbox, no staged id), inject recording hook; capture events; `await handleIncomingChatMessage(...)`; `await pumpEventQueue()`. Assert `DELIVERY_RECEIPT_MINT_SKIPPED` (reason `nonInbox`) present AND `receiptIds` empty.
   - RED on HEAD because: n/a — passes on HEAD. **Over-detach lock**: proves the decision was not deferred/hoisted along with the send.
   - GREEN after fix asserts: skip path unchanged.
   - Mutation that re-reds: move the decision off-path (compute it inside the deferred future) → `MINT_SKIPPED` emitted late/absent or a send is scheduled despite skip → re-red.
   - Distinct-event discriminator: assert `DELIVERY_RECEIPT_MINT_SKIPPED` AND NOT `DELIVERY_RECEIPT_SENT`/hook-invoked.

5. `…::duplicate-receive re-mint is also fire-and-forget`
   - Tier: unit/application
   - Shape/setup: pre-persist a message (existing row), then deliver a duplicate (same id) with `sendDeliveryReceipt: (_) => Completer<void>().future`, `transport: 'inbox'`; `await handleIncomingChatMessage(...).timeout(const Duration(seconds: 2))`. Assert it returns `HandleChatMessageResult.duplicate` while the hook future is pending.
   - RED on HEAD because: dup re-mint site `:342` awaits → blocks → timeout.
   - GREEN after fix asserts: returns `duplicate`, non-blocking. (Covers `:342/:427/:449` — all share the closure.)
   - Mutation that re-reds: restore `await` at `:116` → re-red (the dup path blocks again).

6. `…::confirmatory direct/LAN receipt is deferred but still sent (not suppressed)`
   - Tier: unit/application
   - Shape/setup: default flag (true), `stagedEntryId: 'direct:abc'`, inject recording hook; `await handleIncomingChatMessage(...)`; `await pumpEventQueue()`. Assert `receiptIds == [payload.id]` (sent) AND no `DELIVERY_RECEIPT_MINT_SKIPPED`.
   - RED on HEAD because: n/a — passes on HEAD. **INV-2 lock** (132 stuck-clock fix): the deferral must not become a suppression.
   - GREEN after fix asserts: direct/LAN receipt still sent.
   - Mutation that re-reds: add a `direct:`/`lan:` short-circuit that skips the send → `receiptIds` empty → re-red.

7. `inbox_round_trip_test.dart::drain replays all entries without blocking on receipt sends`  *(PROD-CRITICAL end-to-end leg)*
   - Tier: integration/host (real `_replayStagedInboxEntries` + fakes)
   - Shape/setup: stage N (≥3) chat inbox entries; wire the chat replay path to the **real** `handleIncomingChatMessage` with the production receipt hook backed by a `FakeP2PService` whose `sendMessageWithReply` returns a never-acking / never-completing future (and `storeInInbox` likewise gated). Run `drainOfflineInbox()` (or `_replayStagedInboxEntries`) under `.timeout(const Duration(seconds: 5))`. Assert the drain completes and all N entries are replayed/committed.
   - RED on HEAD because: each entry's awaited receipt send blocks the loop on the gated `sendMessageWithReply` → the drain never completes → timeout.
   - GREEN after fix asserts: drain completes; all N committed; receipt sends remain pending (detached).
   - Mutation that re-reds: restore `await` at `:116` → re-red (drain hangs).
   - Stop-if (wiring): if this file's harness injects a *fake* chat-replay callback (so the real handler's receipt await is not exercised), the test proves nothing — move it to `p2p_service_impl_test.dart` with the real handler injected, or assert at the handler tier (TC-01 already proves the per-message unblock that the loop awaits). Confirm the harness wires the real handler before trusting GREEN.

## Test Coverage Matrix  (ZERO empty cells)

| Spec case | Behavior props | Tier | Test file::name | RED reason on HEAD | Mutation revert | Acceptance gate cmd | Harness registration |
|---|---|---|---|---|---|---|---|
| TC-01 fire-and-forget | async / non-blocking | unit | handle_incoming_chat_message_use_case_test.dart::receipt send is fire-and-forget | HEAD awaits `:116` → call never completes (timeout) | restore `await` at `:116` | `./scripts/run_test_gates.sh 1to1` | AUTO + in `ONE_TO_ONE_TESTS` (`run_test_gates.sh:33`) |
| TC-02 eventual send | preservation | unit | …::deferred receipt still sent exactly once | n/a (HEAD green) — send-preservation lock | drop the `sendDeliveryReceipt(...)` call | `./scripts/run_test_gates.sh 1to1` | AUTO + array |
| TC-03 error caught | fix-risk lock | unit | …::deferred throw caught, not unhandled | n/a (HEAD green) — locks `.catchError` on the unawaited future | drop `.catchError` → unhandled async | `./scripts/run_test_gates.sh 1to1` | AUTO + array |
| TC-04 decision on-path | preservation/INV | unit | …::skip emits MINT_SKIPPED, schedules no send | n/a (HEAD green) — over-detach lock | compute decision inside the deferred future | `./scripts/run_test_gates.sh 1to1` | AUTO + array |
| TC-05 dup re-mint deferred | async / non-blocking | unit | …::duplicate-receive re-mint is fire-and-forget | dup site `:342` awaits → timeout | restore `await` at `:116` | `./scripts/run_test_gates.sh 1to1` | AUTO + array |
| TC-06 confirmatory still sent | preservation/INV-2 | unit | …::direct/LAN receipt deferred but still sent | n/a (HEAD green) — 132 anti-suppression lock | add direct/lan skip of the send | `./scripts/run_test_gates.sh 1to1` | AUTO + array |
| TC-07 drain non-blocking | end-to-end (PROD-CRITICAL) | integration/host | inbox_round_trip_test.dart::drain replays all without blocking on receipts | HEAD awaits per-entry receipt → drain hangs (timeout) | restore `await` at `:116` | `./scripts/run_test_gates.sh 1to1` | AUTO (`test/core/**`) + `inbox_round_trip_test.dart` in `ONE_TO_ONE_TESTS` |

## Invariants (locked by tests)
- INV-1: the use case (and therefore the serial replay loop) does not block on the delivery-receipt network send → TC-01, TC-05, TC-07.
- INV-2: the confirmatory direct/LAN receipt is deferred, never suppressed (132 stuck-pending-clock fix preserved) → TC-06.
- INV-3: the mint decision stays synchronous + per-message; `MINT_SKIPPED` still emits on skip → TC-04.
- INV-4: deferred-send errors are caught + logged; no unhandled async error → TC-03.
- INV-5: the receipt is still sent exactly once per mint → TC-02.
- INV-RED-FIRST and INV-MUTATION-VERIFIED apply to every row above.

## Step-By-Step Implementation Plan
1. **RED first.** Add TC-01..06 to `handle_incoming_chat_message_use_case_test.dart` and TC-07 to `inbox_round_trip_test.dart`. Run the focused commands (Acceptance Gates §1); confirm TC-01/05/07 fail by **timeout** and TC-02/03/04/06 pass on HEAD (they are preservation/over-detach locks — verify their mutations re-red after the fix). Stop-if any timing RED actually passes on HEAD → the await is not where the plan says; re-verify `:116`.
2. **The fix** — `handle_incoming_chat_message_use_case.dart`, closure `maybeSendDeliveryReceipt` (`:115-126`). Replace:
   ```dart
   try {
     await sendDeliveryReceipt(messageId);
   } catch (e) {
     emitFlowEvent(layer: 'FL', event: 'DELIVERY_RECEIPT_HOOK_ERROR', details: {...});
   }
   ```
   with:
   ```dart
   unawaited(
     sendDeliveryReceipt(messageId).catchError((Object e) {
       emitFlowEvent(layer: 'FL', event: 'DELIVERY_RECEIPT_HOOK_ERROR', details: {
         'id': messageId.length > 8 ? messageId.substring(0, 8) : messageId,
         'error': e.toString(),
       });
     }),
   );
   ```
   Keep the null-check + `deliveryReceiptMintDecision` + `MINT_SKIPPED` emission (`:94-114`) exactly as-is and synchronous. Add `import 'dart:async';` if `unawaited` is not already in scope. Leave the four call sites (`:342/:427/:449/:510`) as `await maybeSendDeliveryReceipt(...)` (the closure now returns after scheduling — minimal diff).
3. **GREEN** — run the direct test files; confirm TC-01/05/07 flip green and TC-02/03/04/06 stay green.
4. **Mutation pass** — for each row, apply the named revert, confirm the test re-reds, restore.
5. **Preservation + named gates** — run the sentinels (Acceptance Gates §3). Stop-if any existing receipt test (e.g. the L2053 "invokes after persist… re-invokes on duplicate") goes red: a synchronous fake hook adds before return so it should stay green; if one asserts await-blocking timing, add `await pumpEventQueue()` after the awaited call (the only legitimate test edit). Do NOT weaken a production assertion to make a test pass.

## Risks And Edge Cases
- **Unhandled async error** from the now-unawaited send → pinned by TC-03 (`.catchError`).
- **Existing synchronous-fake receipt tests** asserting `receiptIds` right after the call → stay green because `(id) async => receiptIds.add(id)` runs the `.add` synchronously before its first suspension; only a test asserting the use case *blocked* on the send needs a `pumpEventQueue()` (documented in step 5).
- **Test lifetime / pending timers** — the detached send must complete or be drained within the test; fakes that never complete (TC-01/05/07) are fine because the assertions don't await them, but ensure no `expectAsync`/pending-timer guard trips (use plain `Completer` futures, not `Timer`s).
- **Decision/skip reorder** if someone later unawaits the whole closure → pinned by TC-04.
- **Confirmatory receipt accidentally suppressed** (132 regression) → pinned by TC-06.

## Device/Relay Proof Profile
**host-only for closure.** The change is pure async restructuring strictly *after* decrypt+persist and *before* a network send whose result is already ignored — no OS callback, no migration, no ML-KEM, no multi-device, no real-relay behavior changes. All seven TCs are deterministic at host tier with fakes.
Non-blocking device verification (follow-up, not a closure gate): on a warm-resume notif-tap with several queued messages, confirm the conversation list refreshes as soon as messages persist, and `DELIVERY_RECEIPT_SENT` events still appear (just after the render) in the device log. Pairs naturally with the 145 "catching up" affordance device check.

## Acceptance Gates  (literal — copy/paste)
```bash
# 0) Baseline snapshot (so preservation counts are interpretable)
git status --short

# 1) RED (before production edit) — TC-01/05/07 must FAIL by timeout; TC-02/03/04/06 pass on HEAD
flutter test test/features/conversation/application/handle_incoming_chat_message_use_case_test.dart \
  --plain-name 'receipt send is fire-and-forget'
flutter test test/features/conversation/application/handle_incoming_chat_message_use_case_test.dart \
  --plain-name 'duplicate-receive re-mint is fire-and-forget'
flutter test test/core/inbox/inbox_round_trip_test.dart \
  --plain-name 'without blocking on receipt sends'

# 2) Direct GREEN (after fix) — whole files
flutter test test/features/conversation/application/handle_incoming_chat_message_use_case_test.dart
flutter test test/features/conversation/application/send_delivery_receipt_use_case_test.dart
flutter test test/core/inbox/inbox_round_trip_test.dart
flutter test test/core/services/p2p_service_impl_test.dart

# 3) Preservation sentinels (must stay green — record baseline counts, expect 0 new failures)
./scripts/run_test_gates.sh 1to1                 # all target files live here; expect baseline_total + new, 0 regressions

# 4) Hygiene
flutter analyze            # 0 new issues
git diff --check
```
> Expected count deltas: `handle_incoming_chat_message_use_case_test.dart` 53 → 59 (+TC-01..06); `inbox_round_trip_test.dart` +1 (TC-07). Record exact suite totals from the baseline run; preservation = baseline_total + new, 0 regressions.

## Known-Failure Interpretation
- Expected RED: TC-01, TC-05, TC-07 before the fix (timeout). TC-02/03/04/06 are green-on-HEAD locks; their mutations must re-red after the fix.
- Pre-existing dirty: the `new-feed` tree carries uncommitted work; capture `git status --short` first and do not revert unrelated files.
- Environment blocker (NOT product): none — no sim/device rows.
- Scope drift (BLOCKING): any failure in the mint-decision truth-table tests (`send_delivery_receipt_use_case_test.dart`), the group receipt suites, or message persistence/dedupe tests → stop and replan (you changed more than the send detachment).

## Done Criteria
- [x] RED added first; TC-01/05/07 failed by timeout for the expected reason.
- [x] Mutation-verified (each row has a re-red revert; TC-04's catchable mutation is "schedule-send-despite-skip" — see Execution log note).
- [x] Direct GREEN + `1to1` preservation gate pass (1120), 0 regressions.
- [x] No migration (confirm: no `DB v##` touched).
- [x] Confirmatory direct/LAN receipt still sent (TC-06 green); `MINT_SKIPPED` still synchronous/on-path (TC-04 green).
- [x] `flutter analyze` 0 new; `git diff --check` clean; no Scope Guard violations.

## Scope Guard (hard "Do not")
- Do not touch `send_delivery_receipt_use_case.dart` (the sender, the mint-decision truth table, the no-retry policy, the confirmatory flag) — only the **await** in the handler closure changes.
- Do not `unawaited(...)` the four call sites; detach only the network send inside the closure (keep the decision synchronous).
- Do not suppress the direct/LAN/non-inbox receipt; defer it.
- Do not parallelize the replay loop here → plan 147.
- Do not touch group delivery receipts.

## Accepted Differences / Intentionally Out Of Scope
- Replay parallelization / decrypt fan-out → plan **147** owns it (the larger latency lever).
- Non-blocking route + "catching up" affordance + drain telemetry → plan **145** owns it.
- A production analytics sink for the `DELIVERY_RECEIPT_*` / drain-timing events → future telemetry session (per 145).

## Dependency Impact
- Independent of 145 (no shared files edited; 145 touches `prepare_notification_open` + `conversation_wired` + telemetry, this touches the handler closure). Can land before or after 145.
- Complementary to 147: 146 removes the receipt round-trip from each serial iteration; 147 then overlaps the decrypt round-trips across iterations. Landing 146 first shrinks the per-iteration cost 147 parallelizes, and de-risks 147 (fewer awaited network hops inside the loop).

## Reviewer Findings
3-lens adversarial review workflow (correctness / test-integrity / scope-regression), 10 agents, each finding independently verified (default-refute). **Zero defects in the production change.** 7 candidate findings → 5 "confirmed", but 3 of those (TC-01/03/07) were positive confirmations (the tests are correct + load-bearing) and the 2 refuted were non-issues. Two actionable test-quality items, both FIXED:
- **TC-02 strengthened (was: could not distinguish "hook invoked" from "receiptIds populated by another path").** Added explicit `hookInvocations` counter + `expect(hookInvocations, 1)`. Re-verified: mutation B (drop send) now re-reds with the precise reason `the receipt send hook was invoked exactly once: Expected <1> Actual <0>`.
- **TC-04 comment corrected (was: claimed it observes a microtask-deferred decision, which is impossible).** Comment now states the real load-bearing lock: a skip schedules NO send (`receiptIds` empty) + MINT_SKIPPED present; catchable mutation = "schedule a send despite skip" (mutation D′).
- Refuted: "TC-04 receiptIds assertion is load-bearing but comment overstates scope" (addressed by the comment fix); "missing flow-sink tearDown in TC-02/04" (TC-02 uses no sink; TC-04 has `addTearDown(() => debugSetFlowEventSink(null))`).
- Scope-guard verified clean: only the 3 named files changed; `send_delivery_receipt_use_case.dart`, group-receipt code, and `main.dart` wiring untouched.

### Post-review hardening (2nd pass — 2 external findings, both valid, both FIXED)
- **HIGH — TC-07 was a false green.** The fixture chat ids were `m-fnf-N` (7 chars), but the handler's `CHAT_MSG_RECEIVE_STORED` emit does an UNGUARDED `payload.id.substring(0, 8)` (handle_incoming_chat_message_use_case.dart:566) → the real handler threw `RangeError` AFTER persist, the drain caught it as `P2P_SERVICE_INBOX_STAGED_REPLAY_EXCEPTION` (p2p_service_impl.dart:1260), `replayed` stayed 0 — yet the test passed (it only checked callback counts + persisted rows, both of which happen before the throw). Prod is unaffected (real ids are UUIDs). **Fix:** valid-length ids (`msg-fnf-00N`) + strengthened assertions — TC-07 now wraps the drain in `_captureFlowEvents` and asserts `P2P_SERVICE_INBOX_STAGED_CHAT_COMMITTED` count == N AND zero `..._REPLAY_EXCEPTION`. Proven: short-ids+strong-asserts → committed=0 FAIL; valid-ids → committed=3 PASS. Still RED-on-HEAD by timeout (mutation A).
- **MEDIUM — sync-throwing receipt hook escaped.** `sendDeliveryReceipt(messageId).catchError(...)` only attaches to the returned Future; a hook that throws SYNCHRONOUSLY (before returning) bypassed `.catchError` and threw out of the handler after persist (the old `try { await ... } catch` caught both). **Fix:** `unawaited(Future.sync(() => sendDeliveryReceipt(messageId)).catchError(...))` — the established 145 idiom. Added **TC-08** (sync-throw hook): proven RED on `.catchError`-only ("Bad state: boom-sync" escapes), GREEN after `Future.sync`. Mutation C (drop `.catchError`) now re-reds BOTH TC-03 (async) and TC-08 (sync).

## Arbiter Decision
Structural blockers: none (host-only, no migration, all files already gated). | Deferred details: exact preservation counts (record at execution); TC-07 harness-wiring confirmation. | Accepted differences: 147/145 + telemetry sink deferred as listed.

## Final Execution Verdict
Verdict: **IMPLEMENTED, host-green (reviewed + post-review-hardened).** | Files changed: `lib/features/conversation/application/handle_incoming_chat_message_use_case.dart` (prod: +`import 'dart:async'`, `await sendDeliveryReceipt`→`unawaited(Future.sync(() => sendDeliveryReceipt(messageId)).catchError(...))`), `test/features/conversation/application/handle_incoming_chat_message_use_case_test.dart` (+TC-01..06, +TC-08 sync-throw), `test/core/services/p2p_service_impl_test.dart` (+TC-07 with committed-count + no-exception asserts). | Tests run: TC-01/05/07 RED-first by timeout on HEAD, TC-08 RED on `.catchError`-only; all 8 mutation-verified (restore-await→TC-01/05/07, drop-send→TC-02, drop-catchError→TC-03+TC-08, schedule-send-despite-skip→TC-04, direct/lan-skip→TC-06); `./scripts/run_test_gates.sh 1to1` → **1121 passed, 0 regressions**; `flutter analyze` 0 new; `git diff --check` clean; no DB migration. | Blocking: **none.** | QA verdict: 3-lens adversarial review — zero production defects; two test-quality items fixed (TC-02 invocation tracking, TC-04 comment accuracy). | Non-blocking follow-ups (owner): device verify of perceived latency on warm-resume notif-tap (confirm list refreshes as messages persist + `DELIVERY_RECEIPT_SENT` still appears just after render) — pairs with 145's "catching up" affordance device check.
