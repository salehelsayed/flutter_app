# VC-04 — Call-Signaling Envelope Types  (New Feature)

Status: accepted (post /tdd-review)
Spec: free-text intent (no formal spec) — grounded by `Test-Flight-Improv/Voice-Video-Call-1to1-Feature/VC-00-roadmap.md` (VC-04 story row, rule 5 signaling semantics) + the VC grounding digests (signaling-messaging, harness-conventions, metrics-telemetry; all anchors re-verified against HEAD `new-orbit` on 2026-07-13, drift noted inline).

---

## Planning Progress
| Time | Role | Files inspected | Decision/blocker | Next action |
|---|---|---|---|---|
| 2026-07-13 | Evidence Collector | `incoming_message_router.dart`, `node.go:1693-1717,1783-1862`, `p2p_service_impl.dart:2404-2471,555-572`, `send_delivery_receipt_use_case.dart:90-140`, `run_test_gates.sh:870-1095`, `check_reliability_simulation_discovery.sh`, `run_1to1_device_real.dart`, `run_direct_private_media_device_local_journey.dart`, `test/shared/fakes/{fake_p2p_network,test_user,fake_p2p_service_integration}.dart` | all digest anchors re-verified on HEAD; two digest-refuted claims carried as Corrections (ack-first-then-emit; retryUnacked file cite) | author plan |
| 2026-07-13 | Planner | (this file) | fast-path-only via `sendMessageWithReply` seam; plaintext v1 envelope (delivery_receipt precedent); TTL 45 s; glare = lower-peerId wins | sufficiency review |
| 2026-07-13 | Reviewer (sufficiency) | (this file vs sufficiency-checklist) | all gates pass — see Reviewer Findings | Arbiter |
| 2026-07-13 | Arbiter | (this file) | no structural blockers | hand off to execution |

## Execution Progress
| Time | Phase | Files touched | Command/evidence | Decision/blocker | Next |
|---|---|---|---|---|---|
| | contract extraction (`git status --short` snapshot — preserve pre-existing dirty tree, do NOT revert/absorb it) | | | scope confirmed | |
| | HEAD forward-compat proof (VC-04-08, GREEN on HEAD, BEFORE any router edit) | | `flutter test test/core/services/incoming_message_router_test.dart --plain-name 'VC-04-08'` | old-client drop behavior proven | |
| | RED (slice 3A domain) | | (cmd proving they FAIL) | RED for expected reason | |
| | RED (slice 3B router) | | (cmd) | RED for expected reason | |
| | RED (slice 3C listener) | | (cmd) | RED for expected reason | |
| | RED (slice 3D service) | | (cmd) | RED for expected reason | |
| | RED (slice 3E integration+wiring) | | (cmd) | RED for expected reason | |
| | implementation | | | scoped files only | |
| | direct GREEN | | (exact cmd) | reds now green | |
| | preservation GREEN | | (exact cmd) | sentinels green | |
| | named gates | | (exact cmd + counts) | gate green | |
| | device e2e (USB device + emulator, VC-00 rule 1) | | orchestrator output + latency artifact | round trip proven | |
| | QA (independent) | | (re-run cmds) | blocking: none/list | verdict |

---

## Source Of Truth
- Spec / intent: `VC-00-roadmap.md` — VC-04 story row ("Two peers exchange `call_*` envelopes fast-path-only with TTL, glare resolution, and forward-compat proof"), DECISION RECORD, non-negotiable rules 1, 4, 5, 6, 7.
- Gate definitions: `scripts/run_test_gates.sh` (script wins over prose).
- Discovery/registration: `scripts/check_reliability_simulation_discovery.sh`.
- Numbering / index: VC plans are NOT indexed in `Test-Flight-Improv/00-INDEX.md` (VC-00 rule 7 — feature subdirectories are never indexed; verified zero FDC/LiveKit references). This plan lives only in `Voice-Video-Call-1to1-Feature/`, numbered VC-04.
- House-style exemplar: `Network-Transport-libp2p-Feature/fast-direct-connection/FDC-03-concurrent-durable-inbox-safety-net-tdd-plan.md` (structure only; its pass counts are stale — VC-00 rule 6: capture green baselines at execution start, never hardcode).

**VC-00 rules this plan restates and owns:**
- **Rule 1 (execution environment):** the implementing agent runs the full loop on a USB-connected Android device (adb serial) + Android emulator; the two-party e2e is proven device↔emulator. No iOS legs in this story (no iOS boundary is touched). See *Execution Environment*.
- **Rule 4 (Move-feature gate):** every new call-signaling send funnels **exclusively** through `P2PService.sendMessageWithReply`, whose first line is the `_allowsAccountNetworkSideEffects('p2p_send_message_with_reply', …)` gate (`lib/core/services/p2p_service_impl.dart:2409-2412`; gate impl `:555-572`). No other network egress exists in the feature — test-locked (VC-04-10/12).
- **Rule 5 (signaling semantics):** `call_*` envelopes are fast-path-only (never durable-inboxed, never swept by `retry_unacked_messages_use_case.dart:15` / `retry_failed_messages_use_case.dart:93,225` via `PendingMessageRetrier` `pending_message_retrier.dart:279-299`), carry TTL + `callId` idempotency, and the plan accounts for Go's **ack-first-then-emit** ordering on the immediate-ack path (`go-mknoon/node/node.go:1854` ack write **precedes** `:1860` emit; only the four deferred types at `:1706` emit first). An in-stream ack proves delivery **to the callee's Go node**, not that Dart emitted it and emphatically not that a listener handled it. Forward-compat of unknown `type` is a tested behavior (VC-04-08/09), not an assumption.
- **Rule 6 (gate hygiene):** every new `*_test.dart` classifies (`./scripts/run_test_gates.sh completeness-check`; `classify_path` at `scripts/run_test_gates.sh:870`); the one new Go test runs via a pinned invocation with `GOTOOLCHAIN=go1.25.0` copying the synthetic-path pattern of `run_host_test_gates.sh:144-184`; the gate-doc quartet (`run_test_gates.sh`/`run_host_test_gates.sh` + `test-gate-definitions.md` + `test-gates-reference.md` + `_current-test-map.md`) is updated together; pass counts are captured as green baselines at execution start, never hardcoded.
- Rule 2 (EC2 relay redeploy) is **not triggered**: VC-04 makes zero `go-relay-server/` changes; the device e2e uses the relay **as already deployed** at `mknoun.xyz`. Rule 3 (kill-switch) is **not triggered**: VC-04 adds no feature flag and no default-on network behavior — see *Accepted Differences*.

---

## Session Classification

**implementation-ready** — Dart-heavy new feature with zero Go **production** changes (Go is content-agnostic for new envelope types — verified: `handleIncomingMessage` reads a frame, acks, and emits regardless of `type`, `node.go:1783-1862`; only `shouldDeferDirectAck` inspects type, `:1693-1717`). The domain/application/router work is fully host-testable with existing fakes. The device↔emulator e2e (VC-04-22) is required for closure of the wire leg (PROD-CRITICAL) and is runnable end-to-end on the rule-1 rig by the implementing agent.

---

## Exact Problem Statement

mknoon has no call-signaling vocabulary. The VC epic's decision record (VC-00) selects the existing encrypted 1:1 envelope system (`{type, version, payload}` over `/mknoon/chat/1.0.0`) as the signaling plane for 1:1 voice/video calls, but today the `IncomingMessageRouter` (`lib/core/services/incoming_message_router.dart:171-271`) has no `call_*` cases — a `call_offer` sent to any current build falls into the unknown-type default branch (`:264-270`) and silently no-ops. There is no CallSession state machine, no send primitive with call-appropriate delivery semantics, and — critically — the existing 1:1 send path (`sendChatMessage`, `send_chat_message_use_case.dart:276`) is the **wrong tool** for signaling: it concurrently durable-inboxes every unknown-presence send (`:773-778` gate, `concurrentInbox` declared `:806`), and `PendingMessageRetrier` re-sends persisted rows hours later. A stale `call_offer` replayed from the relay inbox after 7 days (`go-relay-server/inbox.go:29-30`) would ring a phone for a call that ended last week.

Who experiences it: every user of the VC epic — VC-05 (audio call) cannot exist without an offer/answer/end handshake; VC-06/07 (ring) depend on the offer envelope contract; VC-08/09 build on it.

Why it matters now: VC-04 is the MVP-cut critical path (VC-00: VC-03 → **VC-04** → VC-05).

**What must improve:** a complete, test-locked call-signaling layer — six versioned envelope types (`call_offer`, `call_answer`, `call_ice_candidates`, `call_end`, `call_decline`, `call_busy`), a pure-Dart `CallSession` state machine, fast-path-only delivery with TTL both sides, glare resolution, `(callId, seq)` idempotency, busy auto-reply, and a proven device↔emulator round trip over the deployed relay.

**What must stay unchanged → preserved-green sentinels:**
- Existing router dispatch for every current type, and unknown-type/unparseable fall-through: `test/core/services/incoming_message_router_test.dart::"routes unknown types to unknownMessageStream"`, `::"routes unparseable content to unknownMessageStream"`, `::"routes chat_message messages to chatMessageStream"`, `::"routes contact_request messages to contactRequestStream"` (file registered in `ONE_TO_ONE_TESTS`, `scripts/run_test_gates.sh:41`).
- The 1:1 chat send ladder — `sendChatMessage` is **not edited**: `send_chat_message_use_case_test.dart` FDC families (concurrent-inbox, reuse, relay-leg) stay green via the `1to1` gate.
- Delivery-receipt semantics (`send_delivery_receipt_use_case_test.dart`) — the precedent this plan copies, untouched.
- Go node behavior: zero production Go edits; `1to1` gate's pinned relay-notification Go hook (`run_test_gates.sh:862`) stays green.

---

## Root Cause (verify → refute confirmed)

Not a bug — a missing capability. The verified mechanism map for the new seams:

1. **Dispatch seam:** `IncomingMessageRouter._route` is a hardcoded switch on `jsonDecode(message.content)['type']` (`incoming_message_router.dart:171`); there is NO registration API. Unknown types → `MESSAGE_ROUTER_UNKNOWN_TYPE` flow event (`:267`) + `_unknownController.add` (`:270`); parse errors → `:284`. Forward-compat comment precedent at `:222` ("older builds hit the default branch as a no-op"). Adding call types = new cases + one new `StreamController` + getter + `dispose()` entry (`:297-318`).
2. **Fast-path-only send seam:** `P2PService.sendMessageWithReply` (`p2p_service_impl.dart:2404-2471`) is a raw single live send — no DB row, no inbox, no retrier; gate first-line at `:2409`. `PendingMessageRetrier` sweeps only messageRepo rows (`pending_message_retrier.dart:279-299` → `retry_failed_messages_use_case.dart:93,225` status=='failed'; `retry_unacked_messages_use_case.dart:15` status=='sent'). **A sender that never persists via messageRepo is structurally outside all durable/retry machinery** — that is the opt-out, and it also covers the concurrent-durable-inbox branch, which lives inside `sendChatMessage` (`send_chat_message_use_case.dart:773-778,806`) and is therefore never reached. Precedent: `sendDeliveryReceipt` (`send_delivery_receipt_use_case.dart:110` live) — except VC-04 deliberately does NOT copy its `storeInInbox` fallback (`:132`), because call signals must never be inboxed.
3. **Ack ordering (digest Correction — carried):** for any new `call_*` type Go writes `{"ack":true}` **before** emitting `message:received` (`node.go:1854` ack, `:1860` emit); emit-before-ack happens only for the four deferred types (`:1706`) under `EnableDeferredDirectAck`. Consequence: `acked=true` on a call send means "the callee's Go node read the frame", NOT "the callee's Dart handled it". The state machine treats acked-offer as `ringing` (delivered-to-node) but closes the gap with sender-side TTL expiry → `ended(timeout)` (VC-04-14/15).
4. **No TTL machinery exists** in the Dart 1:1 send path (verified-absence grep in the digest; only relay-custody `relayExpiresAt` and private-media expiry). VC-04 introduces `sentAtMs`-based TTL at the application layer.
5. **Frame budget:** `MaxFrameLen=128KB` both sides (`go-mknoon/node/config.go:77`, `go-relay-server/inbox.go:28`). Call envelopes get a defensive `kMaxCallSignalBytes = 96*1024` cap (mirrors `kLiveRelayMaxPayloadBytes`, `send_chat_message_use_case.dart:110`).

