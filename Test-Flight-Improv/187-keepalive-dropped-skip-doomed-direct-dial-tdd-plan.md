# 187 - Keepalive-informed send: skip the doomed direct dial when the active peer is latched-dropped  (Modification / optimization)

Status: IMPLEMENTED + host-green (2026-07-01) — device-proof TC-187-32 deferred (no paired phones; authored + registered, skips silently). All host tiers green + mutation-verified; 4-lens adversarial review returned zero findings.
Spec: `Test-Flight-Improv/187-keepalive-dropped-skip-doomed-direct-dial-spec.md`

## Planning Progress
| Time | Role | Files inspected | Decision/blocker | Next action |
|---|---|---|---|---|
| 2026-07-01 | Evidence Collector (workflow `wf_af438f42`) | send_chat_message_use_case.dart, active_peer_keepalive_use_case.dart, active_conversation_tracker.dart, p2p_service.dart/_impl, main.dart, send/keepalive/FDC-01/02 test suites | seam + 4 refutations resolved (see Root Cause) | build matrix |
| 2026-07-01 | Planner | + tier-matrix / sufficiency-checklist / plan-template | Option A (leg-preserving short-circuit) chosen; off-base `PeerDropSignal`; normalized-key match | emit plan |
| 2026-07-01 | Reviewer (sufficiency) | this plan | see Reviewer Findings | — |
| 2026-07-01 | Arbiter | this plan | see Arbiter Decision | hand off to execution |

## Execution Progress
| Time | Phase | Files touched | Command/evidence | Decision/blocker | Next |
|---|---|---|---|---|---|
| 2026-07-01 | contract extraction (`git status --short`) | — | 185/186 in-tree confirmed, NOT reverted | clean baseline | add RED |
| 2026-07-01 | RED tests added | send/keepalive/liveness test files | keepalive TC-187 RED = compile-fail (`No named parameter 'onLivenessChanged'`) — documented reason | RED-first satisfied | implement |
| 2026-07-01 | implementation | p2p_service(.dart/_impl), keepalive UC, send UC, main.dart | off-base `PeerDropSignal`; keepalive `onLivenessChanged`+`_lastSignalledPeer`; send `directSkipForKeepaliveDrop`+`_tryDirectSend` Option-A short-circuit; main wiring | — | GREEN |
| 2026-07-01 | direct GREEN | — | keepalive+liveness 25/25 (TC-187-12/40/21+purity); send 134/134 (9 TC-187 rows) | — | mutation |
| 2026-07-01 | mutation-verify | send UC (temp `if(false&&…)`) | neutralized short-circuit → TC-187-01 + TC-187-21 RE-RED (skip event absent); INV locks stay green (correct); restored | mutation-sensitive | preservation |
| 2026-07-01 | preservation GREEN | — | `run_test_gates.sh 1to1` 1449/1449 (FDC-01/02 + ranked-race e2e index-coupling + `main_keepalive_wiring`); `run_host_test_gates.sh core-host-all` PASS (272 files) | no FDC re-baseline | hygiene |
| 2026-07-01 | named gates / hygiene | — | `flutter analyze` 0 new (4 pre-existing); `git diff --check` clean; 4-lens adversarial review 0 findings | — | device-proof |
| 2026-07-01 | device-proof | `integration_test/keepalive_drop_skip_direct_proof_test.dart` + discovery script | authored + registered (`check_reliability_simulation_discovery.sh` lists TC-187-32); host-skips; **run deferred — no paired phones** | env blocker (not product) | closure gate open on rig |

## Source Of Truth
- Spec: `Test-Flight-Improv/187-keepalive-dropped-skip-doomed-direct-dial-spec.md`
- Gate definitions: `scripts/run_test_gates.sh` (script wins over prose)
- Numbering / index: `Test-Flight-Improv/00-INDEX.md` (183/184/185/186 plans are NOT indexed there → 187 follows suit, no index entry)

## Session Classification
implementation-ready.

