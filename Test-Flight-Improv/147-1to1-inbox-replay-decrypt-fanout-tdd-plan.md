# 147 - 1:1 Inbox Replay: bounded decrypt fan-out, commit stays serial-in-order  (Feature Improvement)

Status: IMPLEMENTED host-green (2026-06-23) — uncommitted on `new-feed`
Spec: free-text intent (no formal spec) — derived from `Test-Flight-Improv/notification-tap-to-message-load-delay-investigation.md` (the replay-parallelization half of the p2p-performance work carved out of plan 145 at `145:69` / `145:292`)

## Planning Progress
| Time | Role | Files inspected | Decision/blocker | Next action |
|---|---|---|---|---|
| 2026-06-23 | Evidence Collector | p2p_service_impl.dart (`_replayStagedInboxEntries` 1060-1095, `_applyRecoveredInboxOutcome` 1305), handle_incoming_chat_message_use_case.dart (decrypt 164/188, edit/dedupe arms), drain_group_offline_inbox_use_case.dart (bounded-worker pattern 70/108/167), go-mknoon/crypto/decrypt.go (24-77), bridge/bridge.go (181), GoBridge.swift/.kt threading | Decrypt is **stateless ML-KEM-768 + AES-GCM** (no ratchet/prekey/counter), idempotent, order-independent, runs on genuinely concurrent native threads → fan-out SAFE & worthwhile. Commit/persist MUST stay serial-in-order per conversation. Native pools unbounded → fan-out must be bounded. | Build matrix |
| 2026-06-23 | Planner | tier-matrix.md, plan-template.md | 8 TCs (unit floor + integration concurrency/ordering + PROD-CRITICAL deadlock-on-serial end-to-end); all target files already in `ONE_TO_ONE_TESTS` | Emit plan |
| 2026-06-23 | Reviewer (sufficiency) | sufficiency-checklist.md | zero-empty-cell matrix; concurrency proven by a serial-deadlock RED (TC-A7), not just a wrong-impl mutation; ordering invariants locked with distinct flow-event discriminators | — |
| 2026-06-23 | Arbiter | — | host-only closure; the decrypt-injection seam is the named execution risk with a fallback | hand off to execution |

## Execution Progress
| Time | Phase | Files touched | Command/evidence | Decision/blocker | Next |
|---|---|---|---|---|---|
| 2026-06-23 | contract extraction | — | `git status --short` (new-feed dirty w/ 144/145/146) | scope confirmed; all target files in `ONE_TO_ONE_TESTS` | RED |
| 2026-06-23 | RED tests added | p2p_service_impl_test (+5: TC-A1/A2/A4/A5/A7), handle_incoming…_test (+2: TC-A3/A6) | compile-fail: "No named parameter 'predecryptedText'" / missing `predecryptInboxChatEntry`/`maxConcurrentInboxDecrypts` | RED for expected reason (new API absent) | implement |
| 2026-06-23 | implementation | chat_message.dart, handle_incoming_chat_message_use_case.dart, chat_message_listener.dart, p2p_service_impl.dart, main.dart | — | **DESIGN DEVIATION**: threaded plaintext via a transient `ChatMessage.predecryptedText` field (mirrors `transport`/`confirmNonce`) NOT the typedef — extending the shared `ReplayRecoveredInboxChatMessage` typedef would break **55** callback literals (Dart adds-named-param subtyping break, proven empirically). Handler still gains the `predecryptedText` param (TC-A6). Decrypt refactored into shared event-free `_decryptV2ChatEnvelope` (no second copy of the ML-KEM ring) + public `predecryptIncomingChatEnvelope`. | direct GREEN |
| 2026-06-23 | direct GREEN | — | handler 147 +2 GREEN; p2p 147 group +5 GREEN; full p2p file 84/84; handler full 55; disposition; inbox_round_trip 87-combined | reds now green | mutations |
| 2026-06-23 | mutation pass | (reverted) | bound=1→A1(==1)/A5(peak==1)/A7(deadlock) red; `entries.reversed`→A2 red; drop-on-omit→A4 red; ignore-param→A6+A3 red. ALL 7 reverted. | each row re-reds | preservation |
| 2026-06-23 | preservation + gate | — | `./scripts/run_test_gates.sh 1to1` → **+1128 All tests passed** (077 custody + disposition + dedupe + round-trip in gate) | sentinels green, 0 reg | hygiene |
| 2026-06-23 | hygiene | — | `flutter analyze` 0 new err/warn (3 pre-existing handler warnings predate session; test info-lints cleaned to `_,_`); `git diff --check` clean; `graphify update` rebuilt | clean | QA |
| 2026-06-23 | QA (independent) | handle_incoming_chat_message_use_case.dart (+ test) | 4-lens adversarial review (concurrency / decrypt-fidelity / ordering-scope / model-field) → verify → arbiter = **SHIP**, 0 blocker/major. 1 nit FIXED: `MLKEM_RING_FALLBACK_USED` dropped on prefetch-hit ring recovery → `predecryptIncomingChatEnvelope` now emits it (1 new test, mutation-verified). | blocking: none | DONE |