**Refuted / do-NOT-re-introduce (from digest adversarial refutation):**
- Do NOT plan against "emit-then-ack" as the general receive order — that holds only for the four deferred types. Immediate-ack path is ack-first (`node.go:1854-1860`).
- Do NOT cite `retryUnackedMessages` to `retry_failed_messages_use_case.dart` — it lives at `retry_unacked_messages_use_case.dart:15`.
- Do NOT add `call_*` to the `shouldDeferDirectAck` switch (`node.go:1705-1709`) to make acks "mean handled" — that would block the callee's ack behind a 2 s Dart confirm (`DirectConfirmTimeout`, `config.go:95`) and require listener confirm wiring; wrong tradeoff for latency-critical signaling, and a Go protocol change this story forbids. Locked by VC-04-G1.

---

## Real Scope

**In scope (VC-04):**
- NEW `lib/features/call/` feature dir (`domain/`, `application/` — layering per conventions; no `presentation/` in this story):
  - `domain/call_session.dart` — `CallSession` pure-Dart state machine: `idle→dialing→ringing→connecting→active→ended(reason: hangup|decline|busy|timeout|failed)`, illegal-transition guards, `markActive()` seam for VC-05.
  - `domain/call_signal_envelope.dart` — six envelope types, `version:'1'`, fields `callId` (UUID v4), `seq` (int, monotonic per sender per call), `sentAtMs` (UTC epoch ms), payloads: `sdp` (opaque string; offer/answer), `candidates` (list of opaque strings; ice), `reason` (end). Codec with malformed/unknown-version graceful-drop and `kMaxCallSignalBytes` (96 KiB) oversize guard.
  - `application/call_signal_listener.dart` — subscribes `IncomingMessageRouter.callSignalStream`, parses/validates (TTL, dedup, tombstones), exposes typed broadcast streams (`offers`, `answers`, `iceCandidates`, `ends`, `declines`, `busies`).
  - `application/call_signaling_service.dart` — send primitives (`sendOffer/sendAnswer/sendIceCandidates/sendEnd/sendDecline/sendBusy`) over `p2pService.sendMessageWithReply` ONLY; owns the active `CallSession`; glare, busy auto-reply, sender-side expiry; flow events.
  - `application/call_wiring.dart` — single `wireCallSignaling({required IncomingMessageRouter router, required P2PService p2pService, …})` factory that constructs listener + service and subscribes the listener to `router.callSignalStream`; `main.dart` calls it exactly once. Keeps the production DI seam host-testable (VC-04-23).
- `IncomingMessageRouter`: six new cases → one new `_callSignalController` + `callSignalStream` getter + dispose entry.
- DI wiring in `lib/main.dart` (one `wireCallSignaling(...)` call next to `IncomingMessageRouter` construction at `main.dart:2597`) — covered by VC-04-23 plus a literal call-site grep gate (Acceptance step 8).
- TTL: `kCallOfferTtl = 45000` ms (45 s) receiver-side (drop stale by `sentAtMs`) AND sender-side (dialing/ringing expiry → `ended(timeout)`). **Receiver-side age-drop applies to `call_offer` ONLY; `call_answer`/`call_ice_candidates`/`call_end`/`call_decline`/`call_busy` are never age-dropped — session state + tombstones govern them** (a 120 s-old `call_end` for a still-active call must still end it — VC-04-13 sub-case). Cross-plan lock (L1): VC-04 owns this constant epic-wide; VC-06's ring timeout = min(45 s, TTL remaining from `sentAtMs`). Justification below (*Risks*).
- Glare: deterministic winner = lexicographically **lower peerId**; loser abandons its own `callId` (tombstoned) and auto-converts to answering the winner's offer. Both orders test-locked.
- Idempotency: dedup by `(callId, fromPeerId, seq)`, bounded LRU (`kCallDedupLruCapacity`); ended-call tombstones retained ≥ 2×TTL (`kCallTombstoneRetention`) so late re-deliveries never re-ring — both constants declared in `call_signal_listener.dart` next to `kCallOfferTtl`, chosen values recorded in Execution Progress.
- Busy: incoming offer with a different `callId` while the session is non-idle → auto `call_busy`, session untouched.
- Forward-compat: HEAD-router proof that old clients drop `call_offer` gracefully (VC-04-08) + a permanent future-type sentinel (VC-04-09). Ring-compat consequence documented: **an old callee never rings** — VC-06/VC-07's ring push (caller-side relay action `call_push_request`) is the coverage for that gap, not VC-04.
- One new Go **test-only** pin (`call_*` acks immediately) + its pinned gate invocation (rule 6 ceremony).
- Device↔emulator e2e over the deployed relay with signaling-latency capture + orchestrator + full harness registration.

**Out of scope (owning story):**
- WebRTC / SDP generation, `flutter_webrtc` dependency, `RTCPeerConnection` — **VC-05** (here `sdp`/`candidates` are opaque strings).
- Any UI (call screen, ring screen) — **VC-05/VC-06**.
- Push / ring / full-screen intent / CallKit — **VC-06/VC-07** (incl. the old-callee-never-rings gap).
- Video — **VC-08**. Quality metrics beyond signaling flow events, TransportMetrics counters, relay Prometheus call metrics — **VC-09**.
- Relay changes (STUN/TURN — **VC-03**; circuit holding — **VC-01/02**). VC-04 uses the relay as deployed.
- Application-layer encryption of call payloads — deferred (see *Accepted Differences*).

---

## Files To Inspect Next

**Production (new):**
- `lib/features/call/domain/call_session.dart` (NEW)
- `lib/features/call/domain/call_signal_envelope.dart` (NEW)
- `lib/features/call/application/call_signal_listener.dart` (NEW)
- `lib/features/call/application/call_signaling_service.dart` (NEW)
- `lib/features/call/application/call_wiring.dart` (NEW — `wireCallSignaling` factory, VC-04-23)

**Production (edited):**
- `lib/core/services/incoming_message_router.dart` — switch `:171-271` (add cases after `delivery_receipt` `:259-263`), controllers block (`_unknownController` at `:38`), getters (`unknownMessageStream :112`), `dispose() :297-318`.
- `lib/main.dart` — DI next to router construction `:2597`.

**Dependency-only context (NOT edited):**
- `lib/core/services/p2p_service_impl.dart` — `sendMessageWithReply :2404-2471`, gate `:555-572` + first-line call `:2409`.
- `lib/features/conversation/application/send_delivery_receipt_use_case.dart:90-140` — envelope + live-send precedent (fallback NOT copied).
- `lib/features/conversation/application/send_chat_message_use_case.dart:773-778,806` — the concurrent-durable branch the opt-out must never reach (structurally: no dependency on this use case).
- `lib/core/services/pending_message_retrier.dart:279-299`, `retry_unacked_messages_use_case.dart:15`, `retry_failed_messages_use_case.dart:93,225` — retry machinery the feature stays outside of.
- `go-mknoon/node/node.go:1693-1717` (`shouldDeferDirectAck`), `:1854-1860` (ack-then-emit) — pinned by the new Go test, not edited.
- `lib/core/utils/flow_event_emitter.dart` — `emitFlowEvent :202`, `debugSetFlowEventSink :38`, `flowEventLoggingEnabled :6` (force-on via `--dart-define=FDC_FLOW_LOG=1`, `lib/main.dart:320-332`).

**Direct tests (new):**
- `test/features/call/domain/call_session_test.dart`, `test/features/call/domain/call_signal_envelope_test.dart`
- `test/features/call/application/call_signal_listener_test.dart`, `test/features/call/application/call_signaling_service_test.dart`, `test/features/call/application/call_wiring_test.dart`
- `test/features/call/integration/call_signaling_roundtrip_test.dart`
- `test/core/services/incoming_message_router_test.dart` (extended — already in `ONE_TO_ONE_TESTS`, `run_test_gates.sh:41`)
- `go-mknoon/node/call_signal_ack_contract_test.go` (NEW, test-only)
- `integration_test/call_signaling_roundtrip_proof_test.dart` + `integration_test/scripts/run_call_device_real.dart` (NEW — the epic-shared call device orchestrator per cross-plan lock L5; VC-04 creates it, later VC stories add scenarios)

**Test harness (reused, not edited):** `test/shared/fakes/fake_p2p_network.dart` (`storeInInboxCallCount :38`, `duplicateOnDeliver :32` — doc comment `:31`, `deliveryDelay :21`), `test/shared/fakes/test_user.dart:37` (`TestUser` per-user stack whose `router` is an OPTIONAL field `:46` — constructed only with `withReactions`-style opts `:109-112`; no VC-04 row depends on it), `test/shared/fakes/fake_p2p_service_integration.dart` (`sendMessageWithReply` failure/delay knobs `:24,:66`), per-file `FakeP2PService` in `incoming_message_router_test.dart:12`.

---

## Existing Tests Covering This Area

- `test/core/services/incoming_message_router_test.dart::routes unknown types to unknownMessageStream` — covers the default branch old clients hit (exists; sentinel).
- `…::routes unparseable content to unknownMessageStream` (exists; sentinel).
- `…::routes chat_message/contact_request messages to their streams` (exists; sentinels).
- `test/features/conversation/application/send_delivery_receipt_use_case_test.dart` — live-then-inbox precedent this plan deliberately diverges from (exists; sentinel, untouched).
- `test/features/conversation/application/send_chat_message_use_case_test.dart` FDC-03 concurrent-inbox family — locks the durable branch call signaling must never enter (exists; sentinel via `1to1` gate).
- `go-mknoon/node/transport_label_test.go::TestHandleIncomingMessage_DirectAckContract_AttachesConfirmNonce` — pins the deferred-ack contract for the four chat types (exists; adjacent).

**Missing coverage gaps (all owned by this plan):** no test anywhere for `call_*` routing, CallSession transitions, fast-path-only delivery, TTL, glare, dedup, busy, the immediate-ack contract for call types, or a two-party call-signaling round trip.

**Already in curated family arrays?:** `incoming_message_router_test.dart` → `ONE_TO_ONE_TESTS` (`run_test_gates.sh:41`). All other test files are NEW → registration consequences per row in the matrix.

---

## RED Test Catalog  (add BEFORE any production code — INV-RED-FIRST)

> Tier legend: **unit/domain**, **unit/app** = host tests under `test/features/call/**` (AUTO-globbed, `classify_path` `run_test_gates.sh:1015,1025`); **integration** = `test/features/call/integration/` two-party `FakeP2PNetwork`; **device-proof** = `integration_test/*_proof_test.dart` on the rule-1 rig.
> All new-file tests are RED on HEAD because `lib/features/call/` does not exist (verified: `lib/features/` has no `call` dir) — imports fail to compile. Where a subtler RED reason exists it is stated. Flow events are captured with `debugSetFlowEventSink` (`flow_event_emitter.dart:38`; sanitization is unconditional and runs before the sink).

