# FDC-08 — Relay presence lookup (additive inbox action)  (New Feature)

Status: **ready (host tiers) — finalized against FDC-S3 (closed 2026-06-27); live-relay-env closure (S1) + device-tuning of TTL constants remain**

Spec: Network-Arch/Fast-Direct-Connection-Architecture-Proposal.md (§6.3 presence-aware emphasis; §8 P1-1; §11 open-question 2)

## ✅ FINALIZED against FDC-S3 (was: DRAFT — finalize after FDC-S3)

> **FDC-S3 is CLOSED (decided 2026-06-27).** The truth-source question this plan
> was gated on is **resolved** — every `<from FDC-S3>` placeholder below is now
> locked. The locked decisions consumed here:
> - **READ signal = relay presence lookup** via the additive `presence_get`
>   inbox action, answered from `h.Network().Connectedness(pid)` **plus a
>   NET-NEW connectedness-seeded per-peer last-seen map** (seeded by the
>   `EvtPeerConnectednessChanged` handler at `go-relay-server/main.go:145-163`),
>   **preferring FDC-09's self-published `presence_set` state when present**.
> - **Reservation-table truth is OUT** (go-libp2p circuitv2 exposes no public
>   reservation-enumeration API; coarse connectedness + last-seen is sufficient
>   for a HINT). The old "(A) connectedness / (B) reservation-table / (C)
>   last-seen" letters are **dropped** to avoid colliding with FDC-S3's own
>   A/B/C (read=A `presence_get` / write=C `presence_set` / B gossipsub rejected).
> - **Wire schema (canonical):** `{ presence: reachable | unreachable | unknown,
>   ageMs }`. `reachable` requires `ageMs < relayTTL`; otherwise `unknown` —
>   **never silently `unreachable`**.
> - **Constants (device-tunable, inherited from FDC-S3):** relay presence-entry
>   TTL ≈ **180 s**; client-side `presence_get` cache TTL ≈ **10–15 s**.
> - **New hard gate (FDC-S3 Exit-Gate item 4):** a dedicated forced-wrong-value
>   RED — force `reachable` for an actually-offline peer ⇒ message **still
>   delivered** via inbox + push-to-wake (added below as **C7**).
>
> **What still gates closure (NOT the mechanism):** the **live-relay-env**
> closure **S1** (real reservation/connectedness truth + real-wire
> faster-than-probe + end-to-end NET-REL-07 additive-deploy safety) and the
> device-tuning of the TTL constants. These need a deployable relay (FDC-09
> coordinates the env per FDC-S3 risk note); they are NOT a mechanism decision.
>
> **Anchor drift note (verified 2026-06-27 on shared `new-orbit`):** concurrent
> FDC-01/02/03 restructured the send path and `p2p_service_impl.dart`; **every
> line anchor below was re-grounded** against live source (e.g. `probeRelay`
> moved `:4074→:4373`, the emphasis seam moved from the now-DELETED serial probe
> tail to the `unknownPresence` branch `:697-731`). Re-verify by **symbol**, not
> line, before editing.

---

## Source Of Truth
- **Proposal** §6.3 ("online-ish, never foreground"), §8 row **P1-1**, §11 q2/q5.
  Honor the corrections: presence is an **emphasis hint, never a replacement
  for the inbox** (§6.3); the relay can only report *"online-ish, TTL-lagged"*,
  **never foreground/background** (`main.go:145-163` tracks socket connectedness
  only); relay changes must be **additive-only** (NET-REL-07).
- **FDC-S3 decision (CLOSED 2026-06-27)** — `FDC-S3-presence-signal-decision.md`,
  §"Canonical contract consumed by FDC-08 / FDC-09" + §"Carry-forward to FDC-08
  finalize (read side)". **This is now the binding read-side contract** (resolver
  = connectedness + net-new last-seen map, prefer `presence_set`; reservation
  truth OUT; schema `{presence, ageMs}`; constants TTL 180 s / cache 10–15 s;
  add the forced-wrong-value RED). Supersedes any provisional value here.
- **`scripts/run_test_gates.sh`** wins over prose for gate membership/counts.
- **Naming contract (canonical; supersedes any inconsistent inline mention below):**
  the relay presence **READ** action is `presence_get` (symmetric with FDC-09's
  `presence_set`, mirroring the existing `group_store`/`group_retrieve` pair) —
  drop the phantom `presence_lookup`. The move-feature gate token is
  `p2p_get_presence` (verb_noun, matching `p2p_dial_peer`), superseding any
  `p2p_presence_lookup` reference. Apply consistently with FDC-09.
- **This epic's roadmap FDC-00** (sequencing; P1-1 lands in proposal Phase 2,
  the "additive relay deploy" phase — see §9.3). **Order: FDC-10 → FDC-08 →
  FDC-09** (serial on `inbox.go`; FDC-08 owns `presence_store.go` creation, the
  connectedness-seeded last-seen map + read; FDC-09 adds the `presence_set`
  write + heartbeat that enriches the same map).

## Session Classification
**implementation-ready (host tiers) + live-relay-env-gated (closure).** FDC-S3
is closed, so the relay truth-source is **decided** (connectedness + net-new
last-seen map; reservation truth OUT) and the host-testable portions (client
cache, enum, bridge cmd shape, send-path three-way emphasis, relay dispatch +
`ageMs`/staleness logic, additive-contract) are **fully implementation-ready
now**. The remaining gate is the **live-relay-env closure** S1 (real-wire
faster-than-probe + end-to-end NET-REL-07 additive-deploy) and **device-tuning**
of the TTL constants — a deploy/measurement task, **not** a mechanism decision.

## Exact Problem Statement
**What's missing.** There is no cheap, up-front "is this peer online-ish?"
signal to pick *direct-race-with-lazy-inbox* vs *inbox-first* emphasis (§6.3).
The only online/offline probe today is `probeRelay`
(`p2p_service_impl.dart:4373-4388`, move-feature gate `'p2p_probe_relay'` at
`:4374`) → bridge `relay:probe` → `RelayProbe` (`bridge.go:899`) →
`DialPeerViaRelay` (`node.go:1249-1304`) → `dialPeerViaRelayWithTimeout(peerId,
RelayProbeTimeout)` with `RelayProbeTimeout = 5s` (`config.go:30`). That is a
**blind circuit *dial*** — it actually opens a `/p2p-circuit` connection to learn
liveness, costs up to 5 s, and learns reservation-truth only by paying a dial.

**Who feels it.** Any sender deciding emphasis up front. NOTE: FDC-03 already
**removed the serial relay-probe→inbox tail** from the send path (the old
`send_chat_message_use_case.dart:1021-1086` seam no longer exists; all
unknown-presence sends now fire a concurrent inbox at **`:697-731`**). So the
worst-case *serial* cost is already mitigated — but there is still **no cheap
signal to choose lazy-inbox vs inbox-first**, so every unknown-presence send
fires the durable copy and races, even for a peer the relay already knows is
reachable. Presence supplies that missing up-front hint (and lets a known-offline
peer go inbox-first immediately).

**Why.** Reachability is **only learnable per-send via a dialing probe** with no
cached presence and no lightweight relay-side lookup. The relay already *knows*
connectedness (subscribes `EvtPeerConnectednessChanged`, `main.go:145-163`) but
exposes **no per-peer query**, and `RecordPeerSeen` (`business_metrics.go:77-81`)
is **HLL-only and discards the peer ID** — so there is *no* reusable per-peer
last-seen map. A net-new connectedness-seeded last-seen map is required.

**What must improve.** A new **additive inbox action** `presence_get` (request
`{action:"presence_get", to:<peerId>}`) returns `{ presence: reachable |
unreachable | unknown, ageMs }` from the relay's `h.Network().Connectedness(pid)`
+ the net-new last-seen map (preferring FDC-09's self-published `presence_set`
state when present) **without dialing a circuit**. Client caches the answer
short-TTL (10–15 s) and uses it as the §6.3 emphasis hint (direct-race-vs-
inbox-first), replacing the blind 5 s dial on the *decision* path (the
`probeRelay`/`relay:probe` primitive itself stays for introductions).