## Source Of Truth
- Spec / intent: inline below + `Test-Flight-Improv/notification-tap-to-message-load-delay-investigation.md`
- Gate definitions: `scripts/run_test_gates.sh` (script wins over prose)
- Discovery/registration: `scripts/check_reliability_simulation_discovery.sh` (NOT used — no sim/device rows)
- Numbering / index: `Test-Flight-Improv/00-INDEX.md` (next-free after 146 = 147)

## Session Classification
implementation-ready (with one named seam risk — see Arbiter / Stop-Ifs)

---

## Exact Problem Statement

The relay inbox drain replays staged entries **serially**: `p2p_service_impl.dart:1070` `for (final entry in entries)` awaits `chatReplay(message, stagedEntryId: ...)` (`:1092`) fully — decrypt → dedupe → persist → (deferred, after 146) receipt — before starting the next entry. The expensive, independent part of each iteration is the **decrypt bridge round-trip** (`handle_incoming_chat_message_use_case.dart:164` `callDecryptMessage`, fallback ring `:188` → Go `crypto/decrypt.go`). For N drained messages this is N **serial** decrypt round-trips of wall-clock before the screen reload (`conversation_wired.dart:1211/1213` reloads once at the end of the whole drain). On a notif-tap that surfaces several queued messages from one peer, the user waits through all N serial decrypts.

Decrypt is provably independent and parallelizable: `crypto/decrypt.go:24-77` is a pure function — it unmarshals the recipient's **static** ML-KEM-768 secret key fresh per call, decapsulates the per-message KEM ciphertext, and AES-GCM-opens the body. **No double-ratchet, no one-time-prekey consumption, no monotonic counter, no nonce window, no persisted/in-memory mutation.** Decrypting two ciphertexts from the same peer concurrently or out of order is safe and idempotent. The Go bridge decrypt path takes **no `nodeMu`** (`bridge/bridge.go:181`) and runs on genuinely concurrent native threads (iOS global concurrent queue `GoBridge.swift:36`; Android cached thread pool `GoBridge.kt:31/42`), so fan-out uses real cores rather than queueing.

**What must improve:** the per-message **decrypt** is fanned out with **bounded** concurrency so N decrypt round-trips overlap instead of serializing, while the **commit/persist** step stays exactly as it is — serial and in arrival order.

**What must stay unchanged (→ preserved-green sentinels):** commit/persist order per conversation (edits, reactions, deletions depend on their target message already being committed); the stage→ack→replay boundary including the Move-account migration gate re-check at the ack boundary (`p2p_service_impl.dart:1505/1517/1543`); the per-entry disposition state machine (`_applyRecoveredInboxOutcome:1305`, attempt-cap→quarantine `:1334`); dedupe/idempotency (id, dedupKey, content); transient-decrypt → retryable/quarantine behavior; concurrency must be **bounded** (the native pools are unbounded — never spawn a thread per inbox entry).

## Root Cause (verify → refute confirmed)
- **Mechanism (verified):** serial loop `p2p_service_impl.dart:1070`, awaited `chatReplay` `:1092`; the decrypt it transitively awaits is `handle_incoming_chat_message_use_case.dart:164` (`callDecryptMessage`) + fallback `:188`. Reload-once-at-end `conversation_wired.dart:1211/1213`.
- **Refute → fan-out is SAFE (survived, source-proven):** encryption model is stateless per-message ML-KEM-768 + AES-GCM (`crypto/decrypt.go:24-77`); no mutable decrypt state anywhere on the path; bridge decrypt is lock-free + thread-concurrent on both platforms (`bridge/bridge.go:181`, `GoBridge.swift:36`, `GoBridge.kt:31/42`). Idempotent and order-independent ⇒ concurrent/out-of-order decrypt cannot corrupt state.
- **Refute → commit MUST stay serial-in-order (survived):** the chat arm carries edit semantics (`editedAt`/`quotedMessageId`, last-writer-wins vs the committed row); the reaction arm (`handle_incoming_reaction_use_case.dart` `saveReaction`) and deletion arm (tombstone `saveMessage`) target a message that must already be committed; out-of-order commit ⇒ orphan reaction / edit-missing-original / tombstone-before-message. The SQLCipher single write-lock would also contend if commits ran concurrently (the group drain flags the 10s "database has been locked" warning, `drain_group_offline_inbox_use_case.dart:865-873`). So **only decrypt fans out; commit stays serial-in-order.**

Refuted / do-NOT-re-introduce:
- "Parallelize the whole iteration (decrypt + commit) with per-peer buckets" — **rejected as the primary design**: it gives **zero** benefit in the motivating case (notif-tap is usually a single peer → one bucket → serial) and re-introduces the SQLCipher write-lock contention the group code warns about. Decrypt-prefetch helps even within ONE conversation. (Per-peer buckets remain a possible *additional* lever for multi-peer backlogs — out of scope here.)
- "Decrypt advances a ratchet, so out-of-order is unsafe" — **refuted from source**: `crypto/decrypt.go` is a pure static-key KEM decapsulation, not a ratchet.
- "Fan-out is pointless because the bridge serializes on a mutex" — **refuted**: decrypt takes no `nodeMu` and runs on concurrent native threads.

