# FDC-01 — Fix direct_timeout → offline-inbox mis-route + 2s-serial starvation  (Bug)

Status: awaiting-review
Spec: Network-Arch/Fast-Direct-Connection-Architecture-Proposal.md (§4.1 "the correctness bug worth fixing on its own" + §8 P0-3)

## Source Of Truth
- Proposal §4.1 (R2 / the §4.1 correctness bug) and §8 recommendation **P0-3**.
- This epic's roadmap: **FDC-00** (sequencing; FDC-01 runs FIRST in the `send_chat_message_use_case.dart` cluster).
- `scripts/run_test_gates.sh` wins over prose: the test file lives in `ONE_TO_ONE_TESTS` (line 36) and auto-globs into `feature-host-all`.
- All file:line anchors below were re-verified by Read against branch `new-orbit` source (not from the proposal appendix alone).
- **P0-3 ownership note:** the FDC-00 roadmap (`:125`/`:97`) nominally splits P0-3 into FDC-01 *(mis-route correctness)* + FDC-02 *(independent budgets)*. This plan does the **minimal** budget decouple itself (one aggregate const at the outer wrapper) so the mis-route fix is self-contained and testable; the deeper per-leg budget rewrite remains FDC-02's. No behavioural overlap — FDC-02 rebases on the const introduced here.
- **Plan re-verified 2026-06-26** (6-agent verify→refute against `new-orbit`): root cause SURVIVES adversarial refute (bug live + unfixed, no other path rescues, no build-skew); all production anchors EXACT. Corrections folded in below: GREEN step C now uses the compiling `try/catch`-on-`TimeoutException` form (the `onTimeout: () => _RaceResult.failed(...)` shorthand does NOT compile on these typed step futures); `§9.1`→`§9` Phase-0 item 1; `§10`→`§8 P1-3` citations; dial-step reclassified as a defensive hang-guard; sticky-sibling fall-through documented; acceptance counts rephrased as baseline+N.

## Session Classification
**implementation-ready.** Pure-Dart control-flow change in one use case; host-fake testable; no relay/Go deploy, no migration, no native build. The real-wire "live-wins" angle is host-fake-only with a known false-positive risk (proposal §9 "Sequenced rollout" — Phase-0 item 1) → device smoke is DEFERRED, not gating (see Device/Relay Proof Profile).

## Exact Problem Statement
**What's broken.** On a 1:1 send to an **online but slow-to-discover** peer, the message is silently routed to the **offline durable inbox** ("inboxed", custody-only) instead of being **delivered live**. The receiver only sees it on its next inbox poll / push-wake — seconds late — so it "feels broken." Two independent mechanisms cause it:

1. **2s-serial starvation.** The direct leg `_tryDirectSendInner` runs `discoverPeer → dialPeer → sendMessageWithReply` serially, each handed `interactiveDirectBudget.inMilliseconds` (= 2000ms) as its *per-call* `timeoutMs` (`send_chat_message_use_case.dart:1472`, used at `:1477/:1490/:1507`). But the **whole** inner future is *also* hard-capped at the **same** 2s by the outer `.timeout(interactiveDirectBudget, …)` wrapper (`:699-703`). So the per-step budgets are not independent — a discover that consumes ~1.9s starves dial+send, and the outer cap fires mid-dial/mid-send.

2. **`direct_timeout` is not relay-probe-eligible.** When that outer cap fires it yields `_RaceResult.failed('direct_timeout')` (`:701`) with `relayProbeEligible` defaulting **false** (`_RaceResult.failed` default, `:1229-1238`). `relayProbeEligible` is set true ONLY for `peer_not_found` (`:1483`) and `dial_failed` (`:1500`). So the failure-aggregator `completeWithFailure` (`:750-767`) produces a non-eligible race result; the tail at `:1021 if (raceResult.relayProbeEligible)` **skips** the relay probe entirely and falls straight to the sequential inbox store (`:1071-1099`), persisting `status:'inboxed', transport:'inbox'`.

**Who feels it.** Any 1:1 sender whose foreground peer is reachable-via-relay but whose blind discover/dial is momentarily slow (cold-ish open, congested mDNS, relay rendezvous lag). The dominant reported "send feels slow/buggy" case (proposal §4 R2, §4.1).

**What must improve.**
- A slow-but-online peer must end **delivered-live** (`transport ∈ {direct, relay}`, `status:'delivered'`), NOT high-confidence `inbox`.
- The per-step discover/dial/send budgets must be **independent** (a slow step must not starve the others).
- A `direct_timeout` (and any per-step timeout) must be **relay-probe-eligible** so the live relay tail still runs.

