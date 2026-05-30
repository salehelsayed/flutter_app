# 1:1 Send-Path Orchestration Strategy — Problem & Tracking Doc

Prepared on: 2026-05-29
Status: Proposed (investigation complete, no code changed)
Tracking ID: NET-REL-05

## Executive Summary

This doc covers the *orchestration* of a single 1:1 send — the ladder/race logic
that decides, per message, which channel actually carries it. Today
`send_chat_message_use_case.dart` does: (1) reuse an existing connection if
present; else (2) a **parallel first-wins race** of local-WiFi (1500ms budget)
vs direct-discover-dial-send (2s budget); then, only if the race fails, a
**sequential tail**: a relay probe, then an inbox store-and-forward fallback
(3s budget).

The front half (the local-vs-direct race) is good — it's the "hedged racing" we
want. The problems are in the tail and in the lack of memory:

- The **relay probe and inbox are sequential after the race fails**, so an
  offline-peer send can take several seconds before the durable fallback fires.
- There is **no grace window** to prefer a better transport over a worse one
  when both are available (pure first-wins).
- There is **no sticky/learned per-peer transport** — every first message
  re-runs the full race even when we delivered to this peer over `direct` two
  minutes ago.
- The durable fallback (inbox) is the **last rung**, not a concurrent safety net
  — unlike the group path, which fires live + inbox in parallel and dedupes by
  message-id.

The receive side **already dedupes by message-id**, which makes a concurrent
durable fallback feasible for 1:1 (the key enabler). This doc maps the exact
timeline, quantifies worst-case latency, and proposes contained improvements.

## Document Basis

- `lib/features/conversation/application/send_chat_message_use_case.dart` —
  budgets (`~18-24`), connection reuse (`~303-366`), the race (`~368-456`),
  `_tryLocalSend` (`~761-785`), `_tryRelayProbeSend` (`~487-522`), inbox fallback
  (`~531-580`), result persistence/status (`~1114-1185`), crash-safe envelope
  persist (`~292`).
- `lib/core/services/p2p_service_impl.dart` — `sendMessageWithReply`,
  `storeInInbox`, `probeRelay`, `_inferTransportForPeer` (`:159`),
  send transport read (`:1210-1221`).
- `lib/features/conversation/application/retry_failed_messages_use_case.dart` —
  prefers inbox-only re-store on retry (`~189-243`).
- `lib/features/conversation/application/retry_unacked_messages_use_case.dart` —
  inbox re-store for stuck `sent` messages.
- `lib/features/conversation/application/recover_stuck_sending_messages_use_case.dart` —
  reclassifies stuck `sending` → `failed` after 30s.
- `go-mknoon/node/node.go` — `message:send` races addrs in Go (`SendMessageWithTransport`,
  `WithAllowLimitedConn`), inbox via relay (`inbox.go`).
- Group comparison: `go-mknoon/node/pubsub.go` `SendGroupMessageReliable`
  (live + inbox parallel, reconcile by messageId).

## Current Behavior (Evidence)

### Send decision flow (precise sequence + timings)
```
sendChatMessage(targetPeer, text)
  1. persist wireEnvelope to DB        [crash-safe, BEFORE transport]  (~292; row was already
       created with status 'sending' by the optimistic UI at conversation_wired.dart:1655)
  2. if already connected → fast-path send                                              (~303-366)
  3. else RACE (parallel, first-success-wins Completer):                                (~368-456)
        ├─ local   : if isLocalPeer(peer) → _tryLocalSend         budget 1500ms          (~376,383)
        └─ direct  : discover → dial → message:send               budget 2s              (~390-394)
       (both start simultaneously; no head-start/grace window)
  4. if race FAILED → relay probe (SEQUENTIAL):                                          (~487-522)
        if relayProbeEligible → _tryRelayProbeSend (relay:probe then message:send)
  5. if still FAILED → inbox store-and-forward (SEQUENTIAL):     budget 3s               (~531-580)
        storeInInbox → status 'delivered' (custody handed to relay)
  6. else → status 'failed' (wireEnvelope retained for retriers)                         (~590)
```
Budgets: `interactiveLocalBudget = 1500ms`, `interactiveDirectBudget = 2s`,
`interactiveInboxBudget = 3s` (`~18-24`). Also `relayProbeSendAttempts = 2`,
`relayProbeRetryBackoff = 250ms` (`~29-30`) — these drive the tail's worst-case
timing. Note (added after QA): the chat send has **no foreground/background budget
split** — it always uses the `interactive*` budgets regardless of app state, so
proposals must not assume a background profile exists to tune.