## Exact Problem Statement
When the user sends to the **active 1:1 peer** the **183 keepalive has already latched as dropped** (`_dropHandled`), the send still runs the full direct discover→dial leg to completion on a peer that cannot answer. Device-captured 2026-07-01: the keepalive latched Bob dropped at 18:30:04; a send 87 s later still ran `DISCOVER_PEER_BEGIN → DIAL_PEER_BEGIN → DIAL_PEER_ERROR` (~1.5 s), while the concurrent durable inbox had already confirmed custody at **178.7 ms**. The ~1.5 s dial delivered nothing and only spent radio on both devices.

**What must improve:** a send to a latched-dropped active peer must NOT burn the direct discover/dial network legs — it should lean on the already-concurrent durable inbox.
**What must stay unchanged (→ preserved-green sentinels):** unknown-liveness / reachable / warm peers keep the FULL FDC-01/02 budget (no re-baseline); durable inbox always fires; no message loss; no false "delivered"; the race completer still settles; the one-relay-write invariant holds.

**Framing (honesty):** this is a **battery / radio + transport-tier-resolution** win, NOT a user-latency win — custody is already ~179 ms. Success = the doomed dial is gone with zero durability/delivery regression.

## Root Cause (verify → refute confirmed)
- The direct leg is added to `raceFutures` **unconditionally** at `send_chat_message_use_case.dart:855-871`; a file-wide grep for `keepalive|Liveness|PeerLivenessProbe` returns **zero** hits — the send path consults no liveness signal (SURVIVED "already-handled": FDC-02 relay-penalty gates only the relay-LIVE leg :928; learned sticky short-circuit only fires when `learned!=null`; FDC-08 presence-unreachable runs the live legs "afterwards", never skips them).
- The 183 drop latch `_dropHandled` is **private** (`active_peer_keepalive_use_case.dart:60`); only `isProbeActive` (:71) is public; the send entry (`send_chat_message_use_case.dart:242`) receives only `p2pService` and has **no handle** to the keepalive (they share exactly one object: `widget.p2pService`). Exposing the latch requires a new read-only surface (SURVIVED "expose-latch").

**Refuted / do-NOT-re-introduce (encode the guardrails instead):**
- **Naive `targetPeerId == activePeerId` (REFUTED).** `activePeerId` is stored as `normalizeActiveKey(peerId)` (trim + strip `group:…|message:` suffix — `active_conversation_tracker.dart:17,35-49`); `targetPeerId` is raw. → the drop-signal getter MUST normalize internally (reuse `normalizeActiveKey` / the `isViewing` idiom), never a raw `==`.
- **"Skipping the direct leg is free/safe" (REFUTED).** The completer is index-coupled: `isLocalLeg = i==0`, `isDirectLeg = i==1`, relay-live `= i==2` (`:1023-1024`); `directLegPending` inits `true` (:914) and gates completion via `noPendingLegCanBeatBest()` (:983); `pendingCount = raceFutures.length` (:945, dynamic). **Deleting `raceFutures[1]` would slide relay-live into index 1 (mis-tagged as direct) and strand `directLegPending` true (relay best completes only via the grace timer).** → **Option A** (below) sidesteps all of this by keeping the leg present.

## Real Scope
**In scope:**
1. New **off-base** interface `PeerDropSignal { bool isPeerSuspectedDropped(String peerId); void setPeerDropSuspected(String peerId, bool dropped); }` in `lib/core/services/p2p_service.dart` (alongside `PeerLivenessProbe`) — OFF the base `P2PService` so the ~31 fakes are untouched.
2. `P2PServiceImpl implements PeerDropSignal`: a `Set<String> _suspectedDroppedPeers` keyed by `normalizeActiveKey`; both methods normalize their arg.
3. `ActivePeerKeepAliveUseCase`: add an `onLivenessChanged(String peerId, bool suspectedDropped)` callback (constructor param, spy-testable). Fire `(peer, true)` at the drop-latch point (:130); fire `(prev, false)` on recovery (`_resetLiveness` when `alive`) AND when the tracked peer changes/clears/stops (needs a `_lastSignalledPeer` field). Wire in `main.dart:3670` to `p2pService.setPeerDropSuspected`.
4. `send_chat_message_use_case.dart`: compute `directSkipForDrop = unknownPresence && (p2pService is PeerDropSignal) && (p2pService as PeerDropSignal).isPeerSuspectedDropped(targetPeerId)` right after `unknownPresence` (:707); pass it into `_tryDirectSend(..., skipForKeepaliveDrop:)`, which — **Option A** — short-circuits at its top: emit `SEND_DIRECT_LEG_SKIPPED_KEEPALIVE_DROP` and return `_RaceResult.failed('direct_skipped_keepalive_drop', relayProbeEligible: false)` BEFORE any discover/dial. The leg stays in `raceFutures[1]` → indexing, `directLegPending`-clearing, and `pendingCount` are all preserved untouched.