## Design Decision — decrypt-prefetch funneled into the unchanged serial commit loop
1. Add a **bounded-concurrent pre-decrypt pass** in `_replayStagedInboxEntries`, BEFORE the existing serial loop, that decrypts the page's `chat_message` entries via an injected decrypt function, building `Map<entryId, String plaintext>`. Bound concurrency with a new const `maxConcurrentInboxDecrypts` (e.g. 6), reusing the bounded-worker pattern already in `drain_group_offline_inbox_use_case.dart:108` (`drainNext…` index-counter workers + `Future.wait`). A prefetch decrypt failure (transient or wrong-key) simply OMITS that entry from the map (no throw escapes).
2. Thread the prefetched plaintext into the **existing** serial loop unchanged: extend the `ReplayRecoveredInboxChatMessage` typedef and `handleIncomingChatMessage` with an **optional** `String? predecryptedText`. When present, `handleIncomingChatMessage` skips `callDecryptMessage` (`:164`) and uses the supplied plaintext; when absent (default), it decrypts itself exactly as today (the fallback path for omitted/failed prefetch entries, and the gate-off default).
3. **Gate by injection:** the decrypt function is injected into the p2p service (wired in `main.dart` to the same bridge decrypt + ML-KEM fallback ring that `handleIncomingChatMessage` uses). When it is `null` (the default), no prefetch runs and behavior is byte-identical to HEAD — a safe default-off path and a clean test seam.
4. The serial commit loop (`chatReplay` → `saveMessage` / reaction / deletion + `_applyRecoveredInboxOutcome`) and all disposition/ordering logic are **untouched**.

## Real Scope
**In scope:**
- `p2p_service_impl.dart`: new bounded-concurrent `_predecryptInboxChatEntries(entries)` pass invoked at the top of `_replayStagedInboxEntries` (`:1060`) when the injected decrypt fn is present; pass the resulting plaintext into each `chatReplay` call (`:1092`); new const `maxConcurrentInboxDecrypts`; new optional injected `Future<String?> Function(ChatMessage) predecryptInboxChatEntry` (default null).
- The `ReplayRecoveredInboxChatMessage` typedef + `chat_message_listener.dart` replay wiring + `handleIncomingChatMessage`: additive optional `String? predecryptedText` that short-circuits `callDecryptMessage` when supplied.
- `main.dart`: wire `predecryptInboxChatEntry` to the existing bridge decrypt + fallback ring.

**Out of scope (owning work):**
- Deferring the delivery-receipt send → plan **146** (land first; it removes the *other* awaited network hop from each iteration).
- Per-peer/per-conversation bucket parallelism for multi-peer backlogs → future p2p-performance follow-up.
- Group within-group replay parallelization (`drain_group_offline_inbox_use_case.dart:875`) — cross-group is already parallel; within-group is a separate effort.
- The non-blocking route + affordance + telemetry → plan **145**.
- Any change to the decrypt **crypto**, the stage→ack boundary, the disposition state machine, or dedupe.

## Files To Inspect Next
Production: `lib/core/services/p2p_service_impl.dart` (`_replayStagedInboxEntries` 1060-1115, `_applyRecoveredInboxOutcome` 1305-1383, retrieve/ack boundary 1505/1517/1543); `lib/features/conversation/application/handle_incoming_chat_message_use_case.dart` (decrypt 164/188, edit arm 359-390, dedupe 406-453); `lib/features/conversation/application/chat_message_listener.dart` (replay callback wiring); `lib/features/groups/application/drain_group_offline_inbox_use_case.dart` (bounded-worker pattern 108-167, write-lock caveat 865-873 — reference only); `lib/main.dart` (decrypt wiring).
Direct tests: `test/core/services/p2p_service_impl_test.dart`; `test/core/inbox/inbox_round_trip_test.dart`; `test/features/conversation/application/handle_incoming_chat_message_use_case_test.dart`; `test/features/conversation/application/recovered_inbox_chat_disposition_test.dart`.
Dependency-only context: `go-mknoon/crypto/decrypt.go` (proves statelessness — not edited).

## Existing Tests Covering This Area
- `p2p_service_impl_test.dart` — drives the real `_replayStagedInboxEntries` with a fake bridge/replay callback. **MISSING:** any concurrency or prefetch coverage. In `ONE_TO_ONE_TESTS` (`run_test_gates.sh`).
- `inbox_round_trip_test.dart` — end-to-end stage→ack→replay with fakes + real migrations. **MISSING:** decrypt-overlap behavior. In `ONE_TO_ONE_TESTS`.
- `recovered_inbox_chat_disposition_test.dart` — per-entry commit/retryable/rejected/quarantine dispositions. The preservation anchor for the disposition state machine. In `ONE_TO_ONE_TESTS`.
- `handle_incoming_chat_message_use_case_test.dart` (53 tests) — decrypt + edit + dedupe arms. **MISSING:** the `predecryptedText` skip path. In `ONE_TO_ONE_TESTS`.
- `test/core/database/migrations/077_message_relay_custody_test.dart` — the Move-account custody gate. Preservation anchor. In `ONE_TO_ONE_TESTS`.