### Worst-case latency per unhappy path
- **Peer on same LAN, both foregrounded, already discovered:** local usually
  wins quickly (one WS round-trip). Fast.
- **Peer on same LAN but NOT yet discovered:** local tier skipped (NET-REL-01
  P1); direct path carries it (up to ~2s).
- **Peer online, cross-network:** direct race resolves via `message:send`
  (which in Go rides relay); typically within the 2s budget.
- **Peer offline:** race runs to failure (~up to 2s), **then** relay probe
  (sequential, adds its own probe + send time), **then** inbox (up to 3s). The
  durable fallback (inbox) can fire **several seconds** after the user hit send.
  This is the worst case and the most visible to the user (a slow "sending…").

### Relay-probe vs Go-side relay (overlap)
`message:send` in Go opens the chat stream with
`network.WithAllowLimitedConn(ctx,"chat-send")` (`node.go:1234`), which **permits
the stream to ride a limited/relay circuit connection** (libp2p does the actual
address dialing). So the Dart-side `_tryRelayProbeSend` tail partly **overlaps**
Go's own relay usage. The probe exists to detect `NO_RESERVATION`
(peer offline) and to re-establish a circuit, but the layering means "relay" is
attempted at two levels with some redundancy — worth clarifying/consolidating.

### Status states & retriers
- States: `sending` → (`delivered` | `sent` | `failed`).
  `delivered` on ack or inbox handoff; `sent` = written-but-unacked (envelope
  retained); `failed` = all paths failed. (`queued` is a legacy/log-only label,
  not an active DB status — corrected after QA; see `conversation_message.dart:23-24`.)
- Note (added after QA): the unacked-success branch also attempts a **sequential**
  inbox handoff inside `_persistOutgoingSendResult` (`~1130-1149`) before settling
  on `sent` — so inbox is reached in more cases than the timeline's step 5/6
  suggests, and it is sequential there too.
- Retriers: `retryFailedMessages` (prefers **inbox-only** re-store when
  transport was inbox or envelope is safe, else re-runs full `sendChatMessage`,
  `~189-283`); `retryUnackedMessages` (inbox re-store for stuck `sent` > 60s);
  `recoverStuckSendingMessages` (reclassify `sending` > 30s → `failed`).

### Receive-side message-id dedup (enabler for concurrent fallback)
Incoming chat messages are deduped by `messageId` on the receive side
(chat message listener / `handleIncomingChatMessage`), the same mechanism that
lets the **group** path safely fire live + inbox in parallel and discard the
duplicate. This means 1:1 could also send a concurrent durable copy without
double-delivery to the user.

## Problems Identified

**P1 — Sequential relay-probe + inbox tail adds latency on the offline path.**
After the race fails (~2s), the probe and inbox run one after another
(`~487-580`). *Impact:* the durable fallback can be several seconds late; the
user watches a long "sending…" for an offline recipient — the exact case where a
fast "will deliver when they're back" matters most.

**P2 — No grace window in the race.** Pure first-wins (`~398-454`); if relay
(inside `message:send`) happens to resolve before a direct/local path, we accept
the worse transport even when a better one was about to land. *Impact:* we
sometimes settle on relay when direct/local was milliseconds away.

**P3 — No sticky/learned per-peer transport.** `_inferTransportForPeer`
(`p2p_service_impl.dart:159`) exists but is used to *label* unknown incoming
transport, not to *prefer* a known-good transport on the next send. We persist
`messages.transport` but don't consult it to try last-known-good first.
*Impact:* every first message to a peer re-runs the full race/discovery even
when we delivered over `direct` minutes ago — wasted time and battery.

