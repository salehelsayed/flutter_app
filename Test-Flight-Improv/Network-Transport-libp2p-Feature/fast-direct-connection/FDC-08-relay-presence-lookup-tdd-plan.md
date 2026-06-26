# FDC-08 — Relay presence lookup (additive inbox action)  (New Feature)

Status: awaiting-review

Spec: Network-Arch/Fast-Direct-Connection-Architecture-Proposal.md (§6.3 presence-aware emphasis; §8 P1-1; §11 open-question 2)

## ⚠ DRAFT — finalize after FDC-S3

> This plan is **gated by FDC-S3** (the presence-mechanism spike). FDC-S3 must
> decide the **truth source** for "does this peer hold a live relay reservation":
> (A) raw `host.Network().Connectedness(peerID)==Connected` (cheap, already
> available, but TTL-lagged and conflates *any* libp2p conn with a relay
> reservation), vs (B) go-libp2p relay-service **reservation-table** truth
> (accurate "has a reservation" but the table is **not exported** by
> `relay.New` / `libp2p.EnableRelayService` — needs an internal fork/shim or a
> relay-service event subscription), vs (C) a relay-maintained per-peer
> last-seen map fed by `EvtPeerConnectednessChanged` (already subscribed at
> `main.go:134-159`). All values tagged `<from FDC-S3>` below are provisional.
> The **client-side** half (bridge cmd, Dart enum, short-TTL cache, send-path
> wiring, RED catalog rows C1–C6, D1–D6) is fully detailable now and given full
> RED detail; the **relay truth-source** rows (R3/R4) and all device/relay
> rows are flagged as the **closure gate** and finalized after FDC-S3.

---

## Source Of Truth
- **Proposal** §6.3 ("online-ish, never foreground"), §8 row **P1-1**, §11 q2/q5.
  Honor the corrections: presence is an **emphasis hint, never a replacement
  for the inbox** (§6.3); the relay can only report *"online-ish, TTL-lagged"*,
  **never foreground/background** (`main.go:143-149` tracks socket connectedness
  only); relay changes must be **additive-only** (NET-REL-07).
- **`scripts/run_test_gates.sh`** wins over prose for gate membership/counts.
- **Naming contract (canonical; supersedes any inconsistent inline mention below):**
  the relay presence **READ** action is `presence_get` (symmetric with FDC-09's
  `presence_set`, mirroring the existing `group_store`/`group_retrieve` pair) —
  drop the phantom `presence_lookup`. The move-feature gate token is
  `p2p_get_presence` (verb_noun, matching `p2p_dial_peer`), superseding any
  `p2p_presence_lookup` reference. Apply consistently with FDC-09.
- **This epic's roadmap FDC-00** (sequencing; P1-1 lands in proposal Phase 2,
  the "additive relay deploy" phase — see §9.3).
- **FDC-S3** spike output (mechanism + truth source) — **this draft cannot be
  marked implementation-ready until FDC-S3 lands.**

## Session Classification
**evidence-gated** (DRAFT). Host-testable portions (client cache, enum,
bridge cmd shape, send-path emphasis branch) are implementation-ready; the
relay truth-source and the real-wire "reservation-truth" assertions are
**device/relay-gated** and finalized after FDC-S3 picks mechanism A/B/C.

## Exact Problem Statement
**What's missing.** There is no cheap, up-front "is this peer online-ish?"
signal. The only online/offline probe today is `probeRelay` (p2p_service_impl.dart:4074-4089)
→ bridge `relay:probe` → `RelayProbe` (bridge.go:897) → `DialPeerViaRelay`
(node.go:1216) → `dialPeerViaRelayWithTimeout(peerId, RelayProbeTimeout)` with
`RelayProbeTimeout = 5s` (config.go:30). That is a **blind circuit *dial*** — it
actually opens a `/p2p-circuit` connection to learn liveness, costs up to 5s,
and (per §4.1 / §6.3) runs **serially after** the 2s race, so even a
foreground-online send pays a full discover/dial before it can "know" the peer
is reachable.

**Who feels it.** Any sender on the cold/low-confidence path: the serial
probe→dial→send→inbox tail (send_chat_message_use_case.dart:1021-1086) tacks the
5s ceiling onto an already-slow window (proposal §3 "worst perceived path").

