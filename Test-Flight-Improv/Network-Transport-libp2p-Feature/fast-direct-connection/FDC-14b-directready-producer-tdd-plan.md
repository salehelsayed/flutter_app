# FDC-14b — Wire the `NodeState.directReady` producer (Dart direct-conn aggregate, dark)  (New Feature + Modification)

Status: **IMPLEMENTED + host-verified 2026-06-27** (Route B; all named gates green; P-7 BLOCKER
mutation-proven; 3-agent adversarial review all-`correct`; device-proof DEFERRED / flag-gated dark).
Originally REVIEWED 2026-06-27 (adversarial verify→refute); BLOCKER **RESOLVED → Route B chosen**
(Go-authoritative per-connection `isRelay` flag, see §Review Findings 🔴 + D8), multi-layer (Go + Dart).
Spec: free-text intent (no formal spec) — the unowned follow-on deferred by
`FDC-14-online-dot-directly-reachable-tdd-plan.md` (§Open Issues → FDC-14b). Design decisions locked with
the user 2026-06-27 (see §Design Decisions).

> ⚠️ **The locked Q1/Q2 below were REVISED by the 2026-06-27 review — read §Review Findings first.** The
> BLOCKER forced **Route B** (a small Go change surfacing per-connection `isRelay`); Q1's "no Go change" no
> longer holds. The directReady aggregate is still computed **in Dart** in `_emitState` (Q1 spirit intact),
> but now reads the authoritative Go `isRelay` flag to exclude the node's own relay-server socket.
>
> **Scope posture (user-chosen 2026-06-27):** **(Q1) Source = Dart-side direct-connection aggregate** —
> `directReady` is computed in `p2p_service_impl._emitState` from the node's own connection set (≥1 live
> NON-circuit connection), mirroring the existing `_inferTransportForPeer` circuit-precedence convention;
> **no Go change.** **(Q2) Build the full producer now, dark** — wire it + the genuinely-needed predicate
> fix + host tests driving it via real connection events. It stays inert in a default prod build (the
> FDC-11/FDC-12 direct-path flags default OFF) but is fully mutation-verified and ready for when those
> flags flip. See §Reachability Reality Check for the "mostly dark, may light up on LAN" nuance.

---

## Review Findings (adversarial verify→refute, 2026-06-27 — READ FIRST)

A 4-agent verify→refute pass + direct source re-grounding (HEAD is now `017a95db`, two commits
**past** the plan's `5f21d790` base, with `p2p_service_impl.dart` dirty at `+387/-14` vs that base — so
all `p2p_service_impl.dart` anchors were re-checked live). Anchors held **except** the two noted in F-LOW-2.
One finding is a **BLOCKER that inverts the "ships dark" premise** and forces the locked Q1/D1 decision
back open.

### 🔴 BLOCKER — the producer is NOT dark; D1 lights `onlineDirect` for EVERY online node
**Verified in Go (`go-mknoon/node/node.go`):**
- `:1846-1875` — on `EvtPeerConnectednessChanged{Connected|Limited}`, **every** peer is written to
  `n.connections[pid]` with `Address = conns[0].RemoteMultiaddr().String()`. The node's own connection
  **to the relay server** is a *direct* dial to the relay's IP, so its `Address` is a **non-`/p2p-circuit`
  multiaddr** (e.g. `/dns4/relay/tcp/4001`, `/ip4/<relay>/udp/.../quic-v1`). It is **not** `Limited`
  (only peer-through-circuit connections are `Limited`; the relay-server socket is a full direct conn).
- `:658-664` — `Status()` returns **all** `n.connections` (peerId/address/direction) with **no relay
  filter** and does not surface the `Limited` flag it tracks.

⇒ Every relay-connected (i.e. every "online") node holds ≥1 direct, non-circuit connection — the
**relay-server socket itself**. The plan's predicate (D1: "≥1 connection with a non-`/p2p-circuit`
multiaddr ⇒ directReady") therefore returns **true for all online nodes**, immediately, with FDC-11/12
flags OFF. This **falsifies §"Build the full producer now, dark"**, would flip the production self-badge to
`onlineDirect` for everyone, and would **time out** the integration/device waiters
`waitForRelayReadyBadge`/`waitForPlainOnlineBadge` + `_isRelayReady`/`_isPlainOnline` (they wait on
`==onlineDotted`/`==online`, which the node would now skip). The plan's P-2 scope-guard only excludes
`/p2p-circuit`-*addressed* connections — it never excludes the **direct relay-server socket**, so it does
not catch this.
**Why neither existing helper hit this:** `_inferTransportForPeer` (`:3461`) and FDC-15
`hasNonCircuitDirectConn` (`:4697`) are **per-peer** (called only about a specific message-sender / media
peer), so they are never asked about the relay. The directReady **aggregate** is the first consumer to scan
*all* connections — this bug is new to the aggregate.

**Fix — ✅ RESOLVED: USER chose Route B (Go-authoritative per-connection relay flag), 2026-06-27.**
Go already has every piece needed — `func (n *Node) isRelayPeer(pid) bool` (`node.go:1938-1943`, membership
in `n.relayPeerOrder`) and a `connectionInfo.Limited` field (`:138-143`) to model an `IsRelay` flag on. The
bridge is **event-map passthrough** (`go_bridge_client.dart:658` parses the verbatim Go event via
`ConnectionState.fromJson`; `node:status` connections use the same `fromJson`), so **no native Swift/Kotlin
change is required**. Concrete seams (see D8):
1. **Go** — add `IsRelay bool \`json:"isRelay,omitempty"\`` to `connectionInfo` (`node.go:138-143`); set
   `IsRelay: n.isRelayPeer(e.Peer)` where the conn is built (`:1870-1875`); emit `isRelay` in the
   `peer:connected` event (`:1877-1882`) AND the `Status()` connections map (`:658-664`).
2. **Dart `ConnectionState`** (`connection_state.dart`) — add `final bool isRelay` (default false),
   `json['isRelay'] == true` in `fromJson`, carry in `toJson`/`copyWith`.
3. **Dart `_computeDirectReady`** — `connections.any((c) => !c.isRelay && _connHasDirectAddr(c))`.

This keeps directReady **Dart-derived and fresh on every emit** (the `isRelay` flag rides each
`peer:connected` event, so no node-level-bool staleness — superior to a Go-computed node-level
`directReachable`, which would only refresh on `node:status` polls and lag the connection events P-1/P-3
drive). The predicate is now provably correct for all three connection types: relay-server
(`isRelay:true` ⇒ excluded), peer-via-circuit (`isRelay:false` + circuit addr ⇒ excluded by
`_connHasDirectAddr`), peer-direct (`isRelay:false` + direct addr ⇒ **included**). **Do NOT land the producer
until P-7 (relay-only node stays `onlineDotted`) + TG-1 (Go `isRelay` flag) are GREEN.**