**Out of scope (other work owns):**
- Broadening keepalive scope beyond the active 1:1 chat — **decided against** this session (battery). The signal is only ever set for the one pinged peer.
- Skipping the **local/LAN** leg — kept (LAN is independent; only the WAN direct dial is skipped). Gating skip on `unknownPresence` also keeps it aligned with the concurrent-inbox custody guarantee.
- Sender-side reconnect self-heal latency → **186** (FU-185-A) owns it.
- Any budget change for unknown-liveness peers → explicitly forbidden (would overturn FDC-01/02).

## Files To Inspect Next
Production: `lib/core/services/p2p_service.dart` (add interface), `p2p_service_impl.dart` (implement + set state; also the keepalive drop path if latch mirrored), `lib/core/services/active_peer_keepalive_use_case.dart` (callback + `_lastSignalledPeer`), `lib/features/conversation/application/send_chat_message_use_case.dart` (:704-707 predicate, `_tryDirectSend` short-circuit), `lib/main.dart:3670` (wire callback), `lib/core/notifications/active_conversation_tracker.dart` (`normalizeActiveKey` reuse).
Tests: `test/features/conversation/application/send_chat_message_use_case_test.dart`, `test/core/services/active_peer_keepalive_use_case_test.dart`, plus any shared `FakeP2PService` that must `implements PeerDropSignal` for the new send tests.

## Existing Tests Covering This Area
- `send_chat_message_use_case_test.dart` — send race / direct leg / FDC-01 / FDC-02 / FDC-03 concurrent inbox (Phase 1 :2238; FDC-03 group :3533; FDC-01/02 pins :4194-4731). **passes today.** In **`ONE_TO_ONE_TESTS`** array (`run_test_gates.sh`, 1to1 gate) AND auto-globbed by host-all/feature-host-all.
- `active_peer_keepalive_use_case_test.dart` — `_dropHandled` latch behavior (TC-183-05 success resets streak :143, TC-183-06 M-miss→one drop, drain/re-warm counts). **passes today.** Auto-globbed by **core-host-all** only (under `test/core/services/`).
- `ranked_race_relay_penalty_test.dart` — FDC-02 e2e. **passes today.** In `ONE_TO_ONE_TESTS`.
- `send_path_budget_hard_gate_test.dart` — NET-REL-05 budget hard gate. **RED today (pre-existing, unrelated)**; under `test/performance/` (performance-host only). → record in Known-Failure Interpretation; do NOT attribute to 187.

**Missing coverage gaps (all UNWRITTEN today):** skip-direct-on-drop (TC-187-01/02/03), latch/signal exposure + reset (TC-187-12/40), no-regress-on-unknown/reachable/reconnected (TC-187-10/11/20/21), invariants (TC-187-30/31), device-proof (TC-187-32). The skip **predicate** (`unknownPresence && isPeerSuspectedDropped(normalized target)`) has zero coverage; `_dropHandled` is proven only indirectly (no getter test).

## RED Test Catalog  (add BEFORE any production code — INV-RED-FIRST)

1. `send_chat_message_use_case_test.dart`::`TC-187-01 latched-dropped active peer → direct discover/dial leg is skipped`
   - Tier: application/unit. Setup: `FakeP2PService implements PeerDropSignal` with `isPeerSuspectedDropped(target)=true`, `isConnectedToPeer=false`, LAN resolve → false; spy discover/dial calls.
   - RED on HEAD: the field/interface doesn't exist (compile) → after stub, the direct leg still runs (spy sees `discoverPeer`/`dialPeer`; no `SEND_DIRECT_LEG_SKIPPED_KEEPALIVE_DROP`).
   - GREEN asserts: **`SEND_DIRECT_LEG_SKIPPED_KEEPALIVE_DROP` emitted AND NOT `P2P_SERVICE_DISCOVER_PEER_BEGIN`/`P2P_PEER_DIAL_REQUEST`** for that send (distinct-event discriminator).
   - Mutation: revert the `skipForKeepaliveDrop` short-circuit in `_tryDirectSend` → discover/dial fire again → RED.