**Why.** Reachability is **rediscovered per-send via a dialing probe** with no
cached presence and no lightweight relay-side lookup. The relay already *knows*
connectedness (subscribes `EvtPeerConnectednessChanged`, `main.go:134-159`;
`RecordPeerSeen` business_metrics.go:77) but exposes **no per-peer query** — the
HLL registers are cardinality-only (`Estimate()`), not a per-peer map.

**What must improve.** A new **additive inbox action** `presence` (request
`{action:"presence_get", to:<peerId>}`) returns whether the target peer is
"online-ish" (reservation/connectedness `<from FDC-S3>`) **without dialing a
circuit**. Client caches the answer short-TTL and uses it as the §6.3 emphasis
hint (direct-race-vs-inbox-first), replacing the blind 5s probe on the decision
path.

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

## Root Cause (verify→refute confirmed)
- **No relay-side per-peer presence query.** `inboxRequest`
  (inbox.go:1423-1444) has no presence action; the dispatch switch
  (inbox.go:1530-1713) ends in `Unknown action`. `HandleInboxStream(s, inbox,
  groupInbox)` (inbox.go:1500 def; wired main.go:112-114) is **not handed the
  host**, so it cannot answer `h.Network().Connectedness(pid)` — this is the
  primary structural gap a presence action must close. **Verified by Read.**
- **Liveness is learned by dialing.** `probeRelay` →
  `callP2PRelayProbe` (p2p_bridge_client.dart:151-178, `cmd:'relay:probe'`,
  5s `.timeout`) → `RelayProbe` → `n.DialPeerViaRelay` (node.go:1216-1221) →
  `dialPeerViaRelayWithTimeout(…, RelayProbeTimeout=5s)` which **`h.Connect`s a
  circuit address** (node.go:1267-1272). It's a dial, not a lookup. **Verified.**
- **No client presence cache.** `p2p_service_impl.dart` caches *transport*
  (`_learnedTransport` / `lastKnownGoodTransport` TTL eviction :4100-4122) but
  has **no presence cache**. The short-TTL presence cache reuses that read-time
  TTL-eviction pattern. **Verified.**

**Refuted / do-NOT-re-introduce.**
- Do **not** add store idempotency/dedup — it already exists
  (backend_memory.go:121-142, backend_redis.go:272-295, inbox_store.go:7,14);
  proposal §8 P2-2 explicitly says don't rebuild it.
- Do **not** infer foreground/background from connectedness — wrong on iOS
  (§1, §6.3 `main.go:143-149`). Presence is "online-ish" only.
- Do **not** make presence a delivery gate (never let `reachable==false`
  *skip* the inbox or `reachable==true` *skip* it either — §6.3).
- Do **not** repurpose `probeRelay`/`relay:probe` to mean "lookup" — keep it
  (introduction_outbound_delivery.dart:542 still uses it); presence is a
  **new** action/cmd so older clients/relays stay valid (NET-REL-07).

## Real Scope
**In scope.**
- **Relay**: new `presence` inbox action + truth-source resolver `<from FDC-S3>`
  (`go-relay-server/inbox.go`, `go-relay-server/main.go` handler-injection).
- **Go host client**: `RelayPresenceLookup(peerId)` over `InboxProtocol`
  (`go-mknoon/node/inbox.go`) + bridge `RelayPresence` fn + `relay:presence_get`
  dispatch (`go-mknoon/bridge/bridge.go`).
- **Dart**: `relay:presence_get` cmd spec (`go_bridge_client.dart`),
  `callP2PRelayPresence` (`p2p_bridge_client.dart`), `RelayPresence` enum +
  `lookupRelayPresence` interface method (`p2p_service.dart`), impl with
  **short-TTL client cache** (`p2p_service_impl.dart`).
- **Move-feature gate (REQUIRED — account-migration safety):** `lookupRelayPresence` is a NEW relay
  round-trip primitive, and the send use-case is **not** gated at the top — so its impl MUST call
  `_allowsAccountNetworkSideEffects('p2p_get_presence')` as its **first line** (mirror `probeRelay`
  at `p2p_service_impl.dart:4075`) and return `RelayPresence.unknown` (no bridge call) when an
  account-move has paused network side-effects (`migrationExportingNetworkPaused`/`migratedOut`/
  fail-closed). Without this, a relay dial could fire mid-move. **Lock:** a RED test — gate-false ⇒ no
  bridge call, returns `unknown`; mutation = drop the gate ⇒ bridge invoked.
- Wire the presence hint into the send decision **as emphasis only** (§6.3
  three-way: reachable→lazy inbox / unreachable→inbox-first / unknown→today).

