# Transport Reliability — Implementation Audit (NET-REL-01 P1/P2, NET-REL-05 P1–P5)

Independent adversarial audit of the committed implementation at git HEAD
(`9358692d` NET-REL-05, `c86975f2` NET-REL-01). All mutation/negative-control
results below were reproduced by the auditor and the production files restored
clean afterward (`git diff --stat` empty for both mutated files).

**Scope note:** This audit covers NET-REL-01 **P1 (discover-on-send)** and
**P2 (TTL/freshness)**, plus **NET-REL-05 P1–P5**. NET-REL-01 **P3 (local media)**
and **P4 (permission telemetry)** were **OUT OF SCOPE** for this audit (only the
features above were requested).

## Verdict Matrix

| Feature | Verdict | One-line justification |
|---|---|---|
| NET-REL-01 P2 — TTL/freshness read-time eviction (acceptance #2) | **implemented (mutation-pinned)** | Production eviction in `getLocalPeer` is now directly tested: `bonsoir_discovery_getlocalpeer_eviction_test.dart` (R4) instantiates the REAL `BonsoirDiscoveryService`, seeds a back-dated peer via `@visibleForTesting debugSeedPeer`, and asserts `getLocalPeer` returns null AND removed the entry from `discoveredPeers`. Deleting the eviction block now turns the suite RED. |
| NET-REL-01 P1 — discover-on-send for cold same-WiFi peers | **implemented** | Local leg added unconditionally to the race, bounded resolve via `discoverLocalPeer`; U-N1 negative control proves a non-LAN peer never gets `transport=='local'` (mutation fails it). Real-mDNS path (device I3) acknowledged unbuilt. |
| NET-REL-05 P3 — sticky/learned transport (acceptance #2) | **implemented (mutation-pinned) — latency win realized** | Repeat send REUSES the learned path via a short-circuit (`_tryLearnedShortCircuit`, R3) that SKIPS re-discovery/re-dialing; sticky send issues STRICTLY fewer discover/dial than cold (zero vs one). U2 short-circuit tests pin it (sticky `discoverCallCount==0`/`dialCallCount==0` vs cold `==1`/`==1`); deleting the short-circuit call → RED (Expected 0 / Actual 1). Gated behind the now directly-tested `P2PServiceImpl` invalidation paths (R2). |
| NET-REL-05 P2 — best-wins-within-grace completer (acceptance #3) | **implemented** | Grace window + preference rank (local>direct>relay) hard-capped at direct budget. U1 genuinely pins it: first-wins mutation fails `Expected 'local' / Actual 'direct'` (reproduced). |
| NET-REL-05 P1/P4 — concurrent durable fallback + receive-side dedup | **implemented** | Low-confidence gate fires concurrent `storeInInbox`; tail/handoff de-duped to ≤1 extra write; `getMessage(payload.id)` dedup is the production enabler. U3/U-N3/U4/U-N4 pin call counts. Wire-level E2 (both live attempt + InboxStore over Go) NOT built. |
| NET-REL-05 P5 — relay consolidation (`relayProbeSendAttempts` 2→1) | **implemented (mutation-pinned)** | The behavioral delta is now pinned: R5 added a probe-connected-but-post-probe-send-fails test that asserts `sendCallCount == relayProbeSendAttempts == 1`; reverting 1→2 turns it RED. The now-dead `relayProbeRetryBackoff` constant + its three unreachable backoff guards were removed. Go ownership move still correctly deferred. |

**Overall (post-remediation R1–R5):** all six audited features now implemented and
mutation-pinned at the host-fake layer. The previously-partial P2 (TTL), P3 (sticky),
and P5 (relay) are now directly tested against real production code with mutation
proof; P1/P2(grace)/P1P4 remain implemented. Two wire/device liveness proofs remain
explicitly **DEFERRED** (not done): NET-REL-01 **I3** (device mDNS resolve) and
NET-REL-05 **E2** (live attempt + InboxStore over the real Go stack). These features
are proven against host fakes; device/wire proof is pending.

## Per-Feature Evidence

### NET-REL-01 P2 — TTL/freshness (IMPLEMENTED, mutation-pinned — R4)
- `lib/core/local_discovery/local_discovery_service.dart:19,25` — `ttl = 30s`; `isStale()` predicate.
- `lib/core/local_discovery/bonsoir_discovery_service.dart:184-203` — read-time eviction in `getLocalPeer`; `isLocalPeer => getLocalPeer != null` (:181).
- `lib/core/local_discovery/local_ws_server.dart:32` — `_connectTimeout = 800ms` (fast connect cap inside 1500ms budget).
- `lib/main.dart:1375-1377` — production wires `BonsoirDiscoveryService` (`kDisableLocalDiscovery` defaults false).
- `lib/core/services/p2p_service_impl.dart:3139-3160,3169-3177` — delegation to the TTL-enforcing impl.
- **R4 remediation (DONE):** added `@visibleForTesting void debugSeedPeer(LocalPeer)` to `BonsoirDiscoveryService` (production never calls it) so a stale peer can be placed in front of the real eviction block. New `test/core/local_discovery/bonsoir_discovery_getlocalpeer_eviction_test.dart` (5 tests) instantiates the REAL service, seeds a peer back-dated past the 30s TTL, and asserts `getLocalPeer` (a) returns null AND (b) removed the entry from the live `discoveredPeers` map, plus emits an empty snapshot and flips `isLocalPeer` false; negative controls keep a fresh entry. **Deleting the eviction block now turns this suite RED.**

### NET-REL-01 P1 — discover-on-send (IMPLEMENTED)
- `send_chat_message_use_case.dart:525-538` — local leg added UNCONDITIONALLY, `.timeout(interactiveLocalBudget=1500ms)`.
- `send_chat_message_use_case.dart:547-557` — direct leg added independently, own `.timeout(2s)` → parallel, no delay.
- `send_chat_message_use_case.dart:1085-1106` — `_tryLocalSendWithDiscovery`: bounded `discoverLocalPeer` when not already local; sends with remaining budget.
- `p2p_service_impl.dart:3169-3177` → `local_p2p_service.dart:81-85` → `bonsoir_discovery_service.dart:205-239` (resolvePeer nudge-and-wake).
- `p2p_service.dart:179-183` — abstract default `discoverLocalPeer` returns false (negative-control safety in the interface).
- **I3 — DEFERRED (proven against host fakes; device/wire proof pending):** the discover-on-send local leg and the `BonsoirDiscoveryService` TTL eviction (R4) are proven against host fakes / the real service seeded in-process, but a real device-mDNS resolve over the wire (a cold same-WiFi peer actually discovered via native Bonsoir and delivered to) is **NOT built**. U3 uses a fixed 50ms fake delay, not a wall-clock guarantee. Device I3 proof is explicitly DEFERRED, not done.

### NET-REL-05 P3 — sticky/learned transport (IMPLEMENTED, mutation-pinned — R2+R3)
- `send_chat_message_use_case.dart:441` — read `learned = lastKnownGoodTransport(targetPeerId)` (a validity guarantee, not a hint — the invalidation paths drop the entry before it can go stale).
- `send_chat_message_use_case.dart:459-501` — `_tryLearnedShortCircuit`: on a hit, REUSES the known-good path and SKIPS discover/dial ('local' → `sendLocalMessage` with no `discoverLocalPeer`; 'direct'/'relay' → `sendMessageWithReply` with no `discoverPeer`/`dialPeer`); on success persists `sendPath='sticky'` (rung censused as 'reuse'); on any miss/failure returns a FAILED `_RaceResult` and the code falls THROUGH to the full parallel race (`CHAT_MSG_SEND_STICKY_FALLBACK` emitted on miss).
- `send_chat_message_use_case.dart:1208` — `_tryLearnedShortCircuit` helper body.
- `recordSuccessfulTransport` on delivered (excludes inbox) records the learned transport.
- `p2p_service_impl.dart` — TTL (local 30s / direct,relay 10min via `clock.now()`) + isLocalPeer re-validation; disconnect-invalidation; relay-health-transition invalidation on BOTH the modern `relay:state` push (R2 added the previously-missing guard) and the legacy addresses path.
- **R2 remediation (DONE):** added the MISSING relay-health invalidation on the MODERN `_handleRelayStateChanged` path (it computed wasHealthy/nowHealthy but never dropped learned transports — only the legacy `_handleAddressesUpdated` did); switched the two learned-transport timestamps to `clock.now()` for deterministic TTL testing. New `test/core/services/p2p_service_learned_transport_invalidation_test.dart` (9 tests) constructs the REAL `P2PServiceImpl`, records a transport, and fires each trigger through the real bridge callbacks (disconnect, modern relay:state transition, legacy addresses transition, withClock-driven TTL expiry) with negative controls (different-peer disconnect, no-transition push, 'inbox' ignored).
- **R3 remediation (DONE):** enabled the real short-circuit gated behind R2's invalidation. Replaced the deleted tautological U2 with two mutation-resistant short-circuit tests + a paired cold-baseline; updated U-N2(a) so the learned transport genuinely FAILS at the short-circuit and the full race still delivers ('local').
- **Mutation proof (R3):** replacing the `_tryLearnedShortCircuit(...)` call with a null result makes the sticky run fall into the full race → both U2 short-circuit tests RED ('learned direct' Expected 0 / Actual 1 at `discoverCallCount`; 'learned local' Expected 0 / Actual 1 at `discoverLocalPeerCallCount`); restore → 88/88 GREEN.

### NET-REL-05 P2 — grace window (IMPLEMENTED)
- `send_chat_message_use_case.dart:52` — `transportGraceWindow = 150ms`.
- `send_chat_message_use_case.dart:75-81` — `_transportRank` (local=3,direct/reuse=2,relay=1).
- `send_chat_message_use_case.dart:637-660` — best-wins accumulator + grace timer hard-capped at `interactiveDirectBudget`.
- **Negative control (reproduced):** mutating `offerSuccess` to pure first-wins → U1 FAILS `Expected: 'local' / Actual: 'direct'`. Restored.

### NET-REL-05 P1/P4 — concurrent durable fallback + dedup (IMPLEMENTED)
- `send_chat_message_use_case.dart:71` — `kLowConfidenceWindow = 30s`.
- `send_chat_message_use_case.dart:465-486` — low-confidence gate (in-flight-row trap guarded by `last.id != resolvedMessageId`).
- `send_chat_message_use_case.dart:496-514` — concurrent `storeInInbox` fired in parallel (not a race participant).
- `send_chat_message_use_case.dart:813-823,1506-1523` — tail/handoff dedup → ≤1 extra relay write.
- `handle_incoming_chat_message_use_case.dart:191,200-209` — receive-side `getMessage(payload.id)` dedup.
- **E2 — DEFERRED (proven against host fakes; device/wire proof pending):** the concurrent fallback is pinned at the host layer (U3 `sendMessageCallCount == 1 && storeInInboxCallCount == 1`), but the wire-level proof — both a live attempt AND an InboxStore over the real Go stack for one low-confidence send, asserted via Go FLOW events/counters with the receiver getting exactly one — is **NOT built**. The false positive "test passes via dedup even though the live path silently never fired" is guarded only at the host-fake layer. Integration N-control asserts only `storeInInboxCallCount <= 2` (upper bound); the exact `== 1` pin lives only in host unit U3. E2 is explicitly DEFERRED, not done.

### NET-REL-05 P5 — relay consolidation (IMPLEMENTED, mutation-pinned — R5)
- `send_chat_message_use_case.dart` — `relayProbeSendAttempts = 1` (git show 9358692d: `-2 → +1`).
- post-probe loop runs once; `NO_RESERVATION → peer_not_found` offline signal PRESERVED.
- `go-mknoon/node/node.go` — UNCHANGED (P5 commit touched **0** Go files — confirmed); Go move correctly deferred & documented.
- **R5 remediation (DONE):** (a) added 'probe-connected but post-probe send fails attempts exactly once (P5)' to `send_chat_message_use_case_test.dart` — `useNullDiscover:true` makes the direct race leg return `peer_not_found` WITHOUT calling `sendMessageWithReply`, so the post-probe loop is the ONLY caller and `sendCallCount` equals the attempt count verbatim; `probeRelayResult=connected` + `sendMessageResult=false` forces the loop to run its full count. Load-bearing assertions `expect(sendCallCount, relayProbeSendAttempts)` and `expect(sendCallCount, 1)`. (b) Removed the now-dead `relayProbeRetryBackoff` constant and its three unreachable `if (attempt < relayProbeSendAttempts)` backoff guards (send/delete/introduction call sites).
- **Mutation proof (R5):** reverting `relayProbeSendAttempts` 1→2 now turns the new test RED (`sendCallCount` Expected 1 / Actual 2). The previously-unpinned behavioral delta is now pinned.

## Test Commands & Results

- `flutter test test/core/local_discovery/ test/features/conversation/application/send_chat_message_use_case_test.dart` → **162/162 PASS**.
- `flutter test test/core/resilience/transport_switch_learned_invalidation_test.dart test/features/conversation/integration/concurrent_durable_fallback_roundtrip_test.dart test/features/conversation/application/handle_incoming_chat_message_use_case_test.dart` → **39/39 PASS**.
- `flutter test test/features/conversation/application/send_chat_message_use_case_test.dart` → **88/88 PASS** (post R1/R3/R5: U2 short-circuit + cold baseline + P5 probe-fail tests added; tautological U2 removed).
- **Post-remediation suites:** `test/core/services/p2p_service_learned_transport_invalidation_test.dart` (R2, 9/9), `test/core/local_discovery/bonsoir_discovery_getlocalpeer_eviction_test.dart` (R4, 5/5).

### Mutation / negative-control runs (original audit + post-remediation R1–R5)
- **P2 TTL mutant — original audit:** deleted eviction block in `bonsoir_discovery_service.dart`, kept `return p;` → **162/162 STILL PASS** (no test pinned read-time TTL). **R4 closes it:** with `bonsoir_discovery_getlocalpeer_eviction_test.dart` in place, deleting the same eviction block now turns the eviction suite RED. File restored.
- **P5 constant mutant — original audit:** `relayProbeSendAttempts` 1→2 → **85/85 STILL PASS** (no neg control). **R5 closes it:** the new probe-connected-but-post-probe-send-fails test asserts `sendCallCount == 1`; reverting 1→2 turns it RED (`sendCallCount` Expected 1 / Actual 2). Restored.
- **P3 sticky mutant — R3:** replacing the `_tryLearnedShortCircuit(...)` invocation with a null result → both U2 short-circuit tests RED ('learned direct' Expected 0 / Actual 1 at `discoverCallCount`; 'learned local' Expected 0 / Actual 1 at `discoverLocalPeerCallCount`); restore → **88/88 GREEN**. The short-circuit is genuinely pinned.
- **P2 grace mutant (positive) — original audit:** `offerSuccess` → pure first-wins → **U1 FAILS** `Expected 'local'/Actual 'direct'`. (Grace genuinely pinned.) Restored.

## RED FLAGS (original audit findings + remediation status R1–R5)

1. **[RESOLVED — R3] NET-REL-05 P3 acceptance #2.** Original finding: sticky transport did NOT skip/reduce discovery on a repeat send — the head-start gated win-eligibility only; cold vs sticky counters were byte-identical (discover=1 dial=1), so there was NO everyday-latency win, and R1 stripped the "fewer discover/dial → faster" claim. **R3 landed the real short-circuit** (`_tryLearnedShortCircuit` reuses the learned path, skips re-discovery/re-dialing); a sticky send now issues STRICTLY fewer discover/dial than cold (zero vs one), proven by mutation (delete the short-circuit call → U2 RED). The latency claim is now restored as TRUE in the plan/problem/audit docs, cited to those tests.

2. **[RESOLVED — R1+R3] Weak/tautological test — U2 sticky.** Original finding: `expect(stickyP2P.discoverCallCount, lessThanOrEqualTo(coldDiscoverLocal))` compared mismatched counters (`1 <= 1`) and passed even with sticky removed. R1 DELETED it. **R3 replaced it** with two mutation-resistant short-circuit tests (sticky 'direct' and 'local', asserting `discoverCallCount==0`/`dialCallCount==0`, the local one also `discoverLocalPeerCallCount==0`) plus a paired cold-baseline asserting `==1`/`==1`.

3. **[RESOLVED — R4] NET-REL-01 P2 read-time TTL eviction was unpinned.** Original finding: deleting `getLocalPeer`'s eviction block left all 162 tests green; the claim was asserted only against a `FakeP2PService` Set check, never the production `BonsoirDiscoveryService`. **R4 added `bonsoir_discovery_getlocalpeer_eviction_test.dart`** which instantiates the REAL service (seeded via `@visibleForTesting debugSeedPeer`) and asserts the eviction removes the entry; deleting the block now turns the suite RED.

4. **[RESOLVED — R5] NET-REL-05 P5 consolidation was unpinned.** Original finding: reverting `relayProbeSendAttempts` 1→2 left all 85 tests green; no probe-connected-AND-post-probe-send-fails test existed; `relayProbeRetryBackoff` was dead on the single-attempt path. **R5 added** the probe-connected-but-post-probe-send-fails test (`sendCallCount == 1`; revert 1→2 → RED) and **removed** the dead `relayProbeRetryBackoff` constant + its three unreachable backoff guards.

5. **[RESOLVED — R2] Production invalidation paths in `P2PServiceImpl` were untested.** Original finding: real TTL expiry, disconnect-invalidation, and relay-health-transition invalidation had no direct test; coverage ran only against an integration fake. **R2 added `p2p_service_learned_transport_invalidation_test.dart`** (9 tests) against the REAL `P2PServiceImpl`, firing each trigger through real bridge callbacks; R2 also FIXED a real bug — the modern `relay:state` push path was missing the health-transition invalidation that only the legacy addresses path had — and made TTL deterministic via `clock.now()`.

6. **[DEFERRED — proven against host fakes; device/wire proof pending] Wire-level liveness gaps.** NET-REL-01 P1's device-mDNS proof (**I3**) and NET-REL-05 P1/P4's over-the-wire proof (**E2** — live attempt + InboxStore via Go FLOW events) are NOT built. These features pass against deterministic host fakes (and, post-R4, the real `BonsoirDiscoveryService` seeded in-process); the real Go-stack / native-mDNS path is unverified by automated tests. This is explicitly DEFERRED, not done — it is the one remaining gap after R1–R5.

7. **[Minor — watch] transient transport label.** Roundtrip integration showed one non-reproducible transient (offline send labeled `local` instead of `inbox`) — possible warm-up/ordering sensitivity under the parallel race; worth watching in CI.