**What must stay unchanged (preserved sentinels).**
- **NET-REL-07 additive-only**: an older client that never sends `action:"presence_get"`
  must behave byte-identically; an older relay that doesn't know the action must
  return today's `{"status":"ERROR","error":"Unknown action: presence_get"}`
  (inbox.go:1713) and the client must degrade to `unknown` (today's full
  concurrent race), **never** drop the message. Preserved sentinel:
  `INBOX_UNKNOWN_ACTION_DEGRADES_TO_UNKNOWN_PRESENCE`.
- **Presence is hint-only**: the durable inbox deposit (storeInInbox) still
  always fires; `reachable==true` must **not** suppress the safety net (§6.3).
  Preserved sentinel: `PRESENCE_NEVER_REPLACES_INBOX`.
- **Never reports foreground**: the response carries "online-ish", never a
  foreground/background claim (§1, §6.3). Preserved sentinel:
  `PRESENCE_IS_ONLINE_ISH_NOT_FOREGROUND`.
- Existing `store`/`retrieve`/`retrieve_pending`/`ack`/`register_token`/group
  actions unchanged (inbox.go:1530-1713); store-dedup-by-messageId unchanged
  (do NOT touch — backend_memory.go:121-142 / backend_redis.go:272-295).

## Root Cause (verify→refute confirmed; anchors re-grounded 2026-06-27)
- **No relay-side per-peer presence query.** `inboxRequest`
  (`inbox.go:1424-1445`) has no presence action; the dispatch switch
  (`inbox.go:1530`, 10 cases) ends in `default: Unknown action: %s`
  (`:1712-1713`). `HandleInboxStream(s, inbox, groupInbox)` (`inbox.go:1497`
  def; wired `main.go:117-118`) is **not handed the host**, so it cannot answer
  `h.Network().Connectedness(pid)` — this is the **primary structural gap** a
  presence action must close (inject host/resolver into the signature). **Verified.**
- **No reusable last-seen feed.** `RecordPeerSeen` (`business_metrics.go:77-81`)
  is invoked by the connectedness handler (`main.go:145-163`, Connected branch
  `:149-154`, call at `:152`) but is **HLL-only** — it `.Insert()`s into three
  HyperLogLog registers (which hash + discard the peer ID), exposing only
  cardinality `Estimate()`. **It cannot be read per-peer** ⇒ the connectedness-
  seeded last-seen map is **net-new relay state**, not a reuse of `RecordPeerSeen`.
  **Verified.**
- **Liveness is learned by dialing.** `probeRelay` →
  `callP2PRelayProbe` (`p2p_bridge_client.dart:157-184`, `cmd:'relay:probe'`,
  5 s `.timeout`) → `RelayProbe` (`bridge.go:899`) → `n.DialPeerViaRelay`
  (`node.go:1249-1304`) → `dialPeerViaRelayWithTimeout(…, RelayProbeTimeout=5s)`
  which **`h.Connect`s a circuit address** (multi-relay loop
  `buildRelaySelector(nil).ForEach`, `node.go:1270-1272`). It's a dial, not a
  lookup. **Verified.**
- **No client presence cache.** `p2p_service_impl.dart` caches *transport*
  (`_learnedTransport` field `:133` / `lastKnownGoodTransport` read-time TTL
  eviction `:4399-4421` — `clock.now()`-based, `withClock`-testable, 30 s local /
  10 min direct·relay, evicts via `.remove()` on read) but has **no presence
  cache**. The short-TTL presence cache reuses that read-time TTL-eviction
  pattern. **Verified.**

**Refuted / do-NOT-re-introduce.**
- Do **not** add store idempotency/dedup — it already exists
  (backend_memory.go:121-142, backend_redis.go:272-295, inbox_store.go:7,14);
  proposal §8 P2-2 explicitly says don't rebuild it.
- Do **not** reuse `RecordPeerSeen` as the last-seen feed — it is HLL-only and
  discards the peer ID (refuted above). The last-seen map is net-new.
- Do **not** infer foreground/background from connectedness — wrong on iOS
  (§1, §6.3 `main.go:145-163`). Presence is "online-ish" only.
- Do **not** assume a Go-side string dispatch for the bridge cmd — there is
  **none**. `bridge.go` exports functions directly (gomobile FFI); the
  `relay:presence_get` → fn binding lives **only** in the Dart `_cmdMap`
  (`go_bridge_client.dart`). Go side = export a new `PresenceGet(paramsJSON)
  string` (in a NEW `bridge_presence.go`); no Go registration step.
- Do **not** add reservation-table truth — go-libp2p circuitv2 exposes no
  public reservation-enumeration API; FDC-S3 ruled it **OUT** (coarse
  connectedness + last-seen suffices for a HINT).
- Do **not** make presence a delivery gate (never let `reachable==false`
  *skip* the inbox or `reachable==true` *skip* it either — §6.3).
- Do **not** repurpose `probeRelay`/`relay:probe` to mean "lookup" — keep it
  (introduction_outbound_delivery.dart still uses it); presence is a
  **new** action/cmd so older clients/relays stay valid (NET-REL-07).

## Real Scope
**In scope.**
- **Relay**: new `presence_get` inbox action (named handler `handlePresenceGet`,
  not an inline switch arm) + the **locked resolver** = `h.Network().
  Connectedness(pid)` **+ a NET-NEW connectedness-seeded last-seen map**
  (preferring FDC-09's `presence_set` self-published state when present),
  returning `{ presence, ageMs }` where `ageMs ≥ relayTTL(≈180 s) ⇒ unknown`.
  Requires (a) a **new `presence_store.go`** holding the TTL'd map (FDC-08 owns
  its creation; FDC-09 co-owns the write side), (b) a **last-seen WRITE in the
  connectedness handler** (`main.go:145-163`), and (c) **injecting the host/
  resolver into `HandleInboxStream`** (`inbox.go:1497` signature + `main.go:117-118`
  wiring — today it receives only `inbox, groupInbox`). **Concurrency:** the map
  is written by the connectedness goroutine and read by the per-stream goroutine
  ⇒ **`sync.Map`/mutex-guarded + `go test -race` (unconditional, not optional).**
- **Go host client**: `RelayPresenceLookup(peerId)` over `InboxProtocol`
  (`go-mknoon/node/inbox.go`; template `InboxStoreDetailed` `:107-111`, stream
  open `h.NewStream(ctx, relay.ID, InboxProtocol)` `:145`, multi-relay
  `buildRelaySelector(nil).ForEach` mirror of `node.go:1270-1272`) + a new
  exported bridge fn `PresenceGet(paramsJSON) string` in a **NEW
  `go-mknoon/bridge/bridge_presence.go`** (template `RelayProbe` `bridge.go:899`;
  do NOT append to the 2880-line `bridge.go`). **No Go-side cmd registration** —
  gomobile exposes the exported fn; the string binding is Dart-only.
- **Dart**: `relay:presence_get` cmd spec — add `'relay:presence_get':
  _CmdSpec('relayPresenceGet', true)` to `_cmdMap` (`go_bridge_client.dart`,
  near `:114`); `callP2PRelayPresence` (`p2p_bridge_client.dart`, template
  `callP2PRelayProbe` `:157-184`); `RelayPresence` enum + `lookupRelayPresence`
  interface method (`p2p_service.dart`, near the `RelayProbeResult` enum `:9-13` /
  `probeRelay` decl `:192`); impl with **short-TTL (10–15 s) client cache**
  (`p2p_service_impl.dart`, mirror `lastKnownGoodTransport` `:4399-4421`).
- **Move-feature gate (REQUIRED — account-migration safety):** `lookupRelayPresence` is a NEW relay
  round-trip primitive, and the send use-case is **not** gated at the top — so its impl MUST call
  `_allowsAccountNetworkSideEffects('p2p_get_presence')` as its **first line** (mirror `probeRelay`
  at `p2p_service_impl.dart:4374`) and return `RelayPresence.unknown` (no bridge call) when an
  account-move has paused network side-effects. The gate (`_allowsAccountNetworkSideEffects`
  `:447-464` → `account_migration_runtime_network_gate.dart:14-31`) is **100% migration-state-driven**:
  pause states = `migrationPairing` / `migrationImportStaging` / `migrationVerifiedWaitingForCutover`
  / `migrationFailedCleanupRequired` / `migrationExportingNetworkPaused` / `migrationCutoverPendingBlocked`
  / `migratedOut` / fail-closed. **The token string is a LOG LABEL ONLY** — it is never validated
  against an allowlist/enum, so `'p2p_get_presence'` needs **no registration anywhere** (any string
  works; it only appears in the `P2P_SERVICE_ACCOUNT_MIGRATION_NETWORK_BLOCKED` audit event). **Lock:**
  a RED test — gate-false ⇒ no bridge call, returns `unknown`; mutation = drop the gate ⇒ bridge invoked.
