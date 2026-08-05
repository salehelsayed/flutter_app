# Critical review of the go-libp2p transport assessment

**Review basis:** current Dart, Go, bridge, persistence, relay-inbox, and focused test code in this repository. The Go client pins `go-libp2p v0.39.1`. This review therefore replaces several assumptions in the supplied assessment with implementation evidence.

## Executive conclusion

The assessment's central idea is correct:

> Route learning should optimize the next send; it must not delay or weaken proof of delivery for the current send.

The current implementation does mix route preference, delivery proof, and durability. The most important confirmed problems are:

1. The live-race selector ranks a successful transport write without first requiring a committed ACK. A higher-ranked but uncommitted LAN result can replace a committed direct result.
2. The local WebSocket can mint a final delivery ACK without cryptographically authenticating the remote peer. This is a delivery-integrity issue, even though the envelope itself remains application-encrypted.
3. Dart allows 1.5-2 seconds for sends whose receiver may itself spend 2 seconds waiting for durable Flutter commitment.
4. Connected and LAN-visible peers receive no concurrent inbox hedge, so stale connectivity can postpone durable custody for several seconds.
5. Proof-protecting transition rules are not enforced by one persistence-layer invariant; some competing callbacks still use unconditional status updates.

Several proposed remedies should not be adopted now. A native durable spool, two ACK protocols, delayed-activation inbox protocol, new delivery coordinator, message reorder protocol, streaming DHT discovery, and cross-FFI attempt cancellation would add substantial machinery before simpler fixes have been tried.

## What meaningfully adds value

The assessment is strongest as a set of invariants:

- Presence and connection observations are hints, not delivery proof.
- Recipient commitment and relay-inbox custody are different milestones.
- Live attempts may overlap, but proof strength must outrank transport preference.
- Direct-route learning is useful for later sends and should not withhold current-message safety.
- Attachment metadata and media bytes are separate transport objects.
- Timeout contracts and status transitions must remain coherent across Dart, the bridge, Go, and persistence.

Message-ID duplicate handling, repeat receipts, inbox idempotency, and a peer transport coordinator already exist. They should be preserved and tightened where noted below, not rebuilt.

## Recommended priorities

| Priority | Change | Why |
| --- | --- | --- |
| High | Add one atomic outgoing transport-settlement operation in persistence | Makes `delivered` immune to late `inboxed`, `sent`, or `failed` writes and protects the later concurrency changes |
| High | Make settlement proof-aware: only an **authenticated committed ACK** can produce `delivered`, and the first such ACK settles immediately | Fixes a confirmed incorrect-winner case and removes route rank from delivery semantics |
| High | Remove final-delivery authority from unauthenticated local WebSocket chat; use mDNS to feed authenticated libp2p LAN connections | Prevents a LAN endpoint from forging a committed-delivery ACK and causing a false `delivered` status |
| High | Align all live-send ACK budgets with the receiver; enforce one Dart direct-leg deadline and one absolute bound per native command | Prevents valid receiver commits from being classified as late and bounds native work without requiring a new combined API |
| High | Start live work without awaiting presence and add a custody hedge for connected/LAN-visible peers | Removes a real durability gap caused by stale connectivity observations |
| Medium | Permit attachment envelopes over live relay when the encoded envelope fits the cap | Removes an unnecessary latency penalty; media is already uploaded in the normal send flow |
| Medium/low, telemetry-gated | Extend the existing peer coordinator to single-flight foreground discovery/connection establishment | Can avoid repeated rendezvous work during burst sends without serializing messages |
| Low | Classify relay connections primarily with `Conn.Stat().Limited` | Small robustness cleanup; not a central architecture change |

The priority table answers **what matters most**. The rollout roadmap below answers **what to plan and execute next**. When the two appear to differ, dependency order wins.

Discovery restructuring, including foreground single-flight, and exact timing optimization should follow telemetry from the correctness changes, not precede them.

## Adopted implementation invariants

1. Only an authenticated committed ACK proves recipient-device delivery.
2. The first authenticated committed ACK settles immediately. Transport preference affects attempt scheduling and future route learning; it never delays or replaces that ACK.
3. Competing send callbacks may not overwrite stronger proof. They settle through one atomic persistence operation with explicit allowed predecessor states.
4. Live work, presence, and inbox custody may overlap, but the send clock and every native command have one coherent deadline contract.

Verified custody loss is a separate authoritative transition, not an ordinary competing send callback.

## Finding-by-finding verdict

### 1. Static transport ranking delays an already successful delivery

**Verdict: keep the principle, but rewrite the defect. Priority: High.**

The static order and 150 ms preference grace exist in `lib/features/conversation/application/send_chat_message_use_case.dart:61-75,131-143,1046-1188`.