**What must stay unchanged (preserved sentinels).**
- Genuinely-offline peer (`peer_not_found` / `NO_RESERVATION`) still lands in the inbox fast — `:2511` `'all active send paths failing falls back to inbox once'`, `:3513` `'U5 worst-case: offline peer → NO_RESERVATION → durable inbox custody'`.
- A definitive `send_failed` (peer dialed but returned `sent:false`) keeps its **non-eligible** semantics → inbox, NOT probe. (Out of scope; only the *timeout* of the send step becomes `direct_timeout`-eligible.)
- Happy path (fast discover/dial/send) still delivers `direct` with **no** probe and **no** inbox — `:2491` `'relay probe does not block direct discovery on the interactive path'` (asserts `discoverCallCount==1`, `probeRelayCallCount==0`).
- `peer_not_found` / `dial_failed` already-eligible probe behavior preserved — `:1975+` relay-probe group, `:3354` `'RELAY_PROBE_CONNECTED carries the id'`.
- Local-leg, grace-window, sticky head-start, concurrent-inbox (low-confidence) behavior untouched.

## Root Cause (verify→refute confirmed)
- **Confirmed mechanism #1 (starvation):** `_tryDirectSendInner` `:1472` `final budgetMs = interactiveDirectBudget.inMilliseconds;` is reused as the per-step `timeoutMs` for discover (`:1477`), dial (`:1490`), send (`:1507`); the SAME `interactiveDirectBudget` is the outer wrapper cap at `:700`. Per-step ≡ aggregate ⇒ no independence.
- **Confirmed mechanism #2 (mis-route):** `_RaceResult.failed('direct_timeout')` at `:701` omits `relayProbeEligible` (defaults false, `:1231`). `relayProbeEligible:true` appears only at `:1483` (`peer_not_found`) and `:1500` (`dial_failed`). `completeWithFailure` `:756-762` only flips the race result eligible if SOME failure is eligible; a `direct_timeout`-only failure set is not. Tail gate `:1021` then skips `_tryRelayProbeSend`.
- **Refuted / do-NOT-re-introduce:** "just lower the 2s cap" — refuted by proposal §8 P1-3 / §10 (capping a genuinely-cold handshake yields *more* abandoned reservations → *more* inbox fallback). The fix is **decouple** (independent per-step + larger aggregate ceiling), NOT shrink. Also do NOT make `send_failed` (definitive `sent:false`) probe-eligible — that is a different, out-of-scope failure class (FDC-02/relay ownership), and existing inbox-fallback tests lock it.
- **Refuted:** "the always-on concurrent inbox already covers it" — refuted: the concurrent inbox fires ONLY for `lowConfidence` sends (`:608-640`); a HIGH-confidence first send to a slow-online peer has `concurrentInbox==null`, so nothing rescues it before the serial inbox tail. (Generalizing the concurrent inbox is **FDC-03 / P0-2**, out of scope here.)