- Wire the presence hint into the send decision **as emphasis only** (§6.3
  three-way: reachable→lazy inbox / unreachable→inbox-first+push / unknown→today)
  at the `unknownPresence` seam (`send_chat_message_use_case.dart:697-731`), NOT
  the deleted serial probe tail.

**Out of scope (owning FDC-xx).**
- The full §6.2 staggered ranked race / concurrent-inbox generalization →
  **FDC-02/03** (already landed; this plan only supplies the *hint* and must not
  rewrite the race ladder — the race structure `:742-1002` is stable).
- `warmPeer` eager warm → **FDC-04** (landed).
- The `presence_set` self-publish WRITE action + foreground/background heartbeat →
  **FDC-09** (FDC-08 reads from the shared store; FDC-09 writes to it).
- gossipsub heartbeat beacon alternative (§6.3) → **REJECTED by FDC-S3** (Option B:
  continuous churn/battery, useless on iOS background, net-new mesh — pubsub stays
  group-only). Not an option; do not re-open.
- Redis durable backend → **FDC-10** (lands before FDC-08; durability-ordering).
- Reservation-exact truth (go-libp2p relay-service internals) → **OUT** (FDC-S3).

## Files To Inspect Next
> Line anchors verified on `new-orbit` 2026-06-27; concurrent dev drifts them —
> re-verify by symbol. (`<symbol> :N` = current line.)

**Production — relay:** `go-relay-server/inbox.go` (`inboxRequest` :1424,
`inboxResponse` :1447 — **add `Presence`/`AgeMs` fields**, dispatch
`switch req.Action` :1530, `default: Unknown action` :1712-1713,
`HandleInboxStream` :1497 — **add host/resolver param**, store→push
`SendNotification` :867 — **conditional on `metadata.ShouldNotify`, not every
store**); `go-relay-server/main.go` (host create / `EnableRelayService` :62-76;
`HandleInboxStream` wiring :117-118; connectedness sub :138-141, handler
goroutine :145-163, Connected branch :149-154, `RecordPeerSeen` call :152 —
**the last-seen-map WRITE seam**); `go-relay-server/business_metrics.go`
(`RecordPeerSeen` :77-81 — **HLL-only, discards peer ID, NOT reusable**;
last-seen map is net-new); `go-relay-server/limits.go` (`MaxReservationsPerPeer=1`
:82, global `MaxReservations` default 512 :42/:80); **NEW** `presence_store.go`.
**Production — Go host client/bridge:** `go-mknoon/node/inbox.go`
(`inboxRequest`/`inboxResponse` :23-32/:34-45, `InboxStoreDetailed` :107-111 as
the stream-action template, stream open `h.NewStream(ctx, relay.ID,
InboxProtocol)` :145); `go-mknoon/node/node.go` (`DialPeerViaRelay` :1249-1304 —
*replaced on the decision path*; multi-relay `buildRelaySelector(nil).ForEach`
:1270-1272); `go-mknoon/bridge/bridge.go` (`RelayProbe` :899 template;
`InboxStore` :1116; 2880 lines — **put new fn in NEW `bridge_presence.go`**).
**Production — Dart:** `lib/core/bridge/go_bridge_client.dart` (`_cmdMap`:
`relay:probe` :114, `inbox:store` :122; lookup at :843); `lib/core/bridge/p2p_bridge_client.dart`
(`callP2PRelayProbe` :157-184, flow events `P2P_RELAY_PROBE_REQUEST/RESPONSE`);
`lib/core/utils/flow_event_emitter.dart` (`emitFlowEvent` :202-219, test sink
`debugSetFlowEventSink` :38); `lib/core/services/p2p_service.dart`
(`RelayProbeResult` enum :9-13, `probeRelay` :192 interface);
`lib/core/services/p2p_service_impl.dart` (`_allowsAccountNetworkSideEffects`
:447-464, `probeRelay` :4373-4388 gate `'p2p_probe_relay'` :4374, `isConnectedToPeer`
:4391, `lastKnownGoodTransport` TTL pattern :4399-4421, `_learnedTransport` field
:133); `lib/features/conversation/application/send_chat_message_use_case.dart`
(**`unknownPresence` seam :697-731** — emphasis-hint insertion point; the
FDC-08 TODO comment is literally at :693-694; unconditional inbox backstop
:1179-1199; race structure :742-1002 stable).
**Tests:** `go-relay-server/inbox_test.go` (note unrelated `presence_ping`
*message* test :838 — low collision risk), `inbox_dedup_test.go`,
`protocol_contract_test.go` (additive-action contract home);
`go-mknoon/node/inbox_parse_test.go`, `multi_relay_test.go`
(`TestDialPeerViaRelay_TriesSecondRelayWhenFirstFails` :293), `bridge/bridge_test.go`
(SetStreamHandler capture idiom :5050); Dart send + `p2p_service_impl` unit tests
under `test/` (1to1 gate); `integration_test/{wifi_relay_fallback_smoke,transport_e2e}_test.dart`
(`TRANSPORT_TESTS` :179-180).
**Dependency-only context:** `go-mknoon/node/config.go` (`RelayProbeTimeout`
:30, `InboxProtocol = "/mknoon/inbox/1.0.0"` :22).

## Existing Tests Covering This Area
| Test | Exists? | Gate array |
|---|---|---|
| `go-relay-server/inbox_test.go` | YES | `cd go-relay-server && go test ./...` |
| `go-relay-server/inbox_dedup_test.go` | YES | go-relay-server |
| `go-relay-server/protocol_contract_test.go` | YES | go-relay-server (additive-contract home) |
| `go-mknoon/node/inbox_parse_test.go` | YES | `cd go-mknoon && go test ./...` |
| `go-mknoon/node/multi_relay_test.go` (`DialPeerViaRelay_TriesSecondRelay…`) | YES | go-mknoon |
| `go-mknoon/bridge/bridge_test.go` | YES | go-mknoon bridge |
| `send_chat_message_use_case_test.dart` | YES | listed in `run_test_gates.sh` 1to1 array |
| `p2p_service_impl_test.dart` | YES | 1to1 array |
| `integration_test/wifi_relay_fallback_smoke_test.dart` | YES | `TRANSPORT_TESTS` array (`run_test_gates.sh:179`) |
| `integration_test/transport_e2e_test.dart` | YES | `TRANSPORT_TESTS` (:180) |
| **`presence_get`-action relay test** (`inbox_presence_test.go` R1–R6) | **MISSING** | add to go-relay-server (auto-run by `go test ./...`) |
| **`RelayPresenceLookup` node test** (`inbox_presence_test.go` N1–N3) | **MISSING** | add to go-mknoon node |
| **`lookupRelayPresence` Dart unit + cache test** (C1–C4) | **MISSING** | `test/core/bridge/**` + `test/core/services/**` AUTO-glob into `core-host-all` |
| **`send_presence_emphasis_test.dart`** (C5–C7) | **MISSING** | `test/features/**` auto-globs `feature-host-all` only — **manually append to `ONE_TO_ONE_TESTS` (`run_test_gates.sh` array, before `)` at :85)** for the `1to1` gate |
| **`relay_presence_get_smoke_test.dart`** real-wire sim (S1) | **MISSING (live-relay-env-gated)** | `classify_path()` case in `check_reliability_simulation_discovery.sh` (mirror transport example :255-267) **+ append to `TRANSPORT_TESTS`** |

## RED Test Catalog
> Tiers: **Go-relay unit** / **Go-node(client) unit** / **Dart application unit**
> / **transport integration** / **simulator (real relay)**. Lowest tier that
> still fails for the real reason. Each shared-result row names a distinct
> flow-event discriminator.

### Client / Dart (fully detailable NOW)

**C1 — Dart: presence cmd shape + canonical schema + flow events**
`test/core/bridge/p2p_bridge_client_presence_test.dart::callP2PRelayPresence sends relay:presence_get with to-peer and parses {presence, ageMs}`
- Tier: Dart application unit. Setup: fake `Bridge` echoing a captured request;
  return the canonical schema `{"ok":true,"presence":"reachable","ageMs":1200}`.
  (Mirror `callP2PRelayProbe` `p2p_bridge_client.dart:157-184`; assert via
  `debugSetFlowEventSink` `flow_event_emitter.dart:38`.)