The more serious issue is that the selector ranks any successful write, not only a committed delivery:

- A legacy LAN ACK becomes `success=true, acknowledged=false` at `send_chat_message_use_case.dart:1771-1811`.
- Direct send likewise records success from `sent`, separately from `acknowledged`, at `:2043-2050`.
- `offerSuccess` compares transport rank without comparing ACK strength at `:1164-1188`.
- The chosen result's ACK flag later determines `delivered` versus inbox fallback at `:1258-1287,2364-2400`.

This permits the following incorrect result:

```text
direct returns a committed ACK
    -> delayed higher-ranked LAN leg returns only a legacy/uncommitted ACK
    -> LAN replaces direct as the selected result
    -> sender falls back to inbox despite already proving delivery
```

The existing grace tests cover committed legs but not this crossover case.

The same proof-blind rule also appears outside the ranked race: connection reuse and learned/sticky short-circuits return on `sent` even when `acknowledged` is false at `:701-731,786-817,1856-1888`. The correction must therefore be shared settlement logic, not only a race comparator.

The assessment also overstates the absence of warm-route preference. Existing non-relay connections already short-circuit for non-LAN peers at `:662-731`. The problematic exception is deliberate: reuse is suppressed when `isLocalPeer` is true at `:653-678`, allowing a cold or unauthenticated LAN route to outrank the existing connection.

**Keep:**

- First authenticated committed ACK settles `delivered` immediately.
- Route learning may continue for later sends.
- Transport preference affects attempt scheduling, relay staggering, and future route learning only. It never waits for, replaces, or reclassifies the first authenticated committed ACK.
- Uncommitted results remain diagnostic/fallback evidence; they do not settle the live race while an authenticated live leg or inbox custody path remains viable.
- Add a regression test combining a committed direct ACK with a delayed legacy LAN ACK, plus unacknowledged reuse/sticky fallback tests.

**Discard or defer:**

- Treating the 150 ms UI delay as the main defect.
- A large new connection-ranking framework. One shared proof-aware settlement helper across reuse, sticky, and race paths is sufficient.
- `WithNoDial` everywhere. A distinct existing-connection operation can use it later if current `NewStream` behavior causes unwanted dialing, but it is not required to fix settlement.
- New network-generation or route-score state unless telemetry shows the existing TTL and invalidation logic selecting stale routes.

### 2. Inbox custody may be postponed for connected peers

**Verdict: keep, but correct the scope and timing. Priority: High.**

The assessment's universal nine-second description is stale. Peers that are structurally `unknownPresence` already receive an inbox operation at `send_chat_message_use_case.dart:830-938`. This group is defined before presence resolves and can include a peer later reported as reachable. However, connection reuse and sticky-route attempts run first at `:662-828`, so this custody operation is not yet scheduled before every early live path.

The confirmed gap is narrower:

- `unknownPresence` excludes connected and LAN-visible peers at `:844-847`.
- Those peers have no concurrent custody hedge.
- Inbox storage begins only after their live attempts fail at `:1402-1460`.
- The cold direct phases are serial and total about five seconds under a six-second outer guard; inbox adds up to three seconds. A failed reuse attempt can add more time before the live race.
- Presence refresh is awaited for up to 400 ms before live futures are constructed at `:939-955`.
- An `unreachable` result explicitly waits for inbox completion before live routes begin at `:966-980`.

Presence is therefore on the critical path despite comments suggesting otherwise.

**Keep:**

- Move the structurally-unknown-peer inbox scheduling ahead of reuse and sticky early returns, while starting the deposit only once the encrypted envelope is available.
- Start live connection/send work concurrently; presence must not delay it.
- Add a delayed inbox hedge only for connected/LAN-visible paths that currently lack one.
- Tune the hedge using production percentiles.

Define `T0` as entry to `sendChatMessage`, using the existing monotonic `sendStopwatch` at `send_chat_message_use_case.dart:319`. This is the send-use-case boundary after any prerequisite media upload, not the original UI tap. Presence lookup, reuse failure, discovery, and dialing must not restart this clock.

For connected/LAN-visible peers, schedule one initial libp2p hedge from `T0`, using the remaining portion of the hedge when the envelope becomes available. Approximately 2.5-3 seconds is an internally consistent starting experiment because the libp2p receiver may spend two seconds committing. If envelope preparation has already consumed the hedge, start inbox storage immediately. Only an authenticated committed ACK may cancel a scheduled-but-not-started hedge; a WebSocket result may not. Once inbox storage has started, let the idempotent operation complete and rely on atomic settlement—do not add an inbox cancellation protocol. Tune this single value from committed-ACK latency and duplicate-inbox/push telemetry before adding route-specific policy.

**Discard:** the pending-upload/activate/tombstone inbox protocol. It creates new relay state and privacy behavior to solve a problem that a normal hedge can solve.