### Other findings (integrated into the sections below)
| # | Sev | Finding | Section patched |
|---|---|---|---|
| F1 | HIGH | **`hasNonCircuitDirectConn` (`:4697`) already exists** with the *opposite* (direct-presence / `any(non-circuit)`) convention and a comment **explicitly rejecting** the `_inferTransportForPeer` mirror D1 adopts. There are **two** conventions, not "the established convention"; for a single ConnectionState holding *both* a circuit and a direct addr they **disagree** (D1⇒false, FDC-15⇒true). Reconcile + factor one shared per-connection predicate. (The convention divergence itself is **low** in prod — conns are single-address per the convention-reuse agent — but the inconsistency between media-lane and badge is real.) | D7 (new), Step 2 |
| F2 | HIGH | **D3 "unconditional emit" is overstated.** `_stateMeaningfullyChanged` (`:3488-3500`) does **not** compare `directReady` and compares `connections.`**`length`** only (`:3493`), not multiaddr content. A directReady flip that does **not** change connection count (in-place circuit→direct, reconciled only via the *guarded* `node:status` poll at `:3637/:3684`) is **suppressed** ⇒ stale/lying badge. Count-changing writers (`peer:connected/disconnected`, start/stop) are the only unconditional ones. | D3 (reworded), Risks |
| F3 | HIGH | **D4 mislabels the T10 fixture as "relay-typed".** node_state_test.dart T10 (`:413-427`) injects a **DIRECT** `/ip4/192.168.1.1/tcp/4001` multiaddr with explicit `directReady:false`, asserting `onlineDotted`. It stays green via **model/producer layer separation** (the producer in `_emitState` never runs on a directly-built `NodeState`), **not** because the addr is circuit. T10's invariant ("a relay/peer socket ≠ direct self-reachability", `:425-426`) is exactly the BLOCKER restated. | D4 (corrected), PS-4 |
| F4 | MED | **Step 0a aims at the wrong fixtures.** `p2p_service_impl_test.dart:957/:1015` assert message **`transport:'direct'`** (`:988/:1035`), **not a badge** — they are a red herring (hit the plan's own "asserts nothing badge-related ⇒ no change" branch). All badge-asserting host tests (`:4500-5000`) use **empty** connections ⇒ safe. The genuine residual surface is (a) the model T10 (F3) and (b) the integration/device waiters (BLOCKER). | Step 0a, Risks, Files-To-Inspect |
| F5 | MED | **P-2 omits both divergence cases:** no test for (a) the relay-socket case (BLOCKER ⇒ P-7) and (b) a single connection with *both* a circuit and a direct addr (F1 ⇒ P-8). | RED catalog (P-7, P-8) |
| F6 | MED | **Reachability Reality Check is wrong on two points:** `p2p_lan_discovery` is the *account-migration side-effect* gate (`_allowsAccountNetworkSideEffects`, true in normal prod), **not** a directReady source; and `_currentState.connections` is sourced **only** from Go `node:status`, whose direct-peer multiaddrs come from FDC-11 `host.Connect` (gated by `EnableLibp2pLANDial` default FALSE). The legacy WS/bonsoir LAN path is a separate Dart transport that likely never populates `node:status`. So onlineDirect is **fully dark for genuine peers** in default prod — *the only thing that lights it is the relay-socket BLOCKER*. | Reachability Reality Check |
| F7 | LOW | **Step 3 pseudocode is not literally implementable.** Real `_emitState` is a single `_currentState = mergeServiceOwnedReadiness ? _stateWithReadinessProjection(newState) : newState;` then `add(_currentState)` (`:3187-3192`) — no separate `projected`/`withDirect` var. Fold directReady **into** the `_currentState =` assignment and apply on **both** branches (the `mergeServiceOwnedReadiness:false` path must also recompute). This is what makes `nowRelayReadyBadge` (`:3219`, read off `_currentState` *after*) correctly read `onlineDirect`. | Step 3 |
| F8 | LOW | **Anchor drift:** `_handlePeerConnected` is `:3919` (plan cites `:3930` = the inner emit line), `_handlePeerDisconnected` is `:3934` (plan `:3948`). `_emitState:3176`, `_inferTransportForPeer:3461`, `:3185/:3219`, `:2579`, gates `:192/829` all verified accurate. | Source Of Truth |
| F9 | LOW | **`_isSendable` twin is untested** (its file `background_reconnect_test.dart` is `@Tags(['device'])`, never in host gates) — a regression there is invisible to `1to1`/`core-host-all`. Consider making `_isSendable` delegate to the shared `isSendableBadgeState` so F-1 covers both. | Risks, Step 4 |

**Confirmed CORRECT (do not re-investigate):** node_state.dart anchors `:28/:44/:84/:161/:167`;
`node_readiness.dart` is host-importable (no flutter_driver import) ⇒ Step 0b passes; P-4 gate ordering
(`:163` usabilityReady **before** `:167` directReady); harness auto-registration (p2p_service_impl_test in
`ONE_TO_ONE_TESTS` + core-host glob; new predicates file auto-globs); no new exhaustive-switch break
(`onlineDirect` already handled everywhere incl. `background_reconnect_test.dart:55`); round-trip safe (no
prod caller of self `toJson`); `relayLiveSendCount` still absent (D2 holds); injection point (after
projection, before `add`) is the correct seam.

---

## Design Decisions (locked — grounded 2026-06-27, file:line verified)

- **D1 — directReady source = node-self direct-connection aggregate, in Dart.** Set `directReady=true`
  iff `NodeState.connections` contains ≥1 connection that holds a **direct** (non-empty, non-`/p2p-circuit`)
  multiaddr **to a non-relay peer** (⚠️ the "non-relay peer" qualifier is the BLOCKER fix, implemented via the
  Go `isRelay` flag per **D8/Route B** — the original D1 omitted it and would light `onlineDirect` for every
  online node via the relay-server socket). Computed centrally in `_emitState` (`p2p_service_impl.dart:3176-3192`), the SOLE
  writer to the state stream (`_stateController.add` at `:3191`). The per-addr direct test mirrors
  `_inferTransportForPeer` (`:3461-3486`): a multiaddr is direct iff `isNotEmpty && !contains('/p2p-circuit')`.
  ⚠️ **Convention caveat (see D7 + §Review Findings F1):** a *second*, newer helper
  `hasNonCircuitDirectConn` (`:4697`) answers the same "is there a direct path" question with the
  **opposite** per-addr rule (`any(non-circuit)` instead of circuit-precedence) and a comment explicitly
  rejecting the `_inferTransportForPeer` mirror. Pick one convention and factor it (D7); the divergence only
  matters for a single connection holding *both* a circuit and a direct addr (rare — conns are single-address
  in prod).
- **D2 — why NOT the sources the FDC-14 comment named.** Grounding refuted them: `relayLiveSendCount`
  **does not exist** (it was a hypothetical in the FDC-14 review memory; the only real artifact is
  `RelayLiveSendObserver.noteRelayLiveSendStart()`, a fire-once `void` not even implemented by
  `p2p_service_impl` in prod). And **every** transport signal crossing the bridge
  (`transport:upgraded/downgraded`, `_peersUpgradedToDirect`, `_learnedTransport`, `holepunch:success`) is
  **per-peer** ("I have a direct leg *to peer X*") → using any of them as the self-dot source is exactly the
  `connections.isNotEmpty → directReady` inference **FDC-14 T10 locks RED**.
- **D3 — directReady is a SERVICE-OWNED DERIVED field** (like `sendCapabilityReady`/`inboxCapabilityReady`):
  recomputed inside `_emitState` whenever it fires, never persisted, never trusted from `fromJson`. The Go
  bridge never emits a `directReady` key, so the `fromJson` value (`node_state.dart:84`) is always false and
  is **overwritten** by the computed value.
  ⚠️ **CORRECTED (F2):** D3 originally claimed "the only directReady-changing events emit unconditionally" —
  **overstated.** `_stateMeaningfullyChanged` (`:3488-3500`) does **not** compare `directReady` and compares
  `connections.`**`length`** only (`:3493`), never multiaddr content. Precise statement: the
  **count-changing** writers (`_handlePeerConnected`/`_handlePeerDisconnected` at `:3919/:3934`, start/stop)
  emit **unconditionally** and carry a fresh connection set ⇒ directReady is correctly recomputed for the
  shipped scope (a direct peer appearing/dropping always changes the count). **LIMITATION:** a directReady
  flip that does **not** change `connections.length` — i.e. an *in-place* circuit→direct change on the same
  connection, reconciled only via the **guarded** `node:status` health-check poll (`:3637/:3684`) — is
  **suppressed** by the length-only guard, leaving the badge stale (or lying `onlineDirect` on a same-count
  in-place downgrade). Resolve by **(A)** extending `_stateMeaningfullyChanged:3493` to deep-compare
  connection multiaddr content, **or (B)** declaring same-count in-place upgrades out of scope (they are the
  FDC-12 `_peersUpgradedToDirect` territory the plan already lists as a follow-on; the fresh-LAN-dial case
  *does* change the count and is covered). NB: simply adding `directReady` to the guard does **not** work —
  `freshState.directReady` is the `fromJson` `false` (`:84`), read *before* the producer recomputes inside
  `_emitState`.
- **D4 — refine FDC-14 T10 wording, do NOT weaken it.** T10's forbidden inference stays RED. Because the
  producer now legitimately reads `connections`, T10's prose is refined from "*any* connection ⇒ not
  directReady" to "*a CIRCUIT/relay* connection ⇒ not directReady". The new producer-tier guard P-2 carries
  the "non-circuit specifically" lock; **P-7 (new)** carries the "relay-server socket specifically" lock.
  ⚠️ **CORRECTED (F3):** D4 originally stated "T10's own fixture peer is relay-typed" — **wrong.** T10
  (`node_state_test.dart:413-427`) injects a **DIRECT** `/ip4/192.168.1.1/tcp/4001` multiaddr with explicit
  `directReady:false`, asserting `onlineDotted`. T10 stays GREEN not because the addr is circuit but because
  it is a **model-layer** test that builds `NodeState` *directly* — the producer lives in `_emitState` and
  never runs on a directly-built `NodeState`, so the stored `directReady:false` is what the getter reads.
  T10's invariant ("a relay/peer socket must not imply direct self-reachability", `:425-426`) is precisely
  the BLOCKER restated — honor it in the producer (D1's "non-relay peer" qualifier), don't just rely on layer
  separation.
- **D7 — reconcile with the existing `hasNonCircuitDirectConn` (F1).** FDC-15 already shipped
  `hasNonCircuitDirectConn(peerId)` (`:4697-4706`): a **per-peer** "does this peer hold a direct path" test
  using `connections.any((c) => c.peerId==peerId && c.multiaddrs.any((m) => m.isNotEmpty &&
  !m.contains('/p2p-circuit')))`, with a doc comment (`:4691-4696`) **deliberately not reusing**
  `_inferTransportForPeer` because its circuit-precedence "false-negates the coexisting relay+direct case."
  The producer must NOT introduce a third, contradictory definition. **Factor one shared per-connection
  predicate** — e.g. `static bool _connHasDirectAddr(ConnectionState c)` — and have BOTH
  `hasNonCircuitDirectConn` and `_computeDirectReady` call it. ⚠️ Reusing FDC-15's *inner* predicate is
  necessary but **not sufficient** for the aggregate: FDC-15 is per-peer and never sees the relay, so the
  aggregate still needs the **relay-peer exclusion** (BLOCKER / D1) on top. Decide the mixed-addr convention
  once here (circuit-precedence vs `any(non-circuit)`) and apply it in the shared helper.
- **D8 — BLOCKER fix = Route B (Go-authoritative per-connection `isRelay`), LOCKED 2026-06-27.** The producer
  excludes the node's own relay-server socket by reading an authoritative `isRelay` flag that Go stamps on
  each connection (Go owns relay identity via `isRelayPeer`/`relayPeerOrder`). Final predicate:
  `directReady = connections.any((c) => !c.isRelay && _connHasDirectAddr(c))`. Correct for all three
  connection types — relay-server (`isRelay:true`→excluded), peer-via-circuit (`isRelay:false` + circuit
  addr→excluded by `_connHasDirectAddr`), peer-direct (`isRelay:false` + direct addr→**included**).
  - **Go seam** (`go-mknoon/node/node.go`): `connectionInfo` += `IsRelay bool \`json:"isRelay,omitempty"\``
    (`:138-143`); set `IsRelay: n.isRelayPeer(e.Peer)` at the conn build (`:1870-1875`); add `isRelay` to the
    `peer:connected` emit (`:1877-1882`) and the `Status()` connections map (`:658-664`). Uses EXISTING
    `isRelayPeer` (`:1938-1943`) — no new relay-tracking. **Timing VERIFIED SAFE:** `n.relayPeerOrder` is set
    synchronously at start config (`:321/:328`, from the configured relay addresses) **before** the host
    connects to any relay, so the relay-server `EvtPeerConnectednessChanged` always sees `isRelayPeer → true`
    (no false-`isRelay:false` window). GOTOOLCHAIN=go1.25.0 for go tests
    ([[feedback_go126_quicgo_session_ticket_panic]]).
  - **Bridge:** NONE. `peer:connected` and `node:status` both deserialize via `ConnectionState.fromJson`
    (`go_bridge_client.dart:658/672`; `node:status` connections likewise) from the verbatim Go event map, so a
    new JSON key flows through without a native (Swift/Kotlin) edit.
  - **Dart model** (`connection_state.dart`): add `final bool isRelay` (default false), `json['isRelay'] ==
    true` in `fromJson`, carry through `toJson`/`copyWith`. (Today the model drops both `limited` and
    `isRelay`; we add only `isRelay`.)
  - **Freshness:** chosen over a Go node-level `directReachable` bool precisely because the per-connection
    flag rides each `peer:connected`/`peer:disconnected` event, so the Dart producer stays fresh on event
    paths (P-1/P-3) — a node-level bool would only refresh on `node:status` polls and re-introduce the F2
    staleness in a worse form.

## Source Of Truth
- Intent: `FDC-14-online-dot-directly-reachable-tdd-plan.md` §Open Issues → "FDC-14b PRE-WORK".
- Design proposal: `Network-Arch/Fast-Direct-Connection-Architecture-Proposal.md` §6.3/§6.5/§7
  ("directly reachable" = self holds a non-relay path).
- Gate definitions: `scripts/run_test_gates.sh` (`ONE_TO_ONE_TESTS` lists `p2p_service_impl_test.dart`).
- Live code (verified by Read 2026-06-27 on committed HEAD `5f21d790`):
  - `lib/core/services/p2p_service_impl.dart:3176-3192` — `_emitState`, the SOLE state-stream writer.
  - `:3461-3486` — `_inferTransportForPeer`, the circuit-precedence convention to mirror.
  - `:3919 / :3934` — `_handlePeerConnected/_handlePeerDisconnected` defs (unconditional emit at the inner
    `:3930 / :3948` `_emitState` calls; the count-changing directReady events — see F2/D3 for the limitation).
  - `go-mknoon/node/node.go:1846-1875` — relay-server + every peer written to `n.connections` with a
    direct `RemoteMultiaddr`; `:658-664` — `Status()` returns all connections, no relay filter (the BLOCKER).
  - `lib/core/services/p2p_service_impl.dart:4697-4706` — FDC-15 `hasNonCircuitDirectConn` (the existing
    per-peer direct test to reconcile with — D7).
  - `:3184-3185 / :3218-3219 / :3248-3252` — `wasRelayReadyBadge`/`nowRelayReadyBadge` gate of the
    `TIME_TO_RELAY_READY_BADGE` flow event.
  - `lib/features/p2p/domain/models/node_state.dart:28` (`directReady` field, default false `:44`),
    `:161-171` (`badgeReadinessState` already consumes directReady → `onlineDirect`).
  - `lib/features/p2p/domain/models/connection_state.dart:2-7` — `ConnectionState{peerId, List<String> multiaddrs, direction, status}`.
  - `go-mknoon/node/feature_flags.go:36/51` — `EnableLibp2pLANDial` (default FALSE) / `EnableDcutrUpgrade`
    (default FALSE).
- Numbering: this is `FDC-14b` (sibling of FDC-14 in `fast-direct-connection/`), tracked in
  `FDC-00-roadmap.md`, NOT a `00-INDEX.md` NN.

## Session Classification
Implementation-ready, **multi-layer (Route B / D8)**. **New Feature** (the directReady producer) **+
Modification** (Go `isRelay` flag + `ConnectionState` model field + 1 predicate fix). Go host-testable
(TG-1, GOTOOLCHAIN=go1.25.0) + Dart host-testable via injected `peer:connected` events with
direct/circuit multiaddrs and `isRelay`. **No native (Swift/Kotlin) change** (bridge passthrough). No DB
migration. Device-proof is the (deferred) closure gate for the live ✦ badge.

## Execution Progress

- `2026-06-27 20:41:59 CEST` — contract extracted. Scope is Route B only:
  Go per-connection `isRelay`, Dart `ConnectionState.isRelay`, Dart-derived
  `_computeDirectReady` in `_emitState`, shared direct-addr predicate reused by
  `hasNonCircuitDirectConn`, sendable predicate updates, FDC-14/T10 prose
  preservation, focused host/Go tests. Required evidence: `GOTOOLCHAIN=go1.25.0
  go test ./node/...`, targeted Flutter tests for `connection_state`,
  `p2p_service_impl`, `node_readiness_predicates`, `node_state`, indicator
  tests, `1to1`, `core-host-all`, `flutter analyze`, `git diff --check`.
  Dirty-tree note: `node.go`, `p2p_service_impl.dart`, and the FDC-14 doc were
  already modified before this execution; edits must stay narrowly around the
  FDC-14b seams and preserve existing FDC-15/local work.
- `2026-06-27 20:41:59 CEST` — Executor spawned (`Mendel`,
  `019f0a63-d4f6-7c21-acda-5d58fc929896`) with bounded ownership of the
  FDC-14b Go/Dart/test/doc seams. Current phase: executor running. Next action:
  inspect harness shape and wait for executor completion evidence.
- `2026-06-27 20:43:21 CEST` — local Executor fallback started in this
  Codex session because nested spawned-agent tooling is unavailable here.
  Contract re-extracted from this plan; graphify-arch query returned the live
  anchors `_emitState`, `hasNonCircuitDirectConn`, `ConnectionState`, and
  `NodeState.directReady`. Current dirty-tree guard: `node.go`,
  `p2p_service_impl.dart`, and the FDC-14 doc already contain unrelated/local
  edits, so all changes will be additive/narrow around Route B. Next action:
  add focused RED/guard tests for TG-1, CS-1, P-1..P-8, and F-1/F-2 before
  production edits where practical.
- `2026-06-27 21:02:42 CEST` — Executor implementation complete for Route B.
  Files touched for this plan: `go-mknoon/node/node.go`,
  `go-mknoon/node/node_test.go`, `lib/features/p2p/domain/models/connection_state.dart`,
  `lib/core/services/p2p_service_impl.dart`,
  `integration_test/_support/node_readiness.dart`,
  `integration_test/background_reconnect_test.dart`,
  `test/features/p2p/domain/models/connection_state_test.dart`,
  `test/core/services/p2p_service_impl_test.dart`, and new
  `test/core/services/node_readiness_predicates_test.dart`. FDC-14 Open Issues
  wording was inspected and already contained the corrected "one sendable fix,
  relay/plain exclusions correct, TIME_TO_RELAY_READY correct-as-is" wording, so
  no FDC-14 back-patch was needed. Exact direct-test results:
  `cd go-mknoon && GOTOOLCHAIN=go1.25.0 go test ./node/...` PASS
  (`ok github.com/mknoon/go-mknoon/node 442.655s`);
  `flutter test test/features/p2p/domain/models/connection_state_test.dart`
  PASS (17 tests);
  `flutter test test/core/services/node_readiness_predicates_test.dart` PASS
  (2 tests);
  `flutter test test/core/services/p2p_service_impl_test.dart` PASS
  (104 tests);
  `flutter test test/features/p2p/domain/models/node_state_test.dart` PASS
  (20 tests);
  `flutter test test/features/p2p/presentation/widgets/connection_status_indicator_test.dart`
  PASS (19 tests);
  `flutter analyze` FAILS on pre-existing repo-wide analyzer debt after local
  touched-file cleanup (`1637 issues found`, examples include existing
  `avoid_print` integration harness warnings and unrelated unused imports);
  `graphify update .` PASS (`105775 nodes, 179543 edges, 4475 communities`);
  `git diff --check` PASS. Named gates were not run after direct tests because
  the required full Go suite took 442s and `flutter analyze` remains red on
  pre-existing repo-wide issues. Next action: final self-QA and handoff.
- `2026-06-27 21:09:15 CEST` — QA Reviewer completed and found one blocking
  issue: TG-1 seeded `connectionInfo.IsRelay` manually and did not prove the
  production `watchConnectionEvents` stamp or `peer:connected` payload. Fix
  pass replaced TG-1 with a real local-node connect path: mark one connected
  peer in `relayPeerOrder`, dial it through `Host().Connect`, assert
  `peer:connected.isRelay == true` and `Status()` true, then dial a normal peer
  and assert event/status false. Focused triage command
  `cd go-mknoon && GOTOOLCHAIN=go1.25.0 go test ./node -run
  TestStatusConnectionsCarryIsRelayForRelayVsPeer -count=1 -v` PASS. Next
  action: rerun full Go node suite and affected Flutter direct tests.
- `2026-06-27 21:21:04 CEST` — post-fix validation complete. Exact results:
  `cd go-mknoon && GOTOOLCHAIN=go1.25.0 go test ./node/...` PASS
  (`ok github.com/mknoon/go-mknoon/node 445.517s`);
  `flutter test test/features/p2p/domain/models/connection_state_test.dart
  test/core/services/node_readiness_predicates_test.dart
  test/core/services/p2p_service_impl_test.dart` PASS (123 tests);
  `git diff --check` PASS; `graphify update .` PASS (`105775 nodes, 179549
  edges, 4482 communities`). Next action: fresh QA pass to verify the prior
  TG-1 blocker is closed.
- `2026-06-27 21:47:37 CEST` — final gate evidence recorded after QA
  acceptance. `bash scripts/run_test_gates.sh 1to1` PASS (`00:27 +1374: All
  tests passed!`). `bash scripts/run_host_test_gates.sh core-host-all` first
  stopped at #127 because `test/features/push/infrastructure/wake_token_store_impl_test.dart`
  was unclassified by `scripts/run_test_gates.sh completeness-check`; fixed the
  shared classifier by adding `infrastructure` to the existing feature-local
  test directory regex. `bash scripts/run_test_gates.sh completeness-check`
  PASS (`991/991 test files classified`), focused
  `flutter test test/core/gate_classification_completeness_test.dart` PASS, and
  resumed `bash scripts/run_host_test_gates.sh core-host-all --start-at 127`
  PASS through #262 (`PASS: host tests completed for scope: core-host-all`).
  `flutter analyze` remains red only on pre-existing repo-wide debt previously
  recorded above; no FDC-14b-specific analyzer issue remains known.
- `2026-06-27` (independent verification session, separate Claude/Opus run) —
  re-verified the already-landed implementation on the LIVE (concurrently-modified)
  tree without re-implementing. All 8 FDC-14b files + the new
  `node_readiness_predicates_test.dart` confirmed present and matching Route
  B/D8. Ground-truth gates: `GOTOOLCHAIN=go1.25.0 go test ./node/...` PASS
  (`ok …/node 443.683s`, TG-1 included); `flutter test` on
  `connection_state_test` + `node_readiness_predicates_test` + `node_state_test`
  PASS (39); `p2p_service_impl_test` PASS (104 → 105 after the P-5 case-2 add);
  `bash scripts/run_test_gates.sh 1to1` PASS (`+1374`); scoped `flutter analyze`
  0-new (lone repo lint `p2p_service_impl.dart:3496` = concurrent FDC-12
  `_resolveFullPeerId` debt, NOT FDC-14b — `git blame` shows a 22:30 edit by
  another live session). **P-7 BLOCKER mutation re-proven in the main loop**:
  dropping `!c.isRelay` from `_computeDirectReady` re-REDs exactly P-7 at its
  `expect(directReady, isFalse)` (`:5153`), nothing else; reverted byte-for-byte
  (md5 restored). 3-agent read-only adversarial review (Dart producer / Go
  isRelay timing / tests+scope) returned all-`correct`, zero med+ findings; its
  one LOW item (P-5 had only sub-case 1) was CLOSED by adding the
  `onlineDotted→onlineDirect` reshuffle test — empirically confirmed to emit ZERO
  `TIME_TO_ONLINE_BADGE` (plan's case-2 expectation validated). Only file touched
  this session = the additive P-5 case-2 test in `p2p_service_impl_test.dart`; all
  production files left byte-for-byte unchanged. SHARED-TREE: 3 other live
  `claude` sessions + an FDC-S4 sim run share this cwd — `core-host-all` NOT
  re-run to avoid the documented `objective_c.dylib` race (prior session ran it
  green; every FDC-14b host file verified directly). NOT committed.

## Exact Problem Statement
**What's missing / who feels it / why.** FDC-14 shipped the `onlineDirect` badge tier + the `NodeState.directReady`
input + the render/anti-flap, but **no production code ever sets `directReady=true`** — the field is parsed
only from a bridge JSON key the Go side never emits, so it is hard-false in every prod build and the ✦
"directly reachable" badge is unreachable in production. The headline FDC feature ("same-WiFi → talk
directly", proposal §1) therefore remains invisible at the self-status level even when the node genuinely
holds a live direct/LAN path.

**What must improve.**
1. A **producer**: `p2p_service_impl` derives and emits `directReady` from the node's own connection set
   (≥1 live non-circuit connection **to a non-relay peer** — the relay-server socket is itself a direct
   connection and must be excluded, see §Review Findings 🔴), so a real direct path lights the ✦ badge.
2. The **one genuinely-needed downstream fix**: the `isSendableBadgeState`/`_isSendable` predicates must treat
   `onlineDirect` as sendable (it IS), else waiters (`waitForSendableBadge()`) hang once directReady flips.

**What must stay unchanged → preserved sentinels.**
- **PS-1** FDC-14's render contract: `onlineDirect` label `'Online ✦'`, semantics `'…directly reachable'`,
  green styling, anti-flap (T1–T10) — all byte-identical; this plan adds the producer below them, no render edit.
- **PS-2** `_inferTransportForPeer` (`:3461-3486`) and the FDC-12/13 per-peer transport machinery
  (`_peersUpgradedToDirect`, `_learnedTransport`) — untouched; the producer reuses the *convention*, not the
  per-peer state.
- **PS-3** `TIME_TO_RELAY_READY_BADGE` semantics (`:3184-3252`): reaching `onlineDotted` still fires it once;
  `onlineDirect` does **not** fire it (direct-ready ≠ relay-ready). The `== onlineDotted` checks stay (see
  §Accepted Differences for the both-ready lossy nuance).
- **PS-4** FDC-14 T10: peer-presence / relay-peer-connection never sets `onlineDirect` (refined wording per D4).
- **PS-5** Existing `p2p_service_impl_test` cases that build connections must keep their asserted badge —
  unless they legitimately hold a direct multiaddr, in which case the new badge IS `onlineDirect` and the
  test is updated to match (Step 0 audit; see §Risks).

## Root Cause (verify→refute confirmed — file:line)
Not a bug — a **deliberately unwired contract**. `directReady`'s only population path in the entire producer
is `NodeState.fromJson → json['directReady']==true` (`node_state.dart:84`); the Go bridge emits no such key
(zero matches in `go-mknoon/`), and every `copyWith` in `_emitState`'s callers carries the prior `false`
forward. `_stateWithReadinessProjection` (`:2579`) owns only send/inbox capability, never directReady. The
node_state.dart:23-28 self-comment documents exactly this gap ("the live bridge does not yet emit it…
directReady producer = FDC-14b follow-on").

**Refuted / do-NOT-re-introduce:**
- *"derive directReady from FDC-02 `relayLiveSendCount`"* — **refuted, the symbol does not exist.** Do not
  plan against it.
- *"derive directReady from `transport:upgraded` / `_peersUpgradedToDirect` / `_learnedTransport`"* —
  **refuted as scope-guard-violating** (all per-peer; = the forbidden `connections.isNotEmpty` inference).
- *"the 8 ==-sites are all hazards FDC-14b must fix"* (my own prior FDC-14 §Open Issues edit) — **partially
  refuted**: only the 2 `isSendable*` sites need a change; the 4 relay-ready/plain-online sites are correct to
  **exclude** `onlineDirect`; the 2 prod `TIME_TO_RELAY_READY_BADGE` sites are correct as-is (the "never
  fires" framing was an overstatement — see §Accepted Differences for the genuine both-ready nuance). This
  plan corrects that and §Step 0c back-patches the FDC-14 plan.
- *"node-self listen-address is the source"* — **considered and rejected** (D1 alt): ≈always-true once
  started → badge near-meaningless.

## Real Scope (In / Out)
**In (this plan) — Route B, multi-layer (D8):**
- **Go** (`go-mknoon/node/node.go`): `connectionInfo.IsRelay` + `isRelayPeer`-stamp at conn build + `isRelay`
  in the `peer:connected` event and `Status()` connections map. (TG-1)
- **Dart model** (`connection_state.dart`): `final bool isRelay` + `fromJson`/`toJson`/`copyWith`. (CS-1)
- **Dart producer** (`p2p_service_impl.dart`): shared `static bool _connHasDirectAddr(ConnectionState)` (D7,
  also called by `hasNonCircuitDirectConn`) + `bool _computeDirectReady(...)` =
  `any((c) => !c.isRelay && _connHasDirectAddr(c))` injected into the single `_currentState =` assignment in
  `_emitState`.
- **Predicate fix** (the 1 needed downstream change ×2 surfaces): `isSendableBadgeState` + `_isSendable`
  += `onlineDirect`.
- **No native (Swift/Kotlin) change** — the bridge is event-map passthrough (D8).
- `integration_test/_support/node_readiness.dart:51-52` `isSendableBadgeState` += `|| == onlineDirect`.
- `integration_test/background_reconnect_test.dart:35-36` `_isSendable` += `|| == onlineDirect` (private twin).
- Tests: host producer tests (P-1..P-6) in `p2p_service_impl_test.dart`; predicate tests (F-1/F-2) in a new
  host test; FDC-14 T10 prose refinement (D4).
- Back-patch the FDC-14 plan's overstated §Open Issues claim (Step 0c).

**Out (owning work):**
- **Go/bridge changes** — none; if a future design wants an authoritative node-level `directReachable` from
  the Go `Limited` flag (`node.go:142`, not in `Status()` JSON today), that is a separate plan.
- **The relay-ready predicate "both-ready" refinement** (badge-based relay-ready check is lossy when relay+direct
  both hold) — documented Accepted Difference; a follow-on if/when it bites under a live producer.
- **The FDC-12 upgrade-in-place edge** (a relay→direct DCUtR upgrade adds a 2nd conn libp2p does not
  re-announce at connectedness level, so `connections[]` may not reflect it) — documented follow-on; owned by
  FDC-12 territory and dark anyway.
- **Flipping `EnableLibp2pLANDial` / `EnableDcutrUpgrade`** — owned by their device-gated rollouts (FDC-11/12
  D1). This plan must NOT flip them.
- **Per-message transport badge** (`letter_card.dart`) — FDC-13.

## Files To Inspect Next
- **`go-mknoon/node/node.go` (Route B 2a):** `connectionInfo` (:138-143), the conn build in the
  connectedness handler (:1870-1875), the `peer:connected` emit (:1877-1882), `Status()` connections map
  (:658-664), `isRelayPeer` (:1938-1943). Plus the existing Go connection-status test file to home TG-1
  (Step 0d).
- `lib/core/services/p2p_service_impl.dart` — `_emitState` (:3176), `_inferTransportForPeer` (:3461),
  `hasNonCircuitDirectConn` (:4697, the shared-predicate target), `_handlePeerConnected/Disconnected` (defs
  :3919/:3934), the `TIME_TO_RELAY_READY_BADGE` block (:3184-3252).
- `lib/features/p2p/domain/models/connection_state.dart` — `multiaddrs` shape + where to add `isRelay`
  (`fromJson` `:16`-onward parses the verbatim event map; `:658` of go_bridge_client routes `peer:connected`
  here).
- `test/core/services/p2p_service_impl_test.dart` — **Step-0 audit**: cases at `:957-959` and `:1015-1017`
  build connections with a DIRECT multiaddr `['/ip4/192.168.1.10/tcp/4001']`; confirm what badge they assert.
- `integration_test/_support/node_readiness.dart` (:51-60) + `integration_test/background_reconnect_test.dart`
  (:34-44) — the predicate helpers; confirm `node_readiness.dart` is **host-importable** (pure NodeState
  predicates, no flutter_driver import) for F-1/F-2.

## Existing Tests Covering This Area (named; gate family)
- `test/core/services/p2p_service_impl_test.dart` — state emission + `TIME_TO_RELAY_READY_BADGE`/§24 timing;
  **in `ONE_TO_ONE_TESTS` (`run_test_gates.sh:48`)** + AUTO core-host-all. Has direct-multiaddr fixtures
  (`:957/:1015`) — the preservation hot-spot.
- `test/features/p2p/domain/models/node_state_test.dart` — FDC-14 T1–T10 incl. T10 scope-guard (refined by D4).
  AUTO feature-host-all.
- `test/features/p2p/presentation/widgets/connection_status_indicator_test.dart` — FDC-14 render (untouched).
- `integration_test/background_reconnect_test.dart` — device (`@Tags(['device'])`); `_isSendable` fix here.
- `integration_test/_support/node_readiness.dart` — `isSendableBadgeState` fix here; **MISSING** a host test
  → F-1/F-2 add it.
- **Missing coverage gaps:** (1) no test sets directReady via a real connection event (the producer); (2) no
  test that `onlineDirect` is sendable but not relay-ready at the predicate tier.

## RED Test Catalog (BEFORE prod code)

**P-1 — producer: a direct (non-circuit) connection promotes the emitted state to onlineDirect**
- file::name: `test/core/services/p2p_service_impl_test.dart::directReady is set when a non-circuit connection is held`
- Tier: host (core service) — lowest that exercises the real producer seam.
- Shape/setup: start the service (FakeBridge → usabilityReady true: send+inbox proofs satisfied), then drive a
  `peer:connected` event whose `ConnectionState.multiaddrs = ['/ip4/192.168.1.10/udp/45000/quic-v1']` (direct)
  **and `isRelay: false`** (a real peer — Route B/D8). Capture the emitted `NodeState` from `stateStream`.
- RED on HEAD because: no producer exists → `directReady` stays false → `badgeReadinessState` is
  `onlineDotted`/`online`, not `onlineDirect`.
- GREEN asserts: emitted `state.directReady == true` AND `state.badgeReadinessState == BadgeReadinessState.onlineDirect`.
- Mutation that re-reds: delete the `_computeDirectReady(...)` recompute line in `_emitState` → P-1 RED.
- Distinct-event discriminator: paired with P-2 — asserts the promotion is gated on **non-circuit**, not on
  "any connection".

**P-2 — scope-guard (refined T10 at producer tier): a circuit/relay-only connection does NOT set directReady**
- file::name: `test/core/services/p2p_service_impl_test.dart::directReady stays false for a circuit-only connection`
- Tier: host.
- Shape/setup: same as P-1 but `multiaddrs = ['/dns4/relay.example/tcp/4001/p2p/relay-peer/p2p-circuit']`
  (relay) and a second case with `multiaddrs = []` (no addrs). usabilityReady true, relayState 'online'.
- RED on HEAD because: passes trivially on HEAD (directReady already always false) — its load-bearing role is
  the **mutation guard** below (this is the producer-tier analogue of FDC-14 T10; documented non-RED-on-HEAD).
- GREEN asserts: `state.directReady == false` AND badge `== onlineDotted` (relay) — NOT `onlineDirect`.
- Mutation that re-reds: change `_computeDirectReady` to `connections.isNotEmpty` (drop the non-circuit check)
  → P-2 RED (the forbidden inference). This is the exact mutation FDC-14 T10 forbids, now enforced where the
  producer lives.
- ⚠️ **NOTE (F5):** P-2 covers circuit-only and empty, but **NOT** the relay-server-socket case (a *direct*
  multiaddr that must still be excluded) — that is **P-7**, the BLOCKER lock. It also does not cover a single
  connection holding *both* a circuit and a direct addr (the convention-divergence case) — that is **P-8**.

**TG-1 — Go: a relay-server connection is stamped `isRelay:true`; a direct peer is `isRelay:false`** (Route B 2a)
- file::name: `go-mknoon/node/node_test.go::Status connections carry isRelay for relay vs peer` (or the
  existing connection-status test file — Step 0d confirms the home).
- Tier: Go host (`go test ./node/...`, **GOTOOLCHAIN=go1.25.0** — [[feedback_go126_quicgo_session_ticket_panic]]).
- Shape/setup: seed `n.relayPeerOrder` with a relay peer-id; drive the connectedness handler (or directly
  populate `n.connections`) with a relay-peer conn and a non-relay direct-peer conn; call `Status()`.
- RED on HEAD because: `connectionInfo` has no `IsRelay` field and `Status()` emits no `isRelay` key → the
  assertion on `connections[i]["isRelay"]` fails to compile / is absent.
- GREEN asserts: the relay conn's map has `isRelay==true`; the direct-peer conn has `isRelay` false/absent.
  Also assert the `peer:connected` event payload carries `isRelay` (capture via the event sink).
- Mutation that re-reds: revert `IsRelay: n.isRelayPeer(e.Peer)` to `false` → relay conn shows `isRelay:false` → TG-1 RED.
- Harness: `cd go-mknoon && GOTOOLCHAIN=go1.25.0 go test ./node/...` (NOT a Dart gate).

**CS-1 — Dart model: `ConnectionState.fromJson` parses `isRelay`** (Route B 2b)
- file::name: `test/features/p2p/domain/models/connection_state_test.dart::fromJson parses isRelay (default false when absent)`
  (NEW or existing model test file; AUTO feature-host-all).
- Tier: host unit (pure JSON round-trip).
- RED on HEAD because: `ConnectionState` has no `isRelay` field → does not compile / property absent.
- GREEN asserts: `ConnectionState.fromJson({...,'isRelay':true}).isRelay == true`; absent key ⇒ `false`;
  `toJson()` round-trips it.
- Mutation that re-reds: revert the `isRelay` field/parse → CS-1 RED.

**P-7 — BLOCKER lock: a relay-SERVER connection (`isRelay:true`) does NOT set directReady (producer ships dark)**
- file::name: `test/core/services/p2p_service_impl_test.dart::directReady stays false for a relay-server connection`
- Tier: host.
- Shape/setup: usabilityReady true, relayState 'online'. Drive a `peer:connected` whose `ConnectionState`
  has **`isRelay: true`** and a **direct** multiaddr (`['/dns4/relay.example/tcp/4001']`) — i.e. the
  node↔relay-server socket exactly as Go now stamps it. No other connection.
- RED on HEAD because: this is the **producer-tier BLOCKER guard** — it fails the moment a naive
  `connections.any(non-circuit)` producer lands (⇒ directReady true ⇒ `onlineDirect`). On HEAD (no producer)
  it passes trivially; it is the lock that makes the `!c.isRelay` exclusion mandatory.
- GREEN asserts: `state.directReady == false` AND badge `== onlineDotted` (relay-ready, NOT onlineDirect).
- Mutation that re-reds: drop the `!c.isRelay` term from `_computeDirectReady` → P-7 RED.
- Discriminator: a **direct** multiaddr whose connection is **`isRelay:true`** ⇏ directReady — distinguishes
  "direct addr" from "direct to a real peer". This is the test that proves the producer ships dark.
- Pairs with **P-7b** (belt): a direct conn with `isRelay:false` to a real peer ⇒ directReady **true** (the
  inclusion side; folds into P-1 if P-1's fixture is given `isRelay:false`).

**P-8 — convention lock: a single connection holding BOTH a circuit and a direct addr (D7 decision)**
- file::name: `test/core/services/p2p_service_impl_test.dart::directReady for a connection holding both a circuit and a direct multiaddr`
- Tier: host.
- Shape/setup: one `ConnectionState` (non-relay peer) with `multiaddrs = ['/ip4/192.168.1.10/udp/45000/quic-v1', '/dns4/relay/tcp/4001/p2p/relay/p2p-circuit']`.
- RED on HEAD because: passes trivially (no producer); load-bearing as the **convention lock** — it asserts
  whichever D7 outcome is chosen and re-reds if a refactor silently flips circuit-precedence ↔ `any(non-circuit)`.
- GREEN asserts: the D7-chosen result (recommended: **direct-presence** per FDC-15 `hasNonCircuitDirectConn`,
  i.e. directReady `== true` — a coexisting LAN-direct path is the headline "same-WiFi" outcome).
- Mutation that re-reds: flip the shared per-connection predicate to the other convention → P-8 RED.
- Discriminator: locks the media-lane (`hasNonCircuitDirectConn`) and self-dot (`_computeDirectReady`) to the
  **same** answer for the mixed-addr connection.

**P-3 — recompute-on-every-emit: directReady is not sticky; it falls back when the direct conn drops**
- file::name: `test/core/services/p2p_service_impl_test.dart::directReady reverts to false when the direct connection disconnects`
- Tier: host.
- Shape/setup: P-1 (direct conn → onlineDirect), then drive `peer:disconnected` removing that connection (now
  `connections` empty or circuit-only). Capture the post-disconnect state.
- RED on HEAD because: no producer (never reaches onlineDirect to begin with).
- GREEN asserts: post-disconnect `state.directReady == false` AND badge `== onlineDotted`/`online`.
- Mutation that re-reds: compute directReady once and cache it on first true (skip recompute on later emits) →
  P-3 RED (badge stays onlineDirect after disconnect).
- Discriminator: separates "derived every emit" from "latched once".

**P-4 — the producer never bypasses the usabilityReady gate (INV-1 isolation at producer tier)**
- file::name: `test/core/services/p2p_service_impl_test.dart::directReady true with capability not ready stays connecting`
- Tier: host.
- Shape/setup: a direct connection is held (directReady computes true) BUT send/inbox capability is NOT proven
  (usabilityReady false — before the proof window completes).
- RED on HEAD because: passes trivially on HEAD (directReady false); load-bearing once the producer exists —
  guards that the producer sets the field but lets `node_state` enforce the gate.
- GREEN asserts: `state.directReady == true` AND `state.badgeReadinessState == BadgeReadinessState.connecting`
  (NOT onlineDirect) — the gate at `node_state.dart:163` wins.
- Mutation that re-reds: (defensive) if a future change made the producer also force the badge, this flips;
  primary lock is FDC-14 T5 list-2 at the model tier. Documented as a producer-tier belt.

**P-5 — timing emit on the REAL transition (producer-driven FDC-14 T8)**
- file::name: `test/core/services/p2p_service_impl_test.dart::reaching onlineDirect via a direct connection emits TIME_TO_ONLINE_BADGE exactly once`
- Tier: host.
- Shape/setup: drive `connecting → (direct conn appears) → onlineDirect`; capture flow events. Then a second
  case `onlineDotted → (direct conn appears) → onlineDirect`.
- RED on HEAD because: no producer → the node never reaches `onlineDirect` via a connection event, so the
  first-ready emit can never be attributed to a real direct-path transition.
- GREEN asserts: case 1 emits exactly ONE `TIME_TO_ONLINE_BADGE_WIDGET`; case 2 (ready→ready reshuffle) emits ZERO.
- Mutation that re-reds: delete the producer recompute → case 1 never reaches onlineDirect → assertion shape RED.
- Discriminator: ties the producer to the existing badge-timing contract (FDC-14 PS-4 / T8) under a live signal.

**P-6 — onlineDirect does NOT fire TIME_TO_RELAY_READY_BADGE (locks the "==onlineDotted is correct" decision)**
- file::name: `test/core/services/p2p_service_impl_test.dart::onlineDirect does not emit TIME_TO_RELAY_READY_BADGE`
- Tier: host.
- Shape/setup: drive a node from `online` (no relay) directly to `onlineDirect` via a direct connection, with
  relay NOT ready (relayState degraded). Capture flow events.
- RED on HEAD because: no producer → never reaches onlineDirect. (Once the producer exists, this locks current
  behavior.)
- GREEN asserts: NO `TIME_TO_RELAY_READY_BADGE` event emitted across the transition (only `TIME_TO_ONLINE_BADGE`).
- Mutation that re-reds: change `nowRelayReadyBadge` (`:3219`) to `== onlineDotted || == onlineDirect` → P-6 RED
  (spurious relay-ready emit). This documents the deliberate decision NOT to touch `:3185/:3219`.
- Discriminator: `TIME_TO_RELAY_READY_BADGE` absent AND `TIME_TO_ONLINE_BADGE` present.

**F-1 — fix: isSendableBadgeState treats onlineDirect as sendable**
- file::name: `test/core/services/node_readiness_predicates_test.dart::isSendableBadgeState is true for onlineDirect`
  (NEW host test; imports `integration_test/_support/node_readiness.dart` via relative path — Step-0 confirms
  it is host-importable).
- Tier: host unit (pure predicate over an injected `NodeState`).
- Shape/setup: `isSendableBadgeState(NodeState(isStarted:true, send+inbox ready, directReady:true))` (badge ==
  onlineDirect).
- RED on HEAD because: the helper omits `onlineDirect` → returns false.
- GREEN asserts: returns `true` (alongside existing online/onlineDotted true cases preserved).
- Mutation that re-reds: revert the `|| == onlineDirect` add → F-1 RED.
- Discriminator: this is the **load-bearing** fix — without it `waitForSendableBadge()` times out when the
  producer flips directReady.

**F-2 — guard: onlineDirect is NOT relay-ready and NOT plain-online (the 4 "no-change" sites stay correct)**
- file::name: `test/core/services/node_readiness_predicates_test.dart::onlineDirect is not relay-ready nor plain-online`
- Tier: host unit.
- Shape/setup: with an onlineDirect `NodeState`: `isRelayReadyBadgeState(...)` and `isPlainOnlineBadgeState(...)`.
- RED on HEAD because: passes on HEAD (helpers exclude onlineDirect already) — load-bearing as the **guard**
  against an over-eager "add onlineDirect everywhere" fix.
- GREEN asserts: both return `false`.
- Mutation that re-reds: add `|| == onlineDirect` to either relay-ready or plain-online predicate → F-2 RED.
- Discriminator: locks the semantic split — onlineDirect is sendable (F-1) but neither relay-ready nor plain
  (F-2).

## Test Coverage Matrix (zero empty cells)

| Spec case | Behavior props | Tier | Test file::name | RED reason on HEAD | Mutation revert | Acceptance gate cmd | Harness registration |
|---|---|---|---|---|---|---|---|
| Producer promotes | direct conn ⇒ directReady ⇒ onlineDirect | host service | p2p_service_impl_test::directReady is set when a non-circuit connection is held | no producer ⇒ false | delete `_computeDirectReady` call | `flutter test test/core/services/p2p_service_impl_test.dart` | in `ONE_TO_ONE_TESTS` + AUTO core-host-all |
| Scope guard (non-circuit only) | circuit/empty ⇒ NOT directReady | host service | p2p_service_impl_test::directReady stays false for a circuit-only connection | guard (mutation-RED) | `connections.isNotEmpty` ⇒ directReady | same | same |
| Go: isRelay flag (Route B 2a) | relay conn ⇒ isRelay:true; peer ⇒ false | go host | node_test::Status connections carry isRelay for relay vs peer (TG-1) | no `IsRelay` field/key | revert `IsRelay: n.isRelayPeer(...)` to false | `cd go-mknoon && GOTOOLCHAIN=go1.25.0 go test ./node/...` | go test (NOT a Dart gate) |
| Model: isRelay parsed (Route B 2b) | fromJson reads isRelay, default false | host unit | connection_state_test::fromJson parses isRelay (CS-1) | no `isRelay` field | revert field/parse | `flutter test test/features/p2p/domain/models/connection_state_test.dart` | AUTO feature-host-all |
| 🔴 BLOCKER: relay-server socket excluded | conn `isRelay:true` ⇒ NOT directReady (ships dark) | host service | p2p_service_impl_test::directReady stays false for a relay-server connection (P-7) | guard (mutation-RED; fails naive producer) | drop `!c.isRelay` term | same | same |
| Convention lock (mixed addr) | one conn w/ circuit+direct addr ⇒ D7 result | host service | p2p_service_impl_test::directReady for a connection holding both a circuit and a direct multiaddr | guard (mutation-RED) | flip shared predicate convention | same | same |
| Not sticky | disconnect ⇒ directReady false | host service | p2p_service_impl_test::directReady reverts to false when the direct connection disconnects | no producer | cache/latch directReady | same | same |
| usabilityReady gate | directReady true + cap false ⇒ connecting | host service | p2p_service_impl_test::directReady true with capability not ready stays connecting | guard (model T5 owns) | producer forces badge | same | same |
| Timing emit (live) | connecting→direct emits 1; dotted→direct emits 0 | host service | p2p_service_impl_test::reaching onlineDirect via a direct connection emits TIME_TO_ONLINE_BADGE exactly once | no producer | delete producer recompute | same | same |
| Relay-ready telemetry unaffected | onlineDirect ⇏ TIME_TO_RELAY_READY_BADGE | host service | p2p_service_impl_test::onlineDirect does not emit TIME_TO_RELAY_READY_BADGE | no producer | `:3219` += onlineDirect | same | same |
| Sendable predicate fix | onlineDirect is sendable | host unit | node_readiness_predicates_test::isSendableBadgeState is true for onlineDirect | helper omits onlineDirect | revert `|| onlineDirect` | `flutter test test/core/services/node_readiness_predicates_test.dart` | AUTO core-host-all (NEW file) |
| Predicate semantic split | onlineDirect not relay-ready/plain | host unit | node_readiness_predicates_test::onlineDirect is not relay-ready nor plain-online | guard (mutation-RED) | add onlineDirect to relay/plain | same | AUTO core-host-all |
| Refined T10 (model) | relay/circuit peer ⇏ onlineDirect | unit | node_state_test::peer connections and presence do not set onlineDirect (FDC-14 T10, prose refined) | n/a (already green) | `connections.isNotEmpty`⇒directReady | `flutter test test/features/p2p/domain/models/node_state_test.dart` | AUTO feature-host-all |
| Live ✦ on device (closure) | real LAN direct ⇒ ✦ badge | device-proof | integration_test/background_reconnect (or a directready proof) — DEFERRED | flag-gated dark | n/a | `/sims` 2-device, flags ON | DEFERRED (see Device Profile) |

## Blind-Spot Sweep
- **Lifecycle / derived-state durability:** directReady is **derived, never persisted** (D3). On
  reopen/hot-restart, `_emitState(NodeState.fromJson(node:start|status))` rebuilds `connections` and the
  producer recomputes directReady from them — no stale latch survives. Covered by P-1 (fresh emit) + P-3
  (recompute) + the start_response path reading connections. Row: P-1/P-3.
- **Sibling-surface consistency:** the badge renders at `feed_header.dart:48` + FTE `:146` — both build the
  same `ConnectionStatusIndicator` and branch on nothing. One render path → no per-surface divergence. Plus
  the *predicate* sibling-surfaces: `isSendableBadgeState` (public) AND `_isSendable` (private twin in
  background_reconnect) — BOTH fixed (the asymmetry would be a bug); F-1 host-tests the public one, the private
  twin is verified by compile + the deferred device test. Justified.
- **Destructive-action side-effects:** the only "removal" is directReady going false on disconnect/stop —
  P-3 (disconnect) + `NodeState.stopped` (empty connections ⇒ false). Asserted, not assumed.
- **Invariant re-verification under new transitions:** the NEW `*→onlineDirect` transition re-verifies: (a) the
  usabilityReady gate still holds (P-4); (b) the badge-timing contract still emits exactly-once (P-5); (c) the
  relay-ready telemetry is not spuriously triggered (P-6). Each is a row, not an assumption.

## Invariants (locked by tests)
- INV-1 directReady ⇔ ≥1 held connection has a non-empty, non-`/p2p-circuit` multiaddr **to a non-relay
  peer**; recomputed every emit (P-1, P-2, P-3, P-7). The "non-relay peer" clause is the BLOCKER fix — the
  relay-server socket is a *direct* connection and must NOT count (P-7).
- INV-0 (coupling, F2) directReady is fresh **only on emit paths that fire**; count-changing writers fire
  unconditionally, but a same-count in-place flip on a `_stateMeaningfullyChanged`-guarded path is suppressed
  (D3 LIMITATION — resolve via guard deep-compare or scope-out).
- INV-2 directReady never bypasses usabilityReady: cap-false ⇒ connecting even with a direct conn (P-4; model T5).
- INV-3 reaching onlineDirect via a live direct conn emits `TIME_TO_ONLINE_BADGE` exactly once on first-ready,
  zero on ready→ready reshuffle (P-5; FDC-14 PS-4).
- INV-4 onlineDirect is **sendable** but **neither relay-ready nor plain-online** (F-1, F-2); and does NOT fire
  `TIME_TO_RELAY_READY_BADGE` (P-6).
- INV-5 the forbidden `connections.isNotEmpty ⇒ directReady` inference stays RED (P-2; FDC-14 T10, refined D4).

## Step-By-Step Implementation Plan (RED first; name the seam)
0. **Step 0a — preservation audit (CORRECTED, F4).** The originally-named cases at `:957/:1015` assert the
   incoming **message `transport:'direct'`** (`:988/:1035`), **not a badge** — they are a red herring (the
   producer flipping directReady has no effect on a `transport` assertion). All badge-asserting host tests in
   `p2p_service_impl_test.dart` (`:4500-5000`) use **empty** `connections` ⇒ directReady false ⇒ preserved.
   So within this file there is **no badge-preservation flip** to update. Instead, the real audit is:
   (a) **grep recipe** — enumerate any badge-asserting test that feeds a *non-circuit* `ConnectionState`:
   `grep -n "badgeReadinessState" test/core/services/p2p_service_impl_test.dart` cross-referenced with the
   nearest `multiaddrs:`; (b) **model T10** (`node_state_test.dart:413-427`) builds a direct conn but is
   safe via layer separation (F3 / D4) — no change beyond the D4 prose; (c) **integration/device waiters**
   (`waitForRelayReadyBadge`/`waitForPlainOnlineBadge`, `background_reconnect_test.dart` `_isRelayReady`/
   `_isPlainOnline`) are the genuine regression surface **iff the relay-socket BLOCKER is unfixed** — once
   P-7's relay-exclusion lands, relay-only nodes stay `onlineDotted` and these are preserved. The full
   `1to1`/`core-host-all` gates remain the backstop.
   **Step 0b — host-importability check.** Confirm `integration_test/_support/node_readiness.dart` imports no
   flutter_driver/integration_test runtime (pure NodeState predicates) so F-1/F-2 can import it from
   `test/core/services/`. If not importable, fall back to extracting the predicate or asserting via the badge
   computation directly.
   **Step 0c — back-patch FDC-14.** In `FDC-14-online-dot-directly-reachable-tdd-plan.md` §Open Issues, soften
   the "8 hazard sites / TIME_TO_RELAY_READY_BADGE never fires (bug)" claim to the verified picture: 1 fix
   needed (`isSendable*`), 4 correct exclusions, 2 prod sites correct-as-is with a both-ready lossy nuance
   (cross-reference this plan). (Mechanical doc edit.)
   **Step 0d — Go test home (Route B).** Find the existing `go-mknoon/node/*_test.go` that exercises
   `Status()`/`peer:connected`/`n.connections` (e.g. a connection-status or node-status test) and home TG-1
   there; confirm the event sink helper used to capture `peer:connected`. Confirm GOTOOLCHAIN=go1.25.0 is the
   working toolchain ([[feedback_go126_quicgo_session_ticket_panic]]).
1. **RED** — write TG-1 (Go) + CS-1 (model) + P-1..P-8 in `p2p_service_impl_test.dart` and F-1/F-2 in the new
   `test/core/services/node_readiness_predicates_test.dart`. Run; confirm TG-1/CS-1 fail (no field), P-1/P-3/
   P-5/P-6 fail for the no-producer reason and F-1 fails for the omitted-arm reason (P-2/P-4/P-7/P-8/F-2 are
   mutation-guards — green on HEAD, RED only under their named mutation; **P-7 is the BLOCKER guard that fails
   a naive `any(non-circuit)` producer**).
   **Build order: 2a (Go isRelay) → 2b (model) → 2c (producer) → predicate fix** — the producer's `!c.isRelay`
   term depends on the model field, which depends on the Go flag.
2. **Seam: producer helper (Route B — D8).** Implement in layer order:
   - **2a — Go** (`go-mknoon/node/node.go`): `connectionInfo` += `IsRelay bool \`json:"isRelay,omitempty"\``
     (`:138-143`); at the conn build (`:1870-1875`) set `IsRelay: n.isRelayPeer(e.Peer)`; add `isRelay` to
     the `peer:connected` emit (`:1877-1882`) and the `Status()` connections map (`:658-664`). RED-first via
     **TG-1** in a Go test (GOTOOLCHAIN=go1.25.0).
   - **2b — Dart model** (`connection_state.dart`): add `final bool isRelay` (default false), `fromJson`
     `json['isRelay'] == true`, carry through `toJson`/`copyWith`. RED-first via **CS-1**.
   - **2c — Dart producer** (`p2p_service_impl.dart`): factor `static bool _connHasDirectAddr(ConnectionState c)`
     (the FDC-15 per-addr predicate, D7) and have BOTH it and `hasNonCircuitDirectConn` (`:4697`) call it;
     then `bool _computeDirectReady(List<ConnectionState> c) => c.any((x) => !x.isRelay && _connHasDirectAddr(x));`.
3. **Seam: wire into `_emitState`** (`:3187-3192`, the SOLE writer). The real code is a **single assignment**
   (no separate `projected`/`withDirect` var): fold directReady **into** the `_currentState =` assignment and
   apply on **both** branches so every emit recomputes:
   ```dart
   final base = mergeServiceOwnedReadiness
       ? _stateWithReadinessProjection(newState)
       : newState;
   _currentState = base.copyWith(directReady: _computeDirectReady(base.connections));
   if (!_stateController.isClosed) _stateController.add(_currentState);
   ```
   This is also what makes `nowRelayReadyBadge` (`:3219`, read off `_currentState` **after** the assignment)
   correctly observe `onlineDirect` (⇒ P-6 / the both-ready suppression). → GREEN P-1, P-3, P-5, P-6, P-7
   (and P-2/P-4/P-8 stay green; their mutations now have teeth).
4. **Seam: predicate fix (the 1 needed change ×2 surfaces)** — `node_readiness.dart:52` and
   `background_reconnect_test.dart:36`: append `|| state.badgeReadinessState == BadgeReadinessState.onlineDirect`.
   → GREEN F-1. Leave the relay-ready/plain-online predicates UNCHANGED → F-2 stays green.
5. **Seam: refine FDC-14 T10 prose** (D4) — in `node_state_test.dart` T10, update the comment/wording from
   "any connection" to "a circuit/relay connection"; the fixture + assertion are unchanged (stays green).
6. **Run** the Go node suite (`GOTOOLCHAIN=go1.25.0 go test ./node/...`) + the host test files
   (connection_state, p2p_service_impl, node_readiness_predicates) + `flutter analyze`. Apply Step-0a
   assertion updates if the audit flagged them. Re-run `ONE_TO_ONE` + `core-host-all`.
7. **STOP-IF** — the Go change is **bounded to the `isRelay` flag** (D8): do NOT add a Go/bridge
   `directReady`/`directReachable` field, do NOT add new relay-tracking (reuse `isRelayPeer`), do NOT touch
   native Swift/Kotlin. Do NOT touch `:3185/:3219`; do NOT flip `EnableLibp2pLANDial`/`EnableDcutrUpgrade`.
   If TG-1 shows the relay-server socket is NOT stamped `isRelay:true` (e.g. the relay isn't in
   `relayPeerOrder` at connect time), STOP and re-ground the relay-identity timing before wiring the producer.
8. **Mutation pass** — apply each row's mutation, confirm the named test re-reds, revert (via Edit, never
   `git checkout`).

## Risks And Edge Cases (each pinned by a test / documented)
- **🔴 Relay-server socket lights the badge for everyone (PRIMARY / BLOCKER):** the node↔relay direct socket
  is a non-circuit connection on every online node ⇒ naive D1 ⇒ `onlineDirect` always, integration waiters
  time out. Pinned by **P-7** + the relay-peer exclusion (D1/Step 2). See §Review Findings 🔴.
- **Suppressed in-place flip (F2):** a same-count circuit→direct change reconciled only via the guarded
  `node:status` poll is suppressed ⇒ stale badge. Documented D3 LIMITATION; either deep-compare the guard or
  scope-out (FDC-12 territory).
- **Convention drift vs `hasNonCircuitDirectConn` (F1):** two contradictory direct-detection definitions ⇒
  media-lane and self-dot could disagree. Pinned by **P-8** + the shared `_connHasDirectAddr` (D7).
- **Preservation flip (de-escalated, F4):** the originally-named `:957/:1015` fixtures assert message
  `transport`, not a badge → **no flip**. Genuine residual = integration/device waiters (covered once P-7
  lands). Backstopped by the full `ONE_TO_ONE`/`core-host-all` gates.
- **Over-broad producer** (any connection ⇒ directReady, incl. relay) → pinned P-2 (the FDC-14 T10 mutation).
- **Sticky directReady** (latched, not recomputed) → pinned P-3.
- **Bypassing the capability gate** → pinned P-4 (+ model T5).
- **Spurious relay-ready telemetry** when onlineDirect+relay coincide → P-6 locks current behavior; the
  genuine both-ready lossiness is an Accepted Difference (below).
- **FDC-12 upgrade-in-place** (2nd direct conn not re-announced ⇒ connections[] stale ⇒ directReady misses an
  in-place relay→direct upgrade) → documented follow-on; dark anyway. Note in code comment near `_computeDirectReady`.

## Device/Relay Proof Profile
- **Host-only for what this plan ships** (Go `isRelay` flag + model + producer + predicate fix) — Go-host via
  TG-1 (`GOTOOLCHAIN=go1.25.0 go test ./node/...`) + Dart-host via injected `peer:connected` events with
  direct/circuit multiaddrs and `isRelay`. **No device proof required to land FDC-14b's code.** (Route B adds
  a Go tier but stays fully host-testable — `isRelayPeer` is deterministic given a seeded `relayPeerOrder`.)
- **Closure gate (DEFERRED, flag-gated):** the live ✦ badge end-to-end requires `EnableLibp2pLANDial` (and/or
  `EnableDcutrUpgrade`) ON + 2 real devices on the same LAN (iOS sim shares the host mDNS stack →
  `DISABLE_LOCAL_DISCOVERY`, proposal §6.5). When those flags flip, a `/sims` 2-device LAN smoke should observe
  the self-dot actually reaching `onlineDirect`. Until then this is intentionally unverified on device (dark).

## Reachability Reality Check (CORRECTED — F6; the BLOCKER changes this entirely)
**Original claim (WRONG on two points):** ~~existing local discovery can light ✦ independent of the FDC-11
flag; verify the `p2p_lan_discovery` runtime-gate prod default.~~
- `_currentState.connections` is sourced **only** from Go `node:status` (`fromJson` at `:597/:632/:3523/
  :3614`). A direct-*peer* multiaddr only appears there when FDC-11's libp2p `host.Connect` ran — gated by
  `EnableLibp2pLANDial` (**default FALSE**, `go-mknoon/node/feature_flags.go:36`). The legacy WS/bonsoir LAN
  path is a separate **Dart** transport that does **not** populate Go `node:status`. So for *genuine peers*,
  onlineDirect is **fully dark** in default prod.
- `'p2p_lan_discovery'`/`'p2p_lan_dial'` are **account-migration network-side-effect gates**
  (`_allowsAccountNetworkSideEffects`, `:766` — true in normal prod), **not** a directReady source. The
  original "verify this default" instruction was misdirected.

**Corrected reality:** the producer is dark for real peers — **except** for the relay-server socket
(§Review Findings 🔴), which is a *direct, non-circuit* connection present on **every** online node. So
without the D1 relay-peer exclusion (P-7), the badge lights `onlineDirect` for **everyone, always** — the
opposite of "dark". **With** the exclusion, it is genuinely dark until `EnableLibp2pLANDial`/
`EnableDcutrUpgrade` flip (or a future Go-surfaced LAN path populates `node:status`). The build decision
(wire the producer now) is unchanged **only after** the relay-exclusion fix lands.

## Acceptance Gates (LITERAL cmds + expected counts as TODO)
```bash
# RED (before prod edits) — TG-1/P-1/P-3/P-5/P-6/P-7 + CS-1/F-1 must FAIL for the documented reasons
cd go-mknoon && GOTOOLCHAIN=go1.25.0 go test ./node/... -run 'isRelay' ; cd ..   # TG-1: no IsRelay field/key yet
flutter test test/features/p2p/domain/models/connection_state_test.dart --plain-name 'fromJson parses isRelay'  # CS-1
flutter test test/core/services/p2p_service_impl_test.dart --plain-name 'directReady is set when a non-circuit connection is held'
flutter test test/core/services/p2p_service_impl_test.dart --plain-name 'directReady stays false for a relay-server connection'  # P-7 (mutation-guard once producer lands)
flutter test test/core/services/node_readiness_predicates_test.dart --plain-name 'isSendableBadgeState is true for onlineDirect'

# Go GREEN (Route B 2a) — run the WHOLE node pkg, not just -run, before landing
cd go-mknoon && GOTOOLCHAIN=go1.25.0 go test ./node/... ; cd ..   # TG-1 green + go-mknoon node suite unaffected

# Direct GREEN (after Go isRelay + model + producer + predicate fix)
flutter test test/core/services/p2p_service_impl_test.dart            # expected: existing + P-1..P-8 (TODO: capture baseline)
flutter test test/features/p2p/domain/models/connection_state_test.dart  # CS-1 green
flutter test test/core/services/node_readiness_predicates_test.dart  # expected: F-1, F-2 green (NEW file)

# Preservation sentinels
flutter test test/features/p2p/domain/models/node_state_test.dart                       # FDC-14 T1..T10 still green (T10 prose-only change)
flutter test test/features/p2p/presentation/widgets/connection_status_indicator_test.dart  # FDC-14 render untouched

# Named gates
./scripts/run_test_gates.sh 1to1                 # p2p_service_impl_test in ONE_TO_ONE_TESTS — expect unchanged + new P-* (1226 baseline floor, FDC-S0)
./scripts/run_host_test_gates.sh core-host-all   # p2p_service_impl_test + NEW node_readiness_predicates_test; KNOWN pre-existing transport_metrics_privacy FDC-S0 fail is NOT this plan; run host gates ONE AT A TIME (objective_c.dylib race)

# Hygiene
flutter analyze        # 0 new
git diff --check       # clean
```

## Known-Failure Interpretation
- Expected RED: P-1/P-3/P-5/P-6 (no producer) + F-1 (omitted arm) before the fix. P-2/P-4/P-7/P-8/F-2 are
  mutation-guards (green on HEAD; RED only under their named mutation). **P-7 must go RED the instant a naive
  `connections.any(non-circuit)` producer lands without the relay-peer exclusion — that is the BLOCKER
  catch.**
- Expected intended change (NOT a regression): `p2p_service_impl_test` fixtures with direct multiaddrs
  (`:957/:1015`) flipping to `onlineDirect` — update their assertions per Step 0a.
- Pre-existing dirty-tree / environment: `transport_metrics_privacy_test` (FDC-S0 `sinceProcessStartMs`
  allowlist) fails on `core-host-all` independently of this plan; concurrent host-gate runs race on
  `objective_c.dylib`.
- Scope drift (BLOCKING): any Go/bridge change, any `:3185/:3219` edit, any flag flip, any render edit.

## Done Criteria (checkbox)
- [x] **🔴 Route B chosen (Go-authoritative per-connection `isRelay`), 2026-06-27** — see D8.
- [x] **Go (Route B 2a):** `connectionInfo.IsRelay` + `isRelayPeer`-stamp + `isRelay` in `peer:connected`
      event & `Status()` map; **TG-1 GREEN** (GOTOOLCHAIN=go1.25.0) + node suite unaffected.
- [x] **Dart model (Route B 2b):** `ConnectionState.isRelay` + fromJson/toJson/copyWith; **CS-1 GREEN**.
- [x] `_computeDirectReady` = `any((c) => !c.isRelay && _connHasDirectAddr(c))` via shared `_connHasDirectAddr`
      (D7, reconciled with `hasNonCircuitDirectConn`) + wired into the single `_currentState =` assignment in
      `_emitState` (both `mergeServiceOwnedReadiness` branches).
- [x] **P-7 GREEN: a relay-only node (`isRelay:true` conn) stays `onlineDotted` (producer ships dark).**
- [x] `directReady` recomputed every (firing) emit; never sticky; false on disconnect/stop (P-1/P-3); D3
      suppression LIMITATION resolved or explicitly scoped-out (F2).
- [x] Refined T10 / P-2 lock: non-circuit specifically; P-8 convention lock; **D4 T10 fixture relabel applied**.
- [x] usabilityReady gate preserved (P-4); timing emit exactly-once (P-5 — BOTH sub-cases now covered:
      `online→onlineDirect` emits 1, `onlineDotted→onlineDirect` reshuffle emits 0, empirically validated
      2026-06-27 verification session); no spurious relay-ready telemetry (P-6).
- [x] `isSendableBadgeState` + `_isSendable` include onlineDirect (F-1); relay-ready/plain-online predicates
      unchanged (F-2).
- [x] Step 0a preservation audit done; flipped fixtures updated to onlineDirect intentionally.
- [x] FDC-14 §Open Issues inspected; no new back-patch needed because the live doc already contained the corrected wording (Step 0c).
- [x] All RED mutation-verified; analyze 0-new; `1to1` green — **independently re-verified on the live tree
      2026-06-27** (Go node suite `ok …/node 443.683s`; `1to1` `+1374`; `p2p_service_impl_test` 105 incl. the
      9-test FDC-14b group; `connection_state`/`node_readiness_predicates`/`node_state` green; scoped analyze
      0-new — the lone repo lint at `p2p_service_impl.dart:3496` is concurrent FDC-12 `_resolveFullPeerId`
      debt, not FDC-14b). **P-7 BLOCKER mutation re-proven**: dropping `!c.isRelay` re-REDs exactly P-7
      (`:5153`), reverted byte-for-byte. `core-host-all` not re-run this session (every FDC-14b-touched host
      file verified directly + `1to1` green; a fresh broad run was held to avoid the documented
      `objective_c.dylib` race with a live concurrent FDC-S4 sim session — prior session ran it green).
- [x] Device-proof DEFERRED + documented (flag-gated dark) — see §Device/Relay Proof Profile; the live ✦
      closure gate stays open until `EnableLibp2pLANDial`/`EnableDcutrUpgrade` flip (both still default FALSE).

## Scope Guard (hard Do-not)
- **Route B Go edit is IN scope but BOUNDED:** the only permitted Go change is the per-connection `isRelay`
  flag (D8 — `connectionInfo.IsRelay`, `isRelayPeer`-stamp, emit in `peer:connected` + `Status()`). Do NOT add
  a Go/bridge `directReady`/`directReachable` field (the aggregate stays Dart-computed; Go surfaces only
  relay-IDENTITY). Do NOT add new relay-tracking — reuse the existing `isRelayPeer`/`relayPeerOrder`.
- Do NOT change any native (Swift/Kotlin) bridge code — the event map is passthrough.
- Do NOT edit `p2p_service_impl.dart:3185/:3219` or change `TIME_TO_RELAY_READY_BADGE` semantics.
- Do NOT add `onlineDirect` to the relay-ready or plain-online predicates (F-2 guards this).
- Do NOT flip `EnableLibp2pLANDial` / `EnableDcutrUpgrade`.
- Do NOT touch FDC-14's render (`node_state.dart` computation / `connection_status_indicator.dart`).
- Do NOT derive directReady from any per-peer signal (`_peersUpgradedToDirect`, `_learnedTransport`,
  `transport:upgraded`) — FDC-14 T10.

## Accepted Differences / Intentionally Out Of Scope
- **Both-ready relay-ready lossiness:** when a node is relay-ready AND direct-ready, the badge collapses to
  `onlineDirect`, so badge-based relay-ready predicates (`== onlineDotted`) read false even though the relay IS
  reserved. Accepted for now (the relay reservation still functions; only the badge-derived "is relay ready"
  read is lossy). A follow-on may switch those reads to the underlying `relayReady` getter if it bites under a
  live producer. Pinned-as-current-behavior by P-6/F-2.
- **FDC-12 upgrade-in-place edge:** a relay→direct DCUtR upgrade adds a 2nd connection libp2p does not
  re-announce at the connectedness level, so `connections[]` (hence directReady) may not reflect an in-place
  upgrade. Out of scope (dark; FDC-12 territory). The fresh-direct-connection case (FDC-11 LAN dial) IS covered.
- **Authoritative Go node-level reachability** (from the `Limited` flag at `node.go:142`, not in `Status()`
  JSON today) — a cleaner long-term source; a separate plan if ever wanted.

## Dependency Impact
- **Consumes:** FDC-14's shipped render (`onlineDirect` tier + `directReady` field) — this plan supplies the
  missing producer; together they make the ✦ badge reachable.
- **gatedBy (for the LIVE feature, not the code):** `EnableLibp2pLANDial` / `EnableDcutrUpgrade` device-gated
  rollouts — until they flip (or existing LAN discovery forms a direct conn), onlineDirect stays inert in prod.
- **Feeds back:** corrects the FDC-14 plan's §Open Issues overstatement (Step 0c).
- **Collision (widened by Route B):** touches `p2p_service_impl.dart` (`_emitState` + shared `_connHasDirectAddr`
  — refactors FDC-15 `hasNonCircuitDirectConn:4697`), `connection_state.dart` (new `isRelay` field), AND
  `go-mknoon/node/node.go` (`connectionInfo`/`Status()`/`peer:connected` — heavy concurrent FDC-09/11/12/15 Go
  territory). All edits are additive, but the node.go connectedness handler + `Status()` are hot — re-ground
  `:138-143/:658-664/:1870-1882` against the live tree before editing (anchors drift on this shared branch).