**Out of scope (owning FDC-xx).**
- The full §6.2 staggered ranked race / concurrent-inbox generalization →
  **FDC owning P0-2/P0-3** (this plan only supplies the *hint*; it must not
  rewrite the race ladder).
- `warmPeer` eager warm → **P0-1 plan**.
- gossipsub heartbeat beacon alternative (§6.3) → FDC-S3 may pick it instead;
  if so this plan is **superseded/retargeted** by FDC-S3.
- Redis durable backend → **P2-2 plan**.
- Self-published foreground/background status → separate FDC (§6.3, §11 q2).

## Files To Inspect Next
**Production — relay:** `go-relay-server/inbox.go` (`inboxRequest` :1423,
`inboxResponse` :1448, dispatch :1530-1713, `HandleInboxStream` :1500);
`go-relay-server/main.go` (host create :63-77 `EnableRelayService`/`ForceReachabilityPublic`;
handler wiring :112-114; connectedness sub :134-159); `go-relay-server/business_metrics.go`
(`RecordPeerSeen` :77 — candidate last-seen feed for mechanism C).
**Production — Go host client/bridge:** `go-mknoon/node/inbox.go`
(`inboxRequest`/`inboxResponse` :22-44, `InboxStoreDetailed` :104 as the
stream-action template, stream open `h.NewStream(ctx, relay.ID, InboxProtocol)`
:145); `go-mknoon/node/node.go` (`DialPeerViaRelay` :1216 — the thing being
*replaced on the decision path*); `go-mknoon/bridge/bridge.go` (`RelayProbe`
:897 template; `InboxStore` :1114).
**Production — Dart:** `lib/core/bridge/go_bridge_client.dart` (cmd dispatch map
:107 `relay:probe`, :115 `inbox:store`); `lib/core/bridge/p2p_bridge_client.dart`
(`callP2PRelayProbe` :151); `lib/core/services/p2p_service.dart`
(`RelayProbeResult` enum :9, `probeRelay` :186 interface);
`lib/core/services/p2p_service_impl.dart` (`probeRelay` :4074, `isConnectedToPeer`
:4092, `lastKnownGoodTransport` TTL pattern :4100-4122);
`lib/features/conversation/application/send_chat_message_use_case.dart`
(probe tail :1021-1086 — emphasis-hint insertion point, **read-only consumer
here**, race rewrite owned by P0-2/P0-3).
**Tests:** `go-relay-server/inbox_test.go`, `inbox_dedup_test.go`,
`protocol_contract_test.go` (additive-action contract); `go-mknoon/node/inbox_parse_test.go`,
`multi_relay_test.go`; `lib/...` send + p2p_service_impl unit tests under
`test/` (1to1 gate); `integration_test/{wifi_relay_fallback_smoke,transport_e2e}_test.dart`
(transport gate).
**Dependency-only context:** `go-mknoon/node/config.go` (`RelayProbeTimeout`
:30, `InboxProtocol` :22); relay limits (`limits.go`) for any new resource cap.

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
| `integration_test/wifi_relay_fallback_smoke_test.dart` | YES | transport array (`run_test_gates.sh:166`) |
| `integration_test/transport_e2e_test.dart` | YES | transport array (:167) |
| **`presence`-action relay test** | **MISSING** | add to go-relay-server (auto-run by `go test ./...`) |
| **`RelayPresenceLookup` node test** | **MISSING** | add to go-mknoon node |
| **`lookupRelayPresence` Dart unit + cache test** | **MISSING** | `test/core/services/**` AUTO-globs into host gate |
| **`relay:presence_get` real-wire sim scenario** | **MISSING (device/relay-gated)** | needs `classify_path()` + dart-define case in `check_reliability_simulation_discovery.sh` |

## RED Test Catalog
> Tiers: **Go-relay unit** / **Go-node(client) unit** / **Dart application unit**
> / **transport integration** / **simulator (real relay)**. Lowest tier that
> still fails for the real reason. Each shared-result row names a distinct
> flow-event discriminator.

### Client / Dart (fully detailable NOW)

**C1 — Dart: presence cmd shape + flow events**
`test/core/bridge/p2p_bridge_client_presence_test.dart::callP2PRelayPresence sends relay:presence_get with to-peer and parses reachable`
- Tier: Dart application unit. Setup: fake `Bridge` echoing a captured request;
  return `{"ok":true,"presence":"reachable"}`.