Missing coverage gaps: bounded concurrent decrypt (>1 in flight, ≤ bound); commit stays in arrival order despite out-of-order decrypt; edit-after-original causal order; prefetch-failure fallback to in-handler decrypt; `predecryptedText` skip path; **end-to-end drain that cannot complete serially (deadlock-on-serial concurrency proof)**.
Already in curated family arrays?: ALL target files are in `ONE_TO_ONE_TESTS` — no array edit needed.

---

## RED Test Catalog  (add BEFORE any production code — INV-RED-FIRST)

1. `p2p_service_impl_test.dart::prefetch decrypts chat entries concurrently up to the bound`
   - Tier: integration/host (real `_replayStagedInboxEntries` + fake decrypt fn)
   - Shape/setup: stage N=6 chat entries; inject `predecryptInboxChatEntry` that increments a live counter on entry, records the max observed concurrent count, awaits a short release, decrements on exit. Run the drain. Assert `maxConcurrent == min(N, maxConcurrentInboxDecrypts)` and `> 1`.
   - RED on HEAD because: no prefetch exists; decrypt happens serially inside the loop → `maxConcurrent == 1` (and the injected fn is unused / param absent).
   - GREEN after fix asserts: `maxConcurrent` between 2 and the bound.
   - Mutation that re-reds: set the bound to 1 (or remove the prefetch pass) → `maxConcurrent == 1` → re-red.

2. `p2p_service_impl_test.dart::commit/persist stays in arrival order when decrypts finish out of order`
   - Tier: integration/host
   - Shape/setup: 3 entries [m1, m2, m3] (same peer); inject a decrypt fn that completes m3 first and m1 last (reverse completion). Assert the messages are saved/committed in **arrival** order (m1, m2, m3) — assert the order of `saveMessage` calls (spy repo) or the committed-event sequence.
   - RED on HEAD because: n/a — HEAD is serial-in-order. **Ordering invariant lock** (guards the fix against committing on decrypt-completion order).
   - GREEN after fix asserts: arrival order preserved.
   - Mutation that re-reds: commit in decrypt-completion order (e.g. `await Future.wait` then iterate completions) → m3-first → re-red.

3. `handle_incoming_chat_message_use_case_test.dart::edit applies after its base even when the edit decrypts first`
   - Tier: unit/application (drive two entries through the replay path)
   - Shape/setup: [m1 (base), m1-edit] same peer; prefetch completes the edit before the base. Assert the base is committed, then the edit materializes over it.
   - RED on HEAD because: n/a — HEAD serial. **Causal-order lock.**
   - GREEN after fix asserts: edit materializes correctly.
   - Mutation that re-reds: out-of-order commit (edit before base) → edit hits the missing-original path → re-red.
   - Distinct-event discriminator: assert `CHAT_MSG_RECEIVE_EDIT_MATERIALIZED` AND NOT `CHAT_MSG_RECEIVE_EDIT_MISSING_ORIGINAL`.

