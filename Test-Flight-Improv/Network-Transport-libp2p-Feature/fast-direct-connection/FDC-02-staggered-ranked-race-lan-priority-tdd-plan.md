# FDC-02 — Staggered relay-penalized ranked race + LAN-by-priority + migrate-onto-winner  (Modification)

Status: awaiting-review — **REVISED 2026-06-26 after source verification; resolve the Critical Review Findings below before implementing.** The static file/line/harness/proposal claims verified ACCURATE (7-agent + main-loop source read); the *mechanism + test design* have confirmed defects (one BLOCKER) captured in the new section.
Spec: Network-Arch/Fast-Direct-Connection-Architecture-Proposal.md (§6.2 — the corrected core: "staggered ranked race", NOT blind fan-out; §6.1 LAN-by-priority-not-suppression; §12 DefaultDialRanker / iroh-Tailscale "migrate, don't dual-send" / SSB rooms-vs-pubs tier split)

## Critical Review Findings (source-verified 2026-06-26)

> A claim-by-claim review confirmed the plan's file/line/harness/proposal citations are unusually accurate
> (RC1–RC4, every existing-test line ref, the FakeP2PService knobs, the gate arrays/counts, and the §6.2/§12
> design mapping all check out against the live tree). The issues below are about the **mechanism and the RED
> test design**, where several locks would pass for the wrong reason or fail in a correct implementation.
> Severity: **C1 is a BLOCKER** (the core mechanism is unreachable as specified); C2–C7 are MAJOR; C8–C12 are
> minor/nit. Resolve C1 first — its resolution reshapes most TC setups, so do not rewrite TC-02-01/02/07
> bodies before deciding it.

