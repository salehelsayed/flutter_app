# NET-REL-05 — 1:1 Send-Path Orchestration — IMPLEMENTATION PLAN

Prepared: 2026-05-29
Status: **DECIDED** — converts the OPTIONS in `05-send-orchestration.md` into concrete,
ordered, sequentially-applied implementation units. Lead-designer sign-off.
All anchors verified against current source (file:line) AFTER NET-REL-01 landed
(`01-lan-wifi-IMPLEMENTATION-PLAN.md`). The problem doc's `~` anchors are stale;
this plan uses the current line numbers.

Companion problem doc: `05-send-orchestration.md`.
Depends on / coordinates with: `01-lan-wifi-IMPLEMENTATION-PLAN.md` (LAN TTL = **30s**,
`interactiveLocalBudget = 1500ms`).

---

## Decisions (summary)

| Problem | Decision | Rationale (short) |
|---|---|---|
| **P3** (sticky/learned transport) | **In-memory session cache** of last-known-good transport, keyed by full peerId, on `P2PServiceImpl` (sibling to `_peersUpgradedToDirect`). Read once before the race to grant a small **head-start** to the learned leg; NEVER removes or delays the direct leg. **TTL: 'local' = 30s** (matches NET-REL-01 LAN TTL, re-validated via `isLocalPeer`), **'direct'/'relay' = 10min**, invalidated on disconnect / addresses-updated. Falls back to the FULL race on any sticky-leg failure. | Biggest everyday-latency win for repeat conversations. In-memory (not DB) is simplest, safe, and avoids the "latest message ≠ last successful outgoing" trap. Coordinating 'local' TTL with the 30s LAN TTL means a stale sticky-local self-corrects inside the 1500ms budget. |
| **P2** (grace window) | **N = 150ms**, preference order **local > direct > relay**. On first success, if it is not the top rank AND a higher-rank leg is still in budget, arm a single 150ms timer; commit the best result seen when it fires or as soon as a top-rank success lands. Hard-capped by `interactiveDirectBudget` (2s). | The front race already starts both legs simultaneously, so the only window where a "worse" leg beats a "better" one is the few-ms ack-timing gap. 150ms covers a typical LAN-vs-relay ack delta while being imperceptible and well inside budget. |
| **P1/P4** (concurrent durable fallback) | Fire `storeInInbox` **concurrently** with the live race for **low-confidence sends only**, as a fire-and-forget durability side-effect (NOT a race participant for the transport label). Low-confidence heuristic = **signal #1: last-attempt recency** (see below). High-confidence sends stay strictly single-path. Receive-side messageId dedup discards the duplicate. | Narrow, correct lesson from the group path — not "always send twice". Last-attempt recency is the one signal with an existing data source (`getLatestMessageForContact`); peer-presence is folded in as a gate, network-type is unavailable (no `connectivity_plus`). |
| **P5** (relay consolidation) | **Dart-only, host-testable consolidation.** In `_tryRelayProbeSend`, KEEP `probeRelay` as the cheap `NO_RESERVATION` offline detector but **reduce the post-probe send loop from 2 attempts to 1** (`relayProbeSendAttempts: 2 → 1`). Full relay-ownership-into-Go is **OUT OF SCOPE** this run (requires `make all` + `pod install`, not host-verifiable) — DOCUMENTED below. | The direct race leg already invokes the same relay-capable `message:send` (Go rides `WithAllowLimitedConn`), so the 2× probe-send loop is the redundant layer. Dropping one attempt halves the offline-path tail latency while preserving the unique offline signal. No native edits. |

### Open-question answers (problem doc lines 286-297)