2. `send_chat_message_use_case_test.dart`::`TC-187-02 skip still secures concurrent-inbox custody`
   - Tier: application/unit. Same fake; assert `CHAT_MSG_SEND_CONCURRENT_INBOX_BEGIN` + `CHAT_MSG_SEND_CUSTODY_CONFIRMED` still fire and `storeInInbox` is called (custody not sacrificed).
   - RED on HEAD: n/a signal → once wired, verifies custody survives the skip. Mutation: make the skip also suppress the concurrent inbox → custody gone → RED.

3. `send_chat_message_use_case_test.dart`::`TC-187-03 skipped send lands retriable 'inboxed', a later receipt → delivered`
   - Tier: application/unit (host). Assert post-skip row status is `inboxed` (not `failed`, not `delivered`), then a peer-authenticated receipt drives `inboxed→delivered` (reuses existing lane). Mutation: skip returns a terminal `failed` result → row not retriable → RED. (Full on-wire recovery = TC-187-32 device.)

4. `send_chat_message_use_case_test.dart`::`TC-187-10 reachable active peer (signal false) → direct leg runs full budget`
   - Tier: application/unit. `isPeerSuspectedDropped=false`. Assert discover/dial DO run; NO skip event. Mutation: make the skip fire regardless of the signal → RED (over-reach caught).

5. `send_chat_message_use_case_test.dart`::`TC-187-11 unknown / non-active peer → direct leg runs full budget`
   - Tier: application/unit. Signal returns false for a peer that was never marked (keyed by normalized peerId). Assert direct leg runs. This is the FDC-01/02-preserving guard at the send tier.

6. `send_chat_message_use_case_test.dart`::`TC-187-20 warmPeer reconnected (isConnectedToPeer true) → reuse path, never skip`
   - Tier: application/unit. `isConnectedToPeer=true` (signal may still read true within the pre-ping window). Assert the connected-reuse fast path (:527-540) is taken and the skip never evaluates. Mutation: drop the `!isConnectedToPeer` guard / reuse precedence → RED.

7. `send_chat_message_use_case_test.dart`::`TC-187-21 normalized-key match (raw target normalizes to the marked key)`
   - Tier: application/unit. Mark the signal via a value carrying whitespace/`group:` normalization; send with the raw form; assert the skip DOES fire (normalized match) — and a genuinely different peer does NOT skip. Mutation: replace `normalizeActiveKey`-based match with raw `==` → normalized case no longer matches → RED. (Locks the REFUTED naive-match finding.)

8. `active_peer_keepalive_use_case_test.dart`::`TC-187-12 recovery clears the drop signal (PING_SUCCESS → setDropSuspected(peer,false))`
   - Tier: application/unit. Spy `onLivenessChanged`. Drive 2 misses → `(peer,true)`; then a `PING_SUCCESS` → assert `(peer,false)`. Mutation: remove the reset-side callback → no clear → RED.

9. `active_peer_keepalive_use_case_test.dart`::`TC-187-40 signal cleared on chat-close / peer-switch / background (no stale mark)`
   - Tier: application/unit. Spy `onLivenessChanged`. Latch a drop for peerA; then (a) `activePeerId()` returns null (chat closed) on next tick, (b) `activePeerId()` returns peerB (switch), (c) `onBackgrounded()`. Each asserts `(peerA,false)` fired so no stale "dropped" mark survives. Mutation: omit the clear on `_resetLiveness`/`_stop`/peer-change → stale mark persists → RED. **(Blind-spot: derived-state durability.)**

10. `integration_test/…/keepalive_drop_skip_direct_proof_test.dart`::`TC-187-32 device-proof (PROD-CRITICAL)`
    - Tier: device-proof (2 phones, real bridge/relay). Reproduce the 2026-07-01 capture: send to a latched-dropped active peer → **NO ~1.5 s `DIAL_PEER_ERROR` leg** (assert `SEND_DIRECT_LEG_SKIPPED_KEEPALIVE_DROP`, no `DIAL_PEER_*`), custody still lands ~sub-200 ms, and the queued message **delivers on peer recovery** (`DELIVERY_RECEIPT_APPLIED`). Closure gate — unit coverage is NOT sufficient alone.