**P4 — Inbox is the last rung, not a concurrent safety net.** Unlike group
(`SendGroupMessageReliable` fires live + inbox in parallel, reconciled by
messageId), 1:1 only reaches inbox after everything else fails. *Impact:* for
low-confidence sends (peer recently offline, flaky network), we forgo the
reliability win of a concurrent durable copy that the receive-side dedup already
makes safe.

**P5 — Two-level relay redundancy.** Dart `_tryRelayProbeSend` overlaps Go's
in-`message:send` relay usage. *Impact:* unclear ownership of the relay attempt;
harder to reason about and to instrument (NET-REL-04).

## Impact

The front-half race already gives a good fast path. The tail and the missing
memory are where "fast and seamless" leaks: offline sends feel slow, repeated
sends to the same peer re-pay discovery, and we sometimes land on a worse
transport than necessary. These are latency and perceived-reliability costs on
the most common everyday action in the app.

## Proposed Directions (options, NOT implementation)

**P1/P4 — Concurrent durable fallback for low-confidence sends.** When
confidence the peer is reachable is low (e.g. last attempt failed, peer recently
offline, or no recent activity), fire the inbox store **concurrently** with the
live attempt (as group does) and let receive-side message-id dedup discard the
duplicate. *Tradeoffs:* extra relay write per low-confidence send (not every
send — keep high-confidence sends single-path); needs a confidence heuristic.
This is the narrow, correct lesson from the group path — **not** "always send
twice."

**P2 — Grace window / hedged preference.** Keep the parallel race but add a small
grace window that prefers a better transport (local > direct > relay) if it lands
within N ms of a worse one. *Tradeoffs:* choosing N (too high → adds latency;
too low → no effect). Only helps when multiple paths are close; modest win.

**P3 — Sticky / learned per-peer transport.** Record last-known-good transport
per peer (we already have `messages.transport` and a connection map) and reuse it
first, falling back to the full race on failure.
*Current state (LANDED):* a learned transport is recorded on every live success
and, on a repeat send, the learned path is **reused directly via a short-circuit**
that SKIPS re-discovery and re-dialing — for `'local'` it calls `sendLocalMessage`
with no `discoverLocalPeer`, for `'direct'`/`'relay'` it calls `sendMessageWithReply`
with no `discoverPeer`/`dialPeer`. On any miss/failure it falls THROUGH to the full
parallel race (never slower than a cold send). The short-circuit is gated behind the
`P2PServiceImpl` invalidation paths (disconnect / relay-health transition / TTL), so
a stale path is dropped before it can be reused. *Tradeoffs:* must expire/invalidate
stale preferences (peer changed networks); pairs well with NET-REL-01 TTL thinking.
This is the biggest everyday-latency win for repeat conversations — proven by the
mutation-resistant U2 short-circuit tests (`discoverCallCount==0`/`dialCallCount==0`
on a sticky send vs `==1`/`==1` on the cold baseline; deleting the short-circuit
call makes the sticky run pay discovery again → RED).

**P5 — Consolidate the relay attempt.** Decide whether relay is owned by Dart
(probe + explicit send) or Go (inside `message:send`) and remove the redundant
layer, simplifying the ladder and making NET-REL-04 instrumentation cleaner.
*Tradeoffs:* requires careful behavior-preserving refactor.

## Acceptance Criteria / How We'll Know It's Fixed

(Targets are illustrative; calibrate with NET-REL-04 baseline data.)
1. **Offline-peer send:** durable custody (inbox accepted) within ~1.5s of hitting
   send (vs several seconds today), via concurrent fallback for low-confidence
   sends.
2. **Repeat send to a recently-direct peer (LANDED — fewer discover/dial → faster):**
   the learned transport is **reused directly via a short-circuit**: the repeat
   send issues STRICTLY FEWER discover/dial calls than a cold send — zero, vs the
   cold baseline's one discover + one dial — because it skips re-discovery and
   re-dialing entirely and sends straight over the known-good path. Proven by the
   mutation-resistant U2 short-circuit tests in
   `send_chat_message_use_case_test.dart`: a sticky `'direct'` send asserts
   `discoverCallCount==0 && dialCallCount==0` and a sticky `'local'` send asserts
   `discoverLocalPeerCallCount==0` (paired with a cold-baseline test asserting
   `==1`/`==1`). Deleting the short-circuit invocation makes the sticky run fall
   into the full race and pay discovery again → the U2 tests go RED (verified by
   mutation). On a learned-path miss the send falls through to the full race, so
   the unhappy path is never slower than cold.