1. **Low-confidence signal:** last-attempt recency (signal #1). `lowConfidence = true` when the peer is NOT currently connected AND NOT local AND the most recent *outgoing* message to this peer was `status=='failed'` OR `transport=='inbox'`, within `kLowConfidenceWindow = 30s`. High-confidence otherwise. Network type is deliberately omitted (no source in tree).
2. **Grace window:** **150ms** with order local>direct>relay; modest because the race is already simultaneous — only the ack-timing gap matters.
3. **Learned-transport validity:** 'local' = **30s** (coordinated with NET-REL-01 `LocalPeer.ttl = 30s`; re-validated via `isLocalPeer` before trust), 'direct'/'relay' = **10min**, invalidated on `_handlePeerDisconnected` / `_handleAddressesUpdated`. Always falls back to the full race on failure; stale entries are ignored.
4. **Relay ownership:** stays **split** — Dart owns offline DETECTION (`NO_RESERVATION`), Go owns the relay SEND (`WithAllowLimitedConn`). We consolidate the *redundant Dart send loop* (2→1) but do NOT move ownership into Go this run (native, non-host-verifiable). Documented decision in U-P5.
5. **Relay write load:** concurrent inbox adds ≤ 1 relay write per *low-confidence* send only (strict gate → high-confidence stays single-path). Acceptable as a calibration starting point; NET-REL-04 to quantify with the new `recordAttempt(leg:'inbox')` already present.

---

## Build order (sequential — all units share `send_chat_message_use_case.dart`)

```
U-P3-sticky  →  U-P2-grace  →  U-P1P4-concurrent-fallback  →  U-P5-relay
```

Order rationale: U-P3 adds a pre-race read + a head-start leg; U-P2 rewrites the
first-wins completer (must layer on top of U-P3's leg set); U-P1P4 adds a
concurrent side-effect around the (now grace-aware) race; U-P5 trims the tail
constant last (smallest, independent). Each unit leaves the file analyzer-clean
and host-tests green before the next begins.

**Invariants preserved across ALL units (carried from NET-REL-01):**
- The DIRECT leg is ALWAYS added unconditionally and is NEVER delayed/removed.
- Every new local/sticky leg is `.timeout`-wrapped to ≤ its budget.
- Crash-safe envelope persist (`send_chat_message_use_case.dart:308-310`,
  conditional on `messageId != null`) is unchanged.
- `recordMetrics` is called EXACTLY ONCE per send (one terminal rung). The
  concurrent inbox uses `recordAttempt(leg:'inbox')` only — never a terminal rung.
- All three retrier queries and `_persistOutgoingSendResult` semantics unchanged.
- `sendChatMessage` public signature adds ONLY optional params (backward compatible).

---

## U-P3-sticky — learned per-peer transport, head-start (not short-circuit)

**Goal (P3):** a repeat send to a peer we recently reached over `direct` (or
`local`/`relay`) grants that leg a small head-start so it tends to win the race
without re-paying full discovery — while the full race still runs underneath and
takes over on any sticky-leg failure or stale preference.

### Files & changes

1. **`lib/core/services/p2p_service.dart`** — add two interface methods with
   DEFAULT no-op bodies (mirrors the `discoverLocalPeer` default at `:182-183`,
   so all fakes/mocks compile unchanged):
   ```dart
   /// Last successful live transport ('local'|'direct'|'relay') for [peerId],
   /// or null if none/expired. Session-scoped; never authoritative. Default null.
   String? lastKnownGoodTransport(String peerId) => null;

   /// Record a successful LIVE transport for [peerId]. 'inbox' is ignored
   /// (custody handoff, not a live transport). Default no-op.
   void recordSuccessfulTransport(String peerId, String transport) {}
   ```

2. **`lib/core/services/p2p_service_impl.dart`**
   - Add a sibling field next to `_peersUpgradedToDirect` (`:56`):
     ```dart
     final Map<String, _LearnedTransport> _learnedTransport = {};
     ```
     plus a small private value type (top of file or near the field):
     ```dart
     class _LearnedTransport {
       final String transport; // 'local' | 'direct' | 'relay'
       final DateTime at;
       const _LearnedTransport(this.transport, this.at);
     }
     ```
   - Implement the two interface methods near `isLocalPeer` (`:3105`):
     ```dart
     @override
     String? lastKnownGoodTransport(String peerId) {
       final e = _learnedTransport[peerId];
       if (e == null) return null;
       final age = DateTime.now().difference(e.at);
       final ttl = e.transport == 'local'
           ? const Duration(seconds: 30)   // == NET-REL-01 LocalPeer.ttl
           : const Duration(minutes: 10);
       if (age > ttl) { _learnedTransport.remove(peerId); return null; }
       // 'local' must be re-validated against live LAN visibility (peer may
       // have left WiFi inside the TTL): never trust a stale-by-departure local.
       if (e.transport == 'local' && !isLocalPeer(peerId)) {
         _learnedTransport.remove(peerId);
         return null;
       }
       return e.transport;
     }
     @override
     void recordSuccessfulTransport(String peerId, String transport) {
       if (transport == 'local' || transport == 'direct' || transport == 'relay') {
         _learnedTransport[peerId] = _LearnedTransport(transport, DateTime.now());
       }
     }
     ```
   - **Invalidation:** in `_handlePeerDisconnected` (`:2588`) add
     `_learnedTransport.remove(conn.peerId);` (after the connection-list update).
     In `_handleAddressesUpdated` (`:2601`) clear non-local entries on a relay
     health transition (network change): `_learnedTransport.removeWhere((_, v) => v.transport != 'local');`
     ('local' has its own 30s/`isLocalPeer` revalidation, so it self-corrects).

3. **`lib/features/conversation/application/send_chat_message_use_case.dart`**
   - **Add optional param** to `sendChatMessage` (after `transportMetrics`, `:115`):
     no new param is strictly required — read directly from `p2pService`. (Keep the
     signature change to zero by reading `p2pService.lastKnownGoodTransport`.)
   - **READ before the race** — right after `isLocalPeer` is computed (`:385`):
     ```dart
     final learned = p2pService.lastKnownGoodTransport(targetPeerId); // null if none/stale
     ```
   - **WRITE after every live success** — record the learned transport in the
     single success funnel `_completeSuccessfulSend` (`:1122`). At the end, after
     `_recordSuccessfulSendReadinessProof` (`:1185`), add:
     ```dart
     if (message.status == 'delivered' && message.transport != 'inbox') {
       p2pService.recordSuccessfulTransport(targetPeerId, message.transport ?? '');
     }
     ```
     `_completeSuccessfulSend` covers reuse, race-win, and relay-probe-win. The
     dedicated inbox tail (`:582-590`) and the unacked→inbox handoff
     (`:1238-1245`) intentionally do NOT write sticky ('inbox' is custody, not a
     live transport; `recordSuccessfulTransport` ignores it anyway).
   - **HEAD-START (weighting, not short-circuit)** — the race build (`:388-428`)
     stays exactly as is (local leg + unconditional direct leg). When `learned`
     names a transport whose leg already runs (local/direct), grant it a head
     start by delaying the OTHER leg's *participation in the completer* by a small
     constant so the learned leg tends to win ties — WITHOUT delaying the direct
     transport work itself. Concretely, introduce a per-leg `headStartMs`:
     - `learned == 'local'`: local leg participates immediately; the direct leg's
       result is held back from the completer by `kStickyHeadStartMs = 120ms`
       (its work still proceeds; only its eligibility to WIN is delayed). Capped so
       total never exceeds `interactiveDirectBudget`.
     - `learned == 'direct' || 'relay'`: symmetric — hold the local leg's win-eligibility
       by 120ms. (Direct already carries relay via Go, so 'relay' maps to favoring direct.)
     - `learned == null`: no head-start — identical to today's pure first-wins.
     Implementation note: the head-start is most cleanly expressed INSIDE the U-P2
     grace mechanism (a learned leg gets rank-priority + a 0ms grace, the other
     legs get the head-start delay). To avoid a throwaway implementation, **defer
     the head-start wiring to U-P2** and in U-P3 land only the read/write/store +
     interface + invalidation. U-P3's behavior with no grace logic yet: `learned`
     is read and recorded (observable via a new `recordAttempt`-style counter) but
     does not yet reorder the completer. This keeps U-P3 a clean, independently
     testable "memory" layer; U-P2 consumes it.

   > Decision: U-P3 lands the **memory** (read/record/store/TTL/invalidate). The
   > **weighting** is implemented in U-P2 where the completer is already being
   > rewritten — avoids two conflicting rewrites of `:432-490`.

### Caller-contract preservation
- No `sendChatMessage` signature change. New `P2PService` methods have default
  bodies → every fake/mock compiles. Sticky is in-memory/session-scoped, so a
  cold start simply re-races (acceptable; matches today).

### Falls back to full race + ignores stale (problem doc requirement)
- `lastKnownGoodTransport` returns null when expired or (for 'local') no longer
  LAN-visible → the race runs unweighted. If the learned leg loses or fails, the
  other leg (always running) wins. There is no path where a dead learned
  transport traps the send.

### Tests enabled → **U2**, **U-N2**, **I2 (P3 half)**; acceptance #2
- **U2 (sticky happy):** seed `lastKnownGoodTransport`→'direct' via a fake field;
  assert FEWER `discoverCallCount`/`dialCallCount` than a cold baseline run
  (compare two runs; cold==1, sticky favors direct). (Full assertion completes
  after U-P2 supplies weighting.)
- **U-N2 (neg controls):** (a) learned 'direct' but the direct leg FAILS → assert
  full race still delivers (local/relay/inbox) and `message` non-null; (b) an
  EXPIRED preference (age > TTL) returns null → cold race runs (`discoverCallCount==1`);
  (c) learned 'local' but `isLocalPeer==false` → null → not trusted.
- Inline-fake additions: `String? lastKnownGoodTransportResult;` +
  `lastRecordedTransport`/`recordSuccessfulTransportCallCount` counters.

---

## U-P2-grace — grace window + sticky head-start in the completer

**Goal (P2):** prefer a better transport (local>direct>relay) when it lands within
a small window of a worse one, and consume U-P3's `learned` as a head-start. Keep
it modest and hard-capped by `interactiveDirectBudget`.

### Files & changes

`lib/features/conversation/application/send_chat_message_use_case.dart`

1. **Constants** (near `:31`):
   ```dart
   /// Grace window: after a non-preferred success, wait this long for a
   /// better-ranked transport before committing.
   const Duration transportGraceWindow = Duration(milliseconds: 150);
   /// Sticky head-start: hold a non-learned leg's win-eligibility this long so a
   /// recently-good transport tends to win close ties. Capped by direct budget.
   const Duration kStickyHeadStartMs = Duration(milliseconds: 120);
   ```

2. **Transport rank comparator** (top-level helper):
   ```dart
   int _transportRank(String? via) => switch (via) {
     'local' => 3, 'direct' => 2, 'reuse' => 2, 'relay' => 1, _ => 0,
   };
   ```

3. **Rewrite the first-wins completer (`:432-490`)** into a "best-wins-within-grace"
   completer. Pass `learned` (from U-P3) in. Algorithm:
   - Track `_RaceResult? best` and `Timer? graceTimer`.
   - On each leg success:
     - compute `eligibleAt` = now + (this leg is the `learned` transport ? 0 : kStickyHeadStartMs when a different `learned` is set, else 0). The head-start is applied as a delayed `.then` schedule, NOT by delaying the leg's work.
     - if `best == null` or `_transportRank(result.via) > _transportRank(best.via)` → `best = result`.
     - if `best.via` is already the TOP possible rank among still-pending legs → complete immediately.
     - else if `graceTimer == null` → arm `graceTimer = Timer(transportGraceWindow, () => complete(best!))`.
   - On all legs failing (`pendingCount<=0` with no `best`): keep the existing
     aggregated-failure completion (relayProbeEligible OR), unchanged.
   - On `graceTimer` fire OR a top-rank success: `completer.complete(best!)`,
     cancel the timer.
   - Hard cap: the outer `await completer.future` is already bounded because each
     leg is `.timeout`-wrapped; additionally cap the grace timer so
     `sendStopwatch.elapsed + transportGraceWindow <= interactiveDirectBudget` is
     respected (if direct budget is nearly spent, fire grace immediately).
   - The `catchError` arms (`:465-487`) fold into the same accumulation path.

4. **Head-start = U-P3 consumption:** when `learned != null`, the learned leg gets
   `eligibleAt = now` (no delay) and the non-learned leg's success is scheduled via
   `Future.delayed(kStickyHeadStartMs)` before being offered to `best`. This is the
   weighting U-P3 deferred. When `learned == null`, all legs are immediately
   eligible (degenerates to grace-only behavior).

Everything downstream of `final raceResult = await completer.future;` (`:490`) is
unchanged — `raceResult` is now the best-within-grace result.

### Why 150ms / 120ms (justification)
The race starts both legs simultaneously, so a "worse-wins" only happens when the
worse leg's ack returns first by a small margin. On LAN-vs-relay that margin is
typically tens of ms. 150ms grace covers the realistic crossover while being
imperceptible to the user and ~7.5% of the 2s direct budget. 120ms head-start is
slightly under the grace window so a learned leg that is genuinely alive wins
before the grace fires, yet a dead learned leg cannot stall (its delay only gates
WIN-eligibility, and the other leg still completes the race after grace).

### Tests enabled → **U1**, **U-N1(grace)**, completes **U2**; acceptance #3
- **U1 (grace happy):** both local and direct succeed, direct slightly first →
  assert `message.transport == 'local'` (preference honored). NEEDS a direct/local
  delay knob: add `Duration sendDelay`/`Duration localSendDelay` to the inline
  `FakeP2PService` (it only has `discoverLocalPeerDelay` today), OR use a bespoke
  inline `P2PService` (pattern: `_SlowLocalFastDirectP2PService` at test `:2971`).
- **U-N1 (grace neg control):** local FAILS, direct succeeds → `direct` chosen,
  no hung wait — assert via `Stopwatch` that total < a few hundred ms (grace timer
  not armed because direct is top-rank among remaining legs once local has failed).
- **U2 completion:** learned 'direct' + direct delayed slightly behind local →
  head-start lets direct win; assert `discoverCallCount`/`dialCallCount` and
  `message.transport=='direct'`.

---

## U-P1P4-concurrent-fallback — concurrent durable inbox for low-confidence sends

**Goal (P1/P4):** for low-confidence sends, fire `storeInInbox` concurrently with
the live race so durable custody lands fast (~inbox budget) without waiting for
the sequential tail — while high-confidence sends stay single-path.

### Files & changes

`lib/features/conversation/application/send_chat_message_use_case.dart`

1. **Constant** (near `:31`): coordinate with NET-REL-01 LAN TTL.
   ```dart
   /// Low-confidence recency window — same horizon as NET-REL-01 LocalPeer.ttl
   /// (30s) so the reliability layers agree on "recently failed/offline".
   const Duration kLowConfidenceWindow = Duration(seconds: 30);
   ```

2. **Compute confidence BEFORE the race** (after `isAlreadyConnected` `:315` and
   `isLocalPeer`/`learned` `:385`):
   ```dart
   var lowConfidence = false;
   if (!isAlreadyConnected &&
       !isLocalPeer &&
       !p2pService.isConnectedToPeer(targetPeerId)) {
     final last = await messageRepo.getLatestMessageForContact(targetPeerId);
     if (last != null &&
         !last.isIncoming &&
         last.id != resolvedMessageId &&            // exclude the in-flight row
         (last.status == 'failed' || last.transport == 'inbox')) {
       final age = DateTime.now()
           .difference(DateTime.parse(last.createdAt));
       lowConfidence = age < kLowConfidenceWindow;
     }
   }
   ```
   **Trap guarded:** the optimistic 'sending' row for THIS message already exists
   (created by the UI). The `last.id != resolvedMessageId` check (plus the
   terminal-status requirement) ensures we inspect the PRIOR attempt, never the
   in-flight row.

3. **Fire concurrent inbox (side-effect, NOT a race participant)** — immediately
   before building `raceFutures` (`:388`):
   ```dart
   Future<bool>? concurrentInbox;
   if (lowConfidence) {
     concurrentInbox = p2pService
         .storeInInbox(targetPeerId, jsonString,
             timeoutMs: interactiveInboxBudget.inMilliseconds)
         .then((ok) {
           transportMetrics?.recordAttempt(leg: 'inbox', succeeded: ok);
           return ok;
         })
         .catchError((_) => false);
     // Do NOT await here and do NOT let it complete the race completer.
   }
   ```
   Same `jsonString` envelope as the live legs → identical `payload.id` → receiver
   dedups (`handle_incoming_chat_message_use_case.dart:191-210`).

4. **Reconcile after the live race:**
   - **Live race SUCCESS** (`:492-518`): keep the live transport label
     (local/direct/relay). The concurrent inbox is a parallel durability copy; its
     result is ignored for labeling. Because the row reaches `delivered`/`sent`
     with the LIVE transport, the receiver's dedup discards whichever copy arrives
     second. (Do NOT call `recordMetrics(rung:'inbox')` here — terminal rung stays
     the live rung; the inbox `recordAttempt` already fired in step 3.)
   - **Live race FAILURE → tail:** before running the sequential
     `_tryRelayProbeSend`/`storeInInbox` tail (`:520-619`), `await concurrentInbox`
     if it exists. If it already returned `true`, **short-circuit**: persist
     `status:'delivered', transport:'inbox'` (reuse the inbox-success branch
     `:582-618`) and SKIP the redundant sequential `storeInInbox` at `:571` (avoids
     a double relay write — risk flagged in recon). Guard with a local bool so the
     terminal `recordMetrics(rung:'inbox')` still fires exactly once.

5. **`_persistOutgoingSendResult` interaction (unacked branch, `:1226-1258`):**
   the unacked→inbox sequential handoff stays, BUT when a concurrent inbox already
   succeeded for THIS send, skip it. Thread a `bool concurrentInboxStored` into
   `_completeSuccessfulSend`/`_persistOutgoingSendResult`; if true and the live
   result is unacked, return `status:'delivered', transport:'inbox'` directly
   (custody already confirmed) without a second `storeInInbox`. This is the recon's
   "two inbox stores for one message" guard.

### Negative control (must hold)
High-confidence send (peer connected, OR local, OR last outgoing delivered LIVE,
OR no recent failed/inbox attempt) → `lowConfidence == false` → `concurrentInbox`
is null → `storeInInboxCallCount == 0` for a successful live send (acceptance #5).

### Retrier / crash-safety invariants (R1)
- Same `messageId` + `jsonString` reused → receive dedup safe; never mint a new id.
- On concurrent-inbox success the row settles `delivered` + `transport:'inbox'` +
  `wireEnvelope:null` → invisible to all three retriers (failed/sent+envelope/sending).
- The 3s `interactiveInboxBudget` cap keeps the row from sitting in 'sending' past
  the 30s `recoverStuckSending` threshold.
- A successful durable custody is never overwritten by a later live failure: the
  short-circuit (step 4) commits 'delivered' and returns BEFORE the failed branch
  (`:629`). For the in-race-success path, the live 'delivered'/'sent' write stands.

### Tests enabled → **U3**, **U-N3**, **U4/U-N4**, **I1**, **R1**; acceptance #1, #4, #5
- **U3 (concurrent fallback happy):** low-confidence send (seed
  `getLatestMessageForContact`→failed/inbox row within 30s, peer not connected/local)
  → assert `storeInInboxCallCount == 1` AND `sendCallCount == 1` (BOTH fired).
- **U-N3 (neg control):** high-confidence send → `storeInInboxCallCount == 0`.
- **U4 (dedup):** existing send-side "same messageId winning on two paths persists
  one row" (test `:2131`) + receive-side dedup already covered
  (`handle_incoming_chat_message_use_case_test.dart:457`, `:1201`). U-N4 (two
  different ids → two rows) in the handle-incoming test.
- **I1:** extend `offline_inbox_roundtrip_test.dart` — offline recipient → inbox →
  drain → online → retrieved once; neg control online → `storeInInboxCallCount==0`
  (add a counter to the inline two_user fake OR port to shared stack #2).
- **R1:** extend `retry_failed_messages_use_case_test.dart` /
  `retry_unacked_messages_use_case_test.dart` — a row already inboxed by concurrent
  fallback (`delivered`, `wireEnvelope==null`) is NOT selected/re-stored
  (`storeInInboxCallCount==0`); `recoverStuckSending` still flips `sending`>30s→`failed`.

---

## U-P5-relay — consolidate the redundant Dart relay send loop (Dart-only)

**Goal (P5):** remove the two-level relay-send redundancy while preserving the
unique offline-detection signal. **Dart-only, fully host-testable.**

### Decision: Dart-only consolidation; Go ownership move is OUT OF SCOPE this run
Recon confirmed a safe Dart-only consolidation exists. The direct race leg already
calls `sendMessageWithReply` → Go `message:send`, which rides relay via
`network.WithAllowLimitedConn(ctx,"chat-send")` (`node.go:1262`) and self-heals via
`dialPeerViaRelay`. So the probe tail's up-to-2× `sendMessageWithReply` loop is the
redundant layer. The probe's ONLY unique value is the `NO_RESERVATION` fast offline
signal — keep that.

**Moving relay ownership entirely into Go** (making `message:send` surface a
distinct offline/`NO_RESERVATION` signal so Dart could drop `probeRelay`) would
edit `node.go SendMessageWithTransport`, `bridge.go SendMessage` response shape,
and the `SendMessageResult` struct, requiring `gomobile bind` → `make all` +
`pod install`. Per project memory, `flutter run` does not rebuild Go and these
changes are NOT host-verifiable. **Therefore this is explicitly deferred and
documented here, not attempted in this run.**

### Files & changes
`lib/features/conversation/application/send_chat_message_use_case.dart`
- Change the constant (`:30`): `const int relayProbeSendAttempts = 1;`
  (from 2). This collapses the post-probe send loop (`:1006-1056`) to a single
  attempt — the direct race leg already attempted the relay-capable `message:send`,
  so the probe now serves as: (a) `NO_RESERVATION` → fast-fail to inbox; (b)
  `connected` → ONE re-attempt (covers the online-relay-only peer whose addr the
  direct leg didn't know) → then inbox. `relayProbeRetryBackoff` becomes dead on
  the single-attempt path (no inter-attempt sleep) — leave the constant but it is
  no longer exercised; the loop's `if (attempt < relayProbeSendAttempts)` guard
  already skips the backoff when attempts==1.

> Why not 0 attempts? Dropping the post-probe send entirely would regress the
> online-relay-only peer whose address the direct leg failed to discover
> (`peer_not_found` → relayProbeEligible) but who IS reachable once the probe
> establishes the circuit. Keeping ONE attempt preserves that delivery while
> removing the redundant second.

### Tests enabled → **U5**, **L1**; acceptance (latency, no-regression)
- **U5 (worst-case timeline):** peer offline → `probeRelayResult=noReservation`
  → assert tail goes straight to inbox (`probeRelayCallCount==1`, post-probe
  `sendMessageWithReply` NOT called, `storeInInboxCallCount` reached). Online-relay
  case: `probeRelayResult=connected`, first direct attempt had failed → assert the
  single retained `sendMessageWithReply` attempt fires and delivers (behavior-
  preservation neg control flagged in recon).
- **L1 (budget enforcement):** on the integration fake (stack #2) set
  `sendDelay`/`dialDelay` above budget; assert legs cut at their budgets via
  `Stopwatch` (mirror existing `lastLocalSendTimeoutMs == interactiveLocalBudget`).

---

## Acceptance-criteria traceability (problem doc lines 190-204)

| Criterion | Unit(s) | How proven |
|---|---|---|
| #1 offline durable custody within ~1.5s via concurrent fallback | U-P1P4 (+U-P5 trims tail) | U3, U5, I1, E2 (device) |
| #2 repeat send uses learned transport, fewer discover/dial | U-P3 (+U-P2 head-start) | U2, U-N2, I2 |
| #3 transport preference honored (local within grace) | U-P2 | U1, U-N1 |
| #4 no double-delivery (dedup) | U-P1P4 + receive dedup | U4, U-N4, E1 (D1/D3/D4), E2 |
| #5 no regression; high-confidence single-path; crash-safe + retriers unchanged | U-P1P4 (gate) + all | U-N3, R1, crash-persist untouched |

## Test plan → unit map

| Test | Host/Device | Unit | Fake stack |
|---|---|---|---|
| U1 grace happy / U-N1 | host | U-P2 | inline (add `sendDelay`) or bespoke `_SlowLocalFastDirect` |
| U2 sticky / U-N2 | host | U-P3 + U-P2 | inline (`lastKnownGoodTransportResult`) |
| U3 concurrent / U-N3 | host | U-P1P4 | inline (counters exist) |
| U4 / U-N4 dedup | host | U-P1P4 | inline + handle_incoming |
| U5 worst-case | host | U-P5 | inline |
| I1 offline round-trip | host | U-P1P4 | two_user inline (add counter) / port to shared #2 |
| I2 transport switch | host | U-P3 | **shared stack #2** (`simulateTransportSwitch`) |
| L1 budget enforcement | host | U-P5/all | **shared stack #2** (`*Delay`) |
| R1 retrier regression | host | U-P1P4 | retrier fake #3 |
| E1 dedup liveness | device | U-P1P4 | `transport_e2e_test.dart` D1/D3/D4 |
| E2 concurrent-fallback liveness | device | U-P1P4 | NEW `transport_e2e` scenario (Go FLOW counters) |

Use a NEW `group('NET-REL-05 ...')` — the existing `group('NET-REL-01 LAN transport')`
(test `:1476-1610`) already owns U1/U2/U3 names for LAN labeling; NET-REL-05's
U1-U5 are different (grace/sticky/concurrent/dedup/worst-case).

## Risks carried forward (per-unit, from recon)
- **U-P3:** key learned map by FULL peerId (not the short id `_peersUpgradedToDirect` uses); 'local' must be re-validated via `isLocalPeer` and capped at 30s; never key sticky on 'reuse' (persisted transport is the resolved Go transport, never 'reuse').
- **U-P2:** grace timer must be hard-capped so total ≤ `interactiveDirectBudget`; head-start delays WIN-eligibility only, never the leg's transport work; a dead learned leg must not stall (other leg still completes after grace).
- **U-P1P4:** exclude the in-flight row in the recency check (`last.id != resolvedMessageId`); keep the gate STRICT (all high-confidence signals must fail) so acceptance #5 holds; dedupe the second inbox store (`_persistOutgoingSendResult` unacked handoff) when concurrent already stored; cap concurrent inbox at 3s so 'sending' never crosses the 30s stuck threshold; `recordMetrics` stays exactly-once.
- **U-P5:** keep `probeRelay` (NO_RESERVATION) — only the redundant send LOOP shrinks; one attempt retained to not regress the online-relay-only peer; NO_RESERVATION string-match lives in Go (`bridge.go:716-719`) and cannot be hardened from Dart.

## Out of scope (documented decisions)
- **Full relay ownership into Go (P5):** requires `make all` + `pod install`, not host-verifiable. Deferred. Revisit if NET-REL-04 baselines show the split is materially costly.
- **Network-type confidence signal:** `connectivity_plus` absent; the wifi/cellular strings in `p2p_service_impl.dart` are inbound census labels, not device network state. Heuristic deliberately omits it.
- **Durable (cross-restart) sticky:** in-memory session cache only this run; a DB-backed `dbLoadLastDeliveredOutgoingTransportForContact` query is a possible follow-up but not needed to satisfy acceptance #2.