- RED-on-HEAD: `callP2PRelayPresence` does not exist (compile-fail) → real
  reason: no presence bridge call.
- GREEN-asserts: request `cmd=='relay:presence_get'`, `payload.peerId==peer`; emits
  `P2P_RELAY_PRESENCE_REQUEST` then `P2P_RELAY_PRESENCE_RESPONSE`; parses
  `RelayPresence.reachable`.
- Mutation-re-reds: change cmd to `'relay:probe'` → relay test/back-compat
  diverges; drop the RESPONSE flow event → assert fails.
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
  TTL `<from FDC-S3, provisional 10s>`, then advance past TTL, call again.
- RED-on-HEAD: `lookupRelayPresence` absent. GREEN: bridge invoked **once**
  within TTL (second call served from cache), **twice** after expiry;
  eviction mirrors `lastKnownGoodTransport` read-time pattern (:4100-4122).
- Mutation: remove the cache short-circuit → 2 bridge calls within TTL → RED.
- Discriminator: cache-hit emits `P2P_RELAY_PRESENCE_CACHE_HIT` vs miss
  `P2P_RELAY_PRESENCE_REQUEST`.

**C4 — Dart: cache cleared / never trusted when stale (presence is TTL-lagged)**
`..._presence_cache_test.dart::expired presence entry is evicted on read`
- Tier: Dart unit. RED: absent. GREEN: a `reachable` entry older than TTL
  returns `unknown` (re-query), never a stale `reachable`. Mutation: drop the
  age check → returns stale `reachable` → RED. Locks "emphasis, TTL-lagged".

**C5 — Dart send-path: presence is emphasis-only, inbox always fires**
`test/features/conversation/.../send_presence_emphasis_test.dart::reachable presence keeps the durable inbox deposit (lazy, not suppressed)`
- Tier: Dart application unit (send use-case with fake p2pService returning
  `RelayPresence.reachable`). **Coordinate with P0-2 owner — shared file
  collision; this row asserts the invariant, not the race rewrite.**
- RED-on-HEAD: today there is no presence branch; this asserts the *new* branch
  still calls `storeInInbox`/`storeInInboxDetailed`. Written against the
  post-P0-2 race shape (`<gated: confirm seam with P0-2 final>`).
- GREEN: with `reachable`, inbox deposit still invoked (lazy/parallel), live
  legs emphasized; emits `CHAT_MSG_PRESENCE_EMPHASIS{presence:reachable}`.
- Mutation: make `reachable` skip `storeInInbox` → RED (`PRESENCE_NEVER_REPLACES_INBOX`).
- Discriminator: `CHAT_MSG_PRESENCE_EMPHASIS` event with `presence` field
  distinguishes reachable/unreachable/unknown branches.

**C6 — Dart send-path: `unreachable` ⇒ inbox-first custody + push-to-wake; live best-effort**
`..._presence_emphasis_test.dart::unreachable presence commits inbox first then push`
- Tier: Dart application unit. RED: no presence branch. GREEN: order = inbox
  deposit committed before awaiting live legs; emits
  `CHAT_MSG_PRESENCE_EMPHASIS{presence:unreachable}` + push-to-wake. Mutation:
  reorder live-first → RED. **Does not** drop live legs (still best-effort).

### Go host client (node) — detailable NOW (truth-source-agnostic)

**N1 — node: `RelayPresenceLookup` sends `action:"presence_get"` frame**
`go-mknoon/node/inbox_presence_test.go::TestRelayPresenceLookup_SendsPresenceAction`
- Tier: Go-node unit. Setup: in-test relay host `SetStreamHandler(InboxProtocol,…)`
  capturing the request frame (mirror multi_relay_test.go:293 / group_inbox_test.go
  handler pattern), replies `{"status":"OK","presence":"reachable"}`.
- RED-on-HEAD: `RelayPresenceLookup` undefined (compile-fail). GREEN: frame
  decodes to `{action:"presence_get", to:<peerId>}`; returns `Reachable=true`.
- Mutation: send `action:"store"` → handler asserts wrong action → RED.

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

### Go relay unit — truth-source rows (DRAFT, closure-gated by FDC-S3)

**R1 — relay: `presence` action returns reachable for a connected peer** ⚠`<from FDC-S3>`
`go-relay-server/inbox_presence_test.go::TestPresenceAction_ReturnsReachableForConnectedPeer`
- Tier: Go-relay unit. Setup `<from FDC-S3>`: stand up relay host + a peer that
  holds a reservation/connection; send `{action:"presence_get", to:peer}`.