## Test Coverage Matrix  (zero empty cells)
| Spec case | Behavior props | Tier | Test file::name | RED reason on HEAD | Mutation revert | Acceptance gate cmd | Harness registration |
|---|---|---|---|---|---|---|---|
| TC-187-01 | skip predicate + leg short-circuit | application/unit | send_chat_message_use_case_test.dart::TC-187-01 | no signal/interface (compile), then leg runs | revert `_tryDirectSend` short-circuit | `run_test_gates.sh 1to1` | AUTO (glob) + already in `ONE_TO_ONE_TESTS` |
| TC-187-02 | custody preserved under skip | application/unit | …::TC-187-02 | skip could drop custody | make skip suppress concurrent inbox | `run_test_gates.sh 1to1` | AUTO + `ONE_TO_ONE_TESTS` |
| TC-187-03 | retriable inbox → delivered | application/unit | …::TC-187-03 | skip returns terminal failed | skip returns `failed` not retriable inbox | `run_test_gates.sh 1to1` | AUTO + `ONE_TO_ONE_TESTS` |
| TC-187-10 | no over-reach (reachable) | application/unit | …::TC-187-10 | skip fires unconditionally | skip ignores signal | `run_test_gates.sh 1to1` | AUTO + `ONE_TO_ONE_TESTS` |
| TC-187-11 | FDC-01/02 preserved (unknown) | application/unit | …::TC-187-11 | skip fires for unmarked peer | signal not keyed by peer | `run_test_gates.sh 1to1` | AUTO + `ONE_TO_ONE_TESTS` |
| TC-187-20 | reconnected → reuse, not skip | application/unit | …::TC-187-20 | skip ignores connectedness | drop `!isConnectedToPeer` guard | `run_test_gates.sh 1to1` | AUTO + `ONE_TO_ONE_TESTS` |
| TC-187-21 | normalized-key match | application/unit | …::TC-187-21 | raw `==` mis-matches normalized | raw `==` instead of `normalizeActiveKey` | `run_test_gates.sh 1to1` | AUTO + `ONE_TO_ONE_TESTS` |
| TC-187-12 | recovery clears signal | application/unit | active_peer_keepalive_use_case_test.dart::TC-187-12 | no reset-side callback | remove reset callback | `run_host_test_gates.sh core-host-all` | AUTO (`test/core/**`) |
| TC-187-40 | signal clears on close/switch/bg (blind-spot) | application/unit | active_peer_keepalive_use_case_test.dart::TC-187-40 | no clear on `_resetLiveness`/`_stop`/switch | omit those clears | `run_host_test_gates.sh core-host-all` | AUTO (`test/core/**`) |
| TC-187-30 | never falsely delivered | application/unit | send_chat_message_use_case_test.dart::TC-187-30 | (covered w/ TC-187-03) row delivered w/o receipt | skip mints delivered | `run_test_gates.sh 1to1` | AUTO + `ONE_TO_ONE_TESTS` |
| TC-187-31 | one relay write | application/unit | send_chat_message_use_case_test.dart::TC-187-31 | double store under skip | break concurrentInbox tail short-circuit | `run_test_gates.sh 1to1` | AUTO + `ONE_TO_ONE_TESTS` |
| TC-187-32 | wire/transport end-to-end (PROD-CRITICAL) | device-proof | integration_test/…/keepalive_drop_skip_direct_proof_test.dart::TC-187-32 | feature absent → dial still runs | revert skip | `/sims <scope> --only N` (device) | classify_path 'device-proof' case + orchestrator `--scenario` |