1. `test/features/call/domain/call_session_test.dart::VC-04-01 caller lifecycle idle→dialing→ringing→connecting→active→ended(hangup)`
   - Tier: unit/domain. Shape: drive `CallSession` transitions directly: `startDialing(callId)` → `onOfferAcked()` → `onAnswerReceived()` → `markActive()` → `end(hangup)`.
   - RED on HEAD because: `CallSession` does not exist (compile).
   - GREEN asserts: each transition lands in the expected state; state-change history is exact.
   - Mutation that re-reds: make `onOfferAcked()` a no-op (stays `dialing`) → RED.

2. `…call_session_test.dart::VC-04-02 callee lifecycle idle→ringing→connecting→active→ended(hangup)`
   - Tier: unit/domain. Shape: `onOfferReceived(callId)` → `onAnswerSent()` → `markActive()` → `end(hangup)`.
   - RED on HEAD because: compile. GREEN asserts: states as named.
   - Mutation: drop the `ringing→connecting` transition on `onAnswerSent()` → RED.

3. `…call_session_test.dart::VC-04-03 terminal reasons + illegal transitions guarded`
   - Tier: unit/domain. Shape: from `dialing`/`ringing`: `onDeclineReceived()`→`ended(decline)`, `onBusyReceived()`→`ended(busy)`, `onExpiry()`→`ended(timeout)`, `onSendFailure()`→`ended(failed)`; from `idle`: `onAnswerReceived()` is a guarded no-op (stays `idle`, no throw); from `ended`: every input is a no-op (terminal).
   - RED on HEAD because: compile. GREEN asserts: reasons exact; illegal inputs change nothing.
   - Mutation: let `ended` accept `onOfferReceived` back to `ringing` → RED (terminality).

4. `test/features/call/domain/call_signal_envelope_test.dart::VC-04-04 all six types encode/decode round-trip with v1 fields`
   - Tier: unit/domain. Shape: build each of `call_offer/call_answer/call_ice_candidates/call_end/call_decline/call_busy`, `encode()` → JSON string → `CallSignalEnvelope.decode()`.
   - RED on HEAD because: compile.
   - GREEN asserts: top-level `{type, version:'1', payload}` with cleartext `type` (router-dispatchable, same shape as `send_delivery_receipt_use_case.dart:96-102`); payload carries `callId` (UUID), `seq`, `sentAtMs`, and per-type `sdp`/`candidates`/`reason`; decode reproduces the value object.
   - Mutation: drop `sentAtMs` from `encode()` → decode round-trip assertion RED.

5. `…call_signal_envelope_test.dart::VC-04-05 malformed and unknown-version envelopes decode to null (graceful drop)`
   - Tier: unit/domain. Shape: feed truncated JSON, missing `callId`, `version:'99'`, wrong payload types.
   - RED on HEAD because: compile. GREEN asserts: `decode()` returns null (never throws) for every case; a `version:'99'` well-formed envelope is dropped, not misparsed.
   - Mutation: make decode throw on missing `callId` → RED.

6. `…call_signal_envelope_test.dart::VC-04-06 oversize envelope rejected at encode (kMaxCallSignalBytes)`
   - Tier: unit/domain. Shape: offer with a 100 KiB `sdp` string.
   - RED on HEAD because: compile. GREEN asserts: `encode()` throws/returns error for > 96 KiB (`kMaxCallSignalBytes = 96*1024`, mirroring `kLiveRelayMaxPayloadBytes` `send_chat_message_use_case.dart:110`; hard frame cap is 128 KiB, `config.go:77` / `go-relay-server/inbox.go:28`); a 4 KiB SDP passes.
   - Mutation: remove the size check → RED.

7. `test/core/services/incoming_message_router_test.dart::VC-04-07 routes all six call_* types to callSignalStream and NOT unknownMessageStream`
   - Tier: unit/app. Shape: existing file's `FakeP2PService` (`:12`) message injection, one message per type.
   - RED on HEAD because: `router.callSignalStream` getter does not exist (compile); on a getter-stubbed tree the messages land on `unknownMessageStream`.
   - GREEN asserts: each type emits exactly one `ChatMessage` on `callSignalStream`; `unknownMessageStream` stays silent (distinct-event discriminator: `callSignalStream` fires AND NOT `MESSAGE_ROUTER_UNKNOWN_TYPE`).
   - Mutation: delete the `case 'call_busy':` line → that type falls to default → RED.

8. `…incoming_message_router_test.dart::VC-04-08 HEAD PROOF — old client drops call_offer as unknown-type no-op` **(GREEN on HEAD — evidence capture, not RED)**
   - Tier: unit/app. Shape: inject a full v1 `call_offer` envelope into the HEAD router (no listener on `unknownMessageStream`).
   - GREEN **on HEAD** asserts: the message lands on `unknownMessageStream`, a `MESSAGE_ROUTER_UNKNOWN_TYPE` flow event fires (`incoming_message_router.dart:267`), nothing throws, no other stream fires. **This run is executed and recorded in Execution Progress BEFORE the router edit** — it is the forward-compat proof that a pre-VC-04 build no-ops on `call_offer` (precedent comment `:222`). Note: on the wire the old client's Go node still acks the frame (`node.go:1854`) — so the CALLER sees `acked=true` while the old callee never rings; the caller's TTL expiry (VC-04-14) is what ends that call, and VC-06/07's push is the product-level fix.
   - Migration: after the router edit this test inverts by design → it is **rewritten into VC-04-07** with a `// VC-04:` note; the permanent forward-compat lock becomes VC-04-09.
9. `…incoming_message_router_test.dart::VC-04-09 future call type call_upgrade_v99 still drops to unknown no-op (permanent sentinel)`
   - Tier: unit/app. Shape: inject `{type:'call_upgrade_v99',version:'1',payload:{…}}`.
   - RED on HEAD because: the assertion uses `router.callSignalStream` to prove the future type does NOT land there (compile on HEAD; behaviorally green once the getter exists).
   - GREEN asserts: unknown future call types → `unknownMessageStream` + `MESSAGE_ROUTER_UNKNOWN_TYPE`, `callSignalStream` silent — locking that VC-04-era clients degrade gracefully when a future story adds new call types.
   - Mutation: add a wildcard `case` matching `call_*` prefixes to the router → future type lands on `callSignalStream` → RED.

10. `test/features/call/application/call_signaling_service_test.dart::VC-04-10 every send primitive is fast-path-only (parameterized over all six types)`
    - Tier: unit/app. Shape: `FakeP2PService` (integration fake, `fake_p2p_service_integration.dart`) configured **unknown-presence** (not connected, not LAN); an `InMemoryMessageRepository` present in the test but NOT injected (the service takes no repo); invoke each of the six send primitives.
    - RED on HEAD because: compile (`CallSignalingService` missing).
    - GREEN asserts: per type — `sendMessageWithReply` called exactly once with the encoded envelope; `storeInInboxCallCount == 0`; `sendMessage` (persisting chat path) never called; repo has zero rows; **discriminator:** flow events contain `CALL_SIGNAL_SEND{type}` AND NOT `CHAT_MSG_SEND_CONCURRENT_INBOX_BEGIN` (the unknown-presence durable branch, `send_chat_message_use_case.dart:806`, is unreachable — the service has no `sendChatMessage` dependency).
    - Mutation: add a `storeInInbox` fallback after a failed live send (copying `send_delivery_receipt_use_case.dart:132`) → `storeInInboxCallCount == 1` → RED.

11. `…call_signaling_service_test.dart::VC-04-11 retry machinery never re-sends call signals`
    - Tier: unit/app. Shape: after VC-04-10's sends (including a failed one), run `retryFailedMessages` and `retryUnackedMessages` use cases against the same (empty) repo with the fake p2p service.
    - RED on HEAD because: compile.
    - GREEN asserts: both sweeps find zero candidate rows; `sendMessageWithReply`/`storeInInbox` counters unchanged after the sweeps — call signals are structurally invisible to `PendingMessageRetrier`'s two sweep entry points (`pending_message_retrier.dart:279-299`).
    - Mutation: persist a `call_offer` row via the repo inside `sendOffer` → the `'failed'` sweep picks it up → counter moves → RED.

12. `…call_signaling_service_test.dart::VC-04-12 denied/failed send fails clean: ended(failed), no fallback egress, gate honored transitively`
    - Tier: unit/app. Shape: fake configured so `sendMessageWithReply` returns `sent:false` (the shape `P2PServiceImpl` returns when `_allowsAccountNetworkSideEffects('p2p_send_message_with_reply')` denies at `:2409-2412`, and on plain failure).
    - RED on HEAD because: compile.
    - GREEN asserts: `sendOffer` reports failure; session → `ended(failed)`; NO other fake method was invoked (asserts every other counter zero — proving `sendMessageWithReply` is the feature's **only** network egress, satisfying VC-00 rule 4 transitively); `CALL_SIGNAL_SEND_FAILED` flow event emitted; no retry attempt.
    - Mutation: add a second direct `p2pService.sendMessage(...)` retry on failure → other-counter assertion RED.

13. `test/features/call/application/call_signal_listener_test.dart::VC-04-13 receiver-side TTL — stale offer dropped, fresh offer emits, age-drop is OFFER-ONLY`
    - Tier: unit/app. Shape: injectable clock; deliver a `call_offer` with `sentAtMs = now - 46s`, then one with `now - 5s`. Sub-case (offer-only lock): with an active session, deliver a `call_end` with `sentAtMs = now - 120s`.
    - RED on HEAD because: compile.
    - GREEN asserts: stale offer emits NOTHING on `offers` stream and emits `CALL_SIGNAL_EXPIRED_DROP{ageMs}`; fresh offer emits exactly once with `CALL_SIGNAL_RECV` (discriminator: EXPIRED_DROP AND NOT RECV for the stale one). Sub-case: the 120 s-old `call_end` still emits on `ends` (session may then transition `ended(hangup)` downstream) with NO `CALL_SIGNAL_EXPIRED_DROP` — **age-drop applies to `call_offer` ONLY; answer/ice/end/decline/busy are never age-dropped, session state + tombstones govern them**.
    - Mutation: remove the `age > kCallOfferTtl` check → stale offer rings → RED. Second mutation: extend the age check to all six types → the stale-`call_end` sub-case REDs.

14. `…call_signaling_service_test.dart::VC-04-14 sender-side expiry — unanswered offer ends(timeout) and emits best-effort call_end`
    - Tier: unit/app. Shape: `fakeAsync`/injectable timer; `sendOffer` acked; no answer arrives; advance 45 s.
    - RED on HEAD because: compile.
    - GREEN asserts: session `ended(timeout)`; a `call_end{reason:'timeout'}` envelope was sent (best-effort, single attempt); `CALL_SESSION_STATE{to:ended, reason:timeout}` flow event.
    - Mutation: cancel the expiry timer on ack (treat ack as handled — the exact rule-5 mistake) → session stays `ringing` forever → RED.

15. `…call_signaling_service_test.dart::VC-04-15 ack ≠ handled — sent-but-unacked offer stays dialing (never ringing)`
    - Tier: unit/app. Shape: fake returns `sent:true, acked:false` (Go wrote the frame, ack read failed — `node.go:1607-1610` returns acked=false err=nil).
    - RED on HEAD because: compile.
    - GREEN asserts: session remains `dialing` (ringing requires `acked==true` — and the plan text of record: even `acked==true` only means the remote **node** read the frame, ack precedes emit `node.go:1854-1860`); expiry still armed → advancing time → `ended(timeout)`.
    - Mutation: transition to `ringing` on `sent:true` alone → RED.

16. `…call_signaling_service_test.dart::VC-04-16 glare — both orders resolve to lower peerId as caller; loser auto-converts to answer; third-party offer is busy, not glare`
    - Tier: unit/app. Shape: three sub-cases; **in (a) and (b) the incoming offer's `fromPeerId` == the peerId the session is currently dialing** (glare is same-peer only). (a) local peerId `12D3KooWAAA…` (lower), session `dialing(callIdL)` to peer P; incoming offer `callIdR` from P (higher). (b) local peerId higher, same setup mirrored. (c) session `dialing(peer X)`; fresh offer from peer Y ≠ X.
    - RED on HEAD because: compile.
    - GREEN asserts: (a) winner: incoming offer is NOT emitted as a ringable offer; `CALL_GLARE_RESOLVED{role:'winner'}`; session stays `dialing(callIdL)`; loser's callIdR is tombstoned. (b) loser: own `callIdL` abandoned + tombstoned; service auto-sends `call_answer` for `callIdR` (envelope on the fake wire); session → `connecting` with `callIdR`; `CALL_GLARE_RESOLVED{role:'loser'}`. Both orders produce exactly one surviving call with the **same** winning callId. (c) NO glare event; the busy auto-reply path fires instead (a `call_busy` for Y's callId is sent, session unchanged — cross-ref VC-04-18) — locking the glare-vs-busy ordering from the Risks table in a test, not prose.
    - Mutation: flip the comparison to higher-peerId-wins → sub-cases (a)/(b) RED (asymmetric assertions). Second mutation: key glare on "any offer while dialing" (drop the same-peer condition) → sub-case (c) REDs.