### C1 — BLOCKER: a seeded live `/p2p-circuit` conn fires the **reuse fast-path**, which short-circuits *before* the race → the relay-live leg never runs, and FDC-02 does **not** fix the §6.1 warmed-circuit-bypasses-LAN case
The relay-live leg's eligibility ("a live `/p2p-circuit` connection already exists for the peer") is a strict
**subset** of the reuse fast-path's trigger `isAlreadyConnected = currentState.connections.any((c) => c.peerId ==
targetPeerId)` (`send_chat_message_use_case.dart:447-449`). When that is true, the reuse block (`:451-512`) calls
`sendMessageWithReply` and, on `sent`, **returns via `_completeSuccessfulSend` at `:482` — before the race is even
assembled at `:514`** (labeling the send `'relay'` for a circuit conn via `_inferDirectVsRelayForConnectedPeer`
`:1245-1252`). **Verified by an existing test** (`send_chat_message_use_case_test.dart:2280-2311`, "reused
relay"): seeding one `/p2p-circuit` conn yields `transport=='relay'`, `sendCallCount==1`, `discoverCallCount==0`,
`dialCallCount==0` — i.e. pure reuse, no race.

Consequences:
- **Test-construction blocker.** Nearly every TC ("Peer has a live `/p2p-circuit` conn …") routes through reuse,
  not the race. TC-02-01 (expects `'local'`) would get `'relay'` from reuse; TC-02-02's `relayLiveSendCount==1`
  and its "remove `_tryRelayLiveSend`" mutation are moot (reuse still delivers `'relay'`). With the leg-agnostic
  fake (see C2) you cannot even construct "reuse fails but the relay-live leg succeeds" — both call the same
  canned `sendMessageWithReply`.
- **The §6.1 bug lives in the reuse path, not the race.** A warmed circuit that should lose to a 30 ms LAN hop is
  carried by the reuse short-circuit, which never tries LAN. **FDC-04's `isLocalPeer` gate on reuse** (skip reuse
  → fall into the race) is what actually makes the race reachable for a connected peer. So the plan's "Out of
  scope" claim that *"FDC-02's ranking makes [FDC-04's gate] redundant-but-kept"* is **inverted**: FDC-04's reuse
  gate is the precondition for FDC-02's ranking to run at all for connected peers.

Recommended resolution (author's call — pick one and rewrite Step 3 + the TC setups accordingly):
- **(A, preferred — keeps FDC-02 self-contained and the §6.1 fix real):** make the reuse path *circuit-aware*:
  when `isAlreadyConnected` but the only/connected path is a `/p2p-circuit` (relay-live), do **not** short-circuit
  ahead of the LAN/direct race — start the race and only commit the circuit send after `kRelayLegStagger`,
  suppressed by an earlier LAN/direct win. The "relay-live leg" then *is* the staggered, rank-aware circuit send
  carved out of the reuse fast-path. (Touches `:447-512`, a slice the plan currently assigns wholesale to FDC-04 —
  reconcile the collision-map split with FDC-04, which keeps only the `isLocalPeer` belt-and-suspenders.)
- **(B):** re-sequence so FDC-04's reuse `isLocalPeer` gate lands **before/with** FDC-02 (contradicts the current
  FDC-02→FDC-04 roadmap order — needs FDC-00 sign-off).
- **(C):** redefine relay-live eligibility to a state the reuse path does *not* already cover (and document what
  that is) — note "live circuit conn exists" inherently implies `isAlreadyConnected`, so this likely collapses
  into (A).

### C2 — MAJOR: `relayLiveSendCount` cannot distinguish the relay-live leg from the direct leg or the probe tail
The relay-live leg, the direct leg (`:1507`), the reuse path (`:461`) and the probe tail (`:1590`) all call the
**identical** `p2pService.sendMessageWithReply(peerId, msg, timeoutMs:)`. The fake's `sendMessageWithReply` has no
leg-awareness and its `dialPeer` is a no-op that never mutates `currentState.connections`, so "invoked while only a
circuit conn exists" stays true for *every* caller once a circuit conn is seeded → the counter over-counts (a
direct-leg send is counted as relay-live), breaking the `relayLiveSendCount==0` asserts.
**Fix:** make the discriminator leg-attributable — either (a) isolate competing send paths per-TC (force the direct
leg to never reach send via `dialPeerResult=false`, and pin `probeRelayResult` so the tail cannot send) and assert
the existing `sendCallCount` (the proven pattern at `:2173-2178`/`:2206-2209`), or (b) have `_tryRelayLiveSend` use
a test-observable seam (a tag/marker the fake counts distinctly). State explicitly that the counter is unsound
unless the competing send paths are silenced.

### C3 — MAJOR: suppress-on-early-win guard must be `best != null`, not `completer.isCompleted`
A **direct (rank-2) win** does NOT complete the completer immediately — `offerSuccess` only sets `best` and arms a
~150 ms grace timer (`:798-806`); the completer settles later. So a direct success at t∈(~350 ms, 500 ms) leaves
`completer.isCompleted == false` when the 500 ms `kRelayLegStagger` timer fires → the guard passes → the relay-live
leg starts spuriously, defeating suppression exactly in the direct case. **Fix:** guard on `best != null` (any
committed success of any rank; relay-live is lowest rank so it can never improve on an existing `best`). **Add a
TC:** direct ack at ~400 ms while the local leg is slow → `relayLiveSendCount==0`; re-red by reverting the guard to
`completer.isCompleted`. (No current TC covers direct-wins-within-stagger.)

### C4 — MAJOR: the deferred relay-live leg must be counted in `pendingCount` — the "optional late offer that never blocks a failure settle" is unsound
`completeWithFailure` fires at `:820` via `else if (pendingCount <= 0 && deferredSuccessOffers <= 0)`. If the
relay-live leg is NOT counted in `pendingCount` and is started behind `Future.delayed(500ms)`, a fast LAN+direct
**double failure** at t<500 ms drives `pendingCount` to 0 → the race settles as failed **before the relay-live leg
starts** (its guard then suppresses it) → violates Invariant 2 / TC-02-02. `deferredSuccessOffers` (`:741`) buffers
SUCCESSES only, not an unstarted leg. **Fix:** count the eligible relay-live leg in `pendingCount` (or add a
`pendingRelayLive` flag) so a failure cannot settle while it is still eligible/unresolved; suppression is then the
guard resolving it to a *failed* `_RaceResult` (which decrements the count) once `best != null`.

### C5 — MAJOR: FDC-01 rebase facts — outer-wrapper constant, the optional dial wrapper, the missing aggregate ceiling, and unvalued budgets
On HEAD `_tryDirectSendInner` (`:1467-1532`) has **no** per-step `.timeout` wrappers — each step passes only
`timeoutMs: budgetMs` and the bridge calls `discoverPeer`/`dialPeer` add no Dart `.timeout`
(`p2p_bridge_client.dart` `callP2PRendezvousDiscover` ~`:337` / `callP2PPeerDial` ~`:382`). FDC-02 lands on
**FDC-01's** tree, where FDC-01 (its GREEN steps B/C):
- replaces the outer wrapper with `.timeout(interactiveDirectAggregateBudget /*6s*/, … relayProbeEligible: true)`
  and adds the new const `interactiveDirectAggregateBudget` — so the wrapper FDC-02 edits is **not**
  `interactiveDirectBudget`, and dropping it outright **removes the aggregate ceiling FDC-02 itself wants** *and*
  regresses FDC-01's eligible-aggregate-timeout invariant;
- wraps **only discover and send** in per-step `try { … .timeout(const) } on TimeoutException` (the documented
  compile-trap shape — `onTimeout:` won't type-check), and leaves the **dial** wrapper **optional/omitted**
  (no `dialDelay` fake lever exists).
**Fix Step 2 to:** (a) target `interactiveDirectAggregateBudget` as the outer wrapper and **keep a (possibly
relaxed) aggregate ceiling**, not drop it; (b) re-point the discover/send wrappers (try/catch shape) to
`kDirectDiscoverBudget`/`kDirectSendBudget`; (c) **own adding the dial wrapper** + a `dialDelay` lever if
`kDirectDialBudget` is to be tested; (d) **assign concrete values** to all three constants. The current
TC-02-05 (discover SUCCEEDS at 1800 ms ⇒ budget>1800) vs TC-02-06 (discover FAILS at its budget "not at 2 s" ⇒
budget meaningfully <2000) leaves a host-flaky (1800,2000) window — lower TC-02-05's discover (~1200 ms) and pick
e.g. `kDirectDiscoverBudget≈1500`/`kDirectDialBudget≈1000`/`kDirectSendBudget≈1500` under the aggregate ceiling;
state the sum-of-budgets worst case and how it stays bounded.

### C6 — MAJOR: TC-02-02 must pin `probeRelayResult` or the serial probe tail masks the mutation
The existing probe tail also yields `transport=='relay'` (on a `relayProbeEligible` race failure, `:1033-1059`).
The "remove `_tryRelayLiveSend`" mutation only re-reds because the fake's **default** `probeRelayResult` is
`RelayProbeResult.error` (`:82`). An implementer who sets `probeRelayResult=connected` ("relay reachable") gets a
false green. **Fix:** TC-02-02 must explicitly pin `probeRelayResult = error`/`noReservation` and note the tail
produces an identical `'relay'` label.

### C7 — MAJOR: TC-02-07 setup tests suppression, not rank
With the real config (stagger 500 ms), an **instant** direct ack commits `best=='direct'` and (grace) settles well
before the relay-live leg starts at 500 ms — so relay-live is *suppressed*, never raced, and the "extend
`_transportRank`" mutation cannot re-red (relay-live produces no result). **Fix:** make the direct ack land **after**
`kRelayLegStagger` (so relay-live is actually in-flight) with the relay-live ack within `transportGraceWindow` of it
— only then does rank adjudicate.

### C8 — minor: `_transportRank` needs no extension (relay-live reuses `'relay'==1`)
`_transportRank` already returns `local=>3, direct/reuse=>2, relay=>1` (`:71-77`); Go labels the relay-live result
`'relay'`, so it is already rank 1 < direct < local with **no code change**. Drop the "extend `_transportRank`"
language (Real Scope `:137`, Step 1 `:292`); TC-02-08 is RED-on-HEAD only on the **missing constants** (the
`3>2>=1` inequality already holds on HEAD), and the rank-flatten mutation belongs to TC-02-07, not TC-02-08.

### C9 — minor: `CHAT_MSG_SEND_TIMING.sendPath` cannot discriminate a relay-live win
The race-success branch computes `sendPath = raceResult.via == 'local' ? 'local' : 'direct'` (`:865`), so a
relay-live win (`via=='relay'`) is emitted as `sendPath=='direct'`, not `'relay'` (only the probe tail sets
`'relay'` at `:1034`, inbox sets `'inbox'`). The distinct-event note's claim that `sendPath` discriminates
`'relay'` is wrong for the new leg — rely on `message.transport=='relay'` and the (corrected) counter.

### C10 — minor: TC-02-09's "second relay write on win" mutation is a strawman
On the win path the serial probe/inbox tail (`:1021-1109`) is structurally skipped; `_completeSuccessfulSend`
performs no relay write. A "winner triggers a 2nd relay write" mutation would be newly-injected code, not a revert.
**Fix:** reframe TC-02-09 as a pure dedup/one-row preservation test (it overlaps `U4 dedup` `:3452`), or use a
realistic mutation (force `relayProbeEligible` on a WIN and assert the tail is not entered).

### C11 — minor: test-seam mechanics (`_currentState` is final; low-confidence gate keys on `isAlreadyConnected`)
`FakeP2PService._currentState` is `final` (assigned in the constructor `:86`), so `relayLiveConnection` must be a
constructor param (or reuse the existing `currentState:` param), not a mutable setter. Separately, the fake's
`isConnectedToPeer` always returns `false` (`:273`) while the low-confidence gate (`:609-611`) also keys on
`isAlreadyConnected` (from `currentState.connections`); confirm a seeded `/p2p-circuit` conn makes the send
high-confidence (no concurrent-inbox copy) so `storeInInboxCallCount` / one-row asserts hold.

### C12 — nit: a few cross-doc line refs drifted (functions still findable by name)
`p2p_bridge_client.dart` evidence lines are ~6 off (discover `bridge.send` ~`:337`, dial ~`:382`, inbox-store
`.timeout` `:457`). FDC-S5 Go refs (shared with FDC-04): `GoBridge.kt` cached pool is `:38` (not `:31`), `node.go`
`n.mu` RLock sites are not at `1385-1387` (declared `:40`; RLock pairs e.g. `:1418`), `bridge.go` nodeMu read is
`:1029-1031` (not `:1027-1029`), `classifyStreamTransport` starts ~`:129`. Low priority; fix in FDC-S5/FDC-04 too.

## Source Of Truth

1. **The proposal §6.2** (and its §12 prior-art corrections) is the design authority for *what* changes.
2. **`scripts/run_test_gates.sh`** wins over prose for *how it is validated* — the curated `1to1`
   (`ONE_TO_ONE_TESTS`) array is **41 entries**; the FDC-02-relevant members are
   `send_chat_message_use_case_test.dart` (`:36`), `p2p_service_impl_test.dart` (`:48`),
   `handle_app_resumed_upload_ordering_test.dart` (`:31`), `offline_inbox_roundtrip_test.dart` (`:19`) — and the
   `transport` array (`integration_test/{background_reconnect,wifi_relay_fallback_smoke,transport_e2e,media_stable_id_smoke}_test.dart`).
3. **This epic's roadmap `FDC-00-roadmap.md`** owns sequencing and the collision rule: FDC-01 → **FDC-02** →
   FDC-03 → FDC-04 all edit `send_chat_message_use_case.dart` and MUST run sequentially. FDC-02 runs **after
   FDC-01** (the `direct_timeout`→inbox correctness bugfix) and **before FDC-03** (inbox generalization) /
   **FDC-04** (`isLocalPeer` reuse gate + `warmPeer`).

The **leg timing / sequencing / rank** decisions are owned by Dart `sendChatMessage` (stagger,
suppress-on-early-win, per-leg budgets, media-tier gate); the **actual transport each leg uses** (direct vs the
live `/p2p-circuit`) is chosen by **Go/libp2p at send time** — new dials ranked by `DefaultDialRanker`, and among
already-open connections Go prefers a direct conn over a *limited* relay circuit — then Go **labels** the result
(`node.go:123-136 classifyStreamTransport`). **All FDC-02 ranking/stagger logic lives in the Dart
leg-orchestration** — Go is not modified by this plan; it relies only on Go's existing connection-preference +
labeling. There is **no** Dart/bridge seam to *force* relay-only vs direct-only — and none is needed: the
~500 ms stagger is the penalty, Go picks the path.

> **FDC-S5 true-parallel confirmed (gating spike).** This race assumes `race(legLAN, legDirect, legRelay)`
> runs as *real* Go-level concurrency over the single bridge, not a disguised serial ladder — so the
> independent per-leg budgets below are real wall-clock budgets, not stacked.
> [FDC-S5](FDC-S5-go-bridge-concurrency-design-note.md) confirms this by source read at every layer (iOS
> concurrent global queue `GoBridge.swift:35-42`; Android cached pool `GoBridge.kt:31`; Go `nodeMu`
> pointer-read-only `bridge.go:1027-1029`; node `n.mu` RWMutex read-concurrent `node.go:1385-1387`) **and now
> empirically**: the host microbench `TestConcurrentSendDialNoSerialize`
> (`go-mknoon/node/benchmark_bridge_concurrency_test.go`, run under `-race`) shows 8 concurrent dials finish
> in ~0.6 s against a ~4.8 s serial floor, and a real user send completes in <1 ms while 8 speculative warm
> dials each block ~0.6 s — i.e. the user send is **not** head-of-line blocked. No hidden serial ladder; the
> parallel `Future.wait` shape stands.

## Session Classification

**Implementation-ready** for the Dart leg-orchestration changes (relay-leg stagger, media→never-live-relay
exclusion, independent per-leg budgets, rank-LAN-highest, suppress-not-yet-started losers on early win). All
are host-testable against `FakeP2PService` (two-fake for the integration tier).

**Evidence-gated only at closure**: the proposal §9.1 / FDC-00 "Closure caveat" — a host fake can pass a
ranked-race test **via the parallel inbox/dedup copy even when the live leg never fired**. So host-green
proves *delivery + ordering logic*, never *"the LAN/direct leg actually won on the wire."* The
`local`/`direct`/`relay` *transport-label* assertions in this plan close the logic; the real-wire "live-wins"
claim is deferred to a `/sims 1to1` run + a two-device smoke (Device/Relay Proof Profile).

## Exact Problem Statement

**What's broken / missing.** On send, `sendChatMessage` runs exactly **two** race legs that **both start at
t=0 with no stagger** (`send_chat_message_use_case.dart:671-684` local leg, `:693-703` direct leg). There is:

1. **No relay penalty.** Relay is not a ranked, *delayed* leg — it rides *inside* the direct leg's
   `sendMessageWithReply` (Go uses `WithAllowLimitedConn`, label resolved by
   `_resolveGoSendTransport`/`_inferDirectVsRelayForConnectedPeer` :1241-1266) and inside the serial probe
   tail (`:1021-1062`). So a warmed `/p2p-circuit` connection can satisfy the send **as fast as** a direct
   dial — there is no `DefaultDialRanker`-style ~500 ms relay handicap that lets a slower-but-better LAN/direct
   leg win (§6.2a / §12 DefaultDialRanker `RelayDelay=500ms`).
2. **No relay-LIVE vs relay-INBOX tier separation.** A circuit-v2 *live* relay socket is "limited" —
   **2 min / 128 KB per direction, reset on violation, 1 reservation/peer** (§6.2b / §12). Nothing today stops
   a **media or large** 1:1 payload from being written over that live circuit inside the direct leg; the only
   media routing is the fail-closed *encryption* gate (`:329-341`), not a *transport-tier* gate.
3. **A single collective 2 s cap over a serial discover→dial→send.** `_tryDirectSendInner` (:1467-1532) runs
   `discoverPeer` then `dialPeer` then `sendMessageWithReply`, each passed `budgetMs = interactiveDirectBudget
   = 2000` (`:24`), all wrapped by ONE outer `.timeout(interactiveDirectBudget)` (`:699-703`). A slow discover
   **starves** dial+send → outer `onTimeout` yields `direct_timeout` (§4.1 / R2). FDC-02 owns the **latency
   half** of P0-3: give discover/dial/send **independent** budgets. (FDC-01 already owns the orthogonal
   *correctness* half — making `direct_timeout` relay-probe-eligible — and lands first.)
4. **No "migrate onto winner / collapse losers".** Once a leg wins, no mechanism *suppresses* a not-yet-fired
   leg; the relay-live attempt, were it a distinct delayed leg, should never even start once a better leg has
   already committed (iroh/Tailscale collapse-onto-chosen-path; §6.2a / §12). Dart Futures aren't cancellable,
   so an *already in-flight* loser can't be killed — correctness leans on **receiver `messageId` dedup**
   (present; `U4 dedup` test :3452) — but a leg that hasn't started yet *must not be started*.

**Who feels it.** Same-WiFi / both-foreground 1:1 senders: a warmed relay circuit silently carries a send
that a 30 ms LAN hop should have carried ("§6.1 relay-bypass, by latency"); media senders pay (or fail) a
128 KB-capped live circuit; an online-but-slow-to-discover peer's direct leg is starved by the collective cap.

**What must improve.**
- A **viable LAN or direct leg that acks before the relay penalty elapses wins, and the relay-live leg is
  never started** (suppressed-on-early-win, not merely out-ranked after the fact).
- **Media / large payloads NEVER traverse the live relay socket** — they go LAN-live, direct-live, or the
  durable inbox (relay-INBOX) only.
- **Discover / dial / send get independent budgets** so a slow discover no longer starves dial+send.
- **LAN ranks highest** so a warmed relay circuit *races but loses* (§6.1 by priority, not suppression).

**What must stay unchanged (preserved sentinels).**
- Receiver `messageId` dedup is the only correctness backstop for un-cancellable in-flight losers
  (`U4 dedup` :3452, `U-N4 dedup neg` :3476).
- The grace-window rank order `local(3) > direct/reuse(2) > relay(1)` (`_transportRank` :71-77) and the
  existing `U1 grace`/`U-N1 grace neg` outcomes (:3027/:3056).
- The local-leg budget `interactiveLocalBudget = 1500` and its cut-at-budget behavior (`U5 budget` :3551).
- Sticky short-circuit, reuse fast-path, low-confidence concurrent inbox, NET-REL-01 LAN locks, the media
  *encryption* fail-closed gate, and the inbox-custody status semantics ('inboxed' non-terminal, doc 115) —
  all **owned by other FDC plans or prior NET-REL work; FDC-02 must not alter their outcomes.**

## Root Cause (verify→refute confirmed)

| # | Mechanism (file:line, source-read) | Confirmed |
|---|---|---|
| RC1 | **Both legs start at t=0; relay has no handicap.** `raceFutures.add(_tryLocalSendWithDiscovery(...))` (:671-684) and `raceFutures.add(_tryDirectSend(...))` (:693-703) are added back-to-back with no delay; relay is not its own leg but is folded into the direct leg's `sendMessageWithReply` (`_inferDirectVsRelayForConnectedPeer` detects `/p2p-circuit` :1245-1251) and the serial tail `_tryRelayProbeSend` (:1534-1663). | ✅ read |
| RC2 | **No transport-tier media gate.** The only media gate is `_sanitizeDirectMediaAttachments` (:133-147, *encryption* metadata). The direct leg sends `jsonString` over whatever connection `dialPeer` lands — including a `/p2p-circuit` — with no payload-size / media check against the 128 KB live-circuit cap. | ✅ read |
| RC3 | **Single collective direct budget.** `_tryDirectSendInner` passes `budgetMs = interactiveDirectBudget.inMilliseconds` (2000, `:1472`) to all three of `discoverPeer`/`dialPeer`/`sendMessageWithReply`, and the whole future is `.timeout(interactiveDirectBudget)` at `:699-703` → a 1.8 s discover leaves ~0.2 s for dial+send → `direct_timeout` at `:701`. | ✅ read |
| RC4 | **No suppression of an unstarted loser.** The completer commits `best` on first eligible success (`completeWithBest` :743-748) but there is no relay-live leg whose *start* is conditioned on "no better leg has committed yet"; relay work is already in-flight inside the direct leg, so nothing is left to suppress. | ✅ read |

**Refuted — do NOT re-introduce.**
- ❌ "Race *everything* in parallel / blind fan-out" — the proposal §6.2/§12 explicitly rejects this (libp2p
  v0.28 anti-pattern, ~30 % extra dials). FDC-02 is a **staggered** race, not added parallelism.
- ❌ "Cancel the losing legs reliably." Refuted in §6.2 honesty notes: Dart Futures + one-shot Go `message:send`
  are not cancellable. FDC-02 only *avoids starting* an unstarted leg; in-flight losers rely on **receiver
  dedup**. Do not plan a cancellation API.
- ❌ "Suppress the relay entirely when LAN is viable." Refuted by §6.1: LAN-first is **by priority** — relay
  must still *race* (and win when LAN/direct genuinely fail), just *lose* the ranked tie. Suppression-by-flag
  is FDC-04's belt-and-suspenders `isLocalPeer` gate, not FDC-02's mechanism.
- ❌ "Cap the relay/direct dial at 3 s blind." Refuted by §8 P1-3 / FDC-07 — independent budgets are not a
  blanket shortening; the cold relay dial timing is FDC-07/FDC-S1 territory.

## Real Scope

**In scope (FDC-02, all in `send_chat_message_use_case.dart`):**
- A new **staggered relay-LIVE leg** `_tryRelayLiveSend` that (a) runs only when a live `/p2p-circuit`
  connection already exists for the peer, (b) is **started after a `kRelayLegStagger` (~500 ms) delay** (the
  penalty), (c) is **excluded for media / large payloads**, (d) is **labeled by Go's transport result** —
  normally `'relay'` (the live circuit is the path Go uses when no direct conn is open), but the leg is
  **relay-opportunistic, not relay-forced**: if a direct conn is already open, Go may send direct and label it
  so. Dart owns the leg *timing*; Go owns the *path*.
- **Suppress-on-early-win**: the staggered relay-live leg is *not started* if a LAN/direct success has already
  committed (or is committed during the stagger window).
- **Independent per-leg budgets** for the direct leg: `kDirectDiscoverBudget` / `kDirectDialBudget` /
  `kDirectSendBudget` replacing the single collective `interactiveDirectBudget` cap inside `_tryDirectSendInner`
  (the latency half of P0-3).
- **Rank constants aligned with `DefaultDialRanker`**: `kRelayLegStagger = 500ms`, `kPublicAddrTail = 250ms`,
  `kPrivateAddrTail = 30ms`, with the locked ordering invariant `kRelayLegStagger > kPublicAddrTail >
  kPrivateAddrTail`. `_transportRank` is **left numerically unchanged** — Go labels the relay-live result
  `'relay'`, which already ranks 1 < direct(2) < local(3); only a doc comment is added. **(See C8.)**
- **Media → never live-relay** transport-tier gate `_liveRelayEligible(hasAttachments, payloadBytes)`.

**Out of scope (owning plan):**
- `direct_timeout` → relay-probe-eligibility (correctness mis-route) → **FDC-01** (lands before FDC-02).
- Generalizing the durable inbox out of the low-confidence gate + dropping the serial probe→inbox tail →
  **FDC-03**.
- Gating the **reuse fast-path** (`:447-465`) and **sticky short-circuit** (`:528-595`) behind `isLocalPeer`,
  and `warmPeer` → **FDC-04** (FDC-02 only ranks *within the race*). ⚠ **C1 inverts the original "FDC-02's ranking
  makes FDC-04's gate redundant-but-kept" claim:** for a *connected* circuit peer the reuse fast-path returns
  before the race, so FDC-04's `isLocalPeer` reuse gate is what makes FDC-02's race ranking *reachable* — not the
  other way around. Either reconcile this (resolution A pulls a circuit-specific stagger slice of `:447-512` into
  FDC-02) or re-sequence with FDC-04. Update the FDC-00 collision-map split accordingly.
- **Per-address** 30 ms/250 ms Happy-Eyeballs staggering *inside* a single `dialPeer` → that is the Go host's
  `DefaultDialRanker` → **FDC-11** (gated by FDC-S2, device-only). FDC-02 implements the **leg-granularity**
  analog in Dart and pins the constant ordering only.
- Redis durable inbox backend / relay pool → **FDC-10**.

## Files To Inspect Next

**Production entry / use-case (the single edited file):**
- `lib/features/conversation/application/send_chat_message_use_case.dart` — budgets `:21/:24/:27/:48/:57/:67`;
  reuse `:447-512`; sticky `:528-595`; low-confidence inbox `:597-660`; **race assembly `:662-703`**; completer
  / rank / grace / head-start `:705-862`; success persist `:864-896`; serial probe→inbox tail `:998-1109`;
  `_transportRank` `:71-77`; `_tryLocalSendWithDiscovery` `:1275-1307`; `_tryLocalSend` `:1309-1365`;
  `_tryDirectSend`/`_tryDirectSendInner` `:1452-1532`; `_tryRelayProbeSend` `:1534-1663`;
  `_inferDirectVsRelayForConnectedPeer` `:1241-1253`; `_resolveGoSendTransport` `:1255-1266`.

**Models / service contract (dependency-only context, NOT edited):**
- `lib/core/services/p2p_service.dart` — `P2PService` interface: `currentState.connections`
  (`PeerConnection.multiaddrs` carries `/p2p-circuit`), `sendMessageWithReply`, `discoverPeer`, `dialPeer`,
  `discoverLocalPeer`, `isLocalPeer` (:4097), `probeRelay` (:4074), `lastKnownGoodTransport` (:4100),
  `recordSuccessfulTransport`, `storeInInbox`, `RelayProbeResult`, `DurableLanSender`/`LanSendAck`.
- `lib/features/p2p/domain/models/send_message_result.dart` — `SendMessageResult{sent, acknowledged,
  transport, streamOpenMs, writeMs, ackWaitMs}` (the Go transport label surfaces here).
- `lib/features/conversation/domain/models/conversation_message.dart` / `message_payload.dart` — `transport`
  field is the persisted `via`; receiver `dedupKey`/`messageId` is the collapse-losers backstop.

**Direct + integration tests (edited / added):**
- `test/features/conversation/application/send_chat_message_use_case_test.dart` — **curated `1to1` member**
  (`run_test_gates.sh:36`); hosts `FakeP2PService` (knobs: `sendDelay` :219, `localSendDelay` :220,
  `discoverLocalPeerDelay` :202, `discoverLocalPeerResult`, `lastKnownGoodTransportResult` :207,
  `dialPeerResult`, `probeRelayResult`, `storeInInboxCallCount`); existing NET-REL-05 group (:3022) is the
  pattern to extend.
- `test/features/conversation/integration/ranked_race_relay_penalty_test.dart` — **NEW** two-`FakeP2PService`
  integration tier (sender + receiver, dedup-by-id end-to-end).

## Existing Tests Covering This Area

| Test (file::name) | Status | In which gate array |
|---|---|---|
| `send_chat_message_use_case_test.dart::U1 grace: local lands within grace of direct → transport == local` (:3027) | exists | `1to1` (`run_test_gates.sh:36`) |
| `…::U-N1 grace neg: local fails → direct chosen with no hung wait` (:3056) | exists | `1to1` |
| `…::U2 cold baseline: no learned transport pays one discover + one dial` (:3148) | exists | `1to1` |
| `…::U5 budget: a slow local leg is cut at the local budget` (:3551) | exists | `1to1` |
| `…::U5 worst-case: offline peer → NO_RESERVATION → durable inbox custody` (:3513) | exists | `1to1` |
| `…::U4 dedup: same messageId across paths persists exactly one row` (:3452) | exists | `1to1` |
| `…::NET-REL-01 LAN transport U1/U2/U3/U-N1` (:1698-1833) | exists | `1to1` |
| `…::falls through to relay when local send fails` (:1590) | exists | `1to1` |
| `…::Phase 3 — relay probe recovery` group (:1967) | exists | `1to1` |
| `integration_test/transport_e2e_test.dart` | exists | `transport` (`:167`) |
| `integration_test/wifi_relay_fallback_smoke_test.dart` | exists | `transport` (`:166`) |
| **Staggered-relay-penalty / media-never-live-relay / per-leg-budget / suppress-on-early-win locks** | **MISSING** | to add (Tier-1 into the curated send test; Tier-2 new file → add to `1to1` array) |

## RED Test Catalog (BEFORE any prod code)

> Distinct-event discriminator note: several legs persist the same terminal `SendChatMessageResult.success`
> row. The load-bearing discriminators are (a) the persisted `message.transport` label
> (`'local'`/`'direct'`/`'relay'`/`'inbox'`), (b) the `CHAT_MSG_SEND_TIMING` `sendPath`, and (c) a NEW
> per-leg call counter on the fake (`relayLiveSendCount`) proving the relay-live leg *did / did not start*.
> "Delivered via dedup" alone is NOT accepted as proof a live leg won (FDC-00 closure caveat).
>
> ⚠ **Review corrections (must apply): (b) is NOT a valid relay-live discriminator** — the race-success branch
> maps any non-local `via` to `sendPath=='direct'` (`:865`), so a relay-live win emits `'direct'`, not `'relay'`
> (**C9**). **(c) is unsound as defined** — the relay-live, direct, reuse, and probe-tail sends all call the same
> `sendMessageWithReply`, so the counter over-counts unless competing send paths are silenced per-TC (**C2**).
> And **the whole "seed a circuit conn" premise routes through the reuse fast-path, not the race (C1)** — most TC
> setups below need rework after C1 is resolved. Rely on `message.transport=='relay'` + a *leg-attributable*
> counter, never on `sendPath` or delivery alone.

**Test seam additions to `FakeP2PService` (test code only):** `discoverPeerDelay` (gates `discoverPeer`),
`relayLiveConnection` (seed `currentState.connections` with a `/p2p-circuit` multiaddr for the peer — **must be a
constructor param / reuse `currentState:`; `_currentState` is `final` at `:86`**, C11),
`relayLiveSendCount` (**must be leg-attributable, NOT "invoked while only a circuit conn exists"** — that predicate
counts the direct/reuse/probe sends too; see C2), and a `circuitSendDelay` so the relay-live ack can be timed
against `kRelayLegStagger`. **⚠ Seeding `relayLiveConnection` makes `isAlreadyConnected` true → the reuse fast-path
(`:447-512`) short-circuits before the race (C1); these seams are only meaningful once C1's resolution makes the
race reachable for a connected circuit peer.**

> ⚠ **Per-row corrections from the review (apply with C1's resolution):** TC-02-01 setup must make LAN genuinely
> win (disable/delay the direct leg) and avoid the reuse short-circuit — **C1, C2, F5**. TC-02-02 must pin
> `probeRelayResult=error/noReservation` (else the probe tail masks the mutation) — **C6**. TC-02-07's direct ack
> must land *after* `kRelayLegStagger` or it tests suppression not rank — **C7**. TC-02-08 is RED only on the
> missing constants (the rank inequality already holds) — **C8**. TC-02-09's "2nd relay write" mutation is a
> strawman; reframe as dedup preservation — **C10**. Every `relayLiveSendCount` cell depends on the leg-attributable
> redefinition — **C2**; `Discriminator` cells naming `sendPath` for relay-live are invalid — **C9**.

| # | file::name | Tier | Shape / setup | RED-on-HEAD because | GREEN asserts | Mutation that re-reds | Discriminator |
|---|---|---|---|---|---|---|---|
| TC-02-01 | `send_chat_message_use_case_test.dart::FDC-02 relay penalty: LAN ack before the relay stagger wins and the relay-live leg never starts` | 1 (app) | Peer has a live `/p2p-circuit` conn AND is LAN-reachable; `localSendDelay = 40ms`; `circuitSendDelay = 0` (relay would be instant if started). | HEAD has no relay leg stagger and no `relayLiveSendCount`; relay rides the direct leg with no penalty → no symbol/behavior exists. | `transport == 'local'`; `relayLiveSendCount == 0`; `sendPath == 'local'`. | Set `kRelayLegStagger = Duration.zero` → relay-live leg starts at t=0, may win → `relayLiveSendCount >= 1` (and/or `transport=='relay'`). | `relayLiveSendCount`, `message.transport` |
| TC-02-02 | `…::FDC-02 relay penalty: when LAN+direct both fail, the staggered relay-live leg still carries (races-but-wins-when-alone)` | 1 (app) | Live circuit conn present; `discoverLocalPeer→false`, direct `dialPeerResult=false`; circuit send succeeds+acked. | No staggered relay-live leg exists on HEAD (relay only via direct/probe tail). | `transport == 'relay'`; `relayLiveSendCount == 1`; result `success`. | Remove the `_tryRelayLiveSend` add → relay-live never runs → send falls to inbox/probe tail (`transport != 'relay'`). | `message.transport`, `relayLiveSendCount` |
| TC-02-03 | `…::FDC-02 media never live-relay: media payload with a live circuit skips the relay-live leg` | 1 (app) | `mediaAttachments` (full encryption metadata) + live `/p2p-circuit` conn; LAN+direct dials fail. | No transport-tier media gate exists; HEAD would send media over the circuit. | `relayLiveSendCount == 0`; the message does NOT terminate `'relay'` (it lands inbox custody / direct, never live-relay). | Make `_liveRelayEligible` return true for media → `relayLiveSendCount >= 1`. | `relayLiveSendCount` + `DIRECT_MEDIA_*`/timing |
| TC-02-04 | `…::FDC-02 large payload never live-relay: a >budget text payload skips the relay-live leg` | 1 (app) | `text` whose `jsonString` length > `kLiveRelayMaxPayloadBytes`; live circuit conn; LAN+direct fail. | No size gate on HEAD. | `relayLiveSendCount == 0`. | Drop the size branch of `_liveRelayEligible` → `relayLiveSendCount >= 1`. | `relayLiveSendCount` |
| TC-02-05 | `…::FDC-02 independent budgets: a slow discover (1.8s) still delivers direct instead of direct_timeout` | 1 (app) | `discoverPeerDelay = 1800ms`, `dialPeerResult=true`, direct send instant+acked; no LAN, no circuit. | HEAD caps discover+dial+send collectively at `interactiveDirectBudget=2000` → 1.8 s discover starves → `direct_timeout`, result is NOT a live `'direct'`. | `transport == 'direct'`; result `success`; no `direct_timeout` failure path taken. | Revert `_tryDirectSendInner` to a single collective `interactiveDirectBudget` cap (or re-wrap with one outer `.timeout`) → starvation → `direct_timeout`. | `message.transport`, `CHAT_MSG_SEND_TIMING.outcome` |
| TC-02-06 | `…::FDC-02 per-leg budget cap: discover that overruns its OWN budget fails fast, dial/send untouched` | 1 (app) | `discoverPeerDelay` > `kDirectDiscoverBudget`; assert the direct leg returns `peer_not_found`/timeout at ≈ the discover budget, not at 2 s. | HEAD has no separate `kDirectDiscoverBudget`. | Elapsed direct-leg failure ≈ `kDirectDiscoverBudget` (± slack), reason is discover-scoped. | Set `kDirectDiscoverBudget = interactiveDirectBudget` → fails at 2 s. | timing / reason |
| TC-02-07 | `…::FDC-02 rank: relay-live ack within grace of a direct ack loses to direct` | 1 (app) | No LAN; direct dial+ack instant; live circuit also acks; both within `transportGraceWindow`. | HEAD has no separate relay-live leg to out-rank. | `transport == 'direct'` (rank 2 > relay rank 1). | Extend `_transportRank` to give relay-live ≥ direct → `transport == 'relay'`. | `_transportRank`, `message.transport` |
| TC-02-08 | `…::FDC-02 rank invariant: kRelayLegStagger > kPublicAddrTail > kPrivateAddrTail and relayLive ranks below LAN+direct` | 1 (unit) | Pure constant + `_transportRank` assertions (no fake). | Constants / extended rank do not exist on HEAD. | `kRelayLegStagger > kPublicAddrTail > kPrivateAddrTail`; `_transportRank('local') > _transportRank('direct') >= _transportRank('relay')`. | Reorder any constant / flatten the rank → assertion fails. | constant + rank values |
| TC-02-09 | `…::FDC-02 migrate-onto-winner: an in-flight loser is NOT cancelled but the receiver dedups (one row)` | 1 (app) | LAN wins; a direct/circuit loser is also in-flight (un-cancellable) and "delivers"; same `messageId`. | Preserves the dedup invariant under the new leg; on HEAD there is no relay-live loser to assert about. | Exactly ONE persisted outgoing row for the id; `transport == 'local'`; no second relay write (`storeInInbox`/circuit not double-counted). | Make the winner commit start a second sequential relay write → a second row / extra `relayLiveSendCount`. | row count, `relayLiveSendCount` |
| TC-02-10 | `…::FDC-02 preservation: U1 grace local-within-grace still yields transport==local` (re-assert :3027 under new leg wiring) | 1 (app) | Existing U1 setup, now with a relay-live leg present. | N/A — guards regression of the rank machinery. | Unchanged: `transport == 'local'`. | Any rank/stagger change that lets relay/direct beat a within-grace local → fails. | `message.transport` |
| TC-02-11 | `ranked_race_relay_penalty_test.dart::FDC-02 e2e: sender LAN-wins, relay-live leg never fires, receiver persists one decrypted row` | 2 (integ, two fakes) | Sender + receiver `FakeP2PService`; sender has live circuit + LAN; LAN delivers; receiver dedups by id. | New file; behavior absent on HEAD. | Sender `transport=='local'` + `relayLiveSendCount==0`; receiver has exactly one inbound row for the id. | `kRelayLegStagger=0` → relay-live fires → receiver still one row (dedup) BUT sender `relayLiveSendCount>=1` (proves the *fast-path* discriminator, the thing dedup masks). | sender `relayLiveSendCount` (the FDC-00 dedup-masking discriminator) |
| TC-02-12 | `ranked_race_relay_penalty_test.dart::FDC-02 e2e: media send with live circuit reaches the receiver via inbox/direct, never the live circuit` | 2 (integ, two fakes) | Media payload; sender has a live circuit; LAN+direct fail. | New file. | Sender `relayLiveSendCount==0`; receiver eventually holds the media row (via inbox custody). | `_liveRelayEligible` true-for-media → `relayLiveSendCount>=1`. | sender `relayLiveSendCount` |

## Test Coverage Matrix (zero empty cells)

| Spec case (§6.2) | Behavior props | Tier | Test file::name | RED reason on HEAD | Mutation revert | Acceptance gate cmd | Harness registration |
|---|---|---|---|---|---|---|---|
| §6.2a relay penalty ~500 ms; LAN wins, relay leg not started | suppress-on-early-win; `relayLiveSendCount==0` | 1 | `send_chat_message_use_case_test.dart::FDC-02 relay penalty: LAN ack before the relay stagger wins…` (TC-02-01) | no stagger / no relay-live leg | `kRelayLegStagger=0` | `./scripts/run_test_gates.sh 1to1` | already curated (`run_test_gates.sh:36`) — no add |
| §6.2a relay still races-and-wins when LAN/direct fail | relay-live carries; `transport=='relay'` | 1 | `…::FDC-02 relay penalty: when LAN+direct both fail…` (TC-02-02) | no relay-live leg | remove `_tryRelayLiveSend` add | `./scripts/run_test_gates.sh 1to1` | already curated |
| §6.2b media never over live relay | media→`relayLiveSendCount==0` | 1 | `…::FDC-02 media never live-relay…` (TC-02-03) | no transport-tier media gate | `_liveRelayEligible` true-for-media | `./scripts/run_test_gates.sh 1to1` | already curated |
| §6.2b large payload (128 KB cap) never live relay | size→`relayLiveSendCount==0` | 1 | `…::FDC-02 large payload never live-relay…` (TC-02-04) | no size gate | drop size branch | `./scripts/run_test_gates.sh 1to1` | already curated |
| P0-3 latency half: independent budgets fix R2 starvation | slow-discover→`transport=='direct'` | 1 | `…::FDC-02 independent budgets: a slow discover (1.8s)…` (TC-02-05) | single 2 s collective cap | restore collective cap | `./scripts/run_test_gates.sh 1to1` | already curated |
| Per-leg budget isolation | discover fails at its own budget | 1 | `…::FDC-02 per-leg budget cap…` (TC-02-06) | no `kDirectDiscoverBudget` | `kDirectDiscoverBudget=interactiveDirectBudget` | `./scripts/run_test_gates.sh 1to1` | already curated |
| §6.2/§12 rank LAN>direct>relay-live | relay-live within grace loses to direct | 1 | `…::FDC-02 rank: relay-live ack within grace of a direct ack…` (TC-02-07) | no relay-live leg in rank | relay-live rank ≥ direct | `./scripts/run_test_gates.sh 1to1` | already curated |
| §12 DefaultDialRanker constant alignment | `kRelayLegStagger>kPublicAddrTail>kPrivateAddrTail`; rank ordering | 1 | `…::FDC-02 rank invariant…` (TC-02-08) | constants absent | reorder constant / flatten rank | `./scripts/run_test_gates.sh 1to1` | already curated |
| §6.2a migrate-onto-winner / collapse losers via dedup | one row; no second relay write | 1 | `…::FDC-02 migrate-onto-winner…` (TC-02-09) | no relay-live loser path | winner triggers 2nd relay write | `./scripts/run_test_gates.sh 1to1` | already curated |
| Preservation: U1 grace local-within-grace | `transport=='local'` unchanged | 1 | `…::FDC-02 preservation: U1 grace…` (TC-02-10) | guards regression | rank/stagger regression | `./scripts/run_test_gates.sh 1to1` | already curated |
| §6.2a e2e LAN-wins, dedup-masking discriminator | sender `relayLiveSendCount==0`; receiver 1 row | 2 | `ranked_race_relay_penalty_test.dart::FDC-02 e2e: sender LAN-wins…` (TC-02-11) | new file | `kRelayLegStagger=0` | `./scripts/run_test_gates.sh 1to1` + `feature-host-all` | ADD file to the `1to1` readonly array in `scripts/run_test_gates.sh`; auto-globs under `feature-host-all` |
| §6.2b e2e media never live relay | sender `relayLiveSendCount==0`; receiver gets media | 2 | `ranked_race_relay_penalty_test.dart::FDC-02 e2e: media send…` (TC-02-12) | new file | `_liveRelayEligible` true-for-media | `./scripts/run_test_gates.sh 1to1` + `feature-host-all` | same new file (one add covers both) |

## Blind-Spot Sweep

- **Lifecycle / derived-state durability.** The new relay-live leg reads `currentState.connections` at race
  time; if the circuit drops mid-race the leg's `sendMessageWithReply` fails and the race falls through —
  covered by TC-02-02's negative complement (relay fails → inbox custody). The sticky `recordSuccessfulTransport`
  funnel (:1773-1775) must still only fire for **acked LIVE** deliveries; a relay-live win records `'relay'`
  exactly as the probe-tail relay win does today → asserted in TC-02-02 (no change to the funnel contract). **Row.**
- **Sibling-surface consistency.** The **group** send path (`send_group_message_use_case`) has its own race and
  is **NOT** in FDC-02 scope (proposal/roadmap are 1:1-only here). N/A — but the `groups` gate is run as a
  regression floor to prove no shared-helper bleed.
- **Destructive-action side-effects.** None — FDC-02 adds a leg + budgets; it persists no new destructive state.
  The one hazard is a **double relay write** (live leg + sequential tail) for one message → explicitly locked by
  TC-02-09 (one row, no second write). **Row.**
- **Invariant re-verification under new transitions.** (1) Receiver `messageId` dedup under the new leg →
  TC-02-09 / TC-02-11. (2) Rank order `local>direct>relay` under the *added* relay-live participant → TC-02-07.
  (3) Low-confidence concurrent inbox (`:639-660`) must be untouched by FDC-02 — re-run `U3 concurrent` (:3251)
  / `U-N3` (:3391) as preservation. **Row.**
- **Inbox-tier separation (the §6.2b crux).** relay-LIVE (circuit, capped) ≠ relay-INBOX (`storeInInbox`,
  durable). FDC-02 only adds/penalizes the LIVE leg and excludes media from it; the INBOX deposit is FDC-03's
  generalization and FDC-02 must not change `storeInInbox` call sites. Asserted by `storeInInboxCallCount`
  staying as today on the high-confidence path (preservation of `U-N3`). **Row.**

## Invariants (locked by tests)

1. A LAN/direct leg that acks before `kRelayLegStagger` elapses **wins and the relay-live leg never starts**
   (`relayLiveSendCount==0`). [TC-02-01, TC-02-11]
2. The relay-live leg **still races and wins when LAN+direct genuinely fail** (LAN-first is by priority, not
   suppression). [TC-02-02]
3. **Media and large (>`kLiveRelayMaxPayloadBytes`) payloads never traverse the live relay socket.**
   [TC-02-03, TC-02-04, TC-02-12]
4. Discover / dial / send have **independent budgets**; a slow discover no longer starves dial+send into
   `direct_timeout`. [TC-02-05, TC-02-06]
5. Transport rank is `local(3) > direct/reuse(2) > relay-live(1)` and the constant ordering
   `kRelayLegStagger > kPublicAddrTail > kPrivateAddrTail` holds. [TC-02-07, TC-02-08]
6. Exactly **one** outgoing row per `messageId`; un-cancellable losers rely on **receiver dedup**, and a
   committed winner triggers **no second relay write**. [TC-02-09, TC-02-11]
7. Preserved: U1 grace local-win, low-confidence concurrent inbox, NET-REL-01 LAN locks, sticky funnel.
   [TC-02-10 + re-run of named existing tests]

## Step-By-Step Implementation Plan (RED first)

> Each step: write the RED test(s) first, watch them fail for the *named* reason, implement the *named seam*,
> green, then mutate-and-re-red. Stop-if blockers noted.

1. **RED — constants + rank (TC-02-08).** Add the failing constant/rank assertions.
   **Seam:** new top-level consts `kRelayLegStagger = Duration(milliseconds: 500)`,
   `kPublicAddrTail = Duration(milliseconds: 250)`, `kPrivateAddrTail = Duration(milliseconds: 30)`,
   `kLiveRelayMaxPayloadBytes` (e.g. `96 * 1024`, headroom under the 128 KB circuit cap); extend
   `_transportRank` to keep relay at 1 while documenting relay-live. **Stop-if:** if `_transportRank` is read by
   a sibling (grep) before changing, keep its existing numeric outputs.

2. **RED — independent per-leg budgets (TC-02-05/06). ⚠ Rebase precisely on FDC-01's tree (C5).** FDC-01 (GREEN
   steps B/C) already: (i) replaced the outer wrapper with `.timeout(interactiveDirectAggregateBudget /*6s*/, …
   relayProbeEligible: true)` and added the const `interactiveDirectAggregateBudget`; (ii) wrapped **only discover
   and send** per-step as `try { …​.timeout(const) } on TimeoutException` (the compile-trap shape — `onTimeout:`
   won't type-check); (iii) **left the dial wrapper optional/omitted** (no `dialDelay` fake lever). **First verify
   on the actual tree** which wrappers exist (HEAD `_tryDirectSendInner` `:1467-1532` has NONE — only `timeoutMs:`
   args); if FDC-01 has not landed, FDC-02 adds them itself. **Seam (FDC-02's actual work):** (a) re-point the
   discover/send per-step wrappers to `kDirectDiscoverBudget` / `kDirectSendBudget`; (b) **own adding the dial
   wrapper** `kDirectDialBudget` (+ a `dialDelay` fake lever if you want a dial-budget RED — TC-02-06 only
   exercises discover); (c) edit the **outer wrapper as `interactiveDirectAggregateBudget`** (not
   `interactiveDirectBudget`) and **keep a (possibly relaxed) aggregate ceiling** — do NOT drop it: it is the only
   bound on the worst-case `discover+dial+send` *sum* (~Σ per-step) and FDC-01's eligible-aggregate-timeout
   invariant rides on it; (d) **assign concrete values** (e.g. `kDirectDiscoverBudget≈1500` / `kDirectDialBudget≈1000`
   / `kDirectSendBudget≈1500` under the ceiling) and **lower TC-02-05's discover to ~1200 ms** so the current
   (1800, 2000) success-vs-fail window isn't host-flaky. Do NOT rely on the `timeoutMs:` argument alone:
   `discoverPeer`/`dialPeer` forward it to `callP2PRendezvousDiscover` / `callP2PPeerDial`
   (`lib/core/bridge/p2p_bridge_client.dart` ~`:337` / ~`:382`), which `await bridge.send` with **no** Dart
   `.timeout` (it reaches only the Go node — unlike `callP2PInboxStore` `:457` and `callP2PMessageSend:1046-1054`,
   which wrap a Dart `.timeout`), so a hung discover/dial is bounded Dart-side solely by the per-step `.timeout`
   wrappers. **Stop-if:** `U2 cold baseline` (:3148) asserts exactly one discover + one dial — the new budgets must
   not add a retry; verify call counts unchanged.

3. **RED — staggered relay-live leg + stagger + suppress (TC-02-01/02/07/09). ⚠ BLOCKED ON C1** — as written
   ("runs only when a live `/p2p-circuit` connection exists") the leg is unreachable: that state fires the reuse
   fast-path (`:447-512`), which short-circuits before the race. Resolve C1 first (preferred resolution A folds the
   staggered circuit send into the reuse path). The wiring below applies once the race is reachable for a connected
   circuit peer. **Seam:** add `_tryRelayLiveSend(p2pService, peer, jsonString)` that calls `sendMessageWithReply`
   for the circuit path (reuse `_inferDirectVsRelayForConnectedPeer` detection) and returns
   `_RaceResult.succeeded(via: <Go's labeled transport>)` when it acks — **relay-opportunistic** (Go selects the
   connection and labels the result; it does not force relay-only). Wire it as a **third** `raceFutures` entry
   started behind a `Future.delayed(kRelayLegStagger)` **guarded by `best != null`** (any committed success of any
   rank — **NOT `completer.isCompleted`**, which stays false through a direct-leg grace window and would let
   relay-live start spuriously after a direct win; **C3**) so it is *not started* once a better leg has committed
   (suppress-on-early-win). Feed its result through the SAME `onResolved`/`offerSuccess` rank machinery (rank 1).
   **Stop-if / pendingCount (C4):** **count the eligible relay-live leg in `pendingCount`** (or add a
   `pendingRelayLive` flag) so `completeWithFailure` (`:750-767`) **cannot settle while it is still
   eligible/unresolved** — otherwise a fast LAN+direct double-failure before the 500 ms stagger settles the race as
   failed before relay-live starts, breaking TC-02-02. Suppression is then the guard resolving the leg to a
   *failed* `_RaceResult` (which decrements the count) once `best != null`. (The "optional late offer that never
   blocks a failure settle" model is **unsound** — do not use it.)

4. **RED — media/large → never live relay (TC-02-03/04/12).** **Seam:** `_liveRelayEligible(hasAttachments,
   payloadBytes)` returns false for media or `payloadBytes > kLiveRelayMaxPayloadBytes`; the relay-live leg is
   only added when eligible. Media/large still reach LAN/direct-live or the durable inbox. **Stop-if:** do NOT
   touch the inbox path (`storeInInbox`, low-confidence gate) — that is FDC-03.

5. **RED — e2e two-fake (TC-02-11/12).** New `ranked_race_relay_penalty_test.dart`; sender+receiver fakes;
   assert the **dedup-masking discriminator** (sender `relayLiveSendCount`) since receiver row-count alone is
   masked by dedup (FDC-00 caveat). Register the file in the `1to1` readonly array.

6. **Preservation pass.** Re-run the named existing tests (U1/U-N1/U2/U3/U-N3/U4/U5, NET-REL-01) — all green,
   unchanged outcomes.

7. **Mutation sweep.** Apply each "Mutation that re-reds" from the catalog one at a time; confirm the matching
   test fails; revert.

## Risks And Edge Cases

- **Relay-live leg double-fires with the serial probe tail** (`_tryRelayProbeSend` :1534) → two relay sends for
  one message. Pinned by TC-02-09 (one row / no second relay write). Mitigation: the probe tail is reached only
  when the race *failed*; if the relay-live leg already won, the race succeeds and the tail is skipped.
- **`pendingCount` miscount from a deferred leg** (the delayed relay-live start) → a premature `completeWithFailure`
  drops a still-alive LAN/direct success. Pinned by TC-02-02 (relay carries when others fail) + the preserved
  `U-N2` dead-learned-leg test (:3199). Mitigation in Step 3 stop-if.
- **Circuit drops between detection and send** → relay-live `sendMessageWithReply` throws → caught, leg fails,
  race falls through (TC-02-02 negative complement / inbox custody).
- **Payload-size threshold off-by-headroom** (envelope > raw text) → measure `jsonString.length` (the encrypted
  envelope actually written), not the plaintext. Pinned by TC-02-04 using the envelope length.
- **Dedup-masking false positive** (a test passes via the inbox copy while the live leg never fired) → every
  fast-path test asserts `relayLiveSendCount` and `message.transport`, never delivery alone (FDC-00 closure).
- **Network-change re-warm / per-address Happy-Eyeballs** are explicitly **FDC-04 / FDC-11** — not pinned here;
  noted in Accepted Differences.

## Device/Relay Proof Profile

- **Host-only closes the *logic*:** all 12 RED tests + the preservation set run under `1to1` / `feature-host-all`.
  Host-green proves the rank/stagger/budget/media-gate decisions and the dedup-safe one-row outcome.
- **Requires sim/device for the *fast-path* claim:** per FDC-00's dedup-masking caveat, host fakes cannot prove
  "the LAN/direct leg actually won on the real wire and the relay-live leg actually stayed quiet." Closure
  scenario:
  - `./scripts/check_reliability_simulation_discovery.sh` (confirm discovery), then a `/sims 1to1`-class
    run that **asserts the transport label** (`local`/`direct` vs `relay`/`inbox`) on a same-WiFi pair —
    e.g. extend the path the `wifi_relay_fallback_smoke_test.dart` / `transport_e2e_test.dart` family exercises.
    *(Sims is a runner, not a registrar: a new scenario needs a `classify_path()` case + a dart-define case in
    `scripts/check_reliability_simulation_discovery.sh` / the harness first.)*
  - A **two-device smoke** observing the live LAN path winning while a warmed relay circuit is present (the §6.1
    relay-bypass-by-latency case) — the one thing host fakes cannot honestly prove.

## Acceptance Gates (literal)

```bash
# Home 1:1 gate — owns send_chat_message_use_case_test.dart + the new ranked_race_relay_penalty_test.dart
./scripts/run_test_gates.sh 1to1            # expected: 1226 (capture green baseline before FDC-02; prior ~1226) + new FDC-02 cases

# Transport integration gate (real-ish wire fakes)
./scripts/run_test_gates.sh transport       # expected: device/fixture-gated (skips on lone sim) (unchanged; no integration_test/* edited)

# Regression floors
./scripts/run_test_gates.sh feed            # expected: 279 (unchanged)
./scripts/run_test_gates.sh groups          # expected: 896 (unchanged — group send path NOT in scope)
./scripts/run_test_gates.sh baseline        # expected: 112 host

# Host floor (auto-globs test/features/**, incl. the new integration file)
./scripts/run_host_test_gates.sh feature-host-all   # expected: 0 fail
./scripts/run_host_test_gates.sh core-host-all      # expected: 0 fail

# Hygiene
flutter analyze        # expected: 0 new
git diff --check       # expected: clean
```

> **Harness registration (mandatory):** append
> `"test/features/conversation/integration/ranked_race_relay_penalty_test.dart"` to the read-only `1to1`
> family array in `scripts/run_test_gates.sh` (around the existing `:36` entry's array). Tier-1 cases land
> inside the already-curated `send_chat_message_use_case_test.dart` (no array change). `feature-host-all`
> auto-globs the new file regardless; the array add is what makes it run in the *curated* `1to1` gate.

## Known-Failure Interpretation

- Pre-existing flakes NOT caused by FDC-02: durable-media-upload flake (MEMORY: "2 `-1`s pre-existing"),
  `groups` ML-004, and the `ambient_background`/orbit-invite flakes — if these appear, confirm they reproduce on
  a clean tree before attributing. FDC-02 touches no media-upload, group, or orbit code.
- A `transport`/`feed`/`groups` count change is a RED flag (FDC-02 is 1:1-send-only) → investigate before
  proceeding.

## Done Criteria (checkbox)

- [ ] All 12 RED tests written FIRST, each observed RED for its catalogued reason.
- [ ] Each behavior-bearing edit has a passing test AND a verified re-red mutation.
- [ ] `kRelayLegStagger` / `kPublicAddrTail` / `kPrivateAddrTail` / `kLiveRelayMaxPayloadBytes` /
      `kDirectDiscoverBudget` / `kDirectDialBudget` / `kDirectSendBudget` introduced; constant ordering locked.
- [ ] **C1 resolved** (reuse-fast-path collision) and Step 3 / TC setups reshaped accordingly.
- [ ] `_tryRelayLiveSend` added, staggered, suppress-on-early-win (guard `best != null`, C3), counted in
      `pendingCount` (C4), media/large-excluded, rank 1 (reuses `'relay'`, no `_transportRank` change — C8).
- [ ] `_tryDirectSendInner` uses independent per-leg budgets with concrete values, the dial wrapper owned by
      FDC-02, and a **retained (relaxed) aggregate ceiling** `interactiveDirectAggregateBudget` (NOT dropped — C5).
- [ ] Preservation set green (U1/U-N1/U2/U3/U-N3/U4/U5, NET-REL-01), unchanged outcomes.
- [ ] `1to1` + `transport` + `feed` + `groups` + `baseline` gates green; `feature-host-all` / `core-host-all`
      0-fail; `flutter analyze` 0-new; `git diff --check` clean.
- [ ] New integration file registered in the `1to1` array.
- [ ] Device/sim transport-label proof scheduled (closure-deferred, not waived).

## Scope Guard (hard Do-not)

- Do **NOT** edit `direct_timeout`→`relayProbeEligible` (FDC-01) or the reuse/sticky `isLocalPeer` gate /
  `warmPeer` (FDC-04) or the low-confidence-inbox generalization + serial-tail drop (FDC-03) — same collision
  file, different plans, sequential landing.
- Do **NOT** modify any Go (`go-mknoon` / `go-relay-server`) — Dart owns leg **timing/sequencing/rank**; Go
  owns each leg's **transport-path** selection (and labels it). **No transport-policy bridge seam is added** —
  FDC-02 relies on Go's existing connection-preference within each leg's `sendMessageWithReply`.
- Do **NOT** implement per-address 30 ms/250 ms staggering (Go `DefaultDialRanker` / FDC-11) — pin the constant
  ordering only.
- Do **NOT** add a cancellation API for in-flight losers (refuted) — rely on receiver dedup.
- Do **NOT** touch the group send path.

## Accepted Differences

- The 30 ms private / 250 ms public Happy-Eyeballs *per-address* tails are pinned as named constants with a
  locked ordering, but their **per-address application is deferred to FDC-11/Go** (`DefaultDialRanker`,
  device-only). FDC-02's load-bearing Dart stagger is the **leg-granularity** `kRelayLegStagger`.
- In-flight losing legs are not cancelled (Dart/Go one-shot limitation, §6.2 honesty note) — a duplicate *may*
  still hit the wire; correctness is the receiver's `messageId` dedup.
- Net relay + recipient work may rise slightly (§6.2 honesty note) — only the **sender's** perceived latency is
  the FDC-02 target; volume/durability ordering is FDC-03/FDC-10.

## Dependency Impact

- **Upstream:** lands **after FDC-01** (which makes `direct_timeout` probe-eligible). FDC-02's independent
  budgets *reduce* how often `direct_timeout` is produced, so FDC-01's fix and FDC-02's fix are complementary,
  not conflicting; FDC-01 must already be committed on the file.
- **Downstream:** **FDC-03** (inbox generalization) and **FDC-04** (`isLocalPeer` reuse gate + `warmPeer`) build
  on FDC-02's race body and ranking; FDC-04 in particular relies on FDC-02 having made LAN-by-priority real so
  its `isLocalPeer` gate is the documented belt-and-suspenders.
- **Collision file:** `lib/features/conversation/application/send_chat_message_use_case.dart` — shared with
  FDC-01/03/04; MUST run sequentially (FDC-00 collision map; precedent: orbit `feed_wired.dart` 160→163).
- **No migration, no Go change, no new package.** Receiver dedup is the only external invariant relied upon
  (already enforced server-side: `backend_memory.go:121-142` / `backend_redis.go:272-295`).