- RED-on-HEAD: `callP2PRelayPresence` does not exist (compile-fail) → real
  reason: no presence bridge call.
- GREEN-asserts: request `cmd=='relay:presence_get'`, `payload.peerId==peer`; emits
  `P2P_RELAY_PRESENCE_REQUEST` then `P2P_RELAY_PRESENCE_RESPONSE`; parses
  `RelayPresence.reachable` **and surfaces `ageMs`** (so the staleness rule C4/N-tier
  can see it).
- Mutation-re-reds: change cmd to `'relay:probe'` → relay test/back-compat
  diverges; drop the RESPONSE flow event → assert fails; ignore `ageMs` in the
  parse → C4 staleness re-read can't fire → its dependent assert flips.
- Discriminator: distinct events `P2P_RELAY_PRESENCE_*` (NOT `P2P_RELAY_PROBE_*`)
  prove the new path fired, not the legacy probe.

**C2 — Dart: unknown-action / older-relay degrades to `unknown` (NET-REL-07)**
`..._presence_test.dart::lookupRelayPresence maps Unknown action ERROR to RelayPresence.unknown`
- Tier: Dart unit. Setup: bridge returns
  `{"status":"ERROR","error":"Unknown action: presence_get"}` (the literal
  inbox.go:1713 string).
- RED-on-HEAD: method absent. GREEN: returns `RelayPresence.unknown`, NOT
  `unreachable`, emits `P2P_RELAY_PRESENCE_UNKNOWN_ACTION` discriminator.
- Mutation: map unknown-action→`unreachable` → C2 + the
  `PRESENCE_NEVER_REPLACES_INBOX` send test go RED (would inbox-first-suppress a
  maybe-online peer against an old relay). **Locks NET-REL-07 degrade.**

**C3 — Dart: short-TTL cache hit avoids a second bridge call**
`test/core/services/p2p_service_impl_presence_cache_test.dart::lookupRelayPresence caches within TTL and re-queries after expiry`
- Tier: Dart unit, `withClock`. Setup: counting fake bridge; call twice inside
  the cache TTL (**10–15 s**, FDC-S3-locked, device-tunable), then advance past
  TTL, call again.
- RED-on-HEAD: `lookupRelayPresence` absent. GREEN: bridge invoked **once**
  within TTL (second call served from cache), **twice** after expiry;
  eviction mirrors `lastKnownGoodTransport` read-time pattern (`:4399-4421`,
  `clock.now()`-based).
- Mutation: remove the cache short-circuit → 2 bridge calls within TTL → RED.
- Discriminator: cache-hit emits `P2P_RELAY_PRESENCE_CACHE_HIT` vs miss
  `P2P_RELAY_PRESENCE_REQUEST`.

**C4 — Dart: cache cleared / never trusted when stale (presence is TTL-lagged)**
`..._presence_cache_test.dart::expired presence entry is evicted on read`
- Tier: Dart unit. RED: absent. GREEN: a `reachable` entry older than TTL
  returns `unknown` (re-query), never a stale `reachable`. Mutation: drop the
  age check → returns stale `reachable` → RED. Locks "emphasis, TTL-lagged".

**C3b — Dart: account-move pause ⇒ `lookupRelayPresence` makes NO bridge call, returns `unknown`**
`..._presence_cache_test.dart::lookupRelayPresence is gated by _allowsAccountNetworkSideEffects`
- Tier: Dart unit. Setup: counting fake bridge; put the migration authority in a
  pause state (e.g. `migrationExportingNetworkPaused` / fail-closed) so
  `_allowsAccountNetworkSideEffects('p2p_get_presence')` returns false.
- RED-on-HEAD: `lookupRelayPresence` absent. GREEN: **zero** bridge calls;
  returns `RelayPresence.unknown`; emits
  `P2P_SERVICE_ACCOUNT_MIGRATION_NETWORK_BLOCKED{operation:'p2p_get_presence'}`.
- Mutation: drop the gate (make it the first line a no-op) → bridge IS invoked
  → RED. Locks the move-feature safety from Real Scope. (Token needs **no**
  allowlist registration — it is a log label only; the gate is migration-state-
  driven.)

**C5 — Dart send-path: presence is emphasis-only, inbox always fires**
`test/features/conversation/.../send_presence_emphasis_test.dart::reachable presence keeps the durable inbox deposit (lazy, not suppressed)`
- Tier: Dart application unit (send use-case with fake p2pService returning
  `RelayPresence.reachable`). Insert at the `unknownPresence` seam
  (`send_chat_message_use_case.dart:697-731`); the FDC-02/03 race structure
  (`:742-1002`) is **stable/landed** — this row asserts the new emphasis branch,
  it does **not** rewrite the race.