### 3. Sender timeout is shorter than receiver processing allowance

**Verdict: keep the defect; use the narrow fix. Priority: High.**

The mismatch is confirmed:

- Receiver commitment may take two seconds: `go-mknoon/node/config.go:90-95` and `go-mknoon/node/node.go:1833-1857`.
- Cold direct and live relay are cut off after 1.5 seconds in Dart: `send_chat_message_use_case.dart:113-115,1696-1702,2015-2023`.
- Sticky sends have an exact two-second Dart wrapper at `:1856-1868`. Reuse requests a two-second native timeout at `:688-692`, while its bridge watchdog is 500 ms looser; neither contract reserves adequate receiver margin.
- Go already defines a three-second interactive send allowance at `go-mknoon/node/config.go:79-84`.

**Keep:**

- Use at least a three-second committed-ACK allowance for all libp2p live-send variants whose ACK depends on Flutter commitment.
- Add a cross-layer contract test so the Dart budget cannot be shorter than the receiver commitment budget plus margin.
- Separate the ACK allowance from the overloaded direct-attempt constants. Raising the 1.5-second send phase to three seconds makes the current `2s discover + 1.5s dial + 3s send` total exceed the six-second aggregate guard, so that guard must be raised or refactored at the same time.

#### Deadline contract

Keep the current separate discover, dial, and message-send commands; a new combined native API is not required.

1. Dart owns one absolute deadline for the complete direct leg, anchored to `T0`. Each native phase receives at most its phase cap or `remainingLegTime - bridgeWatchdogMargin`. Do not start `message:send` unless its allocated native budget exceeds `ackReserve`; otherwise end the direct leg without writing.
2. Every Go command converts its supplied budget to one absolute deadline when that command enters Go. Relay/address candidates, self-heal, retry, and I/O may not renew the full command budget.
3. `message:send` reserves three seconds for the committed ACK. Stream opening/recovery and the complete frame write must finish before `nativeDeadline - ackReserve`.
4. After the complete frame is written, wait for the ACK until `min(nativeDeadline, writeCompletedAt + ackReserve)`.
5. The direct-leg deadline remains Dart's orchestration bound. Each per-command Dart `Future.timeout` is only a looser bridge watchdog and must fit inside the leg deadline; it may not fire before the native command's own deadline. The current native budget plus 500 ms is a sufficient initial margin.

The final total direct-leg and native-send ceilings belong in the implementation ticket after reviewing existing `discoverMs`, `dialMs`, `streamOpenMs`, `writeMs`, and `ackWaitMs`. The required architecture decisions are the timer anchors, the three-second ACK reserve, and the rule that budgets do not restart.

**Discard for now:**

- A new native durable message spool.
- `ACCEPTED` and `COMMITTED` as a new two-level wire protocol.

The current receive path already durably stages a direct message before confirming it. The timeout contract can be repaired without introducing another persistence owner or ACK state.

### 4. Attachments are excluded from live relay

**Verdict: keep, with a simpler condition. Priority: Medium.**

The blanket exclusion is exact at `send_chat_message_use_case.dart:1672-1676`:

```dart
!hasAttachments && payloadBytes <= kLiveRelayMaxPayloadBytes
```

In the normal producer, encrypted media upload completes before `sendChatMessage` is called at `lib/features/conversation/presentation/screens/conversation_wired.dart:3611-3671,3741-3755`. The live envelope carries metadata, not the media blob. Attachment presence therefore does not describe circuit traffic.

**Keep:**

- Gate live relay on the actual UTF-8 encoded envelope/frame byte count.
- Reuse the existing successful-upload invariant in normal message producers.
- Add a focused attachment-envelope relay test.

**Avoid:** a multi-mode media recovery protocol. If any nonstandard producer can supply an unuploaded attachment, add one explicit remote-blob-ready precondition instead.

### 5. Direct discovery and dialing are serial

**Verdict: the observation is true; the proposed redesign does not match this codebase. Priority: Medium/low until measured.**

The foreground path is rendezvous discovery, then dial, then send at `send_chat_message_use_case.dart:1942-2021`.

Important corrections to the assessment:

- `discoverPeer` makes one rendezvous request and receives a completed peer list; it is not a candidate stream (`lib/core/services/p2p_service_impl.dart:1037-1074`, `go-mknoon/node/rendezvous.go:110-182`).
- There is no production DHT discovery leg in this repository.
- mDNS is already asynchronous and forwards LAN addresses into Go as they appear (`lib/core/services/p2p_impl/p2p_peer_transport_coordinator.dart:300-347`).
- Returned addresses are handed together to Go, where the pinned go-libp2p swarm owns ranked, staggered dialing. Private/public candidates may overlap, QUIC/TCP are staggered, and the built-in relay delay applies when public direct addresses exist—not merely because private/LAN addresses exist.
- A peer warm/debounce coordinator already exists at `p2p_peer_transport_coordinator.dart:399-468`.
- The `enableDcutrUpgrade` rollout flag defaults off, but the host still always installs `libp2p.EnableHolePunching()` at `go-mknoon/node/node.go:417-423`; the flag changes forced reachability at `:397-400`. The current code therefore does not provide a clean subsystem-off guarantee. DCUtR behavior must not be assumed in the near-term decision flow until its gating and device behavior are made explicit.