- RED-on-HEAD: dispatch has no `case "presence_get"` → returns
  `Unknown action: presence_get` (inbox.go:1713). GREEN: `{status:OK,
  presence:"reachable"}`. Mutation: hardcode `unreachable` → RED.
- **Closure note:** requires `HandleInboxStream` to receive the host/resolver
  (signature change main.go:113) — the exact resolver (connectedness vs
  reservation-table vs last-seen map) is the **FDC-S3 decision**; this row's
  *setup* is finalized post-spike.

**R2 — relay: `presence` returns unreachable / online-ish-not-foreground** ⚠`<from FDC-S3>`
`inbox_presence_test.go::TestPresenceAction_UnreachableForNoReservation` and
`::TestPresenceResponseNeverClaimsForeground`
- Tier: Go-relay unit. GREEN: no-reservation peer → `presence:"unreachable"`;
  response schema has **no** foreground/background field (locks
  `PRESENCE_IS_ONLINE_ISH_NOT_FOREGROUND`). RED-on-HEAD: no action. Mutation:
  add a `foreground:true` field → schema test RED.

**R3 — relay: additive contract — unknown clients/actions untouched**
`go-relay-server/protocol_contract_test.go::TestPresenceActionIsAdditive`
- Tier: Go-relay unit. GREEN: every existing action
  (store/retrieve/retrieve_pending/ack/register_token/group_*) returns
  byte-identical responses with the presence case added; a client that never
  sends `presence` is unaffected. RED-on-HEAD: trivially passes (no new action)
  — this is a **preservation lock**, kept green across the change. Mutation:
  changing any existing case while adding presence → RED. **NET-REL-07.**

**R4 — relay: presence never mutates inbox state (read-only action)**
`inbox_presence_test.go::TestPresenceActionDoesNotStoreOrConsume`
- Tier: Go-relay unit. GREEN: a `presence` query leaves the target's queue
  occupancy unchanged (no store, no ack-consume). RED: n/a until action exists.
  Mutation: accidentally enqueue/dequeue on presence → RED.

### Simulator (real relay) — closure gate

**S1 — sim: live relay answers presence without a circuit dial** ⚠ device/relay-gated `<from FDC-S3>`
`integration_test/relay_presence_lookup_smoke_test.dart` (transport gate) +
`/sims 1to1 --only <N>` scenario.
- Tier: simulator against a **real deployed relay** (additive deploy required).
  Proves: (a) reachable peer → `reachable` faster than the 5s probe ceiling;
  (b) backgrounded/offline peer → `unreachable`/`unknown`; (c) an
  **un-upgraded** relay returns `Unknown action` and the client still delivers
  (NET-REL-07 end-to-end). This is the **only** tier that validates real
  reservation-truth + additive-deploy safety; **finalized after FDC-S3** +
  relay redeploy.