- RED-on-HEAD: today there is no presence branch (comment `:693-694` literally
  says "this is FDC-08; everything non-connected/non-local is treated as UNKNOWN
  → concurrent inbox"). Asserts the *new* `reachable` branch still fires the
  concurrent inbox deposit (`:710-731` `storeInInbox`).
- GREEN: with `reachable`, inbox deposit still invoked (lazy = fire-don't-await,
  not suppressed), live legs emphasized; emits
  `CHAT_MSG_PRESENCE_EMPHASIS{presence:reachable}`.
- Mutation: make `reachable` skip `storeInInbox` → RED (`PRESENCE_NEVER_REPLACES_INBOX`).
- Discriminator: `CHAT_MSG_PRESENCE_EMPHASIS` event with `presence` field
  distinguishes reachable/unreachable/unknown branches.

**C6 — Dart send-path: `unreachable` ⇒ inbox-first custody + push-to-wake; live best-effort**
`..._presence_emphasis_test.dart::unreachable presence commits inbox first then push`
- Tier: Dart application unit. RED: no presence branch. GREEN: order = inbox
  deposit committed before awaiting live legs; emits
  `CHAT_MSG_PRESENCE_EMPHASIS{presence:unreachable}` + push-to-wake. Mutation:
  reorder live-first → RED. **Does not** drop live legs (still best-effort).

**C7 — Dart send-path: forced-WRONG presence (`reachable` for an actually-offline peer) STILL delivers via inbox + push-to-wake** ⭐ **(FDC-S3 Exit-Gate item 4 — the hard load-bearing gate)**
`..._presence_emphasis_test.dart::reachable hint for an offline peer still deposits the durable copy (presence never load-bearing)`
- Tier: Dart application unit. Setup: fake p2pService returns
  `RelayPresence.reachable` **but** all live legs fail (peer is really offline /
  backgrounded). This is the adversarial case S3 demands and the read-side twin
  of FDC-09's `TC-09-13` (`TestWakePush_StillDelivers_WhenPresenceWrong`).
- RED-on-HEAD: no presence branch exists → the new `reachable`-lazy path could
  (wrongly) be written to *defer/skip* the durable copy, losing the message.
- GREEN: the durable inbox copy is **still deposited** (the `reachable` branch's
  "lazy" = non-blocking, **never** non-firing); because the fresh chat-message
  store triggers the relay's `metadata.ShouldNotify` push (`inbox.go:867`), the
  backgrounded peer is still woken — assert `CHAT_MSG_PRESENCE_EMPHASIS{presence:
  reachable}` **AND** the inbox-deposit future resolved (or the unacked→inbox
  backstop `:1179-1199` fired). Push-to-wake is satisfied by the store, not by a
  presence-conditional push.
- Mutation: make `reachable` defer the inbox deposit until live-legs settle (or
  skip it) → on an all-fail send the message is lost → RED. **This is the single
  test that proves presence is a HINT, not a delivery gate.**
- Discriminator: assert `CHAT_MSG_SEND_CONCURRENT_INBOX_BEGIN` (or the backstop
  store) **fired** even though `presence==reachable` — distinguishes "lazy" from
  "skipped".

### Go host client (node) — detailable NOW (truth-source-agnostic)

**N1 — node: `RelayPresenceLookup` sends `action:"presence_get"` frame + decodes `{presence, ageMs}`**
`go-mknoon/node/inbox_presence_test.go::TestRelayPresenceLookup_SendsPresenceAction`
- Tier: Go-node unit. Setup: in-test relay host `SetStreamHandler(InboxProtocol,…)`
  capturing the request frame (mirror `multi_relay_test.go:293` /
  `bridge_test.go:5050` handler-capture idiom), replies the canonical schema
  `{"status":"OK","presence":"reachable","ageMs":1200}`.
- RED-on-HEAD: `RelayPresenceLookup` undefined (compile-fail). GREEN: frame
  decodes to `{action:"presence_get", to:<peerId>}`; returns `Presence=reachable`
  **and `AgeMs=1200`** (the node-side `inboxResponse` `:34-45` gains
  `Presence`/`AgeMs` fields).
- Mutation: send `action:"store"` → handler asserts wrong action → RED; drop the
  `AgeMs` field from the decode → N-tier staleness parity assert fails.

**N2 — node: presence lookup tries next relay on failure (parity w/ probe)**
`inbox_presence_test.go::TestRelayPresenceLookup_TriesSecondRelay`
- Tier: Go-node unit (mirror `DialPeerViaRelay_TriesSecondRelayWhenFirstFails`
  multi_relay_test.go:293). RED: undefined. GREEN: first relay errors → second
  relay queried via `buildRelaySelector(nil).ForEach`. Mutation: stop after
  first → RED.

**N3 — node: malformed/old-relay reply ⇒ `unknown`, never throws away the send**
`inbox_presence_test.go::TestRelayPresenceLookup_UnknownActionIsUnknown`
- Tier: Go-node unit. Relay replies the literal
  `{"status":"ERROR","error":"Unknown action: presence_get"}`. RED: undefined.
  GREEN: returns presence=`unknown` (no error propagated as fatal). Mutation:
  treat ERROR as `unreachable` → RED (pairs with C2). **NET-REL-07 lock.**

### Go relay unit — resolver locked (FDC-S3: connectedness + net-new last-seen map; reservation truth OUT)

**R1 — relay: `presence_get` returns reachable for a connected peer**
`go-relay-server/inbox_presence_test.go::TestPresenceGet_ReturnsReachableForConnectedPeer`
- Tier: Go-relay unit. Setup (LOCKED): stand up relay host + a peer with a live
  socket connection (so `h.Network().Connectedness(pid)==Connected`) **and** a
  fresh last-seen entry (`ageMs < relayTTL`); send `{action:"presence_get",
  to:peer}` to `handlePresenceGet`.
- RED-on-HEAD: dispatch has no `case "presence_get"` → returns
  `Unknown action: presence_get` (`inbox.go:1712-1713`). GREEN: `{status:OK,
  presence:"reachable", ageMs:<small>}`. Mutation: hardcode `unreachable` → RED.
- **Seam:** requires `HandleInboxStream` (`inbox.go:1497`) to receive the host +
  presence store (signature change; wiring `main.go:117-118`) so it can read
  `Connectedness(pid)` + the last-seen map. Resolver = connectedness **prefer
  `presence_set` self-published state when present** (FDC-09 writes it; absent →
  connectedness fallback, so R1 passes before FDC-09 lands).

**R2 — relay: `presence_get` returns unreachable / online-ish-not-foreground**
`inbox_presence_test.go::TestPresenceGet_UnreachableForDisconnected` and
`::TestPresenceResponseNeverClaimsForeground`
- Tier: Go-relay unit. GREEN: a peer that is not connected and has no fresh
  last-seen → `presence:"unreachable"`; the response schema has **no**
  foreground/background field (locks `PRESENCE_IS_ONLINE_ISH_NOT_FOREGROUND`).
  RED-on-HEAD: no action. Mutation: add a `foreground:true` field → schema test RED.

**R3 — relay: additive contract — unknown clients/actions untouched**
`go-relay-server/protocol_contract_test.go::TestPresenceGetIsAdditive`
- Tier: Go-relay unit. GREEN: every existing action
  (store/retrieve/retrieve_pending/ack/register_token/unregister_token/group_*)
  returns byte-identical responses with the `presence_get` case added; a client
  that never sends it is unaffected; an old relay still returns
  `Unknown action: presence_get`. RED-on-HEAD: trivially passes (no new action)
  — this is a **preservation lock**, kept green across the change. Mutation:
  changing any existing case while adding presence → RED. **NET-REL-07.**

**R4 — relay: presence never mutates inbox state (read-only action)**
`inbox_presence_test.go::TestPresenceGetDoesNotStoreOrConsume`
- Tier: Go-relay unit. GREEN: a `presence_get` query leaves the target's queue
  occupancy unchanged (no store, no ack-consume). RED: n/a until action exists.
  Mutation: accidentally enqueue/dequeue on presence → RED.

**R5 — relay: stale last-seen (`ageMs ≥ relayTTL`) ⇒ `unknown`, never silently `unreachable`; response carries `ageMs`**
`inbox_presence_test.go::TestPresenceGet_StaleLastSeenIsUnknown`
- Tier: Go-relay unit (`withClock`/injected clock for the relay store). Setup: a
  peer that is NOT currently connected but has a last-seen entry older than
  `relayTTL` (≈180 s). GREEN: `presence:"unknown"` (NOT `unreachable`) and
  `ageMs ≥ relayTTL` is reported. RED-on-HEAD: no action. Mutation: map
  stale→`unreachable` → RED (this is the freshness rule FDC-S3 §canonical-schema:
  "`reachable` requires `ageMs < TTL`; otherwise `unknown`, never silently
  `unreachable`"). Locks `PRESENCE_FRESHNESS_TTL` on the relay side.

**R6 — relay: connectedness handler seeds the net-new last-seen map; map is concurrency-safe**
`inbox_presence_test.go::TestConnectednessHandlerSeedsLastSeen` (+ `go test -race`)
- Tier: Go-relay unit. GREEN: firing `EvtPeerConnectednessChanged{Connected}`
  for a peer (the handler at `main.go:145-163`) records that peer's last-seen in
  the **net-new** `presence_store.go` map (NOT `RecordPeerSeen`, which is
  HLL-only and discards the peer ID); a subsequent `presence_get` then reports
  `reachable` with a small `ageMs`. RED-on-HEAD: no last-seen map exists.
  Mutation: stop the handler from writing the map → presence reads `unknown`
  forever → RED. **Concurrency lock:** the map is written by the connectedness
  goroutine and read by the per-stream `handlePresenceGet` goroutine ⇒ it MUST be
  `sync.Map`/mutex-guarded; `go test -race ./...` is the closure gate (an
  unguarded `map` fails `-race`). This was previously a *conditional* note; with
  the resolver locked it is **unconditional**.

### Simulator (real relay) — live-relay-env closure gate

**S1 — sim: live relay answers presence without a circuit dial** ⚠ live-relay-env-gated
`integration_test/relay_presence_get_smoke_test.dart` (renamed from
`relay_presence_lookup_smoke_test.dart` per FDC-S3) — `TRANSPORT_TESTS` +
`/sims 1to1 --only <N>` scenario.
- Tier: simulator against a **real deployed relay** (additive deploy required).
  Proves: (a) reachable peer → `reachable` faster than the 5 s probe ceiling
  (flow event `PRESENCE_DECISION_MS`, FDC-S3 Method 5); (b) backgrounded/offline
  peer → `unreachable`/`unknown` (and the connectedness-lag bound that fixes the
  TTL, FDC-S3 Method 1); (c) an **un-upgraded** relay returns
  `Unknown action: presence_get` and the client still delivers (NET-REL-07
  end-to-end, FDC-S3 Method 3). This is the **only** tier that validates real
  connectedness-truth + additive-deploy safety + the device-tuned TTL constants;
  closes after the additive relay redeploy (FDC-09 stands up the deployable env
  per FDC-S3 risk note). Distinct closure **category** from device-proof — it is
  a **live-relay-env** proof (FDC-00 §closure-categories).

## Test Coverage Matrix
| Spec case | Behavior props | Tier | Test file::name | RED reason on HEAD | Mutation revert | Acceptance gate cmd | Harness registration |
|---|---|---|---|---|---|---|---|
| New `relay:presence_get` cmd shape + `{presence,ageMs}` | cmd+payload+events+ageMs | Dart unit | p2p_bridge_client_presence_test.dart::C1 | `callP2PRelayPresence` absent | cmd→`relay:probe` / drop ageMs | `./scripts/run_host_test_gates.sh core-host-all` | `test/core/bridge/**` auto-globs |
| Old relay degrade → unknown (NET-REL-07) | unknown-action→`unknown` | Dart unit | p2p_bridge_client_presence_test.dart::C2 | method absent | unknown→`unreachable` | core-host-all | auto-glob |
| Short-TTL cache (10–15 s) | 1 call/TTL, re-query post-TTL | Dart unit | p2p_service_impl_presence_cache_test.dart::C3 | method absent | remove cache | core-host-all | `test/core/services/**` auto-glob |
| Stale evict | never trust stale reachable | Dart unit | p2p_service_impl_presence_cache_test.dart::C4 | method absent | drop age check | core-host-all | auto-glob |
| Move-gate: paused move ⇒ no bridge call | gate-false→`unknown` | Dart unit | p2p_service_impl_presence_cache_test.dart::C3b | gate absent | drop `_allowsAccountNetworkSideEffects` | core-host-all | `test/core/services/**` auto-glob |
| Emphasis-only, inbox always (reachable) | inbox still deposited | Dart app unit | send_presence_emphasis_test.dart::C5 | no presence branch (seam :697-731) | reachable skips inbox | `./scripts/run_test_gates.sh 1to1` | **append `send_presence_emphasis_test.dart` to `ONE_TO_ONE_TESTS`** (array, before `)` at :85; `test/features/**` auto-globs only `feature-host-all`, NOT the `1to1` gate) |
| Unreachable→inbox-first+push | order: inbox before live | Dart app unit | send_presence_emphasis_test.dart::C6 | no presence branch | live-first reorder | `./scripts/run_test_gates.sh 1to1` | same file (`ONE_TO_ONE_TESTS`) |
| ⭐ Wrong `reachable` for offline peer STILL delivers (load-bearing) | inbox deposited + push-to-wake despite wrong hint | Dart app unit | send_presence_emphasis_test.dart::C7 | no presence branch | reachable defers/skips inbox | `./scripts/run_test_gates.sh 1to1` | same file (`ONE_TO_ONE_TESTS`) |
| Client sends presence frame + decodes ageMs | `action:"presence_get"`+`to`+ageMs | Go-node unit | inbox_presence_test.go::N1 | `RelayPresenceLookup` undefined | action→`store` / drop ageMs | `cd go-mknoon && GOTOOLCHAIN=go1.25.0 go test ./...` | go test ./... |
| Multi-relay fallback | tries 2nd relay | Go-node unit | inbox_presence_test.go::N2 | undefined | stop after 1 | `cd go-mknoon && GOTOOLCHAIN=go1.25.0 go test ./...` | go test ./... |
| Old-relay reply→unknown | ERROR not fatal | Go-node unit | inbox_presence_test.go::N3 | undefined | ERROR→`unreachable` | `cd go-mknoon && GOTOOLCHAIN=go1.25.0 go test ./...` | go test ./... |
| Relay reachable answer | OK+`reachable`+ageMs | Go-relay unit | inbox_presence_test.go::R1 | no `case "presence_get"` | hardcode `unreachable` | `cd go-relay-server && GOTOOLCHAIN=go1.25.0 go test ./...` | go test ./... |
| Online-ish-not-foreground | no fg field | Go-relay unit | inbox_presence_test.go::R2 | no action | add `foreground` field | `cd go-relay-server && GOTOOLCHAIN=go1.25.0 go test ./...` | go test ./... |
| Additive contract | existing actions identical | Go-relay unit | protocol_contract_test.go::R3 | preservation (kept green) | mutate any existing case | `cd go-relay-server && GOTOOLCHAIN=go1.25.0 go test ./...` | go test ./... |
| Read-only presence | no store/consume | Go-relay unit | inbox_presence_test.go::R4 | no action | enqueue on presence | `cd go-relay-server && GOTOOLCHAIN=go1.25.0 go test ./...` | go test ./... |
| Stale last-seen ⇒ unknown + ageMs | age≥TTL→`unknown` not `unreachable` | Go-relay unit | inbox_presence_test.go::R5 | no action | stale→`unreachable` | `cd go-relay-server && GOTOOLCHAIN=go1.25.0 go test ./...` | go test ./... |
| Connectedness handler seeds net-new map + race-safe | handler writes last-seen; sync.Map | Go-relay unit | inbox_presence_test.go::R6 | no last-seen map | handler stops writing map | `cd go-relay-server && GOTOOLCHAIN=go1.25.0 go test -race ./...` | go test -race ./... |
| Real-wire faster-than-probe + additive-safe | live relay, NET-REL-07 e2e | sim (real relay) | relay_presence_get_smoke_test.dart::S1 | feature unshipped | n/a (live-relay-env) | `./scripts/run_test_gates.sh transport` + `/sims 1to1 --only <N>` | add `classify_path()` case in `check_reliability_simulation_discovery.sh` (mirror :255-267) + append to `TRANSPORT_TESTS` |

## Blind-Spot Sweep
- **Lifecycle/derived-state durability:** presence cache must survive nothing —
  it is intentionally short-TTL and **re-derived**; on resume/network-change it
  must be treated as cold (no stale `reachable` carried across a WiFi↔cellular
  switch). Covered by C4 (stale evict). Row: **C4**.
- **Sibling-surface consistency:** the introduction outbound path also uses
  `probeRelay` (introduction_outbound_delivery.dart:542). This plan **must not**
  silently change introduction behavior — keep `probeRelay` intact; presence is
  additive. Row: **R3/N3 (probe untouched)** + a justified guard note. If
  FDC-S3 later replaces probe in introductions, that's a separate FDC.
- **Destructive-action side-effects:** presence is **read-only** (must not
  store/ack/consume inbox entries). Row: **R4**.
- **Invariant re-verification under new transitions:** `reachable→false`
  between lookup and send (peer backgrounds, or the hint was simply **wrong**) —
  the inbox-always invariant makes this safe; presence is never load-bearing.
  Now locked by the dedicated forced-wrong-value test. Row: **C7** (primary) +
  **C5/C6**.
- **Push-to-wake actually fires on the reachable branch (nuance):** the relay's
  store→push (`inbox.go:867`) is **conditional on `metadata.ShouldNotify`**, not
  literally "every store" — duplicate / rejected-full stores skip push. But a
  fresh chat-message store sets `ShouldNotify`, so honoring "lazy = fire-don't-
  await" (the `reachable` branch still deposits the durable copy) **does** trigger
  the wake for a just-backgrounded peer. C7 asserts the deposit fires; do **not**
  over-claim "push fires on every store." Row: **C7** + S1 (real-wire push).
- **Go bridge concurrency (§10, per FDC-S5):** the bridge is **concurrent in the
  warm/steady state** (only `Node.Start`'s cold-path write lock serializes), so a
  presence lookup does not blanket-serialize behind the user's send; the residual
  risk is **native thread-pool / dial-limit contention** if lookups are unbounded.
  **N/A to host RED**, but flagged: presence must be **off the send-critical path**
  (cache-served or fire-before-typing), not awaited inline ahead of send — the
  10–15 s client cache (C3) bounds the call rate. Closure: **S1** (`PRESENCE_DECISION_MS`).
- **Relay-side concurrency (net-new shared state):** the last-seen map is written
  by the connectedness goroutine and read by the per-stream handler — covered by
  **R6** + `go test -race`. This is a real shared-mutable-state addition, not a
  justified N/A.

## Invariants (locked by tests)
- `INBOX_UNKNOWN_ACTION_DEGRADES_TO_UNKNOWN_PRESENCE` — C2, N3, R3.
- `PRESENCE_NEVER_REPLACES_INBOX` — C5, C6, R4.
- `PRESENCE_NEVER_LOAD_BEARING` (forced-wrong `reachable` for offline peer STILL
  delivers via inbox + push-to-wake) — **C7** (read-side) ↔ FDC-09 `TC-09-13`
  (relay-side). **This is the FDC-S3 hard acceptance gate.**
- `PRESENCE_IS_ONLINE_ISH_NOT_FOREGROUND` — R2.
- `PRESENCE_LOOKUP_IS_READ_ONLY` (no store/consume) — R4.
- `PRESENCE_FRESHNESS_TTL` (`ageMs ≥ TTL ⇒ unknown`, never silently `unreachable`)
  — R5 (relay), C4 (client cache).
- `PRESENCE_CACHE_SHORT_TTL_NEVER_STALE` (10–15 s) — C3, C4.
- `PRESENCE_MOVE_GATED` (account-move pause ⇒ no bridge call, `unknown`) — C3b.
- `LAST_SEEN_MAP_RACE_SAFE` (net-new shared map, sync.Map/mutex, `-race`) — R6.
- `PROBE_PATH_PRESERVED_FOR_INTRODUCTIONS` (relay:probe untouched) — N3/R3 + sibling note.

## Step-By-Step Implementation Plan
> RED first at the lowest failing tier. FDC-S3 is closed — the resolver is
> locked; the only remaining stop-ifs are the FDC-09 shared-store coordination
> and the live-relay-env closure.

1. **Snapshot the dirty tree** (`git status --short`) — the shared `new-orbit`
   tree has concurrent dev; record it so unrelated changes aren't reverted.
2. **RED N1–N3 + C1–C4 + C3b** (client tiers, resolver-agnostic). Seam: new
   `RelayPresenceLookup(peerId)` in `go-mknoon/node/inbox.go` (template:
   `InboxStoreDetailed` `:107-111`, stream open `:145`); new `Presence`/`AgeMs`
   fields on the node-side `inboxResponse` (`:34-45`). **No stop-if** — the wire
   shape is locked (`action:"presence_get"` → `{presence, ageMs}`).
3. Implement node `RelayPresenceLookup` → GREEN N1–N3. Seam: multi-relay
   `buildRelaySelector(nil).ForEach` (mirror `node.go:1270-1272`),
   `h.NewStream(ctx, relay.ID, InboxProtocol)` `:145`.
4. Bridge: add exported `PresenceGet(paramsJSON) string` in a **NEW
   `go-mknoon/bridge/bridge_presence.go`** (template `RelayProbe` `bridge.go:899`;
   do NOT touch the 2880-line `bridge.go`). Dart side: add `'relay:presence_get':
   _CmdSpec('relayPresenceGet', true)` to `_cmdMap` (`go_bridge_client.dart`
   near `:114`). **No Go-side dispatch registration** (gomobile exposes the fn).
5. Dart: `callP2PRelayPresence` (template `p2p_bridge_client.dart:157-184`);
   `RelayPresence` enum + `lookupRelayPresence` on `P2PService`
   (`p2p_service.dart` near `:9-13`/`:192`); impl with the **move-feature gate as
   the first line** (`_allowsAccountNetworkSideEffects('p2p_get_presence')` →
   `unknown` when paused) + short-TTL (10–15 s) cache (template
   `lastKnownGoodTransport` `:4399-4421`) → GREEN C1–C4 + C3b.
6. **RED C5/C6/C7** then wire the **emphasis-only** three-way branch at the
   `unknownPresence` seam (`send_chat_message_use_case.dart:697-731`; the
   FDC-08 TODO comment is at `:693-694`). The FDC-02/03 race (`:742-1002`) is
   **landed/stable** — do **not** rewrite it; replace the binary `unknownPresence`
   bool with `reachable→lazy-inbox` / `unreachable→inbox-first+push` /
   `unknown→today`, keeping the always-on inbox + the `:1179-1199` backstop.
   GREEN C5/C6; **C7 is the load-bearing gate** (forced-wrong `reachable` still
   deposits). **Stop-if:** none on the race (it's stable) — but keep the diff to
   the `:697-731` seam.
7. **RED R1–R6** (relay). Create the **NEW `presence_store.go`** (TTL'd last-seen
   map, `sync.Map`/mutex; FDC-08 owns creation, FDC-09 co-owns the write side);
   add the **last-seen WRITE** to the connectedness handler (`main.go:145-163`,
   on Connected; optionally stamp on NotConnected); inject the host + store into
   **`HandleInboxStream`** (`inbox.go:1497` signature + `main.go:117-118` wiring);
   add `case "presence_get":` to the dispatch (`inbox.go:1530`) delegating to a
   **named `handlePresenceGet`** that reads `Connectedness(pid)` + last-seen age
   (prefer `presence_set` state) → `{presence, ageMs}` with the freshness rule
   (age≥TTL→`unknown`). Add `Presence`/`AgeMs` to relay `inboxResponse` (`:1447`).
   GREEN R1–R6 (incl. `go test -race`). **Stop-if FDC-09:** coordinate so both
   plans read/write the **same** `presence_store.go` (avoid two divergent maps);
   per roadmap order FDC-08 lands the map+read first, FDC-09 rebases the write on.
8. **S1 (live-relay-env closure):** additive relay redeploy + sim scenario
   registration (`classify_path()` + `TRANSPORT_TESTS`); run transport gate +
   `/sims 1to1`. Device-tune the TTL constants (FDC-S3 Methods 1/2/5 inherited).

## Risks And Edge Cases
- **Truth-source mismatch** (connectedness lies on iOS socket-linger) — pinned
  by R1/R2/R5 + S1 real-wire. The proposal already declares this "online-ish,
  TTL-lagged"; the relay TTL (R5) and the client cache TTL bound the lie (C3/C4).
- **Stale last-seen reported as `unreachable`** (would wrongly push a maybe-online
  peer to inbox-first) — R5 locks age≥TTL→`unknown` not `unreachable`.
- **Old relay in the field** (NET-REL-07) — C2/N3/R3 + S1(c).
- **Presence-as-gate regression** (someone makes `unreachable` drop live legs or
  `reachable` skip/defer inbox) — **C7** (the load-bearing gate) + C5/C6/R4.
- **Just-backgrounded peer hinted `reachable`** loses its wake — covered because
  the `reachable` branch still deposits (fire-don't-await) → the fresh chat store
  triggers the relay push (`inbox.go:867`, ShouldNotify). C7 + S1.
- **Bridge HOL-block** — keep presence off the awaited send-critical path
  (cache-served, 10–15 s TTL bounds the rate); S1 `PRESENCE_DECISION_MS`.
- **Net-new shared relay state data race** — last-seen map written by
  connectedness goroutine, read by stream goroutine — R6 + `go test -race`.
- **Budget/timeout NET-REL lock regression** — run the full 1to1 + transport
  gates; do not retune `RelayProbeTimeout` here (out of scope).

## Device/Relay Proof Profile
- **Host-only closure:** C1–C7, C3b, N1–N3, R1–R6 (resolver locked by FDC-S3)
  close via `GOTOOLCHAIN=go1.25.0 go test [-race] ./...` (both Go modules) + host gates.
- **Requires live-relay-env (distinct from device-proof):** S1 — real
  connectedness-truth, real-wire faster-than-5s-probe, end-to-end NET-REL-07
  additive-deploy safety, and the device-tuned TTL constants (FDC-S3 Methods
  1/2/5). Closure scenario: `/sims 1to1 --only <N>` after additive relay redeploy
  (FDC-09 stands up the deployable env per FDC-S3 risk note).

## Acceptance Gates
> **GOTOOLCHAIN=go1.25.0 is MANDATORY** for both Go modules — go1.26.x panics
> `crypto/tls bug: where's my session ticket?` in node/bridge/relay pkgs (FAIL
> with 0 `--- FAIL:` lines; known hazard). The declared toolchain passes.
```
# Go relay (R1–R6 + additive contract)
cd /Users/I560101/Project-Sat/mknoon-2/flutter_app/go-relay-server && GOTOOLCHAIN=go1.25.0 go test ./...        # expect: ok (~191 pass / 0 fail / 2 skip, +R1–R6)
cd /Users/I560101/Project-Sat/mknoon-2/flutter_app/go-relay-server && GOTOOLCHAIN=go1.25.0 go test -race ./...  # R6 closure: last-seen map written by connectedness goroutine + read by stream goroutine MUST be race-clean
cd /Users/I560101/Project-Sat/mknoon-2/flutter_app/go-relay-server && make lint                                 # edits inbox.go + main.go handler + NEW presence_store.go
# Go host client + bridge (N1–N3, C1 wire)
cd /Users/I560101/Project-Sat/mknoon-2/flutter_app/go-mknoon && GOTOOLCHAIN=go1.25.0 go test ./...             # expect: ok (all pkgs PASS, ~1171 tests, +N1–N3)
cd /Users/I560101/Project-Sat/mknoon-2/flutter_app/go-mknoon && make lint                                       # edits node + NEW bridge_presence.go
# Dart host (C1–C7 + C3b)
./scripts/run_host_test_gates.sh core-host-all                                        # expect: 0 fail (~249/249 core files PASS) — C1–C4, C3b auto-glob
./scripts/run_test_gates.sh 1to1                                                       # expect: ~1226 baseline +N (C5/C6/C7 appended to ONE_TO_ONE_TESTS), 0 reg
# Transport integration + sim closure (S1) — after additive relay redeploy
./scripts/run_test_gates.sh transport                                                  # expect: +1 (live-relay-env-gated; skips on lone sim)
# group-safety floor (presence lookup must not become load-bearing for group delivery — Scope Guard)
./scripts/run_test_gates.sh groups                                                     # expect: 0 fail (no group regression)
./scripts/check_reliability_simulation_discovery.sh                                    # relay_presence_get_smoke_test.dart MUST list (else classify_path wiring is wrong)
/sims 1to1 --only <N — from the dry-run plan after S1 registration>
# Hygiene
flutter analyze    # 0 new
git diff --check
```

## Known-Failure Interpretation
- A RED at C1/N1/R1 with "undefined/compile-fail" is the **expected** TDD start,
  not a flake.
- `Unknown action: presence_get` returned by the relay before step 7 is the
  **correct** HEAD behavior (it is what NET-REL-07 degrade rides on) — R3 stays
  green throughout.
- **Go suite FAILs with 0 `--- FAIL:` lines** = the go1.26.x `crypto/tls`
  session-ticket panic, NOT FDC-08. Re-run under `GOTOOLCHAIN=go1.25.0`. (A go
  test also rewrites `testdata/interop_vectors.json` each run — revert it.)
- A **pre-existing `core-host-all` fail in `transport_metrics_privacy_test.dart`**
  (`sinceProcessStartMs` privacy-allowlist) is **FDC-S0/S1**, not FDC-08 — prove
  via stash-revert before blaming this plan.
- Transport/sim flakes (durable-media-upload, ambient_background guard) are
  **pre-existing**, not FDC-08 (see MEMORY 163/164 notes); interpret transport
  `-1/-2` against the known-flake list before blaming this plan.
- **Shared-tree hazard:** `new-orbit` has concurrent live dev (reaction/pause-flush
  work is uncommitted) — scope `git diff` to FDC-08's own files; do **not**
  `git checkout`/`stash`-revert shared test fakes.

## Done Criteria
- [x] FDC-S3 landed (closed 2026-06-27); resolver locked (connectedness +
      net-new last-seen map; reservation truth OUT); all `<from FDC-S3>` resolved.
- [ ] C1–C7 + C3b GREEN, each mutation re-reds (**C7 is the load-bearing gate**).
- [ ] N1–N3 GREEN, each mutation re-reds.
- [ ] R1–R6 GREEN; R3 additive-contract preserved; R6 race-clean; each mutation re-reds.
- [ ] `{presence, ageMs}` schema + freshness rule (age≥TTL→`unknown`) locked (R5, C1, C4).
- [ ] Move-feature gate locked (C3b): paused move ⇒ no bridge call, `unknown`.
- [ ] S1 closure run on real relay (faster-than-probe + NET-REL-07 e2e) + TTL device-tuned.
- [ ] `relay:probe` / introduction path provably unchanged.
- [ ] Both Go modules (`GOTOOLCHAIN=go1.25.0`, incl. `-race`) + 1to1 + transport
      gates green; `flutter analyze` 0 new; `git diff --check` clean.
- [ ] No store/dedup code touched; no foreground/background field added; `RecordPeerSeen` not reused.
- [ ] Every new exported identifier (`RelayPresenceLookup`, `PresenceGet` bridge fn, `handlePresenceGet`, the `presence_store.go` type, the `RelayPresence` Dart enum, `lookupRelayPresence`) carries a doc comment.

## Scope Guard (hard Do-not)
- **Do NOT** wire the presence lookup into the group send path or make it load-bearing for group delivery — presence emphasis is **1:1-send-only** and additive (NET-REL-07). **Group-safety floor:** `./scripts/run_test_gates.sh groups` 0-regress.
- Do **not** rewrite the send race ladder (FDC-02/03, **landed**; `:742-1002`
  stable) — only add the three-way emphasis at `:697-731` + always-on inbox
  invariant assertions.
- Do **not** remove/repurpose `probeRelay`/`relay:probe` (introductions use it).
- Do **not** add store idempotency/dedup (exists) or change any existing inbox
  action; do **not** reuse `RecordPeerSeen` (HLL-only, discards peer ID).
- Do **not** infer or report foreground/background; do **not** add reservation-
  table truth (FDC-S3 ruled it OUT).
- Do **not** make presence load-bearing for delivery (C7 enforces).
- Do **not** retune `RelayProbeTimeout`/`DialTimeout` (FDC-07 owns cold-start).
- **New bridge entrypoint isolation:** the `PresenceGet` bridge fn (+ any presence glue) goes in a **NEW** `go-mknoon/bridge/bridge_presence.go` — do **NOT** append it to the 2880-line `bridge.go`. Likewise the relay last-seen map goes in a **NEW** `go-relay-server/presence_store.go`, not inline in `inbox.go`/`main.go`.
- **Named relay handler (no inline arm):** the new `case "presence_get":` in the `switch req.Action` (`inbox.go:1530`, now 11 cases) must **delegate to a named `handlePresenceGet`**, not carry an inline arm.
- **Last-seen map race lock (UNCONDITIONAL — resolver locked):** the net-new last-seen map is written by the `main.go` connectedness goroutine (`:145-163`) and read by `HandleInboxStream`'s per-stream goroutine — it **MUST** be `sync.Map`- or mutex-guarded and covered by `GOTOOLCHAIN=go1.25.0 go test -race ./...` (R6); no unguarded shared map. (Was conditional on "if FDC-S3 picks mechanism C"; FDC-S3 decided it, so it is mandatory.)
- **Shared `presence_store.go` co-ownership:** FDC-08 creates it (connectedness-seeded read); FDC-09 adds the `presence_set` write. Coordinate so there is **one** map, not two divergent ones (FDC-09 step-1 stop-if).

## Accepted Differences
- Presence answers "online-ish (socket connectedness + last-seen)", **not**
  foreground and **not** reservation-exact — intentional, documented limitations
  (§6.3; reservation truth ruled OUT by FDC-S3). A lingering iOS socket can read
  `reachable` for a just-backgrounded peer — tolerable because presence is a HINT
  and the inbox always fires (locked by **C7**, not left as an assumption).
- A duplicate inbox copy may exist alongside a live delivery — harmless,
  receiver dedupes by `messageId` (§6.2; backend dedup already present).
- On a never-upgraded relay, presence is permanently `unknown` and the client
  behaves exactly as today — accepted (NET-REL-07).
- Before FDC-09 lands, the resolver has no `presence_set` state to prefer, so it
  falls back to connectedness + last-seen only — accepted (graceful; FDC-09
  enriches the same map later).

## Dependency Impact
- **FDC-S3: RESOLVED** (closed 2026-06-27) — no longer a gate; resolver + schema
  + constants locked. Remaining external dependency = the **live-relay-env** for
  S1 closure (FDC-09 stands it up per FDC-S3 risk note).
- **Sequencing (FDC-00 §Phase-2 / E + W3 tracks): FDC-10 → FDC-08 → FDC-09**,
  serial on `inbox.go`. FDC-10 (Redis durability) lands first to avoid raising
  inbox custody volume on a restart-losable backend — though presence itself is
  read-only and does not raise inbox volume.
- **Shared-store co-ownership with FDC-09:** FDC-08 **owns the creation** of
  `presence_store.go` (the connectedness-seeded last-seen map + read side) and
  the `HandleInboxStream` host/store injection; FDC-09 adds the `presence_set`
  write + heartbeat that enriches the **same** map. Both add a dispatch arm to
  `inbox.go` — serialize; land FDC-08's arm + map first, FDC-09 rebases.
- **Send-path collision:** the FDC-01/02/03/04 send-path rewrites are **landed**;
  this plan adds only the three-way emphasis at `:697-731` (race `:742-1002`
  untouched). Its relay/bridge/node edits are collision-free with the Dart-only
  plans.
- **Additive-only**: no migration, no client/relay version bump, no breaking
  protocol change (new action + new optional `{presence, ageMs}` response fields
  only; old relays return `Unknown action` → `unknown`).