4. `p2p_service_impl_test.dart::a prefetch decrypt failure falls back to in-handler decrypt; disposition unchanged`
   - Tier: integration/host
   - Shape/setup: 2 entries; inject a prefetch fn that THROWS for entry X (omits it from the map) but succeeds for Y; the in-handler decrypt (fake) succeeds for X. Assert X is still committed (via the handler's own decrypt), Y via prefetch, and a genuinely-undecryptable entry still routes to its existing `retryable`/`quarantine` disposition.
   - RED on HEAD because: n/a (no prefetch). **Fallback lock.**
   - GREEN after fix asserts: prefetch failure does not drop or mis-dispose the entry.
   - Mutation that re-reds: make a prefetch failure drop the entry (skip it from the serial loop) → X lost → re-red.

5. `p2p_service_impl_test.dart::decrypt fan-out is bounded — in-flight never exceeds the cap for a large batch`
   - Tier: integration/host
   - Shape/setup: N=20 entries; the injected decrypt fn records peak concurrency. Assert peak ≤ `maxConcurrentInboxDecrypts`.
   - RED on HEAD because: n/a — HEAD peak is 1 (≤ cap). **Resource-safety lock** (the Android cached pool is unbounded; the fix must not spawn a thread per entry).
   - GREEN after fix asserts: peak ≤ cap for N ≫ cap.
   - Mutation that re-reds: remove the bound (decrypt all at once via `Future.wait` over the full list) → peak == N > cap → re-red.

6. `handle_incoming_chat_message_use_case_test.dart::uses predecryptedText when provided and does not call the bridge decrypt`
   - Tier: unit/application
   - Shape/setup: call `handleIncomingChatMessage(..., predecryptedText: 'hello')` with a `callDecryptMessage` fake that throws if invoked. Assert the message persists with text `'hello'` and the decrypt fake was never called.
   - RED on HEAD because: the `predecryptedText` parameter does not exist → won't compile (after scaffolding the param, it locks the skip).
   - GREEN after fix asserts: bridge decrypt skipped; supplied plaintext used.
   - Mutation that re-reds: ignore the param / still call `callDecryptMessage` → the throwing fake fires → re-red.

7. `inbox_round_trip_test.dart::drain of same-peer messages completes only because decrypts overlap`  *(PROD-CRITICAL concurrency proof — RED-on-HEAD by deadlock)*
   - Tier: integration/host (real drain + barrier-latch decrypt fn)
   - Shape/setup: stage N=3 same-peer chat entries; inject a decrypt fn backed by a **barrier latch** that only releases each waiter once **≥2 decrypts are simultaneously waiting** (e.g. a counting latch with target 2). Run the drain under `.timeout(const Duration(seconds: 5))`. Assert the drain completes and all N are committed in arrival order.
   - RED on HEAD because: HEAD decrypts serially — only ever 1 waiter — so the barrier (target 2) is never reached → the first decrypt blocks forever → drain deadlocks → timeout.
   - GREEN after fix asserts: the prefetch puts ≥2 decrypts at the barrier → it releases → drain completes; arrival order preserved.
   - Mutation that re-reds: remove the prefetch pass (or bound=1) → only 1 waiter → deadlock → re-red.
   - Stop-if (wiring): requires the real handler/decrypt path wired through the drain; if this file injects a fake replay callback that bypasses the prefetch, relocate to `p2p_service_impl_test.dart` where the prefetch pass is directly exercised. Confirm the barrier is reached (not a flaky time-based pass) before trusting GREEN.

8. `recovered_inbox_chat_disposition_test.dart` + `077_message_relay_custody_test.dart` + `inbox_round_trip_test.dart`::**preservation** — stage→ack→replay boundary, Move-account custody gate, per-entry disposition, and dedupe/idempotency unchanged
   - Tier: integration/host + migration host
   - Shape/setup: existing suites run unchanged.
   - RED on HEAD because: n/a — these pass today and must keep passing (the fix touches only decrypt scheduling, not the boundary/disposition/dedupe).
   - GREEN after fix asserts: all stay green, same counts.
   - Mutation that re-reds: if the prefetch pass moved decrypt past the ack boundary or altered disposition, these suites fail — the structural guard that the fix stayed within scope.

## Test Coverage Matrix  (ZERO empty cells)

| Spec case | Behavior props | Tier | Test file::name | RED reason on HEAD | Mutation revert | Acceptance gate cmd | Harness registration |
|---|---|---|---|---|---|---|---|
| TC-A1 concurrent decrypt | concurrency | integration/host | p2p_service_impl_test.dart::prefetch decrypts concurrently up to the bound | HEAD serial → maxConcurrent==1 | bound=1 / remove prefetch | `./scripts/run_test_gates.sh 1to1` | AUTO (`test/core/**`) + in `ONE_TO_ONE_TESTS` |
| TC-A2 commit order | ordering/INV | integration/host | p2p_service_impl_test.dart::commit stays in arrival order on out-of-order decrypt | n/a (HEAD green) — ordering lock | commit in decrypt-completion order | `./scripts/run_test_gates.sh 1to1` | AUTO + array |
| TC-A3 edit causal order | ordering/INV | unit | handle_incoming_chat_message_use_case_test.dart::edit applies after base when edit decrypts first | n/a (HEAD green) — causal lock | commit edit before base | `./scripts/run_test_gates.sh 1to1` | AUTO + array |
| TC-A4 prefetch-fail fallback | error/fallback | integration/host | p2p_service_impl_test.dart::prefetch failure falls back to in-handler decrypt | n/a (HEAD green) — fallback lock | drop entry on prefetch failure | `./scripts/run_test_gates.sh 1to1` | AUTO + array |
| TC-A5 bounded cap | resource safety | integration/host | p2p_service_impl_test.dart::fan-out bounded, in-flight ≤ cap | n/a (HEAD green) — resource lock | remove the bound (`Future.wait` all) | `./scripts/run_test_gates.sh 1to1` | AUTO + array |
| TC-A6 predecrypted skip | pure logic | unit | handle_incoming_chat_message_use_case_test.dart::uses predecryptedText, skips bridge decrypt | param absent → won't compile | ignore param / still decrypt | `./scripts/run_test_gates.sh 1to1` | AUTO + array |
| TC-A7 drain overlap (PROD-CRITICAL) | end-to-end concurrency | integration/host | inbox_round_trip_test.dart::same-peer drain completes only because decrypts overlap | HEAD serial → barrier(target 2) never reached → deadlock/timeout | remove prefetch / bound=1 | `./scripts/run_test_gates.sh 1to1` | AUTO + `inbox_round_trip_test.dart` in `ONE_TO_ONE_TESTS` |
| TC-A8 boundary/disposition preserved | preservation | integration + migration host | recovered_inbox_chat_disposition_test.dart + 077_message_relay_custody_test.dart::(existing) | n/a (HEAD green) — scope-stay guard | move decrypt past ack boundary | `./scripts/run_test_gates.sh 1to1` | AUTO (`test/core/**`/`test/features/**`) + array |

## Invariants (locked by tests)
- INV-1: decrypt fans out concurrently (>1 in flight) → TC-A1, TC-A7.
- INV-2: commit/persist stays serial and in arrival order per conversation → TC-A2, TC-A3.
- INV-3: edits/reactions/deletions never commit before their target message → TC-A3 (edit; reaction/deletion mirror via the disposition suite TC-A8).
- INV-4: a prefetch decrypt failure never drops or mis-disposes an entry (falls back to in-handler decrypt + existing retryable/quarantine) → TC-A4.
- INV-5: fan-out is bounded; in-flight ≤ `maxConcurrentInboxDecrypts` → TC-A5.
- INV-6: the stage→ack→replay boundary, the Move-account custody gate, the disposition state machine, and dedupe are unchanged → TC-A8.
- INV-RED-FIRST and INV-MUTATION-VERIFIED apply to every row above.

## Step-By-Step Implementation Plan
1. **RED first.** Add TC-A1..A7; confirm TC-A1 (maxConcurrent==1), TC-A6 (compile), TC-A7 (deadlock/timeout) fail on HEAD; TC-A2/A3/A4/A5/A8 pass on HEAD as locks (verify each mutation re-reds after the fix). Stop-if a concurrency RED passes on HEAD → the loop isn't where the plan says.
2. **Handler skip seam** — `handle_incoming_chat_message_use_case.dart`: add optional `String? predecryptedText`; when non-null, use it in place of the `callDecryptMessage` result at `:164` (and skip the fallback ring `:188`); when null, behavior is byte-identical. Extend the `ReplayRecoveredInboxChatMessage` typedef + `chat_message_listener.dart` wiring to thread it through (optional, default null).
3. **Bounded prefetch pass** — `p2p_service_impl.dart`: add const `maxConcurrentInboxDecrypts` and an optional injected `Future<String?> Function(ChatMessage) predecryptInboxChatEntry` (default null). In `_replayStagedInboxEntries` (`:1060`), when the fn is present, run `_predecryptInboxChatEntries(entries)` BEFORE the serial loop — a bounded-worker fan-out (reuse the `drain_group_offline_inbox_use_case.dart:108` index-counter + `Future.wait` pattern) producing `Map<entryId, String>`; swallow per-entry decrypt failures (omit). Then in the existing serial loop, pass `predecryptedText: map[entry.entryId]` into `chatReplay`. **Do not touch** `_applyRecoveredInboxOutcome`, the ack boundary, or the loop's ordering.
4. **Wire production** — `main.dart`: inject `predecryptInboxChatEntry` backed by the same bridge decrypt + ML-KEM fallback ring used by `handleIncomingChatMessage`. (Leaving it null keeps the feature off — a safe rollback.)
5. **GREEN** — run the direct test files; confirm RED tests flip green and locks stay green.
6. **Mutation pass** — apply each named revert, confirm re-red, restore.
7. **Preservation + named gate** — run `1to1`; the disposition + custody + dedupe suites (TC-A8) must stay green at the same counts. Stop-if any boundary/disposition test reds → the prefetch leaked past the ack boundary; replan, do not hack.

## Risks And Edge Cases
- **Out-of-order commit** corrupting edit/reaction/deletion causality → pinned by TC-A2, TC-A3, TC-A8.
- **Unbounded fan-out** spawning a native thread per entry (Android cached pool) → pinned by TC-A5; bound with `maxConcurrentInboxDecrypts`.
- **Double-decrypt / wasted work** if the handler re-decrypts despite a supplied plaintext → pinned by TC-A6.
- **Prefetch failure dropping a message** (the worst outcome — silent loss) → pinned by TC-A4 (must fall back, never drop).
- **Decrypt-injection seam risk (named execution risk):** the prefetch needs the bridge decrypt + fallback ring accessible from the p2p service. If that cannot be injected cleanly, the Stop-If fallback is to keep the feature default-off (null fn) and land only the handler `predecryptedText` seam + tests, deferring the wiring — rather than a large refactor. Do NOT inline a second copy of the ML-KEM fallback logic.
- **SQLCipher write-lock** — not a risk here because commit stays serial (single writer); explicitly do NOT parallelize commit.
- **Flaky concurrency assertions** — use deterministic latches/barriers (TC-A1/A5/A7), never wall-clock timing, for the concurrency claims.

## Device/Relay Proof Profile
**host-only for closure.** The crypto is unchanged (real decrypt correctness already covered by `one_to_one_media_encryption_round_trip_test.dart` and the two-user integration suites); this change only reschedules when decrypt runs. All concurrency/ordering claims are deterministic at host tier with latches + fake decrypt fns. No migration, no OS callback, no multi-device, no real-relay behavior change.
Non-blocking device verification (follow-up, not a closure gate): on a notif-tap that surfaces several queued same-peer messages, confirm they render together quickly (decrypt overlap) rather than trickling in one-by-one. Pairs with 145's affordance + 146's receipt deferral on the same device session.

## Acceptance Gates  (literal — copy/paste)
```bash
# 0) Baseline snapshot
git status --short

# 1) RED (before production edits) — TC-A1/A6/A7 must FAIL on HEAD for the documented reason
flutter test test/core/services/p2p_service_impl_test.dart \
  --plain-name 'prefetch decrypts concurrently up to the bound'
flutter test test/features/conversation/application/handle_incoming_chat_message_use_case_test.dart \
  --plain-name 'uses predecryptedText'
flutter test test/core/inbox/inbox_round_trip_test.dart \
  --plain-name 'completes only because decrypts overlap'

# 2) Direct GREEN (after fix) — whole files
flutter test test/core/services/p2p_service_impl_test.dart
flutter test test/core/inbox/inbox_round_trip_test.dart
flutter test test/features/conversation/application/handle_incoming_chat_message_use_case_test.dart
flutter test test/features/conversation/application/recovered_inbox_chat_disposition_test.dart

# 3) Preservation sentinels (must stay green — record baseline counts, 0 new failures)
./scripts/run_test_gates.sh 1to1                 # disposition + custody + dedupe suites stay green at baseline counts
flutter test test/core/database/migrations/077_message_relay_custody_test.dart   # Move-account custody gate intact

# 4) Hygiene
flutter analyze            # 0 new issues
git diff --check
```
> Expected count deltas: `p2p_service_impl_test.dart` +3 (TC-A1,A2,A4,A5 → +4 actually; record exact); `handle_incoming_chat_message_use_case_test.dart` 53 → 55 (+TC-A3,A6); `inbox_round_trip_test.dart` +1 (TC-A7). Record exact suite totals from the baseline run; preservation = baseline_total + new, 0 regressions.

## Known-Failure Interpretation
- Expected RED: TC-A1 (maxConcurrent==1), TC-A6 (compile until the param exists), TC-A7 (deadlock/timeout) before the fix.
- Green-on-HEAD locks: TC-A2/A3/A4/A5/A8 — their mutations must re-red after the fix.
- Pre-existing dirty: the `new-feed` tree carries uncommitted work; capture `git status --short` first.
- Environment blocker (NOT product): none — no sim/device rows.
- Scope drift (BLOCKING): any red in the disposition (`recovered_inbox_chat_disposition_test.dart`), custody (`077_*`), or two-user convergence suites → you changed the commit/ack path; stop and replan.

## Done Criteria
- [ ] RED added first; TC-A1/A6/A7 failed for the expected reason (incl. the serial-deadlock RED).
- [ ] Mutation-verified (each row has a re-red revert).
- [ ] Direct GREEN + `1to1` preservation gate pass, 0 regressions; disposition/custody/dedupe suites unchanged.
- [ ] Fan-out is bounded (TC-A5 green); commit order preserved (TC-A2/A3 green).
- [ ] Prefetch failure falls back, never drops (TC-A4 green).
- [ ] No migration (confirm: no `DB v##` touched); decrypt crypto unchanged.
- [ ] `flutter analyze` 0 new; `git diff --check` clean; no Scope Guard violations.

## Scope Guard (hard "Do not")
- Do not parallelize commit/persist; only decrypt fans out. Commit stays serial-in-order.
- Do not move decrypt past the stage→ack boundary or change `_applyRecoveredInboxOutcome` / the Move-account custody gate.
- Do not use unbounded fan-out; cap at `maxConcurrentInboxDecrypts`.
- Do not change the decrypt crypto, dedupe, or disposition logic.
- Do not implement per-peer buckets or group within-group parallelization here.
- Do not defer the delivery-receipt send here → plan 146 owns it.

## Accepted Differences / Intentionally Out Of Scope
- Per-peer/per-conversation bucket parallelism (helps multi-peer backlogs, not the single-peer notif-tap case) → future follow-up.
- Group within-group replay parallelization → separate effort (cross-group is already parallel).
- Delivery-receipt deferral → plan 146.
- A production analytics sink for the drain-timing events (145's `replayMs`) is the natural before/after measurement for this change → future telemetry session.

## Dependency Impact
- Best landed AFTER plan **146**: 146 removes the awaited receipt round-trip from each iteration, so 147's decrypt-prefetch then overlaps the dominant remaining per-iteration cost; landing 146 first also means fewer awaited network hops inside the loop while 147 restructures it.
- Consumes plan **145**'s `replayMs` drain-timing field as the before/after measurement hook (soft dependency — measurement only, no code coupling).

## Reviewer Findings
4-lens adversarial review (workflow) = **SHIP**, 0 blocker/major. Findings addressed:
- **R1 (nit, review workflow):** `MLKEM_RING_FALLBACK_USED` dropped on the prefetch-hit ring-recovery path → `predecryptIncomingChatEnvelope` now emits it (mutation-verified test).
- **R2 (HIGH, second review pass):** the prefetch decrypted a **blocked sender's** ciphertext into memory before the listener's blocked-reject (the listener rejects BEFORE its own decrypt — `chat_message_listener.dart:374` — so 147 regressed the "blocked → never decrypted" policy). FIX: extracted `predecryptStagedInboxChatEntry` (handle_incoming use-case) that checks `contact.isBlocked` FIRST → returns null (no decrypt); main.dart wires it. 3 tests (blocked-skip mutation-verified: removing the check lets the bridge be reached → `decryptCallCount` re-reds).
- **R3 (MEDIUM, second review pass):** the listener still loaded `getOwnMlKemSecretKey`/`Ring` even on a prefetch HIT (handler skips decrypt → keys unused) → wasted serial keystore reads on the drain hot path. FIX: `chat_message_listener.dart` skips both loads when `message.predecryptedText != null`. Test (mutation-verified: always-load → `keyLoads==1` re-reds).
- **R4 (LOW, second review pass):** the plaintext-carrier privacy contract was unpinned. FIX: `chat_message_test.dart` `predecryptedText privacy contract` group — fromJson-ignores / toJson-excludes / equality+hashCode-ignore / toString-no-leak / copyWith-carries.

Sufficiency self-check PASS: every TC has tier+file+RED/lock+mutation+gate+registration; zero empty matrix cells; concurrency proven RED-on-HEAD by a serial-deadlock barrier (TC-A7); ordering invariants use distinct flow-event discriminators (TC-A3); the decrypt-injection seam risk is named with a default-off fallback; safety (stateless decrypt) source-cited (`crypto/decrypt.go:24-77`).

## Arbiter Decision
Structural blockers: none (host-only, no migration, all files already gated). | Named execution risk: the decrypt-injection seam — fallback is keep-default-off + land the handler seam/tests only. | Deferred details: exact preservation counts (record at execution); TC-A7 harness-wiring confirmation. | Accepted differences: per-peer buckets / group parallelization / 146 / telemetry sink deferred as listed.

## Final Execution Verdict
Verdict: **IMPLEMENTED host-green** (uncommitted on `new-feed`; no migration; decrypt crypto unchanged).
Files changed (5 prod + 2 test): `lib/features/p2p/domain/models/chat_message.dart` (transient `predecryptedText` carrier, excluded from `==`/`hashCode`/`toJson`/`fromJson`); `lib/features/conversation/application/handle_incoming_chat_message_use_case.dart` (`predecryptedText` param + skip; shared event-free `_decryptV2ChatEnvelope` + public `predecryptIncomingChatEnvelope`, one copy of the ML-KEM ring; emits `MLKEM_RING_FALLBACK_USED` on prefetch ring recovery); `lib/features/conversation/application/chat_message_listener.dart` (forwards `message.predecryptedText`); `lib/core/services/p2p_service_impl.dart` (`maxConcurrentInboxDecrypts=6`, injected `_predecryptInboxChatEntry`, bounded-worker `_predecryptInboxChatEntries`, prefetch-before-serial-loop); `lib/main.dart` (wired ON to the chat path's key material). Tests: `p2p_service_impl_test.dart` +5 (TC-A1/A2/A4/A5/A7), `handle_incoming_chat_message_use_case_test.dart` +3 (TC-A3/A6 + ring breadcrumb).
Tests run (+counts): **14 new tests total** (8 TC-A + ring-breadcrumb + 3 blocked-sender + listener-skip + 6 model privacy-contract, less overlap), ALL mutation-verified; `1to1` gate +1128→**+1133** (incl. 077 custody + disposition + dedupe + round-trip), 0 regressions; `flutter analyze` 0 new (3 warnings predate session); `git diff --check` clean.
Blocking: none. QA verdict: 4-lens adversarial review = **SHIP** (0 blocker/major). Post-review hardening: R1 ring-breadcrumb (nit), R2 blocked-sender decrypt bypass (HIGH), R3 redundant key-load on prefetch hit (MEDIUM), R4 plaintext-carrier privacy-contract tests (LOW) — all FIXED + mutation-locked (see Reviewer Findings).
**DESIGN DEVIATION (accepted):** plaintext threaded via a transient `ChatMessage.predecryptedText` field, NOT by extending the `ReplayRecoveredInboxChatMessage` typedef as the plan's Design step 2 said — that typedef is SHARED by 5 callbacks and Dart's add-named-param subtyping rule would break **55** callback literals across 9 files (proven empirically). The field carrier (mirroring existing `transport`/`confirmNonce` annotations) achieves identical observable behavior with zero typedef churn; the handler still gains the `predecryptedText` param TC-A6 pins. All INV-1..6 + the full test matrix hold.
Non-blocking follow-ups (owner): device verify of multi-message same-peer notif-tap render alongside 145/146; production analytics sink for `replayMs` as the before/after measurement.