3. **Transport preference honored:** when local and direct both succeed within
   the grace window, local is chosen (assert in test).
4. **No double-delivery:** concurrent fallback never shows the user two copies
   (receive-side dedup covered by test).
5. **No regression:** high-confidence single-path sends still send once; crash-safe
   envelope persistence and retrier behavior unchanged.

## Test Plan

See **NET-REL-06** for harness inventory and the negative-control principle. This
doc has the richest existing host-test coverage to build on
(`send_chat_message_use_case_test.dart` already pins `message.transport`, race
ordering, budgets, and dedup). The false-result risks: (a) a "concurrent fallback"
test that passes because of dedup even though the live path silently never fired,
and (b) a "sticky path" test that passes because the full race ran anyway.

### Unit (host, deterministic) — extend `send_chat_message_use_case_test.dart`
- **U1 (grace window, happy):** local and direct both succeed within N ms → assert
  `message.transport == 'local'` (preference honored). NEGATIVE CONTROL: direct
  succeeds and local fails → `direct` chosen, not a hung wait for local.
- **U2 (sticky/learned) — LANDED & mutation-resistant:** the real short-circuit
  reuses the learned path and skips re-discovery/re-dialing. U2 asserts the sticky
  run does STRICTLY FEWER discover/dial calls than the cold baseline: a sticky
  `'direct'` send asserts `discoverCallCount==0 && dialCallCount==0 &&
  sendCallCount==1`; a sticky `'local'` send asserts `discoverLocalPeerCallCount==0
  && discoverCallCount==0 && dialCallCount==0`; a paired cold-baseline send asserts
  `discoverCallCount==1 && dialCallCount==1`. Proven by mutation: replacing the
  `_tryLearnedShortCircuit(...)` call with a null result makes the sticky run fall
  into the full race and pay discovery again → both U2 short-circuit tests go RED
  (Expected `0` / Actual `1`). NEGATIVE CONTROL U-N2: when the learned transport
  FAILS at the short-circuit, the full race still runs and delivers (`'local'`),
  so sticky never traps us on a dead path; and an expired/stale preference is
  ignored (`P2PServiceImpl` drops it before it can be read).
- **U3 (concurrent durable fallback, happy):** a low-confidence send fires inbox
  concurrently with the live attempt → assert `storeInInboxCallCount == 1` AND the
  live attempt also fired (`sendMessageCallCount == 1`). NEGATIVE CONTROL U-N3: a
  high-confidence send does NOT fire inbox (`storeInInboxCallCount == 0`) — proves we
  didn't just make every send dual-write.
- **U4 (dedup, happy + control):** two copies (live + inbox) of the SAME messageId
  surface once (`messageRepo` count == 1). NEGATIVE CONTROL U-N4: two DIFFERENT
  messageIds surface as TWO — proves dedup isn't swallowing distinct messages.
  (Receive-side dedup verified in `handle_incoming_chat_message_use_case_test.dart`
  / `chat_message_listener_test.dart`.)
- **U5 (worst-case timeline — unhappy):** peer offline → assert the durable custody
  (inbox accepted) happens within the target window; assert the sequential tail
  (relay-probe `relayProbeSendAttempts=2`, `relayProbeRetryBackoff=250ms`, then inbox)
  is bounded. NEGATIVE CONTROL: confirm a budget is actually ENFORCED — a deliberately
  slow path is cut at its budget, not merely fast by luck (pattern after the existing
  `Stopwatch` + `lastLocalSendTimeoutMs == interactiveLocalBudget` assertions).

### Integration (Dart, multi-node) — pick the RIGHT fake (QA correction)
The switch/delay/`*AlwaysFails` knobs live in `fake_p2p_service_integration.dart`, NOT
in `fake_p2p_network.dart` and NOT in the inline `FakeP2PNetwork` that
`offline_inbox_roundtrip_test.dart` / `f2_transport_switch_recovery_test.dart` actually
use. Build I2/budget-cut tests on `fake_p2p_service_integration.dart` (or port the knobs).
- **I1 (offline round-trip):** `setOnline(false)` → send lands in inbox →
  `drainOfflineInbox()` → recipient comes online → message retrieved **exactly once**
  (extend `offline_inbox_roundtrip_test.dart`). NEGATIVE CONTROL: online recipient →
  delivered live, `storeInInboxCallCount == 0`.