**Keep:**

- Do not recreate go-libp2p's per-address dial ranking in Dart.
- Use existing `discoverMs`, `dialMs`, and `sendMs` telemetry before changing budgets.
- If discovery is material, extend the coordinator with a new joinable foreground connection future or introduce one combined Go-owned discover/connect operation. The existing `warmPeer` boolean is not directly joinable and does not perform foreground rendezvous.
- Prefer cached peerstore addresses before a fresh rendezvous request where safe.

**Discard for now:**

- A new streaming mDNS/rendezvous/DHT candidate pipeline.
- An arbitrary 8-10 second DCUtR background budget.
- Treating this optimization as equally urgent as ACK correctness and durability.

### 6. Dart timeouts may not cancel native transport work

**Verdict: keep the bounded-late-work concern; simplify the remedy. Priority: High as part of timeout repair.**

`Future.timeout` does not cancel the native operation, and the bridge has no attempt-cancellation command. More importantly, the supplied native timeout is not consistently one end-to-end deadline:

- Stream open, self-heal, and retry can each receive fresh timeout scopes at `go-mknoon/node/node.go:1531-1563`.
- Stream I/O gets a new deadline after opening at `:1607-1619`.
- Dart and bridge watchdogs are separate at `send_chat_message_use_case.dart:1971,1994,2021` and `lib/core/bridge/p2p_bridge_client.dart:1429-1459`.

The practical risk is that Dart can select inbox while Go is still recovering and can later write the envelope.

The assessment overstates several unverified consequences. The bridge-used send path does close its stream, a timed-out Dart future cannot complete the timeout wrapper twice, and no Go result-channel leak was found in this synchronous bridge path. Late status regression is a persistence concern, but it was not demonstrated as a direct property of `Future.timeout`.

**Keep:**

- Apply the deadline contract above to stream open, recovery, write, and ACK; do not renew the full command budget on self-heal or retry.
- Apply the same absolute-command rule to rendezvous discovery. Its current relay/address failover can create a fresh timeout per candidate at `go-mknoon/node/rendezvous.go:134-145` and `go-mknoon/node/relay_selector.go:198-209`, so native discovery may continue after Dart stops observing it.
- Use Go context cancellation to bound dialing/opening and stream deadlines (`SetDeadline`/`SetReadDeadline`) to bound established-stream I/O.
- Keep each per-command Dart timeout only as the slightly looser bridge watchdog; the separate direct-leg deadline remains the orchestration bound.
- Reset a stream after unsuccessful completion; use `CloseWrite` before waiting for an ACK as protocol hygiene.

**Defer:** cross-FFI attempt IDs and explicit cancellation. Add them only if telemetry shows meaningful native work surviving the absolute operation bound, for example during platform suspension.

### 7. Competing transport callbacks must not regress delivery proof

**Verdict: keep a narrow persistence invariant; discard the universal state ranking. Priority: High before adding the new inbox hedge.**

Existing protections make the assessment's `Critical` label too strong:

- The send race uses a process-local `liveDelivered` guard at `send_chat_message_use_case.dart:830-937`.
- Delivery receipts already use compare-and-set transitions at `lib/features/conversation/application/handle_delivery_receipt_use_case.dart:135-161`.
- Incoming duplicates are durably recognized and re-mint a receipt at `handle_incoming_chat_message_use_case.dart:321-394,443-503`.
- Relay inbox storage already deduplicates by message ID in `go-relay-server/backend_memory.go:114-150`, `backend_redis.go:263-301`, and `inbox.go:1405-1421`.

The residual issue is real: generic status updates are unconditional at `lib/features/conversation/data/repositories/message_repository_impl.dart:359-367` and `lib/core/database/helpers/messages_db_helpers.dart:381-397`. Stronger delivery proof is therefore protected by convention rather than one database invariant.

**Keep:** add one narrow atomic operation such as `settleOutgoingTransport` for ordinary outgoing rows. Route every sender-side settlement writer—including live/inbox callbacks and normal delivery-receipt application—through this contract. Protected/view-once rows should retain their existing lifecycle-guarded atomic settlement equivalent rather than being forced through a new generic SQL path. The existing protected-message rules at `lib/core/database/helpers/messages_db_helpers.dart:1851-1859` provide the right predecessor sets:

| Candidate status | Allowed current statuses | Required evidence |
| --- | --- | --- |
| `delivered` | `sending`, `sent`, `inboxed`, `failed`; the same settled `delivered` result is a no-op | Authenticated committed ACK or authenticated delivery receipt |
| `inboxed` | `sending`, `sent`, `failed`; `inboxed` is idempotent | Durable inbox-custody ACK |
| `sent` | `sending`, `failed`; `sent` is idempotent | Uncommitted live write or retry |
| `failed` | `sending`; `failed` is idempotent | Exhausted attempt with no stronger proof |

No candidate may replace `delivered`, and routine send failure may not replace `inboxed`. A repeated `delivered` settlement is an exact-state no-op: it must not replace the first winner's transport, envelope state, or expiry. Keep `failed -> delivered`: authenticated delivery receipts already perform that compare-and-set at `lib/features/conversation/application/handle_delivery_receipt_use_case.dart:149-161`, and a late authenticated commitment is stronger evidence than an earlier timeout.

The database operation should update the settlement fields together—`status`, `transport`, `wire_envelope`, and `relay_expires_at` as applicable—while checking the allowed predecessor, outgoing-row identity, visibility/deletion predicates, and expected envelope where relevant. It must not perform a Dart read/compare/write or follow the status update with a stale full-row `saveMessage`. Normal delivery-receipt handling must therefore clear its envelope in the same atomic operation instead of its current status-CAS-then-save sequence at `lib/features/conversation/application/handle_delivery_receipt_use_case.dart:135-178`.

This is not a claim that every status transition is permanently monotonic. `inboxed -> sent` remains intentionally available only to the dedicated custody-verification path when relay custody is proven lost at `lib/features/conversation/application/verify_inbox_custody_use_case.dart:126-139`:

> Competing send callbacks may never downgrade stronger proof. Explicit custody-loss verification is a separate authoritative transition.

**Discard or defer:**

- `newStatus = max(current, candidate)`. The real state set includes `sending`, `sent`, `failed`, queue variants, edits, and deletion; it is not a safe total order.
- Duplicate re-ACK work; it already exists.
- Inbox idempotency work; it already exists.
- Persisted `successfulRoutes[]` and `failedAttempts[]`; attempt history belongs in telemetry unless a product feature needs it.
- Same-ID/different-content rejection as part of this change. Current code preserves the first row and logs a mismatch; edits and other ID reuse make a universal hash rule a separate protocol decision.

### 8. Every message may start its own transport race

**Verdict: keep only the missing single-flight behavior, if measurements justify it. Priority: Medium/low.**

The proposed `PeerDeliveryCoordinator` already exists as `_P2PPeerTransportCoordinator` in `p2p_peer_transport_coordinator.dart:105-133`. It already deduplicates warm operations and LAN forwarding. Local discovery also single-flights peer resolution.

The remaining duplication is foreground rendezvous/discover/connect work, which is still created per message at `send_chat_message_use_case.dart:1942-2051`. Rapid sends can repeat application-level discovery even though go-libp2p normally coalesces concurrent connection attempts.

**If telemetry justifies it:**

- Extend the existing coordinator with per-peer singleflight for foreground discovery and connection establishment.
- Share only connection work. Each message retains its own stream, ACK result, and inbox hedge.
- Do not cancel shared warming because one message used relay or inbox.
- First add a burst characterization test; implement single-flight only if repeated foreground discovery/connect work is material.

**Discard for now:**

- A second coordinator abstraction.
- A bounded per-conversation send queue or serializing all sends.
- Conversation sequence numbers and a receiver reorder buffer without an observed causal-order defect.
- Resource-manager customization solely for this hypothetical burst. Revisit resource limits from load-test evidence, not as a prerequisite for coalescing discovery.

### 9. Relay detection uses multiaddress text parsing

**Verdict: keep as a low-priority cleanup.**

The classifier uses string matching for `/p2p-circuit` at `go-mknoon/node/node.go:154-171`.

For the pinned go-libp2p version, the primary signal, after a defensive connection check, is:

```go
conn := s.Conn()
isLimited := conn != nil && conn.Stat().Limited
```

`Limited` formally means constrained by bytes or time and represents circuit-v2 connections in practice in the pinned implementation. Use it first, then retain a typed multiaddress protocol check as a compatibility/telemetry fallback. `s.Stat().Limited` is not necessary because the pinned swarm stream stats do not reliably copy connection limitedness. A similar connection-stat pattern already exists in `go-mknoon/node/lan_dial.go:68-74`.