## Test Coverage Matrix
| Spec case | Behavior props | Tier | Test file::name | RED reason on HEAD | Mutation revert | Acceptance gate cmd | Harness registration |
|---|---|---|---|---|---|---|---|
| New `relay:presence_get` cmd shape | cmd+payload+events | Dart unit | p2p_bridge_client_presence_test.dart::C1 | `callP2PRelayPresence` absent | cmd→`relay:probe` | `./scripts/run_host_test_gates.sh core-host-all` | `test/core/bridge/**` auto-globs |
| Old relay degrade → unknown (NET-REL-07) | unknown-action→`unknown` | Dart unit | p2p_bridge_client_presence_test.dart::C2 | method absent | unknown→`unreachable` | core-host-all | auto-glob |
| Short-TTL cache | 1 call/TTL, re-query post-TTL | Dart unit | p2p_service_impl_presence_cache_test.dart::C3 | method absent | remove cache | core-host-all | `test/core/services/**` auto-glob |
| Stale evict | never trust stale reachable | Dart unit | p2p_service_impl_presence_cache_test.dart::C4 | method absent | drop age check | core-host-all | auto-glob |
| Emphasis-only, inbox always (reachable) | inbox still deposited | Dart app unit | send_presence_emphasis_test.dart::C5 | no presence branch | reachable skips inbox | `./scripts/run_test_gates.sh 1to1` | **append `send_presence_emphasis_test.dart` to `ONE_TO_ONE_TESTS`** (curated array; `test/features/**` auto-globs only `feature-host-all`, NOT the `1to1` gate) |
| Unreachable→inbox-first+push | order: inbox before live | Dart app unit | send_presence_emphasis_test.dart::C6 | no presence branch | live-first reorder | `./scripts/run_test_gates.sh 1to1` | same file (`ONE_TO_ONE_TESTS`) |
| Client sends presence frame | `action:"presence_get"`+`to` | Go-node unit | inbox_presence_test.go::N1 | `RelayPresenceLookup` undefined | action→`store` | `cd go-mknoon && go test ./...` | go test ./... |
| Multi-relay fallback | tries 2nd relay | Go-node unit | inbox_presence_test.go::N2 | undefined | stop after 1 | `cd go-mknoon && go test ./...` | go test ./... |
| Old-relay reply→unknown | ERROR not fatal | Go-node unit | inbox_presence_test.go::N3 | undefined | ERROR→`unreachable` | `cd go-mknoon && go test ./...` | go test ./... |
| Relay reachable answer `<FDC-S3>` | OK+`reachable` | Go-relay unit | inbox_presence_test.go::R1 | no `case "presence_get"` | hardcode `unreachable` | `cd go-relay-server && go test ./...` | go test ./... |
| Online-ish-not-foreground `<FDC-S3>` | no fg field | Go-relay unit | inbox_presence_test.go::R2 | no action | add `foreground` field | `cd go-relay-server && go test ./...` | go test ./... |
| Additive contract | existing actions identical | Go-relay unit | protocol_contract_test.go::R3 | preservation (kept green) | mutate any existing case | `cd go-relay-server && go test ./...` | go test ./... |
| Read-only presence | no store/consume | Go-relay unit | inbox_presence_test.go::R4 | no action | enqueue on presence | `cd go-relay-server && go test ./...` | go test ./... |
| Real-wire reservation-truth `<FDC-S3>` | faster-than-probe, additive-safe | sim (real relay) | relay_presence_lookup_smoke_test.dart::S1 | feature unshipped | n/a (device) | `./scripts/run_test_gates.sh transport` + `/sims 1to1 --only <N>` | add `classify_path()` case + dart-define in `check_reliability_simulation_discovery.sh` |

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
  between lookup and send (peer backgrounds) — the inbox-always invariant
  (C5/C6) makes this safe; presence is never load-bearing. Row: **C5/C6**.