17. `test/features/call/application/call_signal_listener_test.dart::VC-04-17 dedup — duplicate (callId, sender, seq) re-delivery is a no-op`
    - Tier: unit/app. Shape: deliver the same `call_offer` twice, and the same `call_ice_candidates{seq:3}` twice; then a NEW `seq:4` from the same call.
    - RED on HEAD because: compile.
    - GREEN asserts: `offers` emits once; `iceCandidates` emits once for seq 3 and once for seq 4; second deliveries emit `CALL_SIGNAL_DUP_DROP` (discriminator: DUP_DROP AND NOT a second RECV).
    - Mutation: key dedup on `callId` only (ignore seq) → seq 4 dropped → RED.

18. `…call_signaling_service_test.dart::VC-04-18 busy — second incoming offer while non-idle auto-replies call_busy; caller receiving busy ends(busy)`
    - Tier: unit/app. Shape: session `active(callIdA)`; deliver fresh `call_offer{callIdB}` from a third peer. Separately: session `dialing`, deliver `call_busy{callId}`.
    - RED on HEAD because: compile.
    - GREEN asserts: a `call_busy{callIdB}` envelope is sent to the second caller (one `sendMessageWithReply`); session state and `callIdA` unchanged; `CALL_BUSY_AUTO` flow event; the dialing-side `call_busy` receipt → `ended(busy)`.
    - Mutation: skip the auto-busy when state is `active` (only handle `connecting`) → RED.

19. `…call_signal_listener_test.dart::VC-04-19 ended-call tombstone — late duplicate offer for an ended callId never re-rings`
    - Tier: unit/app. Shape: full mini-flow: offer received → ringing → `call_end` received → `ended`; then re-deliver the ORIGINAL offer (same callId/seq — e.g. a network duplicate arriving late).
    - RED on HEAD because: compile.
    - GREEN asserts: no new `offers` emission; no session state change (stays `ended`); `CALL_SIGNAL_DUP_DROP`; tombstone also verifies cleanup boundaries: dedup/tombstone tables are bounded (LRU) and the ended call's entry is retained for ≥ 2×TTL while an unrelated NEW callId still rings (what is preserved).
    - Mutation: clear all dedup state on `ended` → late duplicate re-rings → RED.

20. `test/features/call/integration/call_signaling_roundtrip_test.dart::VC-04-20 two-party offer→answer→end round trip over FakeP2PNetwork (with network duplicates on)`
    - Tier: integration (two full stacks: router + listener + service per party, wired over `test/shared/fakes/fake_p2p_network.dart` with `duplicateOnDeliver = true` — field `:32`, doc `:31`, applied in `deliver` `:81`).
    - RED on HEAD because: compile.
    - GREEN asserts: A `sendOffer` → B `offers` emits once (duplicates deduped) → B ringing → B `sendAnswer` → A `connecting` → A `sendEnd(hangup)` → both sessions `ended(hangup)`; `storeInInboxCallCount == 0` on the network fake for the whole exchange (fast-path-only end-to-end); flow-event sequence on both sides contains SEND/RECV pairs for offer, answer, end and exactly one DUP_DROP per duplicated frame.
    - Mutation: route the offer through a persisted send (repo row) → `storeInInboxCallCount`/repo assertions RED.

21. `…call_signaling_service_test.dart::VC-04-21 flow events are privacy-clean — truncated callId, no SDP, no full peerIds`
    - Tier: unit/app. Shape: capture all events from a full offer→answer→end exchange via `debugSetFlowEventSink` (sanitization is unconditional — `flow_event_emitter.dart:202-218`).
    - RED on HEAD because: compile.
    - GREEN asserts: every `CALL_*` event's details carry `id == callId.substring(0,8)` (id-preview convention, `send_delivery_receipt_use_case.dart:103-108`); NO event detail contains the SDP string, a full 52-char peerId, or a multiaddr (belt: the emitter's own redaction `flow_event_emitter.dart:56,141-160`; suspenders: we never put them in).
    - Mutation: log the raw `sdp` into `CALL_SIGNAL_SEND` details → RED.

22. `integration_test/call_signaling_roundtrip_proof_test.dart::VC-04-22 device↔emulator offer→answer→end over the deployed relay with latency capture` **(PROD-CRITICAL — the wire leg)**
    - Tier: device-proof (`@Tags(['device'])`), real `GoBridgeClient` + `P2PServiceImpl` + router + call stack per party (the per-party stack is built via the SAME `wireCallSignaling(...)` factory `main.dart` calls — the device proof exercises the production wiring seam, and VC-04-23 covers the call-site), relay = `MKNOON_RELAY_ADDRESSES` defaulting to the deployed `/dns/mknoun.xyz/tcp/4001/wss/p2p/12D3KooWGMYMmN1RGUYjWaSV6P3XtnBjwnosnJGNMnttfVCRnd6g` + `/dns/mknoun.xyz/udp/4002/quic-v1/…` pair (`run_test_gates.sh:568`).
    - Roles: `--dart-define=VC04_ROLE=callee` (emulator; prints `VC04_PEER_ID=<peerId>` marker, waits for offer, auto-answers, waits for end) and `--dart-define=VC04_ROLE=caller --dart-define=VC04_REMOTE_PEER_ID=<calleePeerId>` (USB device; sends offer with a synthetic 2 KiB opaque `sdp`, awaits answer, sends `call_end`). Marker/artifact handoff copies the plan-234 automated device+emulator pattern (`run_direct_private_media_device_local_journey.dart`, `_artifactMarker`) — **NEW file, pattern-grounded**.
    - RED on HEAD because: compile (feature + test file missing).
    - GREEN asserts: caller observes answer for its callId within TTL; both legs reach `ended(hangup)`; caller prints `VC04_E2E_ARTIFACT={"offerSendToAnswerRecvMs":N,"offerAckWaitMs":M,"endRoundMs":K}`; the orchestrator (below) validates both artifacts. **Record-and-flag:** if the median `offerSendToAnswerRecvMs` across the ≥ 5 same-network runs exceeds 10000 ms, closure requires an explicit Execution Progress note explaining why (relay path, emulator NAT) — a flag, not a FAIL (the artifact stays the VC-01 baseline), but it never auto-passes silently. **Do NOT treat host/unit coverage as sufficient on its own — this row is the only proof the signaling handshake crosses the real Go bridge, real relay, and two real devices.**
    - Mutation: host-side mutation of the listener TTL/dedup re-reds the host tiers; for the wire leg, pointing `VC04_REMOTE_PEER_ID` at a dead peerId must FAIL the run (proves the pass is not vacuous).

23. `go-mknoon/node/call_signal_ack_contract_test.go::TestCallSignalAckContract_CallTypesAckImmediately` **(GREEN-on-HEAD preservation pin — no Go production edit)**
    - Tier: Go host (pinned invocation). Shape: table-driven over the six `call_*` type names calling `shouldDeferDirectAck` with a minimal `{"type":"call_offer",…}` frame; plus one deferred type (`chat_message`) as a positive control with the flag enabled.
    - GREEN asserts: every `call_*` type returns false (immediate ack — ack `node.go:1854` precedes emit `:1860`); the positive control documents the contrast. This pins the ordering assumption the entire TTL/ack≠handled design rests on.
    - Mutation that re-reds: add `"call_offer"` to the `shouldDeferDirectAck` switch (`node.go:1706`) → RED. (This is precisely the do-not-re-introduce edit.)
    - Gate: NEW pinned synthetic path — see registration row; command `(cd go-mknoon && GOTOOLCHAIN=go1.25.0 go test ./node -run '^TestCallSignalAckContract_' -count=1)`.

24. `test/features/call/application/call_wiring_test.dart::VC-04-23 production DI wiring — wireCallSignaling subscribes the listener and returns a working stack`
    - Tier: unit/app. Shape: construct a real `IncomingMessageRouter` over the router-test-style `FakeP2PService`; call `wireCallSignaling(router: …, p2pService: …)`; inject a fresh v1 `call_offer`; also dispose and re-inject.
    - RED on HEAD because: compile (`call_wiring.dart` missing).
    - GREEN asserts: the offer flows router → listener through the factory-built wiring (the returned listener's `offers` emits once); after dispose, nothing emits (teardown works). The `main.dart` call-site itself is closed by a literal gate: Acceptance step 8 greps `lib/main.dart` for exactly one `wireCallSignaling(` occurrence — factory test + call-site grep together mean an omitted or mis-wired production DI cannot pass the gates while VC-04-22 stays green (VC-04-22's per-party stack is built via the same factory).
    - Mutation: delete the `router.callSignalStream` subscription inside `wireCallSignaling` → VC-04-23 RED (and deleting the `main.dart` call-site fails the step-8 grep).

---

## Test Coverage Matrix  (ZERO empty cells in tier / mutation / gate / registration)