This change fixes Go's chat-stream result label only. Dart still parses `/p2p-circuit` for race eligibility at `send_chat_message_use_case.dart:1617-1669`, its connection model does not retain Go's `limited` field, and `isRelay` identifies configured relay-peer identity rather than a limited route. Unifying that model is separate follow-up work if classification bugs are observed.

This improves robustness but does not warrant `Medium` architectural severity.

### 10. Local WebSocket duplicates direct libp2p transport

**Verdict: keep and elevate from architecture cleanup to delivery-integrity work. Priority: High.**

The authentication concern is confirmed:

- The server and client use plain HTTP/WebSocket at `lib/core/local_discovery/local_ws_server.dart:98-108,673-695`.
- mDNS peer ID and port attributes are trusted by discovery at `lib/core/local_discovery/bonsoir_discovery_service.dart:205-217,320-388`.
- Frames and ACKs are unsigned. A committed ACK contains the echoed nonce and booleans, and the sender checks nonce correlation but no peer-bound signature or session MAC at `local_ws_server.dart:391-420,514-568`.

A malicious LAN service can advertise the intended peer ID, receive the encrypted envelope, echo the visible nonce, and cause the sender to record false delivery. The nonce correlates a request; it does not authenticate the endpoint. This finding does not by itself show loss of message confidentiality because the application envelope remains encrypted.

The simpler long-term design is already partly present:

```text
mDNS                 -> LAN discovery and peerstore addresses
authenticated libp2p -> all live chat envelopes over QUIC/TCP or relay
durable inbox        -> independent custody
```

The peer coordinator already forwards mDNS addresses into libp2p. Prefer completing that migration over designing another custom ACK authentication protocol.

During compatibility:

| WebSocket response | Effective proof for settlement | Authenticated | Effect |
| --- | --- | --- | --- |
| Legacy `ack:true` | `written` | No | Record `local-websocket` telemetry only |
| Claimed `committed:true` | `written` (the commitment claim is untrusted) | No | Record `local-websocket` telemetry only |

- No WebSocket-only result may set `delivered`, win or suppress the live race, cancel authenticated libp2p work, or suppress/cancel inbox custody.
- Apply this rule to every current WebSocket ACK, not only the legacy form. Both forms are correlated only by the echoed nonce at `lib/core/local_discovery/local_ws_server.dart:386-420,537-568`; neither authenticates the peer.
- This is an orchestration rule; it does not require a new persisted authentication field or a general scoring framework.
- A libp2p ACK already inherits peer authentication from the secure stream opened to the intended Peer ID; it does not need a second signed ACK.
- Remove the WebSocket chat-envelope path after same-LAN libp2p migration is reliable. Design a signed/MACed WebSocket protocol only if long-lived compatibility later becomes a hard requirement.
- Keep local media transfer out of this change unless its own threat model requires work; removing WebSocket authority for chat envelopes does not require replacing every LAN media mechanism.

## Minimal target decision flow

```text
T0 = entry to sendChatMessage
  prepare the encrypted envelope
  start eligible authenticated live send(s)
  start existing direct connection work
  do not await presence before live work
  a transitional local-WebSocket attempt may emit telemetry but cannot settle

  if peer is structurally unknown:
      start inbox deposit as soon as the envelope is available

  if peer is connected or LAN-visible:
      schedule one inbox hedge for T0 + hedgeBudget
      if that time has passed when the envelope is ready, start it immediately

first authenticated COMMITTED live ACK
  atomically advance to delivered immediately
  record the route for future preference/telemetry
  never replace it with an uncommitted or unauthenticated result
  cancel only a scheduled-but-not-started inbox hedge
  if inbox storage already started, let it complete idempotently

inbox custody ACK with no committed live ACK
  atomically advance to inboxed

late authenticated COMMITTED live ACK
  atomically advance sent/inboxed/failed -> delivered

connection work
  may continue within its absolute deadline for subsequent messages
```

Live settlement requires three concepts, not a large state machine. Inbox custody remains a separate milestone:

```text
live transport: direct-libp2p (LAN or WAN) | relay-libp2p | local-websocket
delivery proof: failed | written | committed
authenticated:  yes | no
```

Inbox custody is tracked separately as `none | inboxed`. Only `authenticated && committed` is final recipient-device delivery. A small shared predicate is sufficient; no route score or general settlement state machine is needed.

A short delay before *starting* a live relay leg can remain as a measured traffic/cost optimization. It is separate from winner grace: once any authenticated committed ACK arrives, the delivery grace is zero. The current 500 ms stagger and the assessment's proposed 150-250 ms should both be treated as telemetry-tuned values rather than correctness constants.

## Dependency-ordered TDD rollout roadmap

This roadmap—not the priority table—is the reference order for future planning sessions.

Each roadmap item is one independently closable TDD plan:

```text
$tdd-plan for one roadmap item
    -> $tdd-review of that plan
    -> implement its RED tests and production change
    -> reach GREEN and close its focused gates
    -> begin the next dependent roadmap item
```

Do not create one preliminary plan containing all failing regression tests. Each plan below owns the causal RED tests for its behavior and the production change that makes those tests GREEN. Allocate its real `Test-Flight-Improv` number only when that plan is created, so future sessions do not reserve stale numbers.

```text
R1 Atomic outgoing settlement
        ↓
R2 Authenticated committed live settlement
        ↓
R3 Cross-layer deadline contract
        ↓
R4 Presence-independent durability hedge
        ↓
R5 Attachment-envelope live relay
```

### R1 — Atomic outgoing transport settlement

**Why first:** every later plan changes or adds competing callbacks. Persistence must reject stale or weaker results before concurrency is widened.

**Owns:**

- One atomic ordinary-outgoing-row settlement operation for `status`, `transport`, `wire_envelope`, and `relay_expires_at` as applicable.
- The explicit predecessor table in Finding 7, including `failed -> delivered` and exact-state no-op semantics for a repeated `delivered` result.
- Migration of ordinary live/inbox, retry/lifecycle, and normal delivery-receipt writers that can race.
- Atomic envelope clearing during receipt application.
- Preservation of the existing protected/view-once lifecycle-guarded settlement and the separate verified-custody-loss `inboxed -> sent` transition.

**Owns its causal RED tests:** transition-matrix acceptance/refusal, both callback completion orders, late `inboxed`/`sent`/`failed` attempts after `delivered`, a second `delivered` result with a different transport or metadata, `failed -> delivered`, expected-envelope refusal, hidden/deleted refusal, and atomic receipt envelope clearing.

**GREEN closure:** all ordinary settlement writers use the atomic contract; no status CAS is followed by a stale full-row save. No schema migration, ACK-ranking change, timeout change, presence change, or new queue belongs here.

### R2 — Authenticated committed live settlement

**Depends on:** R1.

**Why ACK strength and WebSocket authority are one plan:** both are one decision at the reuse/sticky/race settlement seam:

```text
provesDeviceDelivery = authenticated && committed
```

Splitting them would rewrite the same selector twice and leave an intermediate state that either remains ACK-blind or still trusts a forged WebSocket commitment.

**Owns:**

- The first authenticated committed ACK settles immediately across reuse, sticky, and ranked-race paths.
- Written/unacknowledged results cannot replace or delay stronger proof.
- Transport ranking controls attempt scheduling, relay staggering, telemetry, and future learning only; delivery winner grace is zero.
- Every local-WebSocket ACK, including claimed `committed:true`, is non-authoritative `written` evidence.
- A WebSocket result cannot set `delivered`, suppress authenticated libp2p, cancel/suppress inbox custody, or train the sticky route as a successful delivery.
- Transitional WebSocket telemetry may remain; this plan does not remove the protocol or add a signed/MACed replacement.

**Owns its causal RED tests:** committed libp2p versus delayed higher-ranked legacy/claimed-committed WebSocket results, unacknowledged reuse/sticky fallthrough, first of two authenticated libp2p commits without grace, WebSocket-only fallback to `inboxed` or retryable `sent`, and WebSocket inability to suppress live/inbox work.

**GREEN closure:** host tests prove the authority decision and spoof resistance at the orchestration seam. Any available two-peer Android preservation smoke proves operational same-LAN behavior, not the causal security property; use a physical Android plus Android emulator by default and require no manual taps. Do not add an iOS leg unless the plan makes an iOS-specific boundary or parity claim.

### R3 — Cross-layer deadline contract

**Depends on:** R2. Lengthening ACK opportunities while settlement is still proof-blind can amplify the incorrect-winner race.

**Owns:**

- One Dart direct-leg deadline anchored to `T0` with remaining-budget phase admission.
- Consistent treatment of reuse, sticky, direct, and live-relay sends.
- One absolute Go deadline per rendezvous-discovery, explicit-dial, and message-send command.
- One rendezvous deadline shared across relay/address candidates.
- One message-send deadline across stream open, self-heal, retry, complete frame write, and ACK read.
- A concrete initial three-second post-write committed-ACK reserve.
- A bridge watchdog that is looser than the native command but still fits inside the Dart leg deadline.
- Bounded stream cleanup through the appropriate `CloseWrite`/`Close` or `Reset` outcome.
- Direct registration of the new Go deadline suite in `scripts/run_host_test_gates.sh`; the aggregate gate runs only named synthetic Go legs.

**Owns its causal RED tests:** sender budget versus receiver commitment contract, phase admission when the ACK reserve cannot fit, no timeout renewal across recovery/candidates, post-write ACK timing, watchdog ordering, and success/error stream cleanup. Use controllable clocks/fakes rather than multi-second sleeps where possible.