- **Go bridge concurrency (§10, per FDC-S5):** the bridge is **concurrent in the
  warm/steady state** (only `Node.Start`'s cold-path write lock serializes), so a
  presence lookup does not blanket-serialize behind the user's send; the residual
  risk is **native thread-pool / dial-limit contention** if lookups are unbounded.
  **N/A to host RED**, but flagged: presence must be **off the send-critical path**
  (cache-served or fire-before-typing), not awaited inline ahead of send. Closure:
  **S1** + FDC-S3 budget decision. Row: justified-deferred to FDC-S3.

## Invariants (locked by tests)
- `INBOX_UNKNOWN_ACTION_DEGRADES_TO_UNKNOWN_PRESENCE` — C2, N3, R3.
- `PRESENCE_NEVER_REPLACES_INBOX` — C5, C6, R4.
- `PRESENCE_IS_ONLINE_ISH_NOT_FOREGROUND` — R2.
- `PRESENCE_LOOKUP_IS_READ_ONLY` (no store/consume) — R4.
- `PRESENCE_CACHE_SHORT_TTL_NEVER_STALE` — C3, C4.
- `PROBE_PATH_PRESERVED_FOR_INTRODUCTIONS` (relay:probe untouched) — N3/R3 + sibling note.

## Step-By-Step Implementation Plan
> RED first at the lowest failing tier. Stop-if blockers call out FDC-S3.

1. **RED N1–N3 + C1–C4** (client tiers, truth-source-agnostic). Seam: new
   `RelayPresenceLookup(peerId)` in `go-mknoon/node/inbox.go` (template:
   `InboxStoreDetailed` :104, stream open :145); new `Presence`/`Reachable`
   fields on the node-side `inboxResponse` (:33). **Stop-if:** none — client
   wire shape is fixed (`action:"presence_get"`, response `presence` string).
2. Implement node `RelayPresenceLookup` → GREEN N1–N3. Seam: `buildRelaySelector(nil).ForEach`
   (mirror node.go:1239), `h.NewStream(ctx, relay.ID, InboxProtocol)`.
3. Bridge: add `RelayPresence(paramsJSON)` (template `RelayProbe` bridge.go:897)
   + register `relay:presence_get` in the bridge dispatch + Dart cmd map
   (`go_bridge_client.dart:107` neighborhood) → unblocks C1.
4. Dart: `callP2PRelayPresence` (template p2p_bridge_client.dart:151);
   `RelayPresence` enum + `lookupRelayPresence` on `P2PService`
   (p2p_service.dart:9/:186); impl + short-TTL cache in p2p_service_impl.dart
   (template `lastKnownGoodTransport` :4100-4122) → GREEN C1–C4.
5. **RED C5/C6** then wire the **emphasis-only** branch into the send decision.
   **Stop-if:** coordinate the exact insertion seam with the **P0-2/P0-3**
   owner (shared `send_chat_message_use_case.dart`) — do **not** rewrite the
   race; only add the three-way emphasis using `lookupRelayPresence` + keep the
   always-on inbox. GREEN C5/C6.
6. **RED R1–R4** (relay). **Stop-if FDC-S3:** the truth-source resolver and the
   `HandleInboxStream` signature change (inject host/resolver at main.go:113)
   are gated by FDC-S3 mechanism A/B/C. Implement the chosen resolver + add
   `case "presence_get":` to the dispatch (inbox.go:1530-1713) → GREEN R1–R4.
7. **S1 (closure):** additive relay redeploy + sim scenario registration; run
   transport gate + `/sims 1to1`. Finalize all `<from FDC-S3>` values.

## Risks And Edge Cases
- **Truth-source mismatch** (connectedness lies on iOS socket-linger) — pinned
  by R1/R2 setup `<FDC-S3>` + S1 real-wire. The proposal already declares this
  "online-ish, TTL-lagged"; the cache TTL bounds the lie (C3/C4).
- **Old relay in the field** (NET-REL-07) — C2/N3/R3 + S1(c).
- **Presence-as-gate regression** (someone makes `unreachable` drop live legs or
  `reachable` skip inbox) — C5/C6/R4.
- **Bridge HOL-block** — keep presence off the awaited send-critical path; S1
  + FDC-S3 budget.
- **Budget/timeout NET-REL lock regression** — run the full 1to1 + transport
  gates; do not retune `RelayProbeTimeout` here (out of scope).

## Device/Relay Proof Profile
- **Host-only closure:** C1–C6, N1–N3, R1–R4 (R1/R2 setup finalized post-FDC-S3)
  close via `go test ./...` (both Go modules) + host gates.
- **Requires sim/real relay:** S1 — real reservation-truth, real-wire
  faster-than-5s-probe, and end-to-end NET-REL-07 additive-deploy safety.
  Closure scenario: `/sims 1to1 --only <N>` after additive relay redeploy.

## Acceptance Gates
```
# Go relay (R1–R4 + additive contract)
cd /Users/I560101/Project-Sat/mknoon-2/flutter_app/go-relay-server && go test ./...   # expect: ok (191 pass / 0 fail / 2 skip)
cd /Users/I560101/Project-Sat/mknoon-2/flutter_app/go-relay-server && make lint           # edits inbox.go + main.go presence handler
cd /Users/I560101/Project-Sat/mknoon-2/flutter_app/go-relay-server && go test -race ./...  # presence cache is shared concurrent state
# Go host client + bridge (N1–N3, C1 wire)
cd /Users/I560101/Project-Sat/mknoon-2/flutter_app/go-mknoon && go test ./...         # expect: ok (all pkgs PASS (go1.25.0, ~1171 tests))
cd /Users/I560101/Project-Sat/mknoon-2/flutter_app/go-mknoon && make lint              # edits bridge + node
# Dart host (C1–C6)
./scripts/run_host_test_gates.sh core-host-all                                        # expect: 0 fail (249/249 core files PASS, 0 fail)
./scripts/run_test_gates.sh 1to1                                                       # expect: 1226 baseline +N, 0 reg
# Transport integration + sim closure (S1) — after additive relay redeploy
./scripts/run_test_gates.sh transport                                                  # expect: +1 (device/fixture-gated; skips on lone sim)
# group-safety floor (presence lookup must not become load-bearing for group delivery — Scope Guard)
./scripts/run_test_gates.sh groups                                                     # expect: 0 fail (no group regression)
./scripts/check_reliability_simulation_discovery.sh
/sims 1to1 --only <N from FDC-S3 closure>
# Hygiene
flutter analyze    # 0 new
git diff --check
```

## Known-Failure Interpretation
- A RED at C1/N1/R1 with "undefined/compile-fail" is the **expected** TDD start,
  not a flake.
- `Unknown action: presence_get` returned by the relay before step 6 is the
  **correct** HEAD behavior (it is what NET-REL-07 degrade rides on) — R3 stays
  green throughout.
- Transport/sim flakes (durable-media-upload, ambient_background guard) are
  **pre-existing**, not FDC-08 (see MEMORY 163/164 notes); interpret transport
  `-1/-2` against the known-flake list before blaming this plan.

## Done Criteria
- [ ] FDC-S3 landed; mechanism A/B/C chosen; all `<from FDC-S3>` resolved.
- [ ] C1–C6 GREEN, each mutation re-reds.
- [ ] N1–N3 GREEN, each mutation re-reds.
- [ ] R1–R4 GREEN; R3 additive-contract preserved; each mutation re-reds.
- [ ] S1 closure run on real relay (faster-than-probe + NET-REL-07 e2e).
- [ ] `relay:probe` / introduction path provably unchanged.
- [ ] Both Go modules + 1to1 + transport gates green; `flutter analyze` 0 new;
      `git diff --check` clean.
- [ ] No store/dedup code touched; no foreground/background field added.
- [ ] Every new exported identifier (`RelayPresenceLookup`, the `RelayPresence` bridge fn, `handlePresenceGet`, the `RelayPresence` Dart enum) carries a doc comment.

## Scope Guard (hard Do-not)
- **Do NOT** wire the presence lookup into the group send path or make it load-bearing for group delivery — presence emphasis is **1:1-send-only** and additive (NET-REL-07). **Group-safety floor:** `./scripts/run_test_gates.sh groups` 0-regress.
- Do **not** rewrite the send race ladder (P0-2/P0-3 own it) — only add the
  emphasis hint + always-on inbox invariant assertions.
- Do **not** remove/repurpose `probeRelay`/`relay:probe` (introductions use it).
- Do **not** add store idempotency/dedup (exists) or change any existing inbox
  action.
- Do **not** infer or report foreground/background.
- Do **not** make presence load-bearing for delivery.
- Do **not** retune `RelayProbeTimeout`/`DialTimeout` (P1-3 owns cold-start).
- **New bridge entrypoint isolation:** the `RelayPresence` bridge fn (+ any presence glue) goes in a **NEW** `go-mknoon/bridge/bridge_presence.go` (or `bridge_lan.go`) — do **NOT** append it to the 2878-line `bridge.go`.
- **Named relay handler (no inline arm):** the new `case "presence_get":` in `HandleInboxStream` (222-line switch, inbox.go:1530-1713) must **delegate to a named handler func** (e.g. `handlePresenceGet`), not carry an inline arm.
- **FDC-S3 mechanism-C race lock (Stop-if):** if FDC-S3 selects the relay last-seen presence map (mechanism C), that map is written by the `main.go` connectedness goroutine and read by `HandleInboxStream`'s per-stream goroutine — it **MUST** be `sync.Map`- or mutex-guarded and covered by `go test -race ./...` (the -race gate above); no unguarded shared map.

## Accepted Differences
- Presence answers "online-ish (reservation/connectedness `<FDC-S3>`)", **not**
  foreground — an intentional, documented limitation (§6.3).
- A duplicate inbox copy may exist alongside a live delivery — harmless,
  receiver dedupes by `messageId` (§6.2; backend dedup already present).
- On a never-upgraded relay, presence is permanently `unknown` and the client
  behaves exactly as today — accepted (NET-REL-07).

## Dependency Impact
- **Gated by FDC-S3** (mechanism + truth source + S1 closure `--only N`).
- **Sequencing (proposal §9.3):** lands in the additive-relay-deploy phase,
  alongside/after P2-2 (Redis durability) to avoid raising inbox custody volume
  on a restart-losable backend — but presence itself is read-only so it does
  not raise inbox volume.
- **Collision:** shares `send_chat_message_use_case.dart` (emphasis insertion)
  and `p2p_service_impl.dart` with P0-1/P0-2/P0-3 → run **sequentially** with
  those FDC plans on the send path; this plan's relay/bridge/node edits are
  collision-free with the Dart-only P0 plans.
- **Additive-only**: no migration, no client/relay version bump, no breaking
  protocol change (new action + new optional response fields only).