| Spec case | Behavior props | Tier | Test file::name | RED reason on HEAD | Mutation revert | Acceptance gate cmd | Harness registration |
|---|---|---|---|---|---|---|---|
| VC-04-01 caller lifecycle | pure state machine | unit/domain | `test/features/call/domain/call_session_test.dart::VC-04-01` | compile: `CallSession` missing | no-op `onOfferAcked` | `./scripts/run_host_test_gates.sh feature-host-all` | AUTO (glob `test/features/**`) |
| VC-04-02 callee lifecycle | pure state machine | unit/domain | `…call_session_test.dart::VC-04-02` | compile | drop `ringing→connecting` | `feature-host-all` | AUTO (glob) |
| VC-04-03 terminal reasons + guards | pure logic | unit/domain | `…call_session_test.dart::VC-04-03` | compile | un-terminal `ended` | `feature-host-all` | AUTO (glob) |
| VC-04-04 envelope round-trip | serialization | unit/domain | `…call_signal_envelope_test.dart::VC-04-04` | compile | drop `sentAtMs` | `feature-host-all` | AUTO (glob) |
| VC-04-05 malformed/version drop | serialization guard | unit/domain | `…call_signal_envelope_test.dart::VC-04-05` | compile | throw on missing callId | `feature-host-all` | AUTO (glob) |
| VC-04-06 oversize guard | frame budget | unit/domain | `…call_signal_envelope_test.dart::VC-04-06` | compile | remove size check | `feature-host-all` | AUTO (glob) |
| VC-04-07 router routes call_* | dispatch | unit/app | `test/core/services/incoming_message_router_test.dart::VC-04-07` | `callSignalStream` getter missing (compile); types fall to unknown | delete `case 'call_busy'` | `./scripts/run_test_gates.sh 1to1` | file already in `ONE_TO_ONE_TESTS` (`run_test_gates.sh:41`); also `core-host-all` AUTO |
| VC-04-08 HEAD forward-compat proof | old-client drop (evidence) | unit/app | `…incoming_message_router_test.dart::VC-04-08` | n/a — GREEN on HEAD; executed pre-edit, recorded, then rewritten into VC-04-07 (`// VC-04:` note) | n/a (evidence capture; permanent lock = VC-04-09) | `flutter test test/core/services/incoming_message_router_test.dart --plain-name 'VC-04-08'` (on HEAD) | same file (already registered) |
| VC-04-09 future-type sentinel | forward-compat lock | unit/app | `…incoming_message_router_test.dart::VC-04-09` | compile (uses new getter) | wildcard `call_*` case | `./scripts/run_test_gates.sh 1to1` | same file (already registered) |
| VC-04-10 fast-path-only ×6 (rule 5) | delivery semantics | unit/app | `test/features/call/application/call_signaling_service_test.dart::VC-04-10` | compile | add `storeInInbox` fallback | `feature-host-all` | AUTO (glob) |
| VC-04-11 retrier isolation (rule 5) | delivery semantics | unit/app | `…call_signaling_service_test.dart::VC-04-11` | compile | persist a call row | `feature-host-all` | AUTO (glob) |
| VC-04-12 clean failure + sole-egress (rule 4) | gate/failure | unit/app | `…call_signaling_service_test.dart::VC-04-12` | compile | add second egress on failure | `feature-host-all` | AUTO (glob) |
| VC-04-13 receiver TTL (offer-only) | staleness | unit/app | `test/features/call/application/call_signal_listener_test.dart::VC-04-13` | compile | remove age check; extend age check to all six types (stale-`call_end` sub-case) | `feature-host-all` | AUTO (glob) |
| VC-04-14 sender expiry | staleness | unit/app | `…call_signaling_service_test.dart::VC-04-14` | compile | cancel timer on ack | `feature-host-all` | AUTO (glob) |
| VC-04-15 ack ≠ handled (rule 5) | ack semantics | unit/app | `…call_signaling_service_test.dart::VC-04-15` | compile | ringing on `sent` alone | `feature-host-all` | AUTO (glob) |
| VC-04-16 glare both orders + third-party-is-busy | concurrency | unit/app | `…call_signaling_service_test.dart::VC-04-16` | compile | flip winner comparison; drop same-peer glare condition (sub-case c) | `feature-host-all` | AUTO (glob) |
| VC-04-17 dedup (callId, sender, seq) | idempotency | unit/app | `…call_signal_listener_test.dart::VC-04-17` | compile | dedup on callId only | `feature-host-all` | AUTO (glob) |
| VC-04-18 busy auto-reply + busy receipt | session policy | unit/app | `…call_signaling_service_test.dart::VC-04-18` | compile | skip busy when active | `feature-host-all` | AUTO (glob) |
| VC-04-19 ended tombstone / cleanup bounds | destructive side-effects | unit/app | `…call_signal_listener_test.dart::VC-04-19` | compile | clear dedup on ended | `feature-host-all` | AUTO (glob) |
| VC-04-20 two-party round trip w/ duplicates | e2e (fake net) | integration | `test/features/call/integration/call_signaling_roundtrip_test.dart::VC-04-20` | compile | persisted send path | `./scripts/run_test_gates.sh 1to1` | AUTO (`classify_path` feature-integration `run_test_gates.sh:1015`) + **ADD path to `ONE_TO_ONE_TESTS` array** (`run_test_gates.sh:21`) — headline 1:1 case. Cross-plan lock L5: NO new call family array this epic — headline call tests append to `ONE_TO_ONE_TESTS`; anything heavy enough for nightly-only goes to `NIGHTLY_ONLY_TESTS` (`run_test_gates.sh:556`) |
| VC-04-21 flow-event privacy | telemetry hygiene | unit/app | `…call_signaling_service_test.dart::VC-04-21` | compile | log raw sdp | `feature-host-all` | AUTO (glob) |
| VC-04-23 production DI wiring | integration seam | unit/app | `test/features/call/application/call_wiring_test.dart::VC-04-23` | compile (`call_wiring.dart` missing) | delete `callSignalStream` subscription in `wireCallSignaling`; delete `main.dart` call-site → step-8 grep fails | `feature-host-all` + Acceptance step-8 `grep -c "wireCallSignaling(" lib/main.dart` (expect 1) | AUTO (glob) |
| VC-04-22 device e2e + latency (**PROD-CRITICAL**) | real bridge/relay/devices | device-proof | `integration_test/call_signaling_roundtrip_proof_test.dart::VC-04-22` | compile | dead-peer negative run must fail | `dart run integration_test/scripts/run_call_device_real.dart --scenario vc04_offer_answer_end -d <usbSerial>,<emulatorSerial>` (×≥5 same-network; median, never mean) | `@Tags(['device'])`; `run_test_gates.sh` classify AUTO (`:1036-1039` proof branch); **ADD `classify_path` case** in `check_reliability_simulation_discovery.sh` (`record "1to1" … "test"`); orchestrator scenario (next row) |
| VC-04-22R orchestrator discoverability | harness plumbing | support | `integration_test/scripts/run_call_device_real.dart` (`--list-scenarios` prints `vc04_offer_answer_end`; epic-shared orchestrator per L5 — later VC stories append scenarios, never fork a second runner) | n/a (runner, not a test) | remove scenario id → discovery expansion error | `./scripts/check_reliability_simulation_discovery.sh` (must list; zero-expansion FAILs `:966-968`) | **ADD runner `classify_path` case** (`record "1to1" … "runner"`) **+ dispatch branch** to `expand_1to1_device_real` (`:828-847,:908-931`) |
| VC-04-G1 Go ack-contract pin (rule 5) | Go ack ordering | Go host pin | `go-mknoon/node/call_signal_ack_contract_test.go::TestCallSignalAckContract_CallTypesAckImmediately` | n/a — GREEN-on-HEAD preservation pin | add `call_offer` to `shouldDeferDirectAck` switch (`node.go:1706`) | `(cd go-mknoon && GOTOOLCHAIN=go1.25.0 go test ./node -run '^TestCallSignalAckContract_' -count=1)` | **NEW synthetic Go path** in `run_host_test_gates.sh` copying `:144-184` pattern (matcher + `print_command_for_path :394` + `run_path :431`); rule-6 doc quartet updated |
| PRESERVE router sentinels | existing dispatch | unit/app | `…incoming_message_router_test.dart::routes unknown/unparseable/chat_message/contact_request …` (4 existing) | n/a (green) | n/a — must stay green | `./scripts/run_test_gates.sh 1to1` | already registered (`:41`) |
| PRESERVE 1:1 send ladder + receipts | untouched siblings | gate | `send_chat_message_use_case_test.dart` + `send_delivery_receipt_use_case_test.dart` suites | n/a (green) | n/a | `./scripts/run_test_gates.sh 1to1` — capture green baseline at execution start | already registered |
| Regression floor | no cross-feature breakage | gate | full suites | n/a | n/a | `./scripts/run_test_gates.sh baseline` · `./scripts/run_host_test_gates.sh feature-host-all` · `core-host-all` · `./scripts/run_test_gates.sh completeness-check` | n/a |

No empty cells.

---

## Blind-Spot Sweep

- **Lifecycle / derived-state durability:** CallSession and the dedup/tombstone tables are deliberately **ephemeral** — a call does not survive process restart, by design (a restarted app has torn down any real media session; VC-05 owns in-call lifecycle). No call data is persisted, so there is no derived-state-vs-row divergence to reconstruct. The restart-equivalent hazard that DOES exist — an offer arriving at a freshly-started listener long after it was sent — is covered by **VC-04-13** (receiver TTL drops stale offers on arrival regardless of listener age). Justified N/A for a reopen-reconstruction row; TTL row stands in.
- **Sibling-surface consistency:** the new capability gate is "fast-path-only + gate-honoring send". The parallel surfaces are the six send primitives themselves — **VC-04-10 is parameterized over all six types** so no primitive silently diverges (e.g. a `call_end` that quietly falls back to the inbox). The chat/receipt/reaction send surfaces are intentionally NOT changed (asymmetry is the point: durable for chat, fast-path for calls) and their sentinels stay green via the `1to1` gate.
- **Destructive-action side-effects:** the destructive transitions are `ended`/glare-abandon cleanup. **VC-04-19** asserts what is removed vs preserved: the ended callId's tombstone is retained (late duplicates never re-ring), the dedup LRU stays bounded, and an unrelated new callId still rings. **VC-04-16** asserts the glare loser's abandoned callId is tombstoned. No disk/DB artifacts exist to clean (nothing persisted).
- **Invariant re-verification under new transitions:** glare auto-convert is the risky new transition — it re-enters the answer path with a foreign callId. **VC-04-16** asserts the FULL post-transition state: session callId swapped, own callId tombstoned, exactly one surviving call, dedup still active for the new callId. Busy auto-reply (**VC-04-18**) re-verifies the active session is untouched (state AND callId asserted, not just "a busy was sent"). Timeout expiry (**VC-04-14**) re-verifies the terminal state rejects later inputs via VC-04-03's terminality lock.

---

## Invariants (locked by tests)

- INV-1 **Fast-path-only (VC-00 rule 5):** no `call_*` envelope is ever durable-inboxed or persisted; the retry machinery can never re-send one → VC-04-10, VC-04-11, VC-04-20 (`storeInInboxCallCount==0` end-to-end).
- INV-2 **Sole gated egress (rule 4):** `sendMessageWithReply` (gate first-line `p2p_service_impl.dart:2409`) is the feature's only network egress → VC-04-12.
- INV-3 **Ack ≠ handled (rule 5):** `acked=true` never advances the session past `ringing`, and `call_*` stays on Go's immediate-ack path → VC-04-15 (Dart), VC-04-G1 (Go pin).
- INV-4 **TTL both sides:** offers older than 45 s never ring; unanswered offers end in ≤ 45 s → VC-04-13, VC-04-14.
- INV-5 **Idempotency:** duplicate `(callId, fromPeerId, seq)` delivery is a no-op; ended callIds never re-ring → VC-04-17, VC-04-19, VC-04-20 (duplicates on).
- INV-6 **Deterministic glare:** simultaneous offers converge, both orders, to one call owned by the lower peerId → VC-04-16.
- INV-7 **Busy:** a second concurrent incoming call is auto-refused without touching the active session → VC-04-18.
- INV-8 **Forward-compat:** unknown call types no-op on old routers (proven on HEAD) and future call types no-op on VC-04 routers → VC-04-08 (evidence), VC-04-09 (permanent).
- INV-9 **Privacy:** call flow events carry truncated ids only, never SDP/peerIds/multiaddrs → VC-04-21.
- INV-10 **Wired in production:** `main.dart` builds the call stack via exactly one `wireCallSignaling(...)` call and the factory subscribes the listener to `router.callSignalStream` → VC-04-23 + Acceptance step-8 call-site grep.
- INV-RED-FIRST and INV-MUTATION-VERIFIED apply to every row above.

