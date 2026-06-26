# FDC-00 — Fast Direct Connection: Master Roadmap

**Code:** FDC-00 · **Fidelity:** roadmap (artifact index + sequencing; no RED tests) · **Branch:** `new-orbit`
**Status:** authoring · **Owns no production code** — this is the index/sequencer for the FDC epic.

---

## Epic overview

This epic implements the [Fast, Reliable Direct Connection — Architecture
Proposal](../../../Network-Arch/Fast-Direct-Connection-Architecture-Proposal.md). The proposal's
one-line thesis: the perceived 1:1 send slowness is **not one timer to tune — it is a serial
discover→dial→send cascade with no maintained connection and no presence signal** (proposal §3,
§4). The fix is to *delete the decision window*: warm the peer connection LAN-aware while the human
reads/types (§6.1), then on send run a **staggered, relay-penalized *ranked* race** (NOT blind
fan-out — that is the libp2p anti-pattern deprecated in v0.28, §6.2/§12) while **always depositing
to the durable inbox in parallel as a strictly separate tier** (§6.2b), committing on the first ack
and de-duplicating by `messageId`. The proposal carries hard corrections we honor verbatim:
"~0% on cellular" is a *design assumption*, not a citable figure (~70%±7.1% network-wide per punchr,
§1/§12); the live circuit-v2 relay socket (2 min / 128 KB / 1 reservation) is **not** the durable
inbox and must never carry media (§6.2b); and several wins are **device-only** because iOS sim
shares a host mDNS stack (§6.5). This roadmap decomposes that proposal into 7 spikes + 16 plans,
sequences them by collision/gating, and names the MVP cut.

---

## Executing in a fresh session (reading order — START HERE each session)

Each FDC plan is self-contained (its own grounded `file:line` anchors, RED catalog, literal gates,
collision/dependency notes) but assumes a few cross-doc facts. When you pick up a plan in a NEW
session with no shared context, open the docs in this order:

1. **This file (FDC-00)** — the collision map, the spike→plan gating graph, the sequencing, the MVP
   cut, the **Move-feature interaction**, and the **Known gaps** section. *A plan read in isolation
   will not stop you running it out of order.*
2. **The plan you're executing** (`FDC-NN-*.md`) — its `## Source Of Truth` links the proposal § +
   this roadmap; then read its `## Real Scope`, `## RED Test Catalog`, `## Acceptance Gates`,
   `## Scope Guard`, and `## Dependency Impact`.
3. **Its gating spike** (if the plan shows a `⚠ DRAFT` banner) — resolve `FDC-Sn` FIRST and replace
   every `<from FDC-Sn>` placeholder with the spike's written verdict before coding. A DRAFT plan is
   **not implementation-ready** until its spike lands.
4. **The proposal section** the plan cites (design rationale + the corrections in §1 / §6.2 / §12).

**Non-negotiable cross-session rules (also stated inside each plan):**
- **Collision order:** FDC-01 → 02 → 03 → 04 all edit `send_chat_message_use_case.dart` → run
  sequentially, each **on the previous one's committed tree** (not HEAD). FDC-04/05 also collide on
  `handle_app_resumed.dart:130-191` → **prefer landing FDC-05 first** (warm `warmPeer` slots into
  its already-parallel block); if FDC-04 lands first per the phase order, **rebase** its resume
  call-site when FDC-05 restructures the block (see *Tertiary collision* below — both orders are
  supported, FDC-05-first just avoids a rebase).
- **Spike gates:** FDC-06←S4 · FDC-07←S1 · FDC-08/09←S3 · FDC-11/12←S2 · FDC-15←FDC-11/S2 · FDC-14←FDC-02/11. Don't
  start a gated plan before its gate resolves.
- **Durability ordering:** pull FDC-10 (Redis) earlier than FDC-03's inbox-volume ramp.
- **MVP path:** FDC-S5 → FDC-01 → FDC-02 → FDC-03 → FDC-04 (see *Recommended MVP cut* below).
- **Move-feature gate:** any NEW network primitive must call `_allowsAccountNetworkSideEffects(...)`
  (see *Move-feature (account-migration) interaction* below).

> Tip: capture the green host-gate baseline counts (`1to1`/`feed`/`transport`) before FDC-01 so each
> session can fill the `expected: TODO` counts in the plans' Acceptance Gates. **This is part of
> `FDC-S0` (Baseline + improvement measurement): run FDC-S0's baseline capture FIRST and its re-measure
> at epic close to produce the before→after improvement scorecard.**

---

## Full artifact index

Fidelity legend: **roadmap** = index/sequencer · **spike** = timeboxed measurement/decision, no
shipped RED locks · **tdd-plan** = source-verified RED-cataloged implementation plan.
All plans below are **authored** (this folder is fully populated) — each was written via `/tdd-plan`.
Plans marked **(DRAFT)** in the Fidelity column are spike-gated and **not implementation-ready** until
their gating spike lands (replace every `<from FDC-Sn>` placeholder first); the rest are
implementation-ready.

### This document

| Code | Title | Fidelity | Purpose |
|---|---|---|---|
| **FDC-00** | Fast Direct Connection — Master Roadmap | roadmap | This file. Artifact index, recommendation→plan map, phase sequencing, collision map, spike→plan gating graph, durability-ordering hazard, MVP cut, closure strategy. |

### Spikes (measure / decide before the gated plans can finalize)