- **I2 (transport switch mid-conversation, BUILD):** `f2_transport_switch_recovery_test.dart`
  does NOT actually simulate a switch today — it sends twice and checks both are fast.
  A real I2 must use `fake_p2p_service_integration.dart`'s `simulateTransportSwitch`
  (LAN→relay) and assert delivery continues AND the learned transport (P3, new code)
  invalidates. This is a new test against new code.

### Latency harness (BUILD hard gates)
- **L1:** measure send→custody time per path (offline, cross-network, LAN) before/after
  the change; convert to enforced budget assertions (ties to NET-REL-04 timing). NOTE:
  no existing test ENFORCES a budget (cuts a slow path AT the cutoff) — the
  `_SlowLocalFastDirectP2PService` test only proves slow-local doesn't *block* (direct
  wins regardless of whether the 1500ms cutoff fires). To prove the cutoff itself, use
  `fake_p2p_service_integration.dart`'s `*Delay` knobs set ABOVE the budget and assert
  the path is abandoned at the budget. The in-file `FakeP2PService` has no delay knob.

### Real-stack concurrent-fallback liveness (DEFERRED — device/wire proof pending)
- **E2 (DEFERRED — proven against host fakes; device/wire proof pending):** the host
  U3 proves `sendMessageCallCount == 1 && storeInInboxCallCount == 1`, but only against
  a fake. The wire-level guarantee — a `transport_e2e`-style real-stack scenario that
  sends one low-confidence message and asserts (via Go FLOW events/counters) that BOTH
  a live stream attempt AND an `InboxStore` actually occurred over the wire, with the
  receiver getting **exactly one** — is **NOT built**. The concurrent-fallback liveness
  is therefore proven only at the host-fake layer; the over-the-Go-wire proof that
  closes the false positive "test passes via dedup even though the live path silently
  never fired" is explicitly DEFERRED, not done.

### Retrier interaction (regression)
- **R1:** retriers still prefer inbox-only re-store from the persisted `wireEnvelope`
  and do NOT conflict with or double-send alongside concurrent fallback
  (`retry_failed_messages_use_case_test.dart`, `retry_unacked_messages_use_case_test.dart`,
  `stuck_sending_recovery_test.dart`). Assert `recoverStuckSending` still reclassifies
  `sending`→`failed` after 30s and that a concurrently-inboxed message isn't double-retried.

### Real-network E2E (liveness only — NOT path-pinning)
- **E1:** `transport_e2e_test.dart`-style dedup proofs (D1/D3/D4: same-ID→1, different
  IDs→unique, cross-transport same-ID→1). Here set-acceptance (`direct||relay||inbox`)
  is acceptable because the assertion is about dedup/liveness, not which path won.

## Open Questions

1. What signal defines "low confidence" for the concurrent-fallback decision
   (last-failure recency, peer presence, network type)?
2. What grace-window value (P2) is worth it given the front race already starts
   paths simultaneously?
3. How long is a learned per-peer transport valid before we must re-race (network
   changes)? Coordinate with NET-REL-01 TTL.
4. Should relay ownership move entirely into Go (`message:send`) to remove P5
   redundancy, or stay split for the offline-detection (`NO_RESERVATION`) signal?
5. Does concurrent inbox-on-low-confidence materially increase relay write load,
   and is that acceptable (NET-REL-04 to quantify)?

## References

- Code anchors in Document Basis.
- Cross-ref **NET-REL-01** (the LAN tier this race depends on; TTL/freshness
  shared thinking), **NET-REL-04** (latency + fallback-rung metrics to set
  targets and validate), **NET-REL-03** ("peer is active"/transport preference
  overlaps the sticky-transport idea).
- Group comparison: `go-mknoon/node/pubsub.go` `SendGroupMessageReliable`
  (parallel live + inbox, reconcile by messageId) — the pattern P1/P4 borrows
  narrowly.