**GREEN closure:** Dart, bridge, and Go agree on concrete initial constants and timer anchors. Run the causal Go deadline suite directly during this plan and verify its named registration in the affected host gate. Presence scheduling, inbox-hedge activation, cross-FFI cancellation, DCUtR, discovery redesign, and route ranking remain out of scope.

### R4 — Presence-independent durability hedge

**Depends on:** R1, R2, and R3.

**Owns:**

- Presence refresh no longer delays eligible live work.
- Structurally unknown peers schedule one inbox operation before reuse or sticky early returns, with the actual deposit starting once the encrypted envelope exists.
- Connected/LAN-visible peers receive one `T0`-anchored inbox hedge using the corrected ACK contract.
- Only an authenticated committed ACK cancels a scheduled-but-not-started hedge.
- Once inbox storage starts, it completes idempotently; atomic settlement decides the durable status.

**Owns its causal RED tests:** slow/unreachable presence does not delay live launch, unknown peers schedule exactly one deposit despite reuse/sticky paths, connected and LAN-visible peers hedge at the bound, WebSocket results do not cancel the hedge, authenticated libp2p commitment does, and both `inboxed -> late delivered` and `delivered -> late custody` completion orders preserve the stronger result.

**GREEN closure:** the decision seam is causally host-tested with deterministic time. Reuse the existing relay-inbox protocol and idempotency; do not add pending/activate/tombstone states, inbox cancellation, a second queue, or a new coordinator.

### R5 — Attachment-envelope live-relay eligibility

**Depends on:** the R1-R3 correctness foundation. It is scheduled after R4 to stabilize fallback behavior first and reduce churn in `send_chat_message_use_case.dart` and its large test suite.

**Owns:**

- Live-relay eligibility based on the UTF-8 encoded envelope/frame bytes rather than attachment presence.
- Reuse of the existing uploaded-media invariant before envelope send.
- Preservation of the rule that media blob bytes do not traverse the chat-envelope stream.

**Owns its causal RED tests:** uploaded attachment metadata under the cap uses the live relay, over-cap and multibyte-over-cap envelopes do not, media bytes are absent from the chat frame, and relay-live failure still falls to durable inbox custody.

**GREEN closure:** host tests prove the eligibility decision and media/envelope separation. Any real relay-and-media journey belongs in the affected wave/final proof rather than creating a new mandatory hardware topology for this small decision change. Do not add media-recovery state or a media-availability protocol.

### Gate cadence across the roadmap

- Each plan closes with its focused causal tests, exact preservation sentinels, and the affected curated lane/family gate. Do not run full `host-all` for every plan.
- **Correctness dependency wave:** R1-R3. Run one full `host-all` after R3 closes.
- **Durability/relay rollout wave:** R4-R5. Run full `host-all` again at final rollout/release closure after R5.
- Resolve any device/relay matrix at execution time. Non-iOS-specific paired proof defaults to one discovered USB Android device plus one available Android emulator, both pinned and automated. Unavailable version-specific targets are `N/A` under project policy, not blockers.

### Conditional follow-up plans—do not pre-plan yet

- **Remove WebSocket chat transport:** only after R2 de-authority, R3 deadline safety, R4 custody safety, and authenticated same-LAN preservation evidence. Remove chat-envelope call sites only; keep local media paths out of scope.
- **Foreground connection single-flight:** only if post-R3/R4 telemetry shows material repeated discovery/connect work during burst sends. Extend the existing coordinator rather than create another one.
- **Relay classification cleanup:** only as a small telemetry-quality/robustness plan if `Conn.Stat().Limited` and current multiaddress-derived labels demonstrably disagree. Do not bundle Dart connection-model redesign without evidence.
- **Cross-FFI cancellation, DCUtR rollout, resource-manager policy, deeper discovery, or a signed WebSocket protocol:** create separate plans only when their specific evidence or product requirement exists.

## Explicitly out of scope unless evidence changes

- Native durable spool and a second persistence owner.
- New two-level ACK protocol.
- Pending/activate/tombstone relay-inbox protocol.
- New peer-delivery coordinator or per-conversation transport queue.
- Receiver reorder protocol.
- Streaming DHT/multi-source discovery pipeline.
- DCUtR-specific timing or guarantees until its rollout flag is a clear subsystem gate and device behavior is proven.
- Cross-FFI attempt cancellation before absolute operation bounds are proven insufficient.
- A signed/MACed WebSocket chat protocol unless long-lived WebSocket authority becomes an explicit compatibility requirement.
- Custom resource-manager policy without load-test evidence.
- Reimplementing go-libp2p address racing in Dart.

These may become valid future projects, but none is needed to repair the confirmed delivery, authentication, timeout, and durability issues above.