## Real Scope
**In scope (FDC-01):**
- Decouple per-step direct budgets from the aggregate ceiling (independent budgets).
- Make per-step timeouts (discover/dial/**send**) and the outer aggregate `direct_timeout` **relay-probe-eligible**.
- Lock both with mutation-verified host tests.

**Out of scope:**
- Generalize the concurrent durable inbox out of the low-confidence gate → **FDC-03 (P0-2)**.
- Eager `warmPeer` / LAN-aware reuse gating → **FDC-04 (P0-1)** (§6.1).
- Relay presence lookup replacing the blind probe → **FDC-08 (P1-1)**.
- Making definitive `send_failed` probe-eligible / moving relay ownership into Go → **FDC-04 / NET-REL**.
- Group send path (separate use case, separate budgets) → owning group epic; N/A here.

## Files To Inspect Next
- **Production entry/use-case (THE edit):** `lib/features/conversation/application/send_chat_message_use_case.dart`
  - budgets `:21` `interactiveLocalBudget`, `:24` `interactiveDirectBudget`, `:27` `interactiveInboxBudget`.
  - outer direct-leg wrapper `:693-703` (`direct_timeout` produced `:701`).
  - failure aggregator `completeWithFailure` `:750-767`; tail gate `:1021`.
  - `_tryDirectSend` `:1452-1465`; `_tryDirectSendInner` `:1467-1532` (per-step discover/dial/send).
  - `_RaceResult.failed` `:1229-1238` (default `relayProbeEligible:false`).
  - `_tryRelayProbeSend` `:1534-1663` (probe → dial → single post-probe send).
- **Models (dependency-only):** `lib/features/p2p/domain/models/send_message_result.dart` (`SendMessageResult{sent, acked, reply, transport}`); `lib/core/services/p2p_service.dart` (`RelayProbeResult`, `discoverPeer/dialPeer/sendMessageWithReply/probeRelay/storeInInbox`).
- **Direct test (the RED catalog target):** `test/features/conversation/application/send_chat_message_use_case_test.dart` (4332 lines; `FakeP2PService` `:34-331`, `DurableLanFakeP2PService` `:333`, `FakeMessageRepository` `:399`).
- **Dependency-only context (NOT edited):** `lib/core/services/p2p_service_impl.dart` `probeRelay :4074`, `discoverPeer/dialPeer` (real timeoutMs honoring); `test/core/services/p2p_service_impl_test.dart` (also in `ONE_TO_ONE_TESTS`).

## Existing Tests Covering This Area
- `send_chat_message_use_case_test.dart` — **exists**, registered in `scripts/run_test_gates.sh` `ONE_TO_ONE_TESTS` (line 36) and auto-globbed by `feature-host-all`.
  - `:2491 'relay probe does not block direct discovery on the interactive path'` — happy-path preservation (no probe on fast direct).
  - `:2482 'interactive direct discover uses short budget while background discover remains longer'` — **design/constant** test (`interactiveDirectBudget.inSeconds <= 4`); my new aggregate constant must keep this green.
  - `:2511 'all active send paths failing falls back to inbox once'` — offline inbox preservation.
  - `:1590 'falls through to relay when local send fails'`, `:3354 'RELAY_PROBE_CONNECTED carries the id'`, `:3513 'U5 worst-case: offline peer → NO_RESERVATION'` — relay-probe / offline preservation.
- `p2p_service_impl_test.dart` — exists, `ONE_TO_ONE_TESTS` line 48; not edited (probe/dial impl unchanged).
- **MISSING:** no test exercises (a) a slow-but-online discover delivering direct rather than inbox, or (b) `direct_timeout`/per-step-timeout being relay-probe-eligible. FDC-01 adds them.

## RED Test Catalog
> Tier = **unit/application** (pure function `sendChatMessage` + in-memory fakes). All four go in `test/features/conversation/application/send_chat_message_use_case_test.dart` under a new group `FDC-01 — direct-timeout misroute + per-step budget`. Each behavioral test uses **real wall-clock delays via the fake** (the file already tolerates 5s/3s delay tests — `:3555`, `:4295`); the production-side `.timeout` wrappers (not the fake) provide the deterministic per-step cutoff, so timing is production-driven and stable.

**Test-helper prerequisite (benign, compiles on HEAD):** add `Duration discoverDelay = Duration.zero;` to `FakeP2PService` and honor it at the top of `discoverPeer` (`await Future.delayed(discoverDelay)` before returning `discoverPeerResult`), mirroring the existing delay fields — `sendDelay` (field `:219`, used `:126-127`), `localSendDelay` (field `:220`, used `:264-265`/`:373-374`), `discoverLocalPeerDelay` (field `:202`, used `:239-240`). `discoverPeer` (`:142-150`) currently awaits NO delay, so this lever is genuinely new/valid (not stale). This does NOT change production and leaves all existing tests green (default zero). NB: `discoverCallCount` also exists on a SECOND fake class (`:4081`) — scope every assertion to the `FakeP2PService` instance under test.

### TC-FDC01-01 — slow-but-online discover delivers DIRECT, not inbox (locks the per-step/aggregate decouple)
- **file::name:** `send_chat_message_use_case_test.dart::FDC-01 slow discover within step budget still delivers direct (no starvation)`
- **Tier:** unit/application.
- **Shape/setup:** `FakeP2PService(storeInInboxResult: true)` (NOT local, NOT connected, high-confidence — no prior failed/inboxed row). `..discoverDelay = const Duration(milliseconds: 1900)` (< per-step 2s), `..sendDelay = const Duration(milliseconds: 300)`, `dialPeerResult: true`, `sendMessageAcked: true`. Send a fresh message.
- **RED-on-HEAD-because:** inner total ≈ 2200ms > outer `interactiveDirectBudget` 2000ms ⇒ outer fires mid-send → `direct_timeout` (not eligible) → local fails → sequential inbox store → `status:'inboxed', transport:'inbox'`.
- **GREEN-asserts:** `message.status == 'delivered'`; `message.transport == 'direct'`; `p2pService.storeInInboxCallCount == 0`; `p2pService.probeRelayCallCount == 0`; `p2pService.recordSuccessfulTransportCallCount == 1` (sticky learned 'direct').
- **Mutation-that-re-reds (M1):** revert the outer wrapper duration `directAggregateBudget` → `interactiveDirectBudget` at `:700` ⇒ re-reproduces the 2s starvation ⇒ message inboxed ⇒ asserts fail.
- **Distinct-event discriminator:** terminal is `CHAT_MSG_SEND_SUCCESS` with `via:'direct'` (a live leg), NOT a `via:'inbox'` success → assert `transport=='direct'` AND `storeInInboxCallCount==0`.

### TC-FDC01-02 — slow discover that times out the step is relay-probe-eligible → delivered RELAY, not inbox
- **file::name:** `send_chat_message_use_case_test.dart::FDC-01 discover-step timeout is relay-probe-eligible (online-relay peer delivered live)`
- **Tier:** unit/application.
- **Shape/setup:** `FakeP2PService(storeInInboxResult: true, probeRelayResult: RelayProbeResult.connected, sendMessageAcked: true)`; `..discoverDelay = const Duration(milliseconds: 2100)` (> per-step 2s ⇒ discover step times out). (`sendDelay` stays 0 so the post-probe send is fast.)
- **RED-on-HEAD-because:** outer 2s fires before the fake's 2.1s discover resolves → `direct_timeout` (not eligible) → probe **skipped** (`probeRelayCallCount==0`) → sequential inbox → `inboxed`.
- **GREEN-asserts:** `p2pService.probeRelayCallCount == 1`; `message.transport == 'relay'`; `message.status == 'delivered'`; `p2pService.storeInInboxCallCount == 0`.
- **Mutation-that-re-reds (M2a):** remove the per-step discover `.timeout` wrapper (or set its onTimeout `relayProbeEligible:false`) ⇒ discover no longer yields an eligible `peer_not_found` before the aggregate ⇒ probe skipped / direct ⇒ asserts (`probeRelayCallCount==1`, `transport=='relay'`) fail.
- **Distinct-event discriminator:** `CHAT_MSG_SEND_RELAY_PROBE_CONNECTED` emitted (`:1566-1570`) AND `probeRelayCallCount==1` — proves the LIVE relay tail ran, vs a silent inbox deposit.

### TC-FDC01-03 — send-step timeout becomes `direct_timeout` that IS probe-eligible (the literal §4.1 :701 fix)
- **file::name:** `send_chat_message_use_case_test.dart::FDC-01 send-step direct_timeout triggers relay probe`
- **Tier:** unit/application.
- **Shape/setup:** `FakeP2PService(storeInInboxResult: true, probeRelayResult: RelayProbeResult.noReservation)`; non-null `discoverPeerResult` (fast), `dialPeerResult: true` (fast), `..sendDelay = const Duration(milliseconds: 2100)` (> per-step 2s ⇒ send step times out → `direct_timeout`). Probe returns `noReservation` so the tail still lands in inbox — the *discriminator is whether the probe was attempted at all*.
- **RED-on-HEAD-because:** outer 2s fires during the slow send → `direct_timeout` (not eligible) → probe **skipped** (`probeRelayCallCount==0`) → inbox.
- **GREEN-asserts:** `p2pService.probeRelayCallCount == 1` (the send-step `direct_timeout` is now eligible, so the probe ran); final `message.status == 'inboxed'` (probe found no reservation — preserved offline behavior).
- **Mutation-that-re-reds (M2b):** revert the send-step timeout reason/eligibility (`'direct_timeout', relayProbeEligible:true` → `'send_failed'` / `false`) ⇒ probe skipped ⇒ `probeRelayCallCount==0` ⇒ assert fails.
- **Distinct-event discriminator:** `CHAT_MSG_SEND_RELAY_PROBE_NO_RESERVATION` emitted (`:1642-1646`) ⇒ probe was *attempted* (vs HEAD's silent skip). Asserts `probeRelayCallCount==1` regardless of terminal status, isolating eligibility from probe outcome.

### TC-FDC01-04 — budget-constant decouple lock (no-sleep design test)
- **file::name:** `send_chat_message_use_case_test.dart::FDC-01 aggregate direct budget exceeds the per-step budget`
- **Tier:** unit (pure constant assertion; mirrors the existing `:2482` design test).
- **Shape/setup:** no I/O.
- **RED-on-HEAD-because:** `interactiveDirectAggregateBudget` does not exist on HEAD (compile-level RED); once introduced the assertion encodes the invariant.
- **GREEN-asserts:** `interactiveDirectAggregateBudget > interactiveDirectBudget`; `interactiveDirectAggregateBudget.inMilliseconds >= 3 * interactiveDirectBudget.inMilliseconds`; and (preserve `:2486`) `interactiveDirectBudget.inSeconds <= 4`.
- **Mutation-that-re-reds (M3):** set `interactiveDirectAggregateBudget = interactiveDirectBudget` ⇒ `>` assertion fails (and TC-01 starvation re-reds behaviorally) — guards against silently re-coupling the constants.
- **Distinct-event discriminator:** N/A (constant invariant).

## Test Coverage Matrix
| Spec case | Behavior props | Tier | Test file::name | RED reason on HEAD | Mutation revert | Acceptance gate cmd | Harness registration |
|---|---|---|---|---|---|---|---|
| Slow-online discover within budget delivers live | per-step independent; no starvation; `transport=='direct'`, `status:'delivered'`, no inbox | unit/app | `send_chat_message_use_case_test.dart::FDC-01 slow discover within step budget still delivers direct (no starvation)` | outer==per-step (2s) → starves → inboxed | M1: outer dur → `interactiveDirectBudget` | `./scripts/run_test_gates.sh 1to1` | already in `ONE_TO_ONE_TESTS:36` + auto-glob `feature-host-all` |
| Discover-step timeout is probe-eligible | `peer_not_found`(eligible) before aggregate → probe → `relay` delivered | unit/app | `…::FDC-01 discover-step timeout is relay-probe-eligible (online-relay peer delivered live)` | outer 2s fires first → `direct_timeout` not eligible → probe skipped → inbox | M2a: drop discover `.timeout`/eligibility | `./scripts/run_test_gates.sh 1to1` | same (no array change) |
| Send-step `direct_timeout` is probe-eligible (§4.1 :701) | probe attempted (`probeRelayCallCount==1`) on send timeout | unit/app | `…::FDC-01 send-step direct_timeout triggers relay probe` | `direct_timeout` not eligible → probe skipped | M2b: send-step reason→`send_failed`/`false` | `./scripts/run_test_gates.sh 1to1` | same |
| Budget decouple invariant | aggregate > per-step, ≥3×; per-step ≤4s | unit | `…::FDC-01 aggregate direct budget exceeds the per-step budget` | const absent on HEAD | M3: aggregate == per-step | `./scripts/run_test_gates.sh 1to1` | same |
| **Preservation:** happy fast direct, no probe | `discoverCallCount==1`, `probeRelayCallCount==0` | unit/app | EXISTING `…::relay probe does not block direct discovery on the interactive path` (`:2491`) | (stays green) | n/a (regression guard) | `./scripts/run_test_gates.sh 1to1` | already registered |
| **Preservation:** offline peer still inboxes | `status:'inboxed'`, `storeInInboxCallCount==1` | unit/app | EXISTING `…::all active send paths failing falls back to inbox once` (`:2511`); `…::U5 worst-case: NO_RESERVATION` (`:3513`) | (stays green) | n/a | `./scripts/run_test_gates.sh 1to1` | already registered |
| **Preservation:** definitive `send_failed` (sent:false) stays non-eligible → inbox | no probe on `sent:false` | unit/app | EXISTING inbox-fallback tests (`:2511`) cover; TC-03 contrasts timeout vs sent:false | (stays green) | n/a | `./scripts/run_test_gates.sh 1to1` | already registered |

## Blind-Spot Sweep
- **Lifecycle / derived-state durability:** the new `direct` delivery must persist sticky transport — TC-01 asserts `recordSuccessfulTransportCallCount==1` so a learned-transport entry is written (`:1773-1775`), keeping the §P3 sticky layer consistent with the new path. The inbox `'inboxed'` custody/retry semantics are unchanged (TC-03 still lands `inboxed` on no-reservation).
- **Sibling-surface consistency:** GROUP send path — **N/A**: groups use a separate use case with separate budgets; FDC-01 edits only the 1:1 use case. Edit/retry 1:1 paths (`editChatMessage :1155`, `retryFailedMessage`) funnel through `sendChatMessage`, so they inherit the fix automatically — covered transitively; no extra row needed. **Sticky learned short-circuit** (`_tryLearnedShortCircuit` `:1407-1444`, invoked `:546`) is the OTHER 1:1 direct/relay leg and carries the SAME `interactiveDirectBudget` double-bound (per-call `timeoutMs` `:1414` + outer `.timeout` `:1416`) and a non-eligible `sticky_send_failed` (`:1439`) on timeout — but it is **NOT a mis-route**: on any non-success it FALLS THROUGH to the full parallel race (`:554` gates on `.success`; `:586` emits `CHAT_MSG_SEND_STICKY_FALLBACK`; race at `:597+`; see code comment `:543-544`), so a learned-but-slow online peer is rescued **transitively** by this plan's race fix (decoupled aggregate + eligible `direct_timeout`). Its own 2s `.timeout` is intentionally left non-eligible (the fall-through already covers it; flipping it would be redundant and is out of scope). Consequence: for a LEARNED peer the worst case is the sticky 2s prefix + the ~6s aggregate (see Risks).
- **Destructive-action side-effects:** none — no deletes/tombstones touched; only failure-classification + budget constants.
- **Invariant re-verification under new transitions:** the grace-window timer cap at `:799` (`interactiveDirectBudget - sendStopwatch.elapsed`) now coexists with a direct leg that may legitimately run past 2s. Re-verified: the grace timer arms ONLY on a *non-top successful* leg (`offerSuccess :798-806`); a late direct success with the local leg already failed (1.5s budget) hits `noPendingLegCanBeatBest()` → `completeWithBest()` immediately, so grace never traps a >2s direct win. TC-01 (direct success at ~2.2s, local absent) exercises exactly this and asserts `direct` delivery — implicit grace-invariant lock. No change to `transportGraceWindow`/`kStickyHeadStart`.
- **Concurrent-inbox interaction:** TC-01/02/03 are HIGH-confidence (`concurrentInbox==null`), so the new direct/relay path and the low-confidence concurrent-inbox path don't collide; the low-confidence path is FDC-03's territory and is left byte-identical (preserved by existing `:3251`/`:3319`/`:3391` tests).

## Invariants (locked by tests)
- INV-1: A foreground send whose direct leg makes real progress (discover<budget, dial ok, send acked) is delivered **live** (`direct`/`relay`), never demoted to high-confidence `inbox`. (TC-01, TC-02)
- INV-2: Every per-step direct timeout (discover/dial/**send**) AND the outer aggregate timeout is **relay-probe-eligible**. (TC-02 discover, TC-03 send, TC-01/M1 aggregate; the **dial** clause already holds on HEAD via the eligible `dial_failed` at `:1500` — see GREEN step C: dial = defensive hang-guard, no new RED.)
- INV-3: Per-step budgets are independent: aggregate ceiling strictly exceeds any single step (≥3×). (TC-04)
- INV-4 (preserved): genuinely-offline (`NO_RESERVATION`/null-discover) and definitive `send_failed` (`sent:false`) still inbox; happy fast direct still skips the probe. (existing tests)

## Step-By-Step Implementation Plan
> RED first: write the 4 tests + the `FakeP2PService.discoverDelay` helper; run `./scripts/run_test_gates.sh 1to1` and confirm TC-01/02/03 fail behaviorally (inboxed / probe-skipped) and TC-04 fails to compile. THEN implement.

1. **RED — tests + fake helper.** Add `discoverDelay` to `FakeP2PService` (honor at top of `discoverPeer`). Add the new test group with TC-01..04. Confirm RED. **Stop-if:** TC-01 passes on HEAD (means the chosen delays don't cross the 2s outer cap — bump `sendDelay`/`discoverDelay` so inner total > 2000ms while each step < 2000ms).
2. **GREEN step A — aggregate constant.** Add `const Duration interactiveDirectAggregateBudget = Duration(seconds: 6); // = 3 × per-step; serial ceiling so a slow step can't starve dial+send` near `:24`. Keep `interactiveDirectBudget` (2s) as the documented **per-step** budget. (Greens TC-04.)
   - **Seam:** module-level const block, lines ~21-27.
3. **GREEN step B — decouple the outer wrapper.** At `:699-703` change `.timeout(interactiveDirectBudget, onTimeout: () => _RaceResult.failed('direct_timeout'))` → `.timeout(interactiveDirectAggregateBudget, onTimeout: () => _RaceResult.failed('direct_timeout', relayProbeEligible: true))`. (Greens TC-01 starvation; makes the aggregate `direct_timeout` eligible.)
   - **Seam:** the `raceFutures.add(_tryDirectSend(...).timeout(...))` block.
4. **GREEN step C — per-step timeout in `_tryDirectSendInner`.** Give discover and send their OWN cut-off so a slow-but-bounded step yields an *eligible* failure instead of being swallowed by the aggregate.
   - **⚠ COMPILE TRAP — use `try`/`catch`, NOT an `onTimeout` callback.** `discoverPeer`/`dialPeer`/`sendMessageWithReply` return `Future<DiscoveredPeer?>` / `Future<bool>` / `Future<SendMessageResult>`; `Future.timeout`'s `onTimeout` must return that SAME value type, so `.timeout(interactiveDirectBudget, onTimeout: () => _RaceResult.failed(...))` does **not compile**. Wrap with a bare `.timeout(interactiveDirectBudget)` (default throws `TimeoutException`) inside a `try { … } on TimeoutException { return _RaceResult.failed(…); }`:
     ```dart
     try {
       peer = await p2pService.discoverPeer(targetPeerId, timeoutMs: budgetMs)
           .timeout(interactiveDirectBudget);
     } on TimeoutException {
       return _RaceResult.failed('peer_not_found', relayProbeEligible: true, stepTimings: timings);
     }
     ```
   - **discover step (behaviour-bearing — locked by TC-02):** as above → eligible `peer_not_found`.
   - **send step (behaviour-bearing — locked by TC-03):** wrap the send in a `try { … .timeout(interactiveDirectBudget) } on TimeoutException { sendTimedOut = true; }`, then at the failed-send return (`:1524`) emit `_RaceResult.failed(sendTimedOut ? 'direct_timeout' : 'send_failed', relayProbeEligible: sendTimedOut, stepTimings: timings)` — preserving definitive `sent:false` → non-eligible `send_failed`.
   - **dial step (DEFENSIVE hang-guard — justified no-RED, NOT a tested edit):** `dialPeer` is already passed `timeoutMs: budgetMs` (`:1493`) and on its own timeout returns `false` → the existing `dial_failed` return (`:1499-1500`) is *already* `relayProbeEligible: true`, already locked by the `dialPeerResult: false` probe tests. A wrapping `.timeout` fires only on a native *hang* (dialPeer never returns), which can't be forced deterministically without a new `dialDelay` fake lever. So **either OMIT the dial wrapper** (INV-2's dial clause is satisfied by `:1500`) **or** add it purely as a hang-guard — but do NOT claim it as tested. (If full hang-coverage is wanted, add `dialDelay` to `FakeP2PService` + a TC-FDC01-05 mirroring TC-02, then bump the count to +5.)
   - **Prod vs test cut-off (correct mental model):** against the REAL impl, `discoverPeer`/`dialPeer`/`sendMessageWithReply` catch internally and return `null`/`false`/`sent:false` (they do NOT throw `TimeoutException`), so these `.timeout` wrappers are *hang-guards* in production layered atop the impl's own `timeoutMs`. In TESTS the fake IGNORES `timeoutMs` (only `sendDelay`/the new `discoverDelay` delay), so the `.timeout` wrapper IS the deterministic cut-off that drives TC-02/TC-03. `stepTimings` is ALREADY a named param on `_RaceResult.failed` (`:1232`), so the returns above compile with no factory change. `dart:async` already imported (`:1`) for `TimeoutException`.
   - **Seam:** `_tryDirectSendInner` `:1467-1532` (success return `:1527`, failed-send return `:1524`); `budgetMs` stays `interactiveDirectBudget.inMilliseconds` (the per-step value).
5. **Verify mutations** M1/M2a/M2b/M3 each re-red exactly its mapped test, then restore.
6. **Run gates** (below) + `flutter analyze` + `git diff --check`. **Stop-if:** any existing `ONE_TO_ONE_TESTS` test regresses (especially `:2486` budget-bound, `:2511` inbox-fallback, `:2491` happy-direct) — investigate before proceeding; do not relax the assertion.

## Risks And Edge Cases
- **Latency regression on a truly-stuck online peer (now up to ~6s on the direct leg; ~8s for a LEARNED-then-slow peer that first burns the sticky 2s prefix before falling through to the race).** Pinned by design: each step is still bounded at 2s; the 6s aggregate only accrues when *every* step makes real progress (found peer, dialed, sending) — i.e. an online peer worth waiting for. A null/failed step returns immediately (TC-02/03 hit per-step cutoffs at ~2s, not 6s). Accept per proposal §8 P1-3 ("do NOT blindly cap the cold relay dial"; §10 carries only the NET-REL test-lock, not the anti-cap rationale).
- **Send-step timeout vs definitive `sent:false` conflation.** Pinned by TC-03 (timeout → eligible `direct_timeout`) contrasted with the existing `:2511` (`sent:false` → non-eligible inbox). The `sendTimedOut` flag keeps them distinct.
- **Grace-timer firing with a >2s direct leg.** Pinned by TC-01 (late direct win, local absent) + the §Blind-Spot re-verification of `noPendingLegCanBeatBest()`.
- **Test flakiness from real delays.** Mitigated: the production `.timeout` wrappers (not the fake) drive the cutoffs; delays chosen with ≥100ms margin from the 2s boundary; pattern matches existing `:3555` (5s) / `:4295` (3s) tests.

## Device/Relay Proof Profile
- **Host-only closes the LOGIC.** The fix is pure control-flow (failure classification + budget constants); the four host tests are sufficient for INV-1..4. No relay/Go deploy, no migration.
- **Real-wire "live-wins" is host-fake-only with a false-positive risk** (proposal §9 "Sequenced rollout" — Phase-0 item 1): a host test can pass via receiver `messageId` dedup even if the live path never fired. So a real slow-discover online send cannot be *fully* validated on host.
- **Device/sim smoke — DEFERRED (not gating):** there is no deterministic way to force a "slow discover but reachable" peer on a sim (mDNS shared host stack forces `DISABLE_LOCAL_DISCOVERY`; relay rendezvous timing is uncontrolled). Closest harness: `./scripts/run_test_gates.sh transport` (`integration_test/{background_reconnect,wifi_relay_fallback_smoke,transport_e2e}_test.dart`) as a non-regression check, and a manual 2-device "open→send→online peer" observation. Closure scenario (best-effort): `/sims 1to1 --only <N>` once a slow-peer scenario is registered (NOT in scope to add here).

## Acceptance Gates
```
# 1:1 host gate — ARG-LESS form runs the FULL 53-file ONE_TO_ONE_TESTS array
# (home of send_chat_message_use_case_test.dart + p2p_service_impl_test.dart).
# NOTE: passing args (e.g. --only) delegates to a SMALLER focused ONE_TO_ONE_HOST_TESTS
# subset (run_host_test_gates.sh:14-53) that omits 159-era files — use the arg-less form here.
./scripts/run_test_gates.sh 1to1            # expected: baseline + 4 new tests, 0 fail (record baseline at run; static decl tally ≈1174)

# transport integration smoke (non-regression) — TRANSPORT_TESTS also runs a 4th file
# (integration_test/media_stable_id_smoke_test.dart) beyond background_reconnect / wifi_relay_fallback_smoke / transport_e2e.
./scripts/run_test_gates.sh transport       # expected: device/fixture-gated (skips on lone sim), 0 fail

# regression neighbours (FDC-01 adds 0 tests here → baseline unchanged)
./scripts/run_test_gates.sh feed            # expected: baseline unchanged (static tally 279), 0 fail
./scripts/run_test_gates.sh groups          # expected: baseline unchanged (static tally ≈890), 0 fail

# host floor — feature-host-all auto-globs test/features/** (catches send_chat_message_use_case_test.dart);
# p2p_service_impl_test.dart is under test/core/ → covered by core-host-all/host-all, NOT feature-host-all.
./scripts/run_host_test_gates.sh feature-host-all   # expected: 0 fail
./scripts/run_host_test_gates.sh core-host-all      # expected: 0 fail (covers p2p_service_impl_test.dart)

# hygiene
flutter analyze                              # expected: 0 new
git diff --check                             # expected: clean
```

## Known-Failure Interpretation
- Pre-existing `groups` media-upload flakes (`ML-004`, durable-media-upload) and `ambient_background` Test-Flight-Improv guard are **not** FDC-01 — treat as known non-regressions if seen (per project memory). Any NEW failure inside `ONE_TO_ONE_TESTS` is in-scope and gating.

## Done Criteria (checkbox)
- [ ] `FakeP2PService.discoverDelay` helper added; all 4 RED tests written and confirmed RED behaviorally (TC-01/02/03) / compile (TC-04) on HEAD.
- [ ] `interactiveDirectAggregateBudget` added; outer wrapper decoupled + `direct_timeout` made `relayProbeEligible:true`.
- [ ] `_tryDirectSendInner` per-step `.timeout` wrappers added; send-step `sendTimedOut` distinguishes `direct_timeout`(eligible) from `send_failed`(non-eligible).
- [ ] M1/M2a/M2b/M3 each verified to re-red its mapped test, then restored.
- [ ] `1to1` + `feed` + `groups` + `transport` + `feature-host-all` green; `flutter analyze` 0-new; `git diff --check` clean.
- [ ] No edit to any other production file (collision discipline).

## Scope Guard (hard Do-not)
- Do **not** edit any production file other than `send_chat_message_use_case.dart`.
- Do **not** generalize the concurrent inbox / touch the `lowConfidence` gate (`:597-660`) — that is FDC-03.
- Do **not** make definitive `send_failed` (`sent:false`) probe-eligible.
- Do **not** lower `interactiveDirectBudget` (per-step) or `interactiveLocalBudget`.
- Do **not** add `warmPeer`, presence, or LAN-reuse gating here.
- Do **not** run any mutating git/graphify command; no Go/relay deploy; no migration.

## Accepted Differences
- The direct leg's worst-case wall-clock rises from 2s to the aggregate (~6s) for a genuinely-progressing-but-slow online peer — intentional (proposal §8 P1-3; avoids the more-inbox-fallback regression of capping).
- The GREEN mechanism for TC-02 is the per-step discover timeout yielding eligible `peer_not_found` (which was already eligible) reaching the tail *because* the aggregate no longer pre-empts it; TC-03 isolates the literal `direct_timeout`-eligibility (§4.1 :701). Both are required; neither alone closes INV-1+INV-2.

## Dependency Impact
- **productionFiles:** `lib/features/conversation/application/send_chat_message_use_case.dart` (only).
- **collisionFiles:** same file — shared with **FDC-02/03/04**; this cluster MUST run sequentially and **FDC-01 goes FIRST** (per FDC-00). Later plans rebase on FDC-01's budget constants + failure-eligibility.
- **gatedBy:** none.
- **Unblocks:** FDC-03 (P0-2 concurrent-inbox generalization) builds on the now-eligible failure classification; FDC-02/03/04 rebase on the budget constants.