---

## Execution Environment  (VC-00 rule 1 — the implementing agent runs this loop itself)

**Rig:** one USB-connected physical Android device + one Android emulator, both adb-addressable. No iOS legs in this story (no iOS boundary touched; the deferred-not-waived pattern is therefore not needed here — it applies to VC-07).

```bash
# 1. Discover serials (USB device e.g. 21071FDF600CSC; emulator e.g. emulator-5554)
adb devices -l

# 2. Host tiers (no device needed)
flutter test test/features/call
flutter test test/core/services/incoming_message_router_test.dart

# 3. Single-leg device runs (debugging a leg in isolation) — per-device via -d <serial>
flutter test integration_test/call_signaling_roundtrip_proof_test.dart \
  -d emulator-5554 --dart-define=VC04_ROLE=callee --dart-define=FDC_FLOW_LOG=1
#   → scrape the printed VC04_PEER_ID=<peerId> marker, then:
flutter test integration_test/call_signaling_roundtrip_proof_test.dart \
  -d 21071FDF600CSC --dart-define=VC04_ROLE=caller \
  --dart-define=VC04_REMOTE_PEER_ID=<calleePeerId> --dart-define=FDC_FLOW_LOG=1

# 4. Two-party orchestrator (the closure command) — -d <serialA>,<serialB>,
#    caller leg FIRST id = USB device, callee leg SECOND id = emulator
#    (convention mirrors integration_test/scripts/run_1to1_device_real.dart -d parsing
#     and the plan-234 automated device+emulator runner)
dart run integration_test/scripts/run_call_device_real.dart \
  --scenario vc04_offer_answer_end -d 21071FDF600CSC,emulator-5554 \
  --artifact-dir /tmp/vc04-artifacts

# 5. Different-network variant (VC-00 rule 1: where the scenario demands):
#    put the USB device on cellular/hotspot (WiFi off), emulator stays on host-WiFi NAT;
#    re-run step 4 — the handshake must traverse the deployed relay circuit.

# Relay: MKNOON_RELAY_ADDRESSES defaults to the deployed pair
#   /dns/mknoun.xyz/tcp/4001/wss/p2p/12D3KooWGMYMmN1RGUYjWaSV6P3XtnBjwnosnJGNMnttfVCRnd6g
#   /dns/mknoun.xyz/udp/4002/quic-v1/p2p/12D3KooWGMYMmN1RGUYjWaSV6P3XtnBjwnosnJGNMnttfVCRnd6g
# (run_test_gates.sh:568 APP_DEFAULT_RELAY_ADDRESSES) — used AS DEPLOYED, no redeploy (rule 2 not triggered).
```

The orchestrator (NEW, modeled on `run_direct_private_media_device_local_journey.dart`): launches the callee leg on the emulator, scrapes the `VC04_PEER_ID=` marker, launches the caller leg on the USB device with the dart-defines, collects `VC04_E2E_ARTIFACT=` JSON from both legs, validates the handshake + writes the latency numbers to the artifact dir, exits non-zero on any leg failure. It supports `--scenario all|vc04_offer_answer_end --list-scenarios` (bare ids, one per line — the `expand_1to1_device_real` discovery contract, `check_reliability_simulation_discovery.sh:828-847`). Cross-plan lock L5: `run_call_device_real.dart` is THE epic-shared call device orchestrator — VC-04 creates it, VC-05…09 append scenarios to it; never fork a per-story runner.

---

## Step-By-Step Implementation Plan

1. **Snapshot:** `git status --short` (preserve the pre-existing dirty tree — do not revert/absorb/reformat it); capture green baselines: `./scripts/run_test_gates.sh 1to1`, `baseline`, `./scripts/run_host_test_gates.sh feature-host-all`, `core-host-all`; `flutter analyze` baseline count.
2. **HEAD evidence (before any edit):** add and run VC-04-08 against the HEAD router; record the GREEN run in Execution Progress (this is the old-client forward-compat proof).
3. **RED (per-slice — each sub-step runs immediately BEFORE its paired GREEN step, so design feedback from slice A reshapes later reds instead of staling a pre-authored batch):**
   - **3A (before Step 4):** author VC-04-01…06 + the Go pin file; `flutter test test/features/call` → compile-RED for the stated reasons. Run `(cd go-mknoon && GOTOOLCHAIN=go1.25.0 go test ./node -run '^TestCallSignalAckContract_' -count=1)` — the Go pin must be GREEN immediately (preservation pin; if it is RED, STOP: the ack contract changed under us → replan).
   - **3B (before Step 5):** author VC-04-07/09; router `--plain-name 'VC-04'` selections → getter-missing RED.
   - **3C (before Step 6):** author VC-04-13/17/19 → compile-RED.
   - **3D (before Step 7):** author VC-04-10/11/12/14/15/16/18/21 → compile-RED.
   - **3E (before Step 8):** author VC-04-20 + VC-04-23 (+ the proof-test/orchestrator skeletons for Step 10) → compile-RED.
   Record one `RED (slice)` row per sub-step in Execution Progress with the failing command.
4. **GREEN step A — domain:** implement `call_signal_envelope.dart` (codec, v1, size guard) and `call_session.dart` (state machine). Seam: pure Dart, zero dependencies. → VC-04-01…06 green.
5. **GREEN step B — router:** add the six cases (after `delivery_receipt` `:259-263`), `_callSignalController`, `callSignalStream` getter, `dispose()` entry (`:297-318`). Rewrite VC-04-08 into VC-04-07 with a `// VC-04:` migration note; VC-04-09 becomes the permanent sentinel. Stop-if: any existing router sentinel breaks → the switch edit leaked into another case → fix, never touch other cases.
6. **GREEN step C — listener:** `call_signal_listener.dart` (parse via codec, offer-only TTL check with injectable clock, dedup LRU + tombstones — `kCallDedupLruCapacity`/`kCallTombstoneRetention` declared here, typed streams, RECV/EXPIRED_DROP/DUP_DROP flow events). → VC-04-13/17/19 green.
7. **GREEN step D — service:** `call_signaling_service.dart` (six send primitives over `sendMessageWithReply` only; seq stamping; sender expiry timer; glare policy `localPeerId.compareTo(remotePeerId) < 0` wins, same-dialed-peer only; busy auto-reply; SEND/SEND_FAILED/GLARE/BUSY/SESSION_STATE flow events). → VC-04-10/11/12/14/15/16/18/21 green. Stop-if: any need arises to persist a row or call another P2P method → replan, that violates INV-1/INV-2, do not hack around it.
8. **GREEN step E — integration + DI:** `wireCallSignaling(...)` factory in `call_wiring.dart`; `call_signaling_roundtrip_test.dart` green over `FakeP2PNetwork` (duplicates on); wire listener/service in `main.dart` via exactly one `wireCallSignaling(...)` call next to `:2597`. → VC-04-20/23 green.
9. **Registration (rule 6):** (a) append `test/features/call/integration/call_signaling_roundtrip_test.dart` to `ONE_TO_ONE_TESTS` (`run_test_gates.sh:21` array; cross-plan lock L5: no new call family array this epic — nightly-heavy e2e would go to `NIGHTLY_ONLY_TESTS` `:556`); (b) add the synthetic Go path for `call_signal_ack_contract_test.go` to `run_host_test_gates.sh` (copy `:144-184`: `readonly GO_CALL_SIGNAL_ACK_TEST=… GO_CALL_SIGNAL_ACK_RUN='^TestCallSignalAckContract_'`, matcher, `print_command_for_path :394`, `run_path :431`, `GOTOOLCHAIN=go1.25.0`); (c) add `classify_path` cases in `check_reliability_simulation_discovery.sh` for the proof test (`record "1to1" … "test"`) and the orchestrator `run_call_device_real.dart` (`record "1to1" … "runner"` + dispatch branch to `expand_1to1_device_real`); (d) update the gate-doc quartet together: `test-gate-definitions.md`, `test-gates-reference.md`, `_current-test-map.md` (+ the two scripts), AND record in Execution Progress the exact added-test list per gate (router VC-04-07/09 additions + roundtrip array entry + Go path) so the step-5 baseline+delta comparison is a mechanical diff, not a rough count. Verify: `./scripts/run_test_gates.sh completeness-check` green; `./scripts/check_reliability_simulation_discovery.sh` lists both new entries with a `/sims 1to1 --only N` slot; `./scripts/run_host_test_gates.sh host-all --list` shows the Go path. (This step may be swapped after Step 10 — the device e2e does not depend on registration, and running the wire leg first surfaces relay/NAT reality before registration churn.)
10. **Device e2e (rule 1):** implement the proof test + orchestrator (`run_call_device_real.dart`); run the Execution Environment step-4 command on the real rig ≥ 5 times same-network (median of `offerSendToAnswerRecvMs`, never mean; record-and-flag if median > 10 s); capture the latency artifacts; run the dead-peer negative (must fail) once to prove non-vacuity; run the different-network variant. May run immediately after Step 8 (before Step 9) — feasibility before plumbing.
11. **Full gates + hygiene + mutations:** re-run every Acceptance Gate; re-run each named mutation to confirm re-RED; `flutter analyze` (0 new vs step-1 baseline); `git diff --check`.

---

## Risks And Edge Cases