## Blind-Spot Sweep
- **Lifecycle / derived-state durability:** the suspected-dropped flag is **in-memory derived state**. **TC-187-40** locks that it clears on chat-close / peer-switch / background so a stale mark cannot cause a wrong skip after re-entry. (This is the highest-risk blind spot — a persisted stale mark would silently route a reachable peer to relay.)
- **Sibling-surface consistency:** the skip lives in the shared `_tryDirectSend` direct leg, so it applies uniformly to text/media/reaction sends (all route through the same race). Media already never live-relays (FDC-02) but still uses the direct leg → skip applies. TC-187-01 exercises the shared path; **N/A for a separate per-surface row** (single shared seam, no parallel gate).
- **Destructive-action side-effects:** N/A — no delete/cleanup/cancel introduced.
- **Invariant re-verification under new transitions:** the recovery/rearm transition that clears the signal must let the NEXT send run direct again — locked by **TC-187-12** (clear) + **TC-187-10** (send runs direct when clear). Together they re-verify "skip only while latched-dropped" survives the clear transition.

## Invariants (locked by tests)
- INV-1 (custody never sacrificed): concurrent inbox still fires + `CUSTODY_CONFIRMED` under skip → TC-187-02.
- INV-2 (no false delivered): no `delivered` without a receipt → TC-187-03/30.
- INV-3 (one relay write): `storeInInbox` exactly once → TC-187-31.
- INV-4 (FDC-01/02 untouched): unknown/reachable peers keep full budget → TC-187-10/11 + the FDC-01/02 sentinels stay green.
- INV-5 (no stale skip): signal clears on recovery/close/switch/bg → TC-187-12/40.
- INV-6 (race integrity): completer still settles; leg indices/`directLegPending` preserved (Option A keeps the leg present) → TC-187-01 (send resolves) + FDC-02 rank sentinels stay green.

## Step-By-Step Implementation Plan
1. `git status --short` snapshot (185/186 changes are in-tree — do NOT revert).
2. Add RED tests 1–10 above; run focused; confirm each fails for its documented reason.
3. Add `PeerDropSignal` off-base interface in `p2p_service.dart`; `P2PServiceImpl implements` it with a normalized `Set<String>`; make the send test's `FakeP2PService implements PeerDropSignal`. Stop-if: any base-`P2PService` fake breaks → the interface leaked onto the base; move it off.
4. `ActivePeerKeepAliveUseCase`: add `onLivenessChanged` callback + `_lastSignalledPeer`; fire `(peer,true)` on drop-latch, `(prev,false)` on `_resetLiveness`(alive)/peer-change/`_stop`. Wire in `main.dart:3670` to `p2pService.setPeerDropSuspected`.
5. `send_chat_message_use_case.dart`: compute `directSkipForDrop` after :707; thread `skipForKeepaliveDrop` into `_tryDirectSend`; short-circuit at its top (emit discriminator, return `_RaceResult.failed('direct_skipped_keepalive_drop', relayProbeEligible: false)`) — **do NOT remove the leg from `raceFutures`** (Option A). Stop-if: any FDC-02 rank test flips → the leg identity/index coupling was disturbed → revert to leg-preserving form.
6. Rerun direct RED→GREEN, then preservation sentinels, then named gates. Then device-proof.

## Risks And Edge Cases
- **Index-coupled completer** (`:914/:983/:1023-1024`) → mitigated by Option A (leg stays at index 1); pinned by FDC-02 rank sentinels + TC-187-01 (send still resolves).
- **Stale drop mark** → INV-5 / TC-187-40.
- **`isConnectedToPeer` racing warmPeer recovery** → reuse fast path (:527-540) precedes the leg; TC-187-20 locks it.
- **Key-format mismatch** → normalize both sides; TC-187-21.
- **~31 fakes** → off-base interface (reference: `reference_p2pservice_interface_addition_breaks_all_fakes`); only impl + send-test fake implement it.

## Device/Relay Proof Profile
Requires a **2-phone device-proof** for closure (TC-187-32) — the only path that proves the real discover/dial leg is actually skipped on the wire and the queued message still delivers on recovery. Reuse the 183 rig (Pixel 6 → iPhone 11, `FDC_FLOW_LOG=1` + `MKNOON_ENABLE_NATIVE_MDNS=true`). No feature flag to flip; no DB migration.