| Code | Title | Fidelity | Purpose |
|---|---|---|---|
| **FDC-S0** | Baseline + improvement measurement | spike (bookend) | The **measurement bookend** — runs **FIRST** (capture the baseline on today's `new-orbit`, before FDC-01) **and at epic close** (re-measure → a before→after **improvement scorecard**). 10 metrics: perceived 1:1 send latency by scenario · notif-tap→first-live-message · online→inbox **misroute rate** (→0, FDC-01) · transport **distribution** (% local/direct/relay/inbox) · cold-start time-to-online [reuse FDC-S1] · LAN-win-rate [reuse FDC-S6] · reconnect time · reaction-to-offline reliability [FDC-18] · inbox-durability survives relay restart [FDC-10] · host-gate floor. Reuses existing telemetry (`emitFlowEvent`, `NOTIFICATION_TAP_TO_LIVE_MESSAGE_TIMING`, the `transport` column, `TransportMetrics`, Go `benchmark_*_test.go`) — minimal new aggregation. **Gates nothing; it MEASURES the epic.** Felt-UX metrics are device-only. |
| **FDC-S1** | Cold-start timing measurement | spike | Measure real-device cold-open **time-to-circuit-address** and **time-to-first-mDNS-resolve** (proposal §11.3) so foreground budgets are set from data, not re-timed blind. **Gates FDC-07.** Output: a numbers table + a "do/don't cap the cold relay dial" verdict. |
| **FDC-S2** | QUIC identify-handshake re-validation | spike | Re-validate the §5 / `UI-15-WS-Server/plan.md` L42-48 "QUIC identify-handshake hang": is a libp2p QUIC/TCP **LAN dial's identify** reliable now? **Gates FDC-11 and FDC-12** (both add libp2p direct-dial paths — FDC-11 the bonsoir-fed LAN dial, FDC-12 the DCUtR upgrade). Device-only. |
| **FDC-S3** | Presence-signal decision | spike | Decide the "online-ish" signal: additive **relay-lookup** action (needs deploy, reservation-truth may need go-libp2p relay internals) vs **gossipsub beacon** (no relay change, adds churn; node already inits pubsub `node.go:379`) vs explicit **client→relay status-push** on pause/resume. Also: how to self-publish foreground (§6.3/§11.2). **Gates FDC-08 and FDC-09.** |
| **FDC-S4** | iOS pause-flush feasibility | spike | Resolve the §6.4 / §10 open invariant: can a **bounded, inbox-store-only** network flush run on the iOS pause transition via `beginBackgroundTask` (or an APNs-backed path) before suspension? Today `handleAppPaused` is local-DB-only, no network (`main.dart:4314-4316`). Output: feasible-or-not + the pre-suspension budget (how many in-flight sends, §11.6). **Gates FDC-06.** |
| **FDC-S5** | Go-bridge concurrency design note | spike | Design note (no measurement gate) on the §10 hazard: do `warmPeer` + `fastReprime` + the user's send serialize at the Go bridge, or run concurrently? **Finding: the bridge is largely concurrent in the warm/steady state** (concurrent native queues at Swift/Kotlin + Go read-lock layers; Dart `Future.wait` DOES yield real Go concurrency); the **only** serialization point is `Node.Start`'s write lock on the **cold path**. Output: a prioritization contract (keep speculative warm off the cold-start path + behind the node-started gate; the FDC-02/03 race keeps its true-parallel shape) the Phase-0 plans build against. **Informs FDC-04, FDC-05 (advisory design-gate, not a delivery/sequencing gate); first step of the MVP cut.** The verdict is **source-grounded (settled, usable now)**; its **device M1/M2 confirmation rides the post-FDC-04 two-device smoke** and does not gate Phase 0 (S5 status stays "open" only on that device measurement). |
| **FDC-S6** | libp2p-LAN soak + WS-transport retirement decision | spike (decision) | The **last-step decommission decision**: is libp2p LAN device-proven on **both** platforms and winning enough to **retire the WS chat/media transport**? Decides 3 components separately — (1) **WS chat transport** = retire iff libp2p-LAN chat ≥95% same-WiFi win-rate over ≥14 d on both OS + zero net-new LAN failures + bonsoir-fed dial proven on both platforms + FDC-11 D1 green; (2) **WS/HTTP LAN media server** = retire iff a libp2p-LAN media path is device-proven OR relay-CDN-only LAN media is accepted (needs a NEW media plan first); (3) **bonsoir discovery** = **keep always** (iOS entitlement). Fail-safe = keep both + ranked-race + `messageId` dedup. **Gated by FDC-11** (device-proof); gates no current plan. **FDC-15** (1:1 media over libp2p LAN — now AUTHORED) is the media prerequisite it consumes; spawns a **WS-chat-removal** plan (repoint `startAdvertising` off `wsPort` to the libp2p host port) + **WS-media removal** only if both component verdicts say retire. |

### Plans (implementation; authored via `/tdd-plan`, then executed)

| Code | Title | Proposal | Fidelity | Purpose |
|---|---|---|---|---|
| **FDC-01** | `direct_timeout`→inbox mis-route fix | P0-3 / §4.1 | tdd-plan | Narrowest correctness bugfix: a slow-to-discover but **online** peer burns the 2 s budget → outer `onTimeout` (`send_chat_message_use_case.dart:701`) yields `direct_timeout`, which is **not** `relayProbeEligible` (set only at `:1483`/`:1500`) → skips the probe tail and lands an online peer in the **offline inbox**. Make `direct_timeout` probe-eligible (or lean on the always-on concurrent inbox + a continuing live attempt). |
| **FDC-02** | Staggered relay-penalized ranked race | §6.2 | tdd-plan | Replace the single 2 s cap over a serial leg with a **ranked** race modeled on `DefaultDialRanker`: LAN-direct + libp2p-direct first, **relay-live leg penalized ~500 ms**, private/LAN ~30 ms tail / public ~250 ms; commit on first ack, **migrate onto winner + collapse losers** (iroh/Tailscale pattern, NOT permanent dual-send). LAN-first **by priority, not suppression** (rank LAN highest, relay races-but-loses). Keep **relay-live vs durable-inbox as strictly separate tiers**; media never over the live relay socket. Gives discover/dial/send **independent** budgets (the latency half of P0-3). |
| **FDC-03** | Generalize the concurrent durable inbox | P0-2 | tdd-plan | Lift the inbox deposit out of the "low confidence only" gate (`:608-660`) → fire `storeInInbox` **concurrently** with the live race for all unknown-presence sends; drop the serial probe→inbox tail (`:1021-1086`). The inbox is the **delivery guarantee tier**, not a race participant. Dedup by `messageId` is already server-side. **Raises inbox volume → see durability-ordering hazard.** |
| **FDC-04** | LAN-aware eager `warmPeer` | P0-1 | tdd-plan | New idempotent, **debounced** `warmPeer(peerId)` = `discoverLocalPeer` (seed the LAN map FIRST → prevents the §6.1 relay-bypass) + speculative `dialPeer` (no send), on conversation-open / notif-tap / resume. **Gate reuse/sticky behind `isLocalPeer`** so a warmed relay circuit never bypasses LAN. **Per-`(peer,transport)` backoff/debounce** (libp2p swarm backoff 5 s→5 m on offline peers) + **network-change (WiFi↔cellular) re-warm**, prefer QUIC. |
| **FDC-05** | Parallel resume re-prime | P1-2a | tdd-plan | Run relay re-prime + bonsoir discovery restart + peer warm + inbox drain **in parallel** with foreground 3 s budgets — NOT serialized behind an awaited drain (`handle_app_resumed.dart:136-191`). Keep the existing unawaited-drain "catching up…" affordance. |
| **FDC-06** | Graceful pause-flush | P1-2b | tdd-plan (DRAFT) | On pause/hidden, flush every in-flight `sending` message to the inbox **before** OS suspend (the "send one message then close" case). Bounded, **inbox-store-only**, via the S4-chosen mechanism (`beginBackgroundTask`/APNs). Issue the inbox deposit *before* the direct attempts (§12 verbatim borrow). **Gated by FDC-S4.** |
| **FDC-07** | Cold-start: earlier mDNS / reserve | P1-3 | tdd-plan (DRAFT) | Start mDNS advertise/discover + relay reservation **earlier** (not buried in the post-startup fire-and-forget warm). **Do NOT blindly cap the cold relay dial at 3 s** — the 15 s `DialTimeout` runs in a background goroutine that doesn't block sends; capping a genuinely-cold QUIC/TLS handshake risks *more* abandoned reservations → *more* inbox fallback. **Gated by FDC-S1** (measure cold time-to-circuit first). |
| **FDC-08** | Relay presence lookup (additive) | P1-1 | tdd-plan (DRAFT) | Additive inbox action: "does this peer hold a live reservation?" → client-side short-TTL cache → pick direct-race vs inbox-first up front, replacing the blind 5 s `DialPeerViaRelay` probe. Reports **"online-ish," never "foreground."** Must not break older clients (NET-REL-07). **Gated by FDC-S3.** |
| **FDC-09** | Foreground self-publish + push-to-wake hardening | §6.3 / §12 | tdd-plan (DRAFT) | Peer **self-publishes** foreground/background (gossipsub heartbeat beacon OR client→relay status push — chosen by S3); presence inference from connectedness is wrong on iOS. Harden push-to-wake: per-recipient **access-token** gate (only contacts can wake you), **opaque-token** routing decoupled from the message path, **visible** push (iOS throttles silent pushes ~1–2/hr). **Gated by FDC-S3.** |
| **FDC-10** | Durable inbox backend (Redis) + relay pool | P2-2 | tdd-plan | Move the relay inbox off the **in-memory default** to the **existing Redis backend** so durable **control-plane** state (queue + push tokens + rendezvous) survives a relay bounce; **relay reservations are libp2p circuit-v2 runtime state — NOT Redis-persisted; they survive a bounce only via clients re-reserving + the relay pool's redundancy**. Deposit to a **small fixed relay pool**, not one relay. **Store dedup by `messageId` already exists** (`backend_memory.go:121-142`, `backend_redis.go:272-295`, `inbox_store.go:7,14`) — do NOT rebuild it; **durability is the only gap.** Additive (NET-REL-07). **Pull EARLIER — see durability-ordering hazard.** |
| **FDC-11** | libp2p LAN-direct dial (bonsoir-fed) | P2-1 | tdd-plan (DRAFT) | Bonsoir discovery feeds LAN-discovered peer addresses to the Go host; add `AddrInfo` to peerstore + `host.Connect` → a same-WiFi peer becomes a direct libp2p dial that `DefaultDialRanker` races ahead of relay; `IdentifyPush` keeps the LAN addr hot. Keep bonsoir+WS as the proven foreground/iOS fast path; dedup by `messageId`. **Gated by FDC-S2.** Device-only validation (sim shares host bonsoir stack → `DISABLE_LOCAL_DISCOVERY` disables both bonsoir and the libp2p LAN dial). |
| **FDC-12** | DCUtR relay→direct upgrade + stable peer-identity session + TCP lane | P2-3 | tdd-plan (DRAFT) | Behind a flag, let DCUtR upgrade a relay conn to direct (DCUtR is config-OFF today via `ForceReachabilityPrivate`, not capability-failed). Build a **stable peer-identity session layer**: DCUtR hands a *second* connection (unlike iroh/Tailscale in-place migration) → re-point "the peer" to the new direct conn + dedupe by `messageId`. Include a **TCP-direct lane** (punchr: TCP==QUIC); spend effort on RTT-sync precision + UPnP/PMP reversal, NOT retries (97.6% of wins first-attempt). **Gated by FDC-S2.** Device-only. |
| **FDC-13** | Relay→direct "upgraded" transport badge | §6.2b / Q4 gap | tdd-plan | Make a relay→direct **upgrade** visible per-message: new `'upgraded'` transport value + `Icons.upgrade` glyph + `message_*_via_upgraded` a11y in `letter_card.dart` (the **only** renderer — no feed `message_bubble` twin). **No DB migration** (existing TEXT column). Incoming render host-testable now via a synthetic `transport:upgraded` event; **outgoing-from-production-data + the upgrade actually firing are gated on FDC-12.** |
| **FDC-14** | "Online" dot also means directly-reachable + anti-flap | §6.3 / Q7 gap | tdd-plan (DRAFT) | New `BadgeReadinessState.onlineDirect` tier + `NodeState.directReady` input rendered by `ConnectionStatusIndicator`, plus a **badge anti-flap** test. New-tier render + anti-flap host-testable now; **`directReady` signal source gated on FDC-02/FDC-11** (provisional). Anti-flap notes added to FDC-05/06/07. Peer-presence (FDC-08/09) never feeds this dot. |
| **FDC-15** | 1:1 media over a peer-authenticated libp2p LAN stream | §6.2b / FDC-S6 prereq | tdd-plan (DRAFT) | Stream the same `EncryptedMediaArtifact` ciphertext over a NEW Noise-authenticated libp2p stream (`/mknoon/media-lan/1.0.0`) on the FDC-11 direct LAN conn — replacing the WS path's **TXT-record peerId trust + plaintext `ws://`** with cryptographic peer-AUTH (confidentiality unchanged; media already app-encrypted). Additive behind `EnableLibp2pLanMedia`; WS HTTP-PUT + relay-CDN kept as parallel fallbacks (idempotent by blob-id/SHA-256; relay-CDN stays UNCONDITIONAL — no 112-dangling-attachment regression). **1:1-only** (group media = relay-CDN, untouched). **Gated by FDC-11 + FDC-S2.** Device-only closure. Enables FDC-S6's media-server retire verdict. |
| **FDC-18** | 1:1 reaction send reliability | reactions gap | tdd-plan | Mirror **FDC-03's concurrent durable inbox** onto the reaction send path (`send_reaction_use_case.dart`) so a reaction to a slow/offline peer is durably queued (not dropped/late) and an online peer isn't demoted to inbox-only. **Calibrated:** the reaction path has a **single** transport leg (thin `sendMessage`) → FDC-01/02's race/budget wins are **N/A**; only the concurrent-inbox + online-not-demoted transfer. Receive last-writer-wins tombstone preserved. **No migration** (table 016 exists). **1:1-only** (group reactions = pubsub, disjoint). Lands **after FDC-03** (copies its pattern); **separate file from the send-path spine → parallelizable** (its own 1-file mini-track). 7 RED tests. |

---

## Recommendation → plan mapping

The proposal's prioritized recommendations (§8) map onto FDC codes as follows. Note P0-3 splits
into a narrow correctness bugfix (FDC-01) and the latency redesign that subsumes its
independent-budget half (FDC-02); P1-2 splits into resume (FDC-05) and pause (FDC-06).

| Proposal rec | Title (§8) | FDC code(s) |
|---|---|---|
| **P0-1** | LAN-aware eager `warmPeer` | **FDC-04** |
| **P0-2** | Generalize the concurrent inbox | **FDC-03** |
| **P0-3** | Fix 2s-serial starvation / online→inbox mis-route (§4.1) | **FDC-01** (mis-route correctness) **+ FDC-02** (independent budgets) |
| **P1-1** | Relay presence lookup (additive) | **FDC-08** |
| **P1-2** | Lifecycle split + graceful handoff | **FDC-05** (resume re-prime, P1-2a) **+ FDC-06** (pause-flush, P1-2b) |
| **P1-3** | Cold-start: earlier mDNS/reserve | **FDC-07** |
| **P2-1** | libp2p LAN-direct dial (fed by bonsoir discovery) | **FDC-11** |
| **P2-2** | Durable inbox backend (Redis) | **FDC-10** |
| **P2-3** | Opportunistic DCUtR upgrade (flagged) | **FDC-12** |
| **§6.2** | Staggered relay-penalized ranked race | **FDC-02** |
| **§6.3 / §12** | Foreground self-publish + push-to-wake hardening | **FDC-09** |

Every §8 recommendation is covered. FDC-09 (§6.3 self-publish + §12 push hardening) and FDC-02
(§6.2 ranked race) are the two plans that come from architecture sections rather than the §8 table.

---

## Phase sequencing

| Phase | Theme | Plans | Deploy surface | Validation |
|---|---|---|---|---|
| **Phase 0** | Dart-only, no relay/Go deploy — deletes the perceived window for the warm-open case + fixes the online→inbox mis-route | FDC-S5 (note) → **FDC-01 → FDC-02 → FDC-03 → FDC-04** | pure Dart (`send_chat_message_use_case.dart`, `p2p_service_impl.dart`) | host gates **+ a device smoke** (host-fake "live-wins" has a false-positive risk; see Closure) |
| **Phase 1** | Lifecycle + cold-start | **FDC-05**, **FDC-06** (gated S4), **FDC-07** (gated S1) | mostly Dart + small Go timeout reuse | host gates; **measure cold time-to-circuit (S1) before re-timing anything** |
| **Phase 2** | Additive relay deploy | **FDC-08** (gated S3), **FDC-09** (gated S3), **FDC-10** | relay/Go server (additive, NET-REL-07) | host fakes + a live-relay env; **pull FDC-10 earliest** (durability hazard) |
| **Phase 3** | Go host change + device-only | **FDC-11** (gated S2), **FDC-12** (gated S2) | `go-mknoon/node` libp2p | **device-only** (iOS sim shares host mDNS → forces `DISABLE_LOCAL_DISCOVERY`) |

Phase ordering is a *gating* order, not a hard serial wall — within Phase 2, FDC-10 should actually
land first (see hazard). Phase 3 cannot even be host-validated; it ships behind flags with
device-proof only.

**"Dart-only, no relay/Go deploy" (Phase 0) describes the CODE surface, not production enablement:**
FDC-03's *code* is pure Dart and host-testable, but its **production rollout / inbox-volume ramp is
gated on FDC-10's Redis deploy** (durability hazard above) — Phase 0 can be authored and host-tested
without a relay deploy, but FDC-03 must not reach production volume until FDC-10 is live.

**The UI + reaction plans are not in the phase grid above** (they track by collision file, not deploy
surface — see *Tracks & waves*): **FDC-13** (transport badge) and **FDC-14** (self online-dot) are
host-testable UI (W1/W5); **FDC-15** (1:1 media over libp2p LAN) is **Phase-3 device-only**, after
FDC-11 (gated FDC-11/S2); **FDC-18** (reactions) lands after FDC-03, parallel.

---

## THE COLLISION MAP (must read before scheduling Phase 0)

**FDC-01, FDC-02, FDC-03, and FDC-04 all edit the same production file:**

```
lib/features/conversation/application/send_chat_message_use_case.dart   (1893 lines)
```

- FDC-01 edits the `direct_timeout` / `relayProbeEligible` path (`:701`, `:1483`, `:1500`).
- FDC-02 rewrites the race body + per-leg budgets (`:21`, `:24`, `:48`, `:57`, `:693-703`).
- FDC-03 lifts the inbox out of the low-confidence gate + drops the serial tail (`:608-660`, `:1021-1086`).
- FDC-04 gates the reuse/sticky short-circuit behind `isLocalPeer` (`:447-465`, `:528-595`).

Because they overlap the same hot region of one file, **they MUST run SEQUENTIALLY — never in
parallel agents/worktrees** (a parallel landing would clobber a sibling's uncommitted edits, exactly
the incident class MEMORY warns about).

**Recommended order: FDC-01 → FDC-02 → FDC-03 → FDC-04** — smallest-blast-radius bugfix first
(FDC-01 is a one-path correctness fix that is independently shippable and de-risks the rest), then
the race redesign it sits inside (FDC-02), then the inbox generalization (FDC-03), then warming
(FDC-04, the largest new surface). Each lands, re-greens the 1:1 gate, and commits before the next
starts.

**Precedent (cite this when scheduling):** the app-smoothness structural epic hit the identical
pattern — plans **160 → 161 → 162 → 163 all edit `lib/features/orbit/feed_wired.dart`** and were
explicitly run **sequentially** for exactly this reason (`157-app-smoothness-structural-roadmap.md`
collision column; MEMORY: "feed_wired.dart collision → run 160→161→162→163 sequentially"). FDC
inherits that rule verbatim, substituting `send_chat_message_use_case.dart`.

**Secondary collision (lower-severity, still serialize on overlap):**
`lib/core/services/p2p_service_impl.dart` (4250 lines) is touched by **FDC-04** (`warmPeer`,
`discoverLocalPeer :4132`, `isLocalPeer :4097`) and **FDC-08** (presence-lookup cache,
`probeRelay :4074-4089`). (FDC-05 does **not** edit `p2p_service_impl.dart` — it reorders the call
sites in `handle_app_resumed.dart` + the test fake only.) These land in different phases so natural
sequencing already separates them; if any two are ever co-scheduled, serialize.

**Tertiary collision:** `lib/core/lifecycle/handle_app_resumed.dart` (`:130-191`) is edited by
**FDC-04** (inserts the resume `warmPeer` call-site) and **FDC-05** (un-serializes that exact block
into the parallel re-prime). Serialize, and **prefer landing FDC-05 first** (then FDC-04's resume call slots straight into the parallel block); if FDC-04 lands first per the phase order, rebase FDC-04's
resume `warmPeer` call onto FDC-05's parallel block. (FDC-04 is Phase 0 / FDC-05 is Phase 1, so if
FDC-04 lands first its resume call-site must be re-pointed when FDC-05 restructures the block — see
FDC-04's Step-14 stop-if and FDC-05's Dependency Impact.)

---

## Spike → plan GATING graph

A plan **cannot finalize** (its `/tdd-plan` cannot lock its budgets/mechanism) until its gating
spike resolves. Phase-0 plans have **no spike gate** — they ship first.

```
FDC-S1 (cold-start timing)          ─────────────►  FDC-07   (don't re-time blind)
FDC-S2 (QUIC identify re-validate)  ──┬──────────►  FDC-11   (libp2p LAN-direct dial)
                                      └──────────►  FDC-12   (DCUtR direct upgrade)
FDC-S3 (presence-signal decision)   ──┬──────────►  FDC-08   (relay presence lookup)
                                      └──────────►  FDC-09   (foreground self-publish + push)
FDC-S4 (iOS pause-flush feasibility) ────────────►  FDC-06   (graceful pause-flush)
FDC-S5 (Go-bridge concurrency note) ─ informs ───►  FDC-04, FDC-05  (advisory, no hard gate)
FDC-S0 (baseline + measurement)     ─ bookend ───►  capture BEFORE FDC-01, re-measure at CLOSE (gates nothing)

FDC-11 (LAN device-proof, both OS) ──┬───────────►  FDC-15   (1:1 media over libp2p LAN — peer-auth; gated FDC-11+S2)
                                     └───────────►  FDC-S6   (WS-retirement DECISION — last step)
FDC-15 (media device-proof) ─────────────────────►  FDC-S6   (feeds the media-server retire verdict)
FDC-S6 (retire verdict, per-component) ─ spawns ─►  [WS-chat-removal plan]  (+ WS-media removal once FDC-15 proven)

UNGATED (Phase 0, ship first):  FDC-01, FDC-02, FDC-03, FDC-04
```

FDC-S5 is the only "spike" that gates nothing hard — it is a **design note**, authored first because
its bridge-prioritization contract (user-send > speculative warm/reprime) shapes how FDC-04 and
FDC-05 are written. It opens the MVP cut precisely so the warm work in FDC-04 doesn't head-of-line
block the send it means to accelerate (§10).

---

## DURABILITY-ORDERING hazard (the cross-phase trap)

**FDC-03 raises inbox volume BEFORE FDC-10 makes the inbox durable.** FDC-03 (P0-2) fires a parallel
`storeInInbox` on *every* unknown-presence send instead of only the low-confidence ones — many more
copies land in the relay inbox. But the relay inbox **defaults to the in-memory backend**, which is
**wiped on every relay restart/bounce**. So for the whole window between FDC-03 shipping and FDC-10
shipping, the new high-volume durable-custody copies sit in a **restart-losable** store — the exact
opposite of the "durable inbox = THE guarantee" invariant (§12).

**Recommendation: pull FDC-10 (Redis durable backend) EARLIER — land it alongside or before FDC-03**,
not last in Phase 2. This shrinks the blast radius of a relay bounce during the volume ramp.

**Critical clarification (do not re-scope FDC-10):** this is a **durability** hazard, **not an
idempotency** one. Store-side dedup by `messageId` is **already implemented and correct**
(`backend_memory.go:121-142`, `backend_redis.go:272-295`, `inbox_store.go:7,14`). FDC-10 must
**only** swap the backend + add the relay pool — it must NOT rebuild dedup. Idempotency is fine;
*durability is the single gap* FDC-10 closes.

Concretely, the cross-phase order becomes: **FDC-10 is the one Phase-2 plan allowed to start during
Phase 0/1** (it is additive, server-side, and independent of the Dart send-path collision file), so
the durable backend is live before FDC-03's volume ramp reaches production traffic.

---

## Recommended MVP cut

The smallest end-to-end slice that meaningfully improves the reported "open app → send one message →
close" experience, entirely in **pure-Dart code** and **host-testable** (FDC-03's code is pure Dart,
but its **production rollout is gated on FDC-10's Redis deploy** — see the durability note below):

```
FDC-S5  (bridge-concurrency design note — sets the prioritization contract)
   │
   ▼
FDC-01  →  FDC-02  →  FDC-03  →  FDC-04      (sequential; SAME collision file)
   │
   ▼
/sims reliability run  +  a two-device smoke      ← BEFORE starting Phase 1+
```

Rationale: these four plans delete the perceived window for the common **warm-open** case, fix the
online→inbox **correctness** mis-route (FDC-01), and require **no relay/Go deploy** — so they can
land and ship on host gates faster than anything gated on a spike or a server deploy. FDC-S5 first
because its bridge contract changes how FDC-04 is written. After FDC-04, **do not proceed to Phase 1
on host-green alone** — run the reliability sims and a real two-device smoke, because the live-wins
behavior these plans change is the one thing host fakes cannot honestly prove (see Closure caveat).

Durability ordering within the MVP: because FDC-03 is in the cut, **FDC-10 must be deployed and live
in production before FDC-03's production traffic volume ramps**. Development can proceed in parallel
(server-side, no collision-file overlap), but the durable backend has to be live *before* volume
reaches production — "in flight in parallel" is not enough on its own. See the hazard above.

---

## Parallel execution — tracks & waves (what can run concurrently)

The epic is **not** one sequence. There are **8 collision-bound tracks** (A–H below); only the send-path spine is
strictly serial. Plans in **disjoint file sets** can run in parallel sessions/branches.

**Tracks (serial WITHIN each — the bound file is the reason):**
- **A · 1:1 send-path spine (critical path):** FDC-01→02→03→04 on `send_chat_message_use_case.dart` —
  STRICTLY serial, each on the prior's committed tree, re-green `1to1` between each. **Never parallel.**
- **B · Resume lifecycle:** FDC-05 (`handle_app_resumed.dart`).
- **C · Pause lifecycle:** FDC-06 (`main.dart` pause / `handle_app_paused.dart`; gated S4).
- **D · Go libp2p host (device-only):** FDC-07 → FDC-11 → {FDC-12, FDC-15} on `node.go`/`config.go`/
  `feature_flags.go`; gated S1/S2; FDC-11 before 12/15.
- **E · Relay server (additive):** FDC-10 → FDC-08 → FDC-09 on `inbox.go`/push path; 08/09 gated S3.
- **F · Transport badge UI:** FDC-13 (`letter_card.dart` — the only renderer).
- **G · Self online-dot UI:** FDC-14 (`node_state.dart`/`connection_status_indicator.dart` — isolated).
- **H · Reactions:** FDC-18 (`send_reaction_use_case.dart` — separate file from the spine; **lands after
  FDC-03** to copy its concurrent-inbox pattern; otherwise parallel).

**Wave schedule:**
- **W0 · spikes (concurrent; they gate everything):** FDC-S5 note first (shapes 04/05), then S1/S2/S3/S4
  in parallel. FDC-S6 last (needs FDC-11+15+soak).
- **W1 · 4 CONCURRENT sessions:** Track A (the spine) ∥ FDC-10 (Redis — durable BEFORE FDC-03's volume) ∥
  FDC-13 (badge) ∥ FDC-14 (dot). File-disjoint. → after FDC-04: `/sims` + a two-device smoke before Phase 1.
- **W2 · lifecycle (after S1/S4 + Track A):** FDC-05 (lands before FDC-04's resume warm IF that call has not landed yet; **if FDC-04 already landed in W1/Phase 0, rebase its resume `warmPeer` onto FDC-05's parallel block** — see Tertiary collision), FDC-06 (after S4),
  FDC-07 (after S1). 05∥06 disjoint; serialize 07's `p2p_service_impl` edits behind FDC-04.
- **W3 · relay presence (after S3 + FDC-10):** FDC-08 → FDC-09 (serial on `inbox.go`; FDC-08 also after Track A).
- **W4 · Go host device-only (after S2):** FDC-11 → {FDC-12, FDC-15}; coordinate go-mknoon edits with 07/10.
- **W5 · late wiring + decommission:** FDC-13 outgoing data (after FDC-12 emits the `'upgraded'` Go label),
  FDC-14 `directReady` source (after FDC-02+11), then FDC-S6.

**Cross-track serialization to respect** (never two parallel agents on the same file): `handle_app_resumed.dart`
(04/05/09 → 05 first **preferred**, else rebase FDC-04's resume call when FDC-05 lands if FDC-04 landed first in Phase 0); the pause path (06/09); `p2p_service_impl.dart` (04/07/08/09/12/13 — disjoint regions
but one writer at a time); go-mknoon `node.go`/`config.go` (07/10/11/12/15); relay `inbox.go` (10→08→09); and
the durability rule (FDC-10 before FDC-03 reaches prod volume).

**Net:** parallelize the 4 disjoint W1 tracks; keep the send-path spine and each Go/relay file strictly serial;
let the spike gates pace W2–W5.

---

## Global numbering note

The next-free **top-level** index number in
[`Test-Flight-Improv/00-INDEX.md`](../../00-INDEX.md) is **170** (the last allocated entry is
`169-orbit3-dimension-persistence-tdd-plan.md`). This epic deliberately uses an internal `FDC-NN`
code space and **lives in this `fast-direct-connection/` subfolder**, *not* the flat top-level index
— mirroring the **Group-Chat-Feature** precedent, where the C4-0x / matrix docs live in their own
`Group-Chat-Feature/` subfolder with internal codes rather than consuming top-level numbers.

**Allocation rule:** if/when an individual FDC plan is *promoted* to the top-level index (e.g. it
becomes a headline tracked deliverable), allocate **170, 171, …** at that point and cross-link the
top-level number to its `FDC-NN` doc here. Until promotion, FDC codes are the sole identifiers and
no top-level numbers are consumed.

---

## Closure strategy

> **Improvement scorecard (`FDC-S0`):** the epic's overall *did-we-actually-make-it-faster* proof is
> owned by FDC-S0 — capture its baseline **before** FDC-01 and re-measure at **close** (and per wave).
> The per-plan gates below are the regression/correctness floor; FDC-S0 is the before→after delta.

**Phase 0 — host gates (necessary, not sufficient).** Each of FDC-01..04 closes on:

- `./scripts/run_test_gates.sh 1to1` — the home gate (`send_chat_message_use_case_test.dart`,
  `p2p_service_impl_test.dart`, `handle_app_resumed_upload_ordering_test.dart`,
  `offline_inbox_roundtrip_test.dart` all live here). Expected count: 1226 (capture the green
  baseline before FDC-01 starts; prior 1:1 runs were ~1226).
- `./scripts/run_test_gates.sh transport` —
  `integration_test/{background_reconnect,wifi_relay_fallback_smoke,transport_e2e,media_stable_id_smoke}_test.dart`.
  Expected count: device/fixture-gated (skips on lone sim).
- `./scripts/run_test_gates.sh feed` · `groups` · `baseline` — regression floors. Expected: feed 279 · groups 896 · baseline 112 host.
- `./scripts/run_host_test_gates.sh feature-host-all` (and `core-host-all`) — host floor, 0 fail.
- Hygiene: `flutter analyze` (0 new) · `git diff --check`. **Go-hygiene convention:** `git diff --check` is whitespace/conflict-marker only and is **NOT** the Go analogue of `flutter analyze` — every Go-touching plan (FDC-07/08/09/10/11/12/15) must additionally run `make lint` (gofmt -l + go vet, per-module), and every plan that introduces shared concurrent state must also run `go test -race`.

**Phases 1–3 — host gates PLUS `/sims` + device-proof closure** for the plans whose wins touch a
real wire or a real OS transition: **FDC-04, FDC-06, FDC-07, FDC-09, FDC-11, FDC-12, FDC-15** (plus a
distinct **live-relay-env** closure for **FDC-08** — see below).

- Sims: `./scripts/check_reliability_simulation_discovery.sh` to confirm discovery, then
  `/sims <scope> --only N`. (Sims is a *runner*, never a registrar — new scenarios need a
  `classify_path()` case + a dart-define case in
  `scripts/check_reliability_simulation_discovery.sh` / the harness first.)
- Device-proof: a real two-device pair for "live-wins" / LAN / DCUtR / **media-LAN** claims.
  FDC-11/12/**15** are **device-only** by construction (iOS sim shares a host mDNS stack → forces
  `DISABLE_LOCAL_DISCOVERY`, proposal §6.5). **FDC-09** (visible push-to-wake, access-gated wake,
  self-publish — rows TC-09-20..24) also needs **device** closure (2 devices + real relay + APNs),
  deferred-not-waived if the relay env is unavailable.
- Live-relay-env closure (a *separate* category from device-proof): **FDC-08** (real reservation-truth,
  faster-than-probe, NET-REL-07 additive-deploy safety) closes on a running/deployed relay env via
  `/sims 1to1` (the transport sim scenarios — `transport_e2e_test.dart` / `wifi_transport_test.dart` — are
  discovered under the `1to1` reliability-sim category; there is no `transport` *sim* scope, only the host gate
  `./scripts/run_test_gates.sh transport`), not on host fakes (proposal Phase-2 "live-relay env" column).

**The host-test false-positive caveat (the reason device-proof is mandatory, not optional):** these
plans dedupe by `messageId`. A host fake can therefore make a test **pass via the inbox copy even
when the live/LAN/direct leg never fired at all** — dedup *masks a dead live path* (proposal §9.1:
"a test can pass via dedup even if the live path never fired"; "host-testable ≠ validated"). So for
FDC-04/06/07/11/12, a green host gate proves *delivery*, not *the fast path*. Closure for those plans
**requires** a sims run that asserts the transport label (`local`/`direct` vs `relay`/`inbox`) AND a
device smoke that observes the live path actually winning — never host-green alone.

**Go closure** (FDC-10/11/12 server/host changes): `cd go-mknoon && go test ./...` and
`cd go-relay-server && go test ./...` must stay green; **FDC-10's Redis cross-process durability proof
is build-tagged → ALSO run `cd go-relay-server && go test -tags integration ./...`** (the
`redis_failover_integration_test.go` / `TestRedisControlPlaneSharedAcrossProcesses` test carries
`//go:build integration` and does NOT run under plain `go test ./...`). Additive only (NET-REL-07 — shipped clients
have a hardcoded relay and no version negotiation). **Go decomposition convention:** new Go feature logic goes in its own `node/<concern>.go` or a new `bridge_<concern>.go`; only minimal registration/teardown may touch `node.go` `Start`, the 2878-line `bridge.go`, or the relay `HandleInboxStream` switch.

**Harness registration reminder:** `test/features|core|performance/**` AUTO-globs; any curated
1to1/feed/groups/transport headline test these plans add must be appended to the read-only array in
`scripts/run_test_gates.sh`, or it will silently not run in the gate.

---

## Open questions carried from the proposal (§11) — resolve via the spikes

1. iOS cold notif-tap: **where is `peerId` first available**, and can `warmPeer` fire before the
   Flutter engine/chat screen builds (NSE vs main isolate)? → informs **FDC-04** scope.
2. Presence signal: relay-lookup (deploy) vs gossipsub beacon (churn) vs status-push? How to
   self-publish foreground? → **FDC-S3** → FDC-08/09.
3. Measured cold-open time-to-circuit-address + time-to-first-mDNS-resolve on real devices →
   **FDC-S1** → FDC-07.
4. Unify the two LAN stacks (bonsoir discovery → libp2p LAN-direct dial) or keep parallel with dedup? Gated on the QUIC-identify
   re-validation → **FDC-S2** → FDC-11.
5. Can the relay ship additive presence + Redis without breaking older clients (NET-REL-07)? Is the
   live relay env reproducible from-repo for validation? → FDC-08/FDC-10.
6. iOS pre-suspension budget for the pause-flush — how many in-flight sends must it cover? →
   **FDC-S4** → FDC-06.

---

## Known gaps from the design Q&A review (2026-06-26)

A 7-question review of the design against live code surfaced these. Q2/Q3/Q5 were confirmed sound
(no change). The rest:

- **LAN-direct dial via bonsoir (RESOLVED in FDC-11).** Both iOS and Android use **bonsoir for
  discovery** (uniform stack); bonsoir feeds the LAN address into the libp2p host for the dial. No
  libp2p-native `mdns.NewMdnsService` is registered on either platform — bonsoir discovery is the sole
  discovery source feeding the libp2p LAN-direct dial (on Android a libp2p-native mDNS would be a
  redundant second mechanism; on iOS raw multicast is entitlement-blocked anyway). FDC-11 carries a
  unified discovery + dial design (no platform-split). The iOS Local-Network permission
  (`NSLocalNetworkUsageDescription`) and background-multicast-drop caveats remain. (Contradiction in an
  earlier verbal explanation, now fixed.)
- **GAP — relay→direct "upgraded" badge.** The per-message transport badge already exists for
  **wifi/direct/relay/inbox** (plan-155 `transportStatusGlyph`, `letter_card.dart`), and the design
  reuses it — but a **relay→direct upgrade** currently folds into the plain `"direct"` badge
  (`_inferTransportForPeer` → `"direct"`); the upgrade is only counted in the **debug** diagnostics
  card. **FDC-13 (authored)** adds an `"upgraded"` transport value + a distinct `Icons.upgrade` glyph +
  `message_*_via_upgraded` a11y in the conversation `letter_card.dart`. Two facts from its grounding:
  **(O2)** there is **no feed `message_bubble` transport twin** — the feed Letters bubble renders no
  transport glyph, so `letter_card` is the only renderer; **(O1)** FDC-13 ships the **incoming** upgraded
  render now (host-testable via a synthetic `transport:upgraded` event), but **outgoing**
  upgraded-from-production-data needs the Go stream to emit an `"upgraded"` label → **gated on FDC-12**.
- **SCOPE NOTE — media byte-path unaffected.** FDC routes media correctly at the **envelope** layer
  (FDC-02 `_liveRelayEligible` gate: media never over the 2min/128KB live relay → direct-or-inbox), but
  the media **byte** transfer (LAN HTTP-PUT `local_media_sender.dart`, relay-CDN `media.go`, inbox)
  stays on the **existing dedicated channels** and is **out of scope** for the new libp2p/mDNS/DCUtR
  roads (which carry only the chat envelope). Preservation floor: re-run
  `integration_test/media_stable_id_smoke_test.dart` (already in `TRANSPORT_TESTS`) as a Phase-0 gate
  after FDC-02/04 to prove media bytes still deliver.
- **GAP — the self "online" green dot.** `ConnectionStatusIndicator` (driven by
  `NodeState.badgeReadinessState`: grey=offline / amber=connecting / green=send+inbox-ready / green-dot=
  also relay-reserved) is **untouched** by any plan, yet FDC-05/06/07 move the very lifecycle timings
  that drive it. **(a)** FDC-05/06/07 each must carry a **"no badge-transition flap"** acceptance note
  (assert no spurious `connecting` flap on resume/pause/cold-start). **(b)** The design adds a NEW axis
  the dot does not express — **"reachable for a direct connection"** (LAN/DCUtR). Keeping the dot
  inbox/relay-based is fine; if the product wants it to mean "directly reachable," **FDC-14 (authored,
  DRAFT)** adds a new `BadgeReadinessState.onlineDirect` tier + a `NodeState.directReady` input + the
  anti-flap test. The new-tier render + anti-flap are host-testable now; the `directReady` **signal
  source is gated on FDC-02/FDC-11** (provisional until they land). The anti-flap notes are now in
  FDC-05/06/07. Peer-presence (FDC-08/09) is a **different** axis and never feeds this dot.
- **SCOPE NOTE — 1:1 reactions are a SEPARATE path (out of scope).** Emoji reactions use
  `send_reaction_use_case.dart` → the thin `p2pService.sendMessage()` + a manual `storeInInbox()`
  fallback — **not** `send_chat_message_use_case.dart`. So reactions inherit **none** of FDC-01/02/03/04's
  orchestration wins (per-step budget, ranked race, concurrent inbox); the same latent slow-online-peer
  misroute FDC-01/03 fix for chat also affects reactions, **unfixed**. They DO transitively benefit from
  the Go/transport plans (FDC-08..12) below the shared `callP2PMessageSend`. **No regression risk** —
  reactions are a separate use case and the shared `sendMessage`/`storeInInbox` are dependency-only (not
  edited by any FDC plan); if a future plan ever edits those, add a reaction round-trip guard. FDC-13
  'upgraded' badge = **N/A** (reactions carry no transport field). Reaction send reliability is now **FDC-18 (authored)** — it mirrors only FDC-03's concurrent durable
  inbox onto `sendReaction` (the reaction path has a SINGLE transport leg → FDC-01/02's race/budget are
  N/A); lands after FDC-03, separate file, parallelizable.

---

## Scope: 1:1 messaging — group-safety mandate (2026-06-26)

The **entire epic is scoped to 1:1 messaging**; group messaging must not regress. Two tiers:

- **1:1-use-case plans** (own the 1:1 send/UI path only; group uses a SEPARATE use case): FDC-01, 02,
  03 (`send_chat_message_use_case.dart` — group = `send_group_message_use_case`), FDC-13/14 (1:1 UI /
  self-dot). Naturally 1:1-exclusive.
- **Shared-host / relay plans** (touch the libp2p HOST or relay that group members ALSO use → NOT
  1:1-exclusive, must be group-SAFE): FDC-04, 05, 06, 07, 08, 09, 10, 11, 12, 15. Each now carries a
  **hard Scope-Guard bullet** forbidding any change to group behavior + a **group-safety floor**
  preservation gate (`./scripts/run_test_gates.sh groups` for Dart-touching plans; `pubsub_delivery_test.go`
  / group Go tests via `go test ./...` for Go-host plans).

**Highest risk — FDC-11 & FDC-12:** they change how the shared libp2p host **connects to every
same-WiFi peer including group members** (FDC-11 `HandleLanPeerFound`→`host.Connect`) and **re-point
shared connections** (FDC-12 DCUtR). Their `pubsub_delivery_test.go`-green floor is **mandatory** — the
new LAN dial / upgrade must be additive and leave group pubsub connection behavior unchanged.

**No group send / UI / media path is modified anywhere in the epic.** Group media stays on its own
relay-CDN path; FDC-15 adds the libp2p-LAN media leg to the **1:1 path only**.

---

## Move-feature (account-migration) interaction (2026-06-26 review)

The account-move feature suppresses **all** network side-effects through one central gate —
`_allowsAccountNetworkSideEffects` (`p2p_service_impl.dart:394`), backed by
`AccountMigrationRuntimeNetworkGate` (`migrationExportingNetworkPaused`/`migratedOut`/fail-closed →
false). Every existing wire primitive already calls it (warmBackground/send/discover/dial/storeInInbox/
retrieve/healthCheck/drain/probeRelay/discoverLocalPeer/startNode/registerPushToken); the move-account
**inbox-ack skip** is at `:1601-1618`; the whole resume path is gated at `handle_app_resumed.dart:114`;
the **pause** path (`main.dart:4314-4316`) is local-DB-only and **ungated**.

- **Inherited-safe (ride existing gated primitives — no new ungated wire op; no fix needed):** FDC-02
  (race), FDC-03 (concurrent inbox → `storeInInbox` gated), FDC-05 (resume re-prime → whole-resume
  gated), FDC-06 (pause-flush → `storeInInbox` gated), FDC-07 (cold-start → `startNode` gated). **FDC-04** (warmPeer) explicitly calls the gate — the model.
- **FIXED — FDC-11 (bonsoir-fed LAN dial):** `HandleLanPeerFound`→`host.Connect` is a NEW Go-side wire op
  driven by the **continuous** bonsoir peer-found stream — node-start gating does **not** cover a migration
  that begins while the node is already running (peer-found keeps firing; the Go handler never consults the
  Dart gate). The Dart-side `bonsoir-peer-found` bridge forwarder now **REQUIRES**
  `_allowsAccountNetworkSideEffects('p2p_lan_dial')` before crossing to Go (added to FDC-11's move-feature
  gate bullet + a RED lock; parallels FDC-04/08/09).
- **FIXED — FDC-08 (presence lookup):** `lookupRelayPresence` is a NEW ungated relay primitive on the
  (top-ungated) send path → now **REQUIRES** `_allowsAccountNetworkSideEffects('p2p_presence_lookup')`
  (added to FDC-08 Real Scope + a RED lock).
- **FIXED — FDC-09 (self-publish):** `presence_set{background}` fires from the **ungated pause path**
  (`main.dart:4314`) → would announce the moving device as online mid-move; `setPresence` now
  **REQUIRES** the gate (`p2p_set_presence`) so both pause and resume are suppressed (added to FDC-09
  Real Scope + a RED lock).
- **Low RISK — FDC-03 vs the move ack-skip:** during a recipient's move, inbox copies are intentionally
  **not** acked (`:1601-1618`) so the new device can still fetch them → they linger to the 7-day TTL;
  FDC-03 multiplies those copies. Bounded by 7d TTL + `messageId` dedup. **FDC-10** (Redis) sizing
  should be aware of it; not blocking.