| Risk / edge | Pinned by |
|---|---|
| **TTL value wrong.** 45 s chosen: ≥ 30 s so a full fast-path send cycle (6 s direct aggregate budget, `send_chat_message_use_case.dart:36`) plus relay traversal plus human-scale ring never false-expires; ≤ 60 s so a dead-listener callee (old client whose node acked — VC-04-08 note) leaves the caller stuck at most 45 s. The 30-60 s band is a design choice (Signal/Matrix ring-timeout precedent), NOT a repo-derived constraint — VC-00 rule 5 says only "short TTL"; the derivation above carries the choice. Cross-plan lock L1: `kCallOfferTtl = 45000` ms is owned by VC-04; VC-06's ring timeout = min(45 s, TTL remaining from `sentAtMs`). | VC-04-13/14 (constant `kCallOfferTtl`; changing it re-runs both) |
| **Clock skew between peers** — receiver TTL uses sender's `sentAtMs` vs receiver clock; > 45 s skew degrades to dropped offers. | Observable via `CALL_SIGNAL_EXPIRED_DROP{ageMs}` (VC-04-13); accepted — NTP-level skew ≪ 45 s; documented, VC-09 can add skew telemetry |
| **Both-glare-and-busy** — glare offer arrives while ALSO active with a third peer: busy check runs first (non-idle + different callId → busy), glare only applies when `dialing` to the SAME peer. Ordering locked. | VC-04-16 (dialing) vs VC-04-18 (active) disjoint state setups |
| **Ack read failure** (`sent:true, acked:false`, `node.go:1607-1610`) leaves caller in `dialing` → expiry, no retry storm. | VC-04-15 + VC-04-14 |
| **Duplicate frames from network layer** (relay redelivery, FakeP2PNetwork `duplicateOnDeliver`). | VC-04-17/19/20 |
| **Unbounded dedup memory** on long sessions. | VC-04-19 (LRU bound asserted) |
| **A future story adds `call_ringing` etc.** — old VC-04 clients must no-op. | VC-04-09 |
| **Someone "fixes" ack semantics by deferring call acks in Go** — breaks latency + requires confirm wiring. | VC-04-G1 mutation (`node.go:1706`) |
| **Envelope > frame cap** (VC-05's real SDP + candidate batches). | VC-04-06 (96 KiB guard; hard cap 128 KiB `config.go:77`) |
| **Emulator↔device NAT asymmetry** — handshake must work relay-circuit-only (pre-VC-01 world: no held circuits; dial happens per send via `openChatStreamForSend` `node.go:1507-1538`). Latency will improve when VC-01 lands (roadmap: "VC-01 improves latency"). | VC-04-22 different-network variant; latency artifact is the baseline |

---

## Device/Relay Proof Profile

**Requires device for closure:** VC-04-22 is the PROD-CRITICAL wire leg — host tiers cannot prove the real bridge/relay/device path (a host fake passes even if the wire leg is broken). Closure = orchestrator run green on the rule-1 rig (USB Android + emulator), same-network AND different-network variants, latency artifact saved.

Discovery + slot: `./scripts/check_reliability_simulation_discovery.sh` must list the proof test and orchestrator; `/sims 1to1 --list` (dry-run, no devices needed) must show the `vc04_offer_answer_end` slot (`--only N`). `/sims` is a runner, never a registrar — if the slot is missing, the bug is the `classify_path`/dispatch wiring from Step 9.

Relay defaults: `/dns/mknoun.xyz/tcp/4001/wss/p2p/12D3KooWGMYMmN1RGUYjWaSV6P3XtnBjwnosnJGNMnttfVCRnd6g` (+ quic-v1 :4002 twin). **No EC2 redeploy** — VC-04 touches zero `go-relay-server/` code, so VC-00 rule 2 is not triggered; the e2e runs against the relay as already deployed. (Stories that DO redeploy: VC-01/VC-03/VC-06/VC-07.)

No iOS legs (rule 1 rig is Android-only; nothing here is iOS-boundary). iOS wire-leg proof is inherited from existing 1:1 chat coverage (same bridge/protocol, no new platform channel); any iOS-specific call behavior enters VC-07's deferred-not-waived ledger — deferred with a named owner, not waived.

---

## Metrics Ownership  (VC-00 metrics table — VC-04's share)

VC-04 has no dedicated row in VC-00's metrics table; it owns the **signaling slice** of the "Call setup time (invite→connected)" row (headline owner VC-05/VC-09) plus its own observability:

| Metric | Vehicle | Named test / runsheet step |
|---|---|---|
| Signaling handshake latency: `offerSendToAnswerRecvMs`, `offerAckWaitMs`, `endRoundMs` | `VC04_E2E_ARTIFACT` JSON printed by the device e2e (device profile builds use `--dart-define=FDC_FLOW_LOG=1` — `flowEventLoggingEnabled` defaults to `kDebugMode` but is force-enabled in profile via `lib/main.dart:320-332`, per digest correction: never "debug-only") | VC-04-22 GREEN assertion + orchestrator artifact validation (Execution Environment step 4); recorded in this dir alongside the run per FDC-S0 RESULTS conventions (median of ≥ 5 runs, never mean) |
| Signaling send/recv/expiry/dup counts | Flow events `CALL_SIGNAL_SEND / CALL_SIGNAL_RECV / CALL_SIGNAL_SEND_FAILED / CALL_SIGNAL_EXPIRED_DROP / CALL_SIGNAL_DUP_DROP / CALL_GLARE_RESOLVED / CALL_BUSY_AUTO / CALL_SESSION_STATE` via `emitFlowEvent` (`flow_event_emitter.dart:202`), layer `CALL`, unconditional sanitization | VC-04-21 locks emission + privacy; VC-04-13/17 lock EXPIRED_DROP/DUP_DROP specifically |
| Per-send step timings (`streamOpenMs/writeMs/ackWaitMs`) | Already returned by `sendMessageWithReply` → `SendMessageResult` (`node.go:1583-1620`, `send_message_result.dart:7-9`); the service copies `ackWaitMs` into `CALL_SIGNAL_SEND` details | VC-04-10 asserts the detail key present |

Deferred to VC-09 (accepted): TransportMetrics aggregate counters for calls, relay Prometheus `relay_call_*` metrics, drop-cause taxonomy.

---

## Acceptance Gates  (LITERAL — copy/paste; capture green baselines at execution start, never hardcode counts — VC-00 rule 6)

```bash
# 0. Snapshot (before anything)
git status --short                      # record; preserve pre-existing dirty tree
./scripts/run_test_gates.sh 1to1        # capture green baseline count
./scripts/run_test_gates.sh baseline    # capture green baseline count
flutter analyze                         # record baseline issue count (dirty tree)

# 1. HEAD forward-compat proof (BEFORE any router edit) — must PASS on HEAD
flutter test test/core/services/incoming_message_router_test.dart --plain-name 'VC-04-08'

# 2. RED (per slice 3A-3E, each run immediately before its GREEN step) — must FAIL for the documented reasons
flutter test test/features/call                                          # compile-RED
flutter test test/core/services/incoming_message_router_test.dart --plain-name 'VC-04-07'

# 3. Go preservation pin — GREEN on HEAD (STOP if RED)
(cd go-mknoon && GOTOOLCHAIN=go1.25.0 go test ./node -run '^TestCallSignalAckContract_' -count=1)

# 4. Direct GREEN (after implementation)
flutter test test/features/call
flutter test test/core/services/incoming_message_router_test.dart
flutter test test/features/call/integration/call_signaling_roundtrip_test.dart

# 5. Preservation sentinels + named gates (expect: match step-0 baselines + new-test delta; 0 fail)
./scripts/run_test_gates.sh 1to1
./scripts/run_test_gates.sh baseline
./scripts/run_host_test_gates.sh feature-host-all
./scripts/run_host_test_gates.sh core-host-all

# 6. Registration verification (rule 6)
./scripts/run_test_gates.sh completeness-check          # every new *_test.dart classifies
./scripts/check_reliability_simulation_discovery.sh     # proof test + orchestrator listed, ≥1 scenario expanded
./scripts/run_host_test_gates.sh host-all --list | grep call_signal_ack   # synthetic Go path present
dart run integration_test/scripts/run_call_device_real.dart --scenario all --list-scenarios
# → prints: vc04_offer_answer_end

# 7. Device e2e (rule 1 rig; PROD-CRITICAL closure) — ≥5 same-network runs, median never mean
adb devices -l
for i in 1 2 3 4 5; do
  dart run integration_test/scripts/run_call_device_real.dart \
    --scenario vc04_offer_answer_end -d <usbSerial>,<emulatorSerial> \
    --artifact-dir /tmp/vc04-artifacts/run-$i
done
# expect: exit 0 each run; VC04_E2E_ARTIFACT with offerSendToAnswerRecvMs recorded from both legs;
#   the MEDIAN of the 5 offerSendToAnswerRecvMs values recorded in RESULTS (median, never mean)
# record-and-flag: same-network median > 10000 ms requires an explicit Execution Progress note
#   explaining why (relay path, emulator NAT) — a flag, not a FAIL (artifact stays the VC-01 baseline)
# then the different-network variant (device on cellular/hotspot) — same command, must stay green
# then the non-vacuity negative: --dart-define VC04_REMOTE_PEER_ID=<dead peerId> leg must FAIL

# 8. Hygiene + wiring call-site closure (INV-10)
grep -c "wireCallSignaling(" lib/main.dart   # expect: 1 (exactly one production call-site — VC-04-23)
flutter analyze            # 0 new vs step-0 baseline
git diff --check
```

No migration gate: no schema change (nothing persisted — verified scope).

---

## Known-Failure Interpretation

- **Expected RED (pre-implementation):** everything under `test/features/call/` (compile — feature dir absent) and the `VC-04-07`/`VC-04-09` router selections (missing getter).
- **Expected GREEN-on-HEAD:** VC-04-08 (that's the point) and VC-04-G1 (preservation pin). If VC-04-G1 is RED on HEAD, the Go ack contract drifted → BLOCKING, replan.
- **Expected inversion:** VC-04-08 flips after Step B by design — it is rewritten into VC-04-07 with a `// VC-04:` note, never silently deleted.
- **Pre-existing dirty tree:** large unrelated modified set exists on `new-orbit` (see step-0 snapshot) — do not revert, absorb, or reformat it; analyzer baseline drift not caused by this plan is recorded, not "fixed".
- **Environment blockers (NOT product):** no USB device / emulator attached (`adb devices` empty) blocks step 7 only — host tiers still gate; missing relay reachability (mknoun.xyz down) fails step 7 with dial errors — verify with a plain `ping`/existing `/sims 1to1 --list` before blaming the feature.
- **`1to1` gate count differs from baseline** by exactly the added-tests delta (router additions + roundtrip array entry) → expected; diff the named tests, not the raw count.
- **Scope drift (BLOCKING):** any failure in `send_chat_message_use_case_test.dart`, group/feed/posts suites, or Go suites other than the new pin — VC-04 must not touch those paths.

---

## Working Piece On Close

A `CallSignalingService` + `CallSignalListener` pair that **round-trips a full offer→answer→end handshake between a real USB Android device and an emulator over the deployed relay**, with measured signaling latency, and with TTL (both sides), glare (both orders), busy auto-reply, `(callId, seq)` dedup, ended-call tombstones, and forward-compat all test-locked across unit, integration, and device tiers. The payloads are opaque strings with the exact fields WebRTC needs (`sdp`, `candidates`), the session machine exposes `markActive()`, and delivery semantics are final — **VC-05 plugs `RTCPeerConnection` straight into the typed streams without touching the signaling layer.** Self-contained: nothing in the app changes behavior for users who never receive a call envelope, and old clients provably no-op.

---

## Done Criteria

- [ ] `git status --short` snapshot recorded; green baselines (1to1, baseline, feature/core-host-all, analyze) captured at execution start.
- [ ] VC-04-08 executed GREEN **on HEAD** and recorded (old-client forward-compat proof) before any router edit; migrated into VC-04-07 with rationale note.
- [ ] VC-04-01…21 + VC-04-23 authored RED-first per slice (3A–3E, each slice's RED recorded before its GREEN step), each RED for the stated reason, then GREEN; VC-04-G1 GREEN on HEAD and wired into its new pinned gate.
- [ ] Every mutation in the matrix re-run and confirmed to re-RED its test.
- [ ] Preservation sentinels green: 4 router sentinels, `1to1`/`baseline` gates at baseline+delta, feature/core-host-all 0 fail.
- [ ] Harness registration done AND verified in gate runs: `ONE_TO_ONE_TESTS` array entry (L5: no new family array); discovery `classify_path` cases (test + runner `run_call_device_real.dart`) with `/sims 1to1 --list` slot visible; synthetic Go path in `run_host_test_gates.sh`; `completeness-check` green; gate-doc quartet (`test-gate-definitions.md`, `test-gates-reference.md`, `_current-test-map.md`, scripts) updated together (rule 6); exact added-test list per gate recorded in Execution Progress (mechanical baseline+delta diff).
- [ ] VC-04-22 device e2e green on the rule-1 rig: ≥ 5 same-network runs with the MEDIAN `offerSendToAnswerRecvMs` recorded (median, never mean; if median > 10 s, explicit record-and-flag note in Execution Progress) AND the different-network (device on cellular/hotspot) run green, latency artifacts saved to this dir per FDC-S0 RESULTS conventions, dead-peer negative run failed as required (non-vacuity).
- [ ] VC-04-23 green and Acceptance step-8 call-site grep = exactly one `wireCallSignaling(` in `lib/main.dart` (INV-10).
- [ ] No schema change confirmed (no migration test needed); nothing call-related persisted.
- [ ] `flutter analyze` 0 new vs baseline; `git diff --check` clean; no Scope Guard violations.

---

## Scope Guard (hard "Do not")

- Do NOT add `flutter_webrtc` or any WebRTC/SDP-generating code — **VC-05** owns it (here `sdp`/`candidates` are opaque strings).
- Do NOT add any UI (screens, ring surfaces, notifications) — **VC-05/VC-06** own them.
- Do NOT touch push/FCM/APNs/CallKit or relay push seams — **VC-06/VC-07** own them.
- Do NOT edit `go-relay-server/` (VC-03 owns TURN; rule 2 stays untriggered) or any **production** Go file in `go-mknoon/` — the only Go change is the new test file `call_signal_ack_contract_test.go`. In particular do NOT add `call_*` to `shouldDeferDirectAck` (`node.go:1705-1709`).
- Do NOT edit `send_chat_message_use_case.dart`, `pending_message_retrier.dart`, or the retry use cases — the opt-out is structural (no dependency), not an edit to them.
- Do NOT persist any call row, ever (no messageRepo dependency in `lib/features/call/`), and do NOT call `storeInInbox` for any `call_*` envelope.
- Do NOT extend `parseEncryptedEnvelope`/the ML-KEM chat encryption seam — payload encryption is a recorded deferral (Accepted Differences), not a sneak-in.
- Do NOT touch `p2p_bridge_client.dart` flag maps or `feature_flags.go` — VC-04 adds no feature flag (collision file per VC-00; VC-01/02 own it).
- Do NOT run concurrently with VC-05 — collision on `lib/features/call/` + conversation routing (VC-00 collision map: VC-04 → VC-05 sequential).
- Do NOT index this plan in `Test-Flight-Improv/00-INDEX.md` (VC-00 rule 7).

---

## Accepted Differences / Intentionally Out Of Scope

- **Plaintext v1 envelope (no application-layer ML-KEM encryption of call payloads).** The `delivery_receipt` precedent (deliberately plaintext v1, `send_delivery_receipt_use_case.dart:95-102`, D-4 rationale) is copied because: (a) `type` must be cleartext for router dispatch anyway (even v2 chat keeps it cleartext, `message_payload.dart:143-159`); (b) the v2 encrypted envelope is chat_message-specific (`parseEncryptedEnvelope` rejects other types, `:165-181`) and extending that seam is real crypto work; (c) **fast-path-only means the relay never stores call payloads** — content rides libp2p's peer-to-peer security handshake (noise) end-to-end even through a circuit, unlike inboxed messages which the relay holds. Residual exposure: SDP/candidate strings visible to the two endpoints' transport layer only. Revisit when VC-05 introduces real SDP; owner: VC-05 (decides) / VC-09 (privacy toggle).
- **No kill-switch feature flag (rule 3 not triggered).** VC-04 changes no default network behavior: no code path sends a `call_*` envelope without an explicit API call, and no UI exists to trigger one. The only autonomous behaviors (busy auto-reply, glare auto-answer) run solely in response to an incoming `call_offer`, which no shipped build can send. The revert path is "nothing calls the API" — already true. VC-05, which makes calls user-reachable, owns the user-facing flag decision.
- **Caller `ringing` on acked offer is "delivered-to-node", not "callee ringing"** — documented UX approximation, bounded by the 45 s expiry; VC-06/07's push + (optionally) a future `call_ringing` signal tighten it. Locked as-is by VC-04-01/15.
- **Old callee never rings** (unknown type no-ops, proven by VC-04-08): the product-level fix is VC-06/VC-07's ring push — ONE mechanism, cross-plan lock L2: caller-side relay action `call_push_request` (rate-limited per peer), relay-dispatched by the callee's registered token type (FCM high-priority DATA push on Android; APNs VoIP push via PushKit token, VC-07 on iOS). A "TTL-d wake deposit via inbox" alternative is REJECTED epic-wide: `call_*` is never durable-inboxed (VC-00 rule 5 / INV-1), so no inbox-based ring path exists or may be added. Not VC-04's scope either way.
- **No TransportMetrics/Prometheus call counters** — VC-09 owns the metrics loop closure; VC-04 ships flow events + the e2e latency artifact only.
- **ICE candidate `seq` ordering is dedup-only** (no reorder buffer): WebRTC tolerates out-of-order candidate arrival; VC-05 consumes them as they come.

---

## Dependency Impact

- **VC-05 (flutter_webrtc audio call)** depends on this because: it consumes `CallSignalingService`'s send primitives + `CallSignalListener`'s typed streams for offer/answer/ICE, plugs real SDP into the opaque payload fields, and calls `CallSession.markActive()` on RTC connection. The envelope field contract (`callId/seq/sentAtMs/sdp/candidates`) is frozen by VC-04-04.
- **VC-06/VC-07 (ring planes)** depend on the `call_offer` TTL semantics — `kCallOfferTtl = 45000` ms is owned here (L1); VC-06's ring timeout = min(45 s, TTL remaining from `sentAtMs`), so the push (caller-side relay action `call_push_request`, L2) must beat the expiry — and on the documented old-callee-never-rings gap they exist to close.
- **VC-08 (video)** and **VC-09 (reliability/metrics)** build on the same signaling layer; VC-09 extends the flow events into aggregate/relay metrics.
- **VC-01 (circuit holding)** improves signaling latency (roadmap note) but is NOT a dependency — VC-04-22 must pass in the pre-VC-01 dial-per-send world (that run IS the baseline VC-01 improves).
- **Collision map (VC-00):** VC-04 and VC-05 collide on `lib/features/call/` and conversation routing — strictly sequential; VC-04 commits and re-greens `1to1` before VC-05 starts.
- No migration, no schema change, no relay deploy, no feature-flag files touched.

---

## Reviewer Findings

**/tdd-review verdict (2026-07-13, adversarial audit + source-verified fact check):**
- Dimension scores: goal-clarity 85 (strong) · compartmentalization 76 (strong) · anti-drift 86 (strong) · define-good 79 (strong) · goal-verification 78 (strong).
- Findings: 0 material structural, 5 moderate, 5 nits from the assessment; 4 source-verified factual corrections from the verifier. **All applied:**
  - Factual (verifier): `duplicateDelivery` → `duplicateOnDeliver` (`fake_p2p_network.dart:32`, doc `:31`); `APP_DEFAULT_RELAY_ADDRESSES` cite `:567` → `:568`; TestUser harness description corrected (router is an OPTIONAL field `:46`, built only with `withReactions`-style opts `:109-112`); the "brief's 30-60 s band" TTL attribution replaced with the honest framing (design choice per Signal/Matrix precedent, NOT repo-derived — cross-plan lock L1).
  - Moderate: (1) receiver-side TTL pinned to `call_offer` ONLY with a stale-`call_end` sub-case + all-types mutation (VC-04-13); (2) main.dart DI wiring now test-locked via `wireCallSignaling` factory + VC-04-23 + step-8 call-site grep (INV-10, new matrix row); (3) latency baseline hardened: ≥ 5 same-network runs, median-never-mean in the LITERAL gates + record-and-flag at median > 10 s; (4) RED authoring de-waterfalled into per-slice sub-steps 3A–3E paired with GREEN steps A–E, per-slice Execution Progress rows; (5) VC-04-22's 44-second-pass hole closed by the same record-and-flag branch.
  - Nits: glare-vs-busy disambiguation moved into VC-04-16's test spec (same-dialed-peer condition + sub-case c); LRU/tombstone constants named (`kCallDedupLruCapacity`/`kCallTombstoneRetention`); Steps 9/10 reorder note (feasibility before plumbing); added-test-delta list recorded per gate; iOS N/A reworded to deferred-not-waived via VC-07's ledger.
  - Cross-plan contract locks applied: L1 (TTL 45000 ms owned here; VC-06 consumes min(45 s, remaining)); L2 (ring push = caller-side relay action `call_push_request`; inbox wake deposit REJECTED — recorded in Accepted Differences); L5 (no new family array; headline → `ONE_TO_ONE_TESTS`, nightly-heavy → `NIGHTLY_ONLY_TESTS :556`; orchestrator renamed to the epic-shared `integration_test/scripts/run_call_device_real.dart`).

Sufficiency checklist run against this draft (2026-07-13):
- Spec-case totality: 24 spec cases (VC-04-01…23 + G1), every one has ≥1 named test row at a stated tier — PASS.
- Every INV has a test (INV-1…10 mapped) — PASS.
- Mutation-verified: every behavior edit names test + exact revert — PASS.
- No vacuous coverage: compile-RED is documented per new-file test; behavior discriminators asserted where results coincide (callSignal vs unknown stream; SEND vs CONCURRENT_INBOX_BEGIN; RECV vs EXPIRED_DROP/DUP_DROP); device e2e has a mandatory dead-peer negative — PASS.
- Migration gate: N/A, no schema change (explicitly recorded) — PASS.
- Boundaries proven real: VC-04-22 device-proof with real bridge/relay/devices, marked PROD-CRITICAL — PASS.
- Preservation sentinels named with gate commands (counts = capture-at-start per rule 6) — PASS.
- Literal gates incl. `flutter analyze` + `git diff --check` — PASS.
- Registration named per test (AUTO / array / classify_path ×2 / synthetic Go path), verification commands listed — PASS.
- Known-failure interpretation + dirty-tree snapshot planned — PASS.
- Refuted findings recorded (ack ordering; retryUnacked cite; deferred-ack temptation) — PASS.
- Blind-spot sweep: 4/4 classes have rows or justified N/A — PASS.
- Matrix gate: zero empty cells in tier/mutation/gate/registration — PASS.
Two fixes applied during review: (1) VC-04-08's inversion-by-design was moved out of the RED set and given an explicit migration path + permanent sentinel (VC-04-09) so no test is silently deleted; (2) the Go pin's gate registration was upgraded from "manual go test" to a pinned synthetic path with the rule-6 doc-quartet ceremony (a Go test that runs in no gate is invisible coverage).

## Arbiter Decision

Structural blockers: none. | Deferred details: exact values of `kCallDedupLruCapacity`/`kCallTombstoneRetention` (named, homed in `call_signal_listener.dart`, bounded + ≥ 2×TTL retention test-asserted — implementer picks values and records them in Execution Progress); orchestrator artifact-dir layout (follows plan-234). | Accepted differences: as listed (plaintext v1; no kill-switch — rule 3 untriggered, no default-on network behavior; ringing-on-ack = delivered-to-node semantics bounded by 45 s expiry; metrics deferral to VC-09; ring push is VC-06/07-owned via relay action `call_push_request` per lock L2, inbox wake deposit rejected epic-wide; 30-60 s TTL band recorded as a design choice, not repo-derived, per lock L1).

## Final Execution Verdict

Verdict: (pending execution) | Files changed: — | Tests run (+counts): — | Blocking: — | QA verdict: — | Non-blocking follow-ups (owner): —