## Acceptance Gates  (literal)
```bash
# RED (before production edits) — must FAIL for the documented reason
flutter test test/features/conversation/application/send_chat_message_use_case_test.dart --plain-name 'TC-187-01'
flutter test test/core/services/active_peer_keepalive_use_case_test.dart --plain-name 'TC-187-40'

# Direct GREEN (after fix)
flutter test test/features/conversation/application/send_chat_message_use_case_test.dart
flutter test test/core/services/active_peer_keepalive_use_case_test.dart

# Preservation sentinels (must stay green) — FDC-01/02 + keepalive + relay-race e2e
./scripts/run_test_gates.sh 1to1                 # expect: prior pass count + new TC-187 send rows
./scripts/run_host_test_gates.sh core-host-all   # keepalive suite incl. TC-187-12/40

# Hygiene
flutter analyze     # 0 new
git diff --check

# Device-proof (closure) — discovery + run
./scripts/check_reliability_simulation_discovery.sh    # new proof scenario MUST list
# /sims <scope> --list → note --only N → /sims <scope> --only N
```

## Known-Failure Interpretation
- Expected RED: TC-187-01…40 before the fix.
- **Pre-existing dirty (NOT ours):** `test/performance/…/send_path_budget_hard_gate_test.dart` is RED on HEAD today (performance-host gate) — record, do not fix or attribute to 187. Also the 185/186 in-tree edits.
- Environment blocker (NOT product): no paired phones → TC-187-32 deferred, but host rows still close the logic.
- Scope drift (BLOCKING): any FDC-01/02 rank/budget sentinel flipping RED = the leg-index coupling was disturbed → revert to Option A form.

## Done Criteria
- [x] RED added first, failed for the expected reason (keepalive TC-187 = compile-fail on missing `onLivenessChanged`).
- [x] Each fix mutation-verified (neutralized `_tryDirectSend` short-circuit → TC-187-01 + TC-187-21 re-RED; INV locks correctly unaffected).
- [x] Direct GREEN + FDC-01/02 + keepalive sentinels + 1to1 (1449/1449) / core-host-all (PASS) gates pass.
- [ ] Device-proof TC-187-32: authored + registered (discovery lists it), **run deferred — no paired phones** (host rows close the logic; env blocker, not product).
- [x] New send-test fake `implements PeerDropSignal`; interface stays OFF base `P2PService` (fakes intact — locked by the p2p_service_peer_liveness purity test).
- [x] `flutter analyze` 0 new; `git diff --check` clean; no Scope Guard violation (4-lens adversarial review: 0 findings).

## Scope Guard (hard "Do not")
- Do NOT change discover/dial budgets for unknown-liveness peers; do NOT re-baseline FDC-01/02.
- Do NOT delete the direct leg from `raceFutures` (index coupling) — short-circuit inside it (Option A).
- Do NOT skip the local/LAN leg; do NOT suppress the concurrent durable inbox.
- Do NOT broaden keepalive scope beyond the active 1:1 chat.
- Do NOT put `PeerDropSignal` on the base `P2PService` (would break the ~31 fakes).

## Accepted Differences / Intentionally Out Of Scope
- Latency unchanged (custody already ~179 ms) — this is battery/tier only, by design.
- Sender-side reconnect self-heal → 186 owns it.
- Broadened (multi-peer / sticky) keepalive scope → declined this session.

## Dependency Impact
- None outward. Consumes the 183 keepalive latch (new read-only surface) and the FDC-03 concurrent inbox; leaves FDC-01/02 contracts intact.

## Reviewer Findings
Sufficient: every spec case (TC-187-01/02/03/10/11/12/20/21/30/31/32) has ≥1 tiered, mutation-verified row; the blind-spot sweep added TC-187-40 (the highest-risk stale-mark durability gap); FDC-01/02 preservation is explicit; the index-coupling refutation is encoded as Option A + INV-6; the naive-match refutation is locked by TC-187-21; harness registration is concrete (AUTO + `ONE_TO_ONE_TESTS` / core-host-all / device classify_path). Thin spot: TC-187-03's on-wire recovery is only fully proven at the device tier (TC-187-32) — acceptable, host locks the status logic.

## Arbiter Decision
Structural blockers: none. The one design hazard (index-coupled completer) is neutralized by the leg-preserving short-circuit (Option A); the one correctness hazard (stale drop mark) is locked by TC-187-40. No DB migration. Device-proof is the named closure gate. **Structurally sufficient — hand off to execution.**
