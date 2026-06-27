# FDC-S3 — Presence-signal decision  (Spike / Decision)

Status: **closed — READ = Option A `presence_get` (relay presence lookup) · WRITE = Option C `presence_set` (client→relay status-push) · Option B (gossipsub beacon) REJECTED.** (decided 2026-06-27; per its own terms this spike runs **no app/relay build** — device Methods 1/2/5 are inherited by FDC-08/09 as a device-tuning task, Exit-Gate clause 2.)

## ✅ DECISION (LOCKED — 2026-06-27)

> **How this was discharged:** re-grounded against live `new-orbit` source and adversarially verified via a re-ground → refute → reconcile workflow (12 agents). All four decision pillars survived their hardest refutation; the verdict already drafted in **Expected Output** below stands, with the naming/factual corrections and carry-forwards recorded here. This section is **canonical and supersedes** any inconsistent inline mention in the body below (notably the body still names the read action `presence_lookup`; the locked name is **`presence_get`** — see Naming).

### Verdict
- **READ signal = Option A — relay presence lookup.** A new additive inbox action `presence_get` answers from the relay's existing socket-connectedness (`h.Network().Connectedness(pid)`, fed by the `EvtPeerConnectednessChanged` handler at `go-relay-server/main.go:145-163`) **plus a connectedness-seeded last-seen map**, preferring Option C's self-published state when present. Returns coarse `{ presence: reachable | unreachable | unknown, ageMs }`. Retires the blind ≤5 s `DialPeerViaRelay`/`probeRelay` circuit dial from the send hot path. `"online-ish, TTL-lagged," **never** foreground`.
  - **Resolver ladder rule #1 (reconciled FDC-09b):** "prefer the self-published state" means the resolver **branches on its fg/bg value to pick the coarse answer** — a FRESH self-published state → `reachable` **iff `foreground`, else `unreachable`** (not "entry-exists ⇒ reachable"). This is exactly where Option C's "express foreground/background" purpose is realized: a `background` self-publish drives §6.3 `unreachable → inbox-first + push-to-wake`, while `foreground` drives `reachable → direct-race + lazy inbox`. A STALE self-state (past its TTL) falls through to the connectedness/last-seen rungs and degrades to `unknown`, never silently `unreachable`. The WIRE response still exposes ONLY `reachable|unreachable|unknown` — the fg/bg is consumed INTERNALLY (`PRESENCE_IS_ONLINE_ISH_NOT_FOREGROUND` holds). `presence_store.go::Lookup` rule #1; locked by `TestPresenceSet_BackgroundResolvesUnreachable_ForegroundReachable`.
- **WRITE / self-publish = Option C — client→relay `presence_set` status-push** on resume + a slow foreground heartbeat, **best-effort** on pause. The **only** mechanism that carries an **explicit foreground/background label** (the relay provably cannot infer it; Option B's beacon encodes only liveness, not a labeled state).
- **Option B (gossipsub beacon) = REJECTED** as the presence transport: continuous churn/battery, useless on iOS background (node killed in seconds → beacon absence ≡ offline), cold-open subscribe-before-read miss, net-new pubsub mesh+validator, and it cannot express fg/bg. Pubsub stays **group-only**. (Narrow residual niche — foreground-both on Android — is exactly the case that least needs a hint, so it does not reopen B.)
- **Reservation-exact truth = OUT.** `go-libp2p`'s circuitv2 relay holds reservations internally with **no public enumeration API**; coarse connectedness + last-seen is sufficient for a HINT. Revisit only if false-`reachable` proves too costly (lazy inbox too lazy).
- **Presence is a HINT, never load-bearing — the inbox is always the guarantee.** With presence forced to a *wrong* value (`reachable` for an offline peer), a message MUST still deliver via inbox + push-to-wake. This is a **hard acceptance gate for FDC-08** (see Exit-Gate item 4).

### Canonical contract consumed by FDC-08 / FDC-09
- **Read action:** `presence_get` (move-feature gate token `p2p_get_presence`; bridge call `presenceGet`). *(Renamed from this spike's body name `presence_lookup` per FDC-08's canonical naming contract — symmetric with `presence_set`, mirroring the existing `group_store`/`group_retrieve` pair; the verb_noun gate matches the live `p2p_probe_relay` / `p2p_dial_peer` tokens.)*
- **Write action:** `presence_set` (move-feature gate token `p2p_set_presence`; bridge call `presenceSet`).
- **Wire response schema (canonical):** `{ presence: reachable | unreachable | unknown, ageMs }`. Proposal §6.3's `online`/`offline` are conceptual synonyms for `reachable`/`unreachable`. `reachable` requires `ageMs < TTL`; otherwise `unknown` (never silently `unreachable`).
- **§6.3/§7 emphasis branch:** `reachable → inbox lazy (fire, don't await; live legs carry)`; `unreachable → inbox-first + push-to-wake`; `unknown → full concurrent race + concurrent inbox`. "lazy" means **non-blocking, never non-firing**.
- **Starting constants (device-tunable; inherited by FDC-08/09):** presence-entry TTL ≈ **180 s**; foreground heartbeat/refresh ≈ **60 s**; client-side `presence_get` cache TTL ≈ **10–15 s** (the cache is FDC-08's read-side, not FDC-09's).
- **Server surface for FDC-09 deploy:** two additive inbox actions (`presence_get`, `presence_set`) + a **shared TTL'd presence store** (one map, co-owned by FDC-08 read / FDC-09 write; `sync.Map`/mutex + `go test -race`). No reservation-service internals, no pubsub change. Order with/after the FDC-10 Redis-durability move.

### Re-grounded anchors (verified on `new-orbit`; decision-neutral drift)
| Claim | S3 body cites | Actual (verified) | Status |
|---|---|---|---|
| `EvtPeerConnectednessChanged` handler (raw socket connectedness; no fg/bg) | `main.go:143-149` | `main.go:145-163` (case `:148`, Connected branch `:149-154`, `RecordPeerSeen` `:152`, `len(h.Network().Peers())` `:153`) | drifted, claim holds |
| Relay service enabled | `main.go:72-74` | `main.go:72-74` | accurate |
| Per-peer reservation cap | `limits.go:80-82` "MaxReservations…=1" | `MaxReservationsPerPeer = 1` at `:82`; global `MaxReservations` at `:80` defaults to **512** (env-overridable) | **factual fix** (see body correction) |
| No presence/last-seen map exists | (judgment) | `RecordPeerSeen` (`business_metrics.go:74-81`) is **HLL-only and discards the peer ID** → Option A's "+last-seen" is **net-new** relay state, not reuse | confirmed |
| Inbox additive surface | `inbox.go:1424-1445`, `:1530`, `:1712-1713` | identical (`switch req.Action`, 10 cases, `default: "Unknown action: %s"`) — **no `presence_*` exists** (only `inbox_test.go:838` `presence_ping` *message* test) | accurate |
| Pubsub inits once, group-only | `node.go:379`, `pubsub.go:71-86/105` | init at `node.go:396`; `NewGossipSub` `pubsub.go:72-74`; only group Join `pubsub.go:141` (prefix `config.go:44`) | drifted, claim holds |
| `probeRelay` 3-way result (the path being retired) | `p2p_service_impl.dart:4074-4089` | `p2p_service_impl.dart:4373-4388` (gate `p2p_probe_relay` `:4374`) | drifted +299, claim holds |
| `DialPeerViaRelay` per-target /p2p-circuit dial, ≤5 s | `node.go:1216-1271`, `config.go:30` | `node.go:1245-1304` (wrapper `:1249-1254`); `RelayProbeTimeout = 5s` `config.go:30` | drifted, claim holds |
| Option C write hooks | `handle_app_resumed.dart:136-191`, `main.dart:4314-4316` | resume handler `37-830` (FDC-05 parallel block `~174-240`, account-migration gate `:121-133`); pause/hidden branch `main.dart:4313-4316` → `_onPaused` `:4339` → `handleAppPaused`; **pause path UNGATED** | drifted, claim holds + gating note |

### Exit-Gate discharge
1. **A + C confirmed, B rejected** — ✅ recorded above (adversarially survived: read=A, reject-B, self-publish=C all held).
2. **TTL/heartbeat constants** — ✅ via clause-2 branch: this spike runs no build, so Methods 1/2/5 device numbers are **inherited by FDC-08/09 as a device-tuning task** with the starting constants above. (Live relay env is gitignored/unverifiable from-repo — FDC-09 must stand up a deployable relay before these run.)
3. **Back-compat / NET-REL-07** — ✅ **static half confirmed from-repo**: the single `switch req.Action` + `default: "Unknown action: %s"` (`inbox.go:1530`/`:1712-1713`, no version-negotiation field in `inboxRequest`) proves `presence_get`/`presence_set` are purely additive; a new client hitting an old relay gets the clean `"Unknown action"` error → maps to `unknown`. Device half (new-client ↔ old-relay round-trip) deferred to FDC-08 deploy.
4. **Load-bearing hard gate** — ⚠ **PARTIAL → carry-forward to FDC-08.** The invariant is design-safe and multiply-locked: FDC-08 scope-guard (`:119`) + `PRESENCE_NEVER_REPLACES_INBOX` + C5 mutation (`make reachable skip storeInInbox → RED`); a **structural backstop** in current code (the unconditional sequential `storeInInbox` on the all-paths-failed tail, `send_chat_message_use_case.dart:1179-1199`, not presence-gated); and the relay `store → SendNotification` push that fires on **every** successful store with no presence consultation (`inbox.go:866-867`). FDC-09 already instantiates the forced-wrong-value test (`TC-09-13`). **FDC-08 still lacks a dedicated** "force `reachable` for an actually-offline peer → still delivered via inbox + push-to-wake" RED — it must add one on finalize (this item demands it explicitly).

### Carry-forward to FDC-08 finalize (read side)
- Lock the relay resolver = `Connectedness(pid)` + a **connectedness-seeded last-seen map** (net-new; `RecordPeerSeen` is HLL-only and cannot be reused), optionally preferring FDC-09's self-published `presence_set` state. **Demote reservation-table truth to OUT** (its internal "B"), not a co-equal `<from FDC-S3>` candidate.
- Disambiguate the **A/B/C label collision**: FDC-08's internal truth-source letters (connectedness / reservation-table / last-seen) clash with this spike's mechanism letters — rename them to descriptive names.
- Adopt the canonical wire schema `{ presence: reachable | unreachable | unknown, ageMs }`.
- Add the **dedicated forced-wrong-value RED** (Exit-Gate item 4) to the RED catalog + Acceptance Gates.
- Rename the lone `presence_lookup` straggler: sim test `relay_presence_lookup_smoke_test.dart` → `relay_presence_get_smoke_test.dart`.
- Re-ground anchors per the table above (esp. `probeRelay :4373-4388` gate `p2p_probe_relay`, `DialPeerViaRelay :1245-1304`, connectedness `:145-163`, `inboxRequest :1424`).
- Ensure a **just-backgrounded-but-`reachable`-hinted** peer still gets a wake: the naive §7 mapping pushes only on `unreachable`, but the relay's store→push (`inbox.go:866-867`) fires on every store — so honoring "fire, don't await" already satisfies push-to-wake; assert it.

### Carry-forward to FDC-09 finalize (write side)
- FDC-09 **already encodes the decision correctly** (Option C `presence_set`; B rejected; constants TTL 180 / hb 60 inherited+tagged; `p2p_set_presence` gate REQUIRED on both pause and resume; `TC-09-13` load-bearing lock). No decision change needed.
- The **pause path is UNGATED** (`handle_app_paused.dart` has no account-migration gate, unlike resume `:121-133`) — so the `presence_set` primitive MUST self-gate `p2p_set_presence` (a moving/migrating device must not announce `reachable` on pause). Already required; confirmed against source.
- Re-ground line cites: resume gate `handle_app_resumed.dart:121-133` (not `:114`); connectedness `main.go:145-163`; resume hook block `~174-240` (coexist with FDC-05's re-prime); pause branch `main.dart:4313-4316`.

---

Gates:
- **FDC-08 (presence-aware send emphasis)** — cannot be finalized until this resolves. FDC-08
  consumes the *read* API shape (`reachable(peer) → online | offline | unknown` + freshness) and
  the three-way emphasis branch in proposal §6.3 / state machine §7 (`reachable==true → inbox
  lazy`, `==false → inbox-first + push-to-wake`, `unknown → full concurrent race`). Without a
  decided signal, FDC-08 would invent a presence source (and likely assume the relay can report
  "foreground", which it cannot — see Background).
- **FDC-09 (additive relay deploy: presence + durable Redis)** — cannot be finalized until this
  resolves. FDC-09 consumes *which server-side actions to add*, *whether they are additive under
  NET-REL-07*, and *where presence state is stored* (relay presence store vs go-libp2p relay-service
  internals vs pubsub). The deploy surface differs completely between options A, B, and C.

---

## Question

Two coupled decisions:

1. **The "online-ish" presence READ signal** — how does a *sender* cheaply learn whether a peer is
   likely reachable, to pick *direct-race-with-lazy-inbox* vs *inbox-first* up front (replacing
   today's blind serial 5 s `DialPeerViaRelay` probe)?
2. **The foreground/background self-publish WRITE mechanism** — how does a peer *announce* its own
   fg/bg state, given the relay provably cannot infer "foreground" from socket connectedness?

Pick from: **(A)** relay presence lookup (additive inbox action), **(B)** gossipsub beacon
self-published over the existing pubsub, **(C)** explicit client→relay status push on pause/resume.
These are not mutually exclusive: A is a *read* mechanism, B and C are *write/self-publish*
mechanisms. The decision must name the read signal AND the self-publish signal.

---

## Why it blocks

FDC-08's entire branch structure (proposal §6.3) keys off `reachable(peer)`. If the signal is
undefined, FDC-08 must invent one — and the most natural wrong invention is "ask the relay if the
peer is online/foreground," which silently assumes the relay tracks foreground. It does not:
`go-relay-server/main.go:143-149` only handles `EvtPeerConnectednessChanged` (raw libp2p socket
connectedness via `h.Network().Peers()`), which on iOS *lingers seconds after backgrounding* and
*never* distinguishes fg/bg (proposal §1 row 3, §6.3). A plan built on that assumption ships a
presence signal that reads "online" for a peer that has already backgrounded — and if any plan ever
makes it load-bearing (gates the inbox on it), messages are lost. This spike fixes the source and
the semantics (HINT-only) before the dependent plans encode them.

---

## Background  (grounded in real source)

**What the relay knows today (and doesn't):**
- The relay subscribes to `EvtPeerConnectednessChanged` and, on `network.Connected`, bumps
  `connectionsActive`/`biz.RecordPeerSeen` and logs `len(h.Network().Peers())`
  (`go-relay-server/main.go:143-149`). This is **raw socket connectedness**, a superset of "holds a
  reservation," and it **lags iOS background** and **cannot express foreground** (proposal §1, §6.3).
- The relay service is `libp2p.EnableRelayService(relay.WithResources(...))`
  (`go-relay-server/main.go:72-74`); the per-peer reservation cap `MaxReservationsPerPeer = 1` lives
  at `limits.go:82` (the global `MaxReservations` at `:80` defaults to **512**, env-overridable — the
  per-peer cap of 1 is the load-bearing fact). **go-libp2p's circuitv2 relay holds reservations internally and exposes
  no public enumeration API** — so "does peer X hold a *reservation* (vs merely a socket)?" is **not**
  directly readable from the relay without wrapping relay-service internals. This is exactly the
  caveat in proposal §6.3 / P1-1 ("exposing reservation-truth may need go-libp2p relay-service
  internals").

**What the client can already do (the thing we're replacing):**
- `probeRelay` (`lib/core/services/p2p_service_impl.dart:4074-4089`) returns
  `connected | noReservation | error` by calling the Go-side `DialPeerViaRelay`
  (`go-mknoon/node/node.go:1216-1271`): it dials the **target** via `/p2p-circuit`, ~100 ms for
  `NO_RESERVATION` / ~500 ms for a live circuit, hard-ceiled at `RelayProbeTimeout=5s`
  (`config.go:30`). So reservation-truth is *already* client-reachable — but as a **per-target
  circuit dial on the send-critical path, run serially after the 2 s race** (proposal R3, §4.1). It
  is the expensive thing P1-1 replaces with a cheap lookup, not a new capability.

**The inbox is a clean additive-action surface:**
- `inbox.go` dispatches a single JSON `inboxRequest{Action,...}` (`:1424-1445`) via
  `switch req.Action` (`:1530`) over `store|retrieve|retrieve_pending|ack|register_token|
  unregister_token|group_*`, with a **`default: Status:"ERROR", Error:"Unknown action: %s"`**
  (`:1712-1713`). A *new* action (`presence_lookup`, `presence_set`) is therefore **additive**:
  old clients never send it; a new client hitting an *old* relay gets a clean `"Unknown action"`
  error it can map to `unknown` (NET-REL-07 satisfied — no version negotiation needed).

**Pubsub exists but has no presence topic:**
- The node inits GossipSub once at start (`node.go:379` → `pubsub.go:71-86`,
  `pubsub.NewGossipSub(..., WithFloodPublish(true))`), but it only ever `Join`s **group** topics
  (`GroupTopicPrefix+groupId`, `pubsub.go:105`). There is **no** global/per-contact presence topic
  or mesh today; Option B would add one.

**iOS background reality (proposal §1, §6.4, §12):** the node is killed within seconds of
backgrounding; only the push-woken inbox covers backgrounded peers. Any self-published beacon
*stops* on background, so its absence ≈ "offline-or-backgrounded" with the same TTL lag as
connectedness — there is no free lunch on iOS.

---

## Options

### Option A — Relay presence **lookup** (additive inbox action)  [READ signal]
- **Description:** add `case "presence_lookup"` to `inbox.go` (`:1530`). It answers from state the
  relay *already* has — `h.Network().Connectedness(pid)` plus a last-seen timestamp seeded by the
  existing `EvtPeerConnectednessChanged` handler (`main.go:143-149`) — returning a coarse
  `{ state: online|offline|unknown, ageMs, source }`. Optionally enriched by Option C's
  self-published store (preferred when present). Client caches result with a short TTL and uses it
  for the §6.3 emphasis branch; the existing `DialPeerViaRelay` probe is retired from the hot path.
- **Pros:** cheap (one inbox stream, no per-target circuit dial); reuses the relay's existing
  connectedness tracking; cleanly additive (`:1712-1713`); strictly a *read* — adds **zero** churn
  from the queried peer; directly replaces the blind 5 s probe (P1-1).
- **Cons:** connectedness is a *superset* of reservation-truth and **lags iOS background** — so by
  itself it answers "has-a-recent-socket," not "foreground." Reservation-exact truth would need
  wrapping go-libp2p relay-service internals (not exposed) — **out of scope**; coarse
  connectedness + last-seen is sufficient for a HINT.
- **Cost:** server: ~1 action + a small last-seen map keyed off the existing event handler
  (S–M). Client: a `presenceLookup(peerId)` bridge call + short-TTL cache (S).
- **Additive / NET-REL-07:** ✅ additive (new action; `default` arm protects old relays).
- **iOS/Android:** symmetric on the *reader* side (just an inbox request). Accuracy is bounded by
  the *target's* background lag, which is the iOS problem Option C addresses.

### Option B — Gossipsub presence **beacon** (self-published over existing pubsub)  [WRITE signal]
- **Description:** each node joins a presence topic and floods a periodic signed heartbeat; peers
  subscribe to contacts' beacons. Built on `pubsub.NewGossipSub` (`pubsub.go:71`), **no relay
  change**.
- **Pros:** no server deploy; presence is end-to-end / serverless; reuses an inited subsystem.
- **Cons:** **adds continuous churn/battery** — a new always-on topic mesh, periodic publishes from
  every node, validator + subscription per contact (proposal §6.3 "adds churn"); **useless on iOS
  background** (node killed in seconds → beacon stops → looks identical to "offline," same TTL lag
  as A but with extra battery cost while foreground); a *reader* must be subscribed to the mesh
  *before* it can learn presence (cold-open miss, mirrors the §3 bonsoir cold-map problem);
  metadata leak (broadcasting "I'm online" into a mesh). No existing presence topic/validator —
  net-new infra (`pubsub.go` only has group topics).
- **Cost:** M–L (new topic, validator, subscribe-per-contact lifecycle, signing) + ongoing battery.
- **Additive / NET-REL-07:** ✅ no relay change at all, but a *protocol* addition (older clients
  don't publish/subscribe → invisible to each other; degrades to `unknown`, acceptable).
- **iOS/Android:** Android can sustain a foreground beacon; **iOS background kills it** — so it
  delivers presence only while *both* peers are foregrounded, which is the case that least needs a
  presence hint (you're about to race direct anyway).

### Option C — Explicit client→relay **status push** on pause/resume  [WRITE signal]
- **Description:** add `case "presence_set"` to `inbox.go` (`:1530`): client posts
  `{ state: foreground|background, ttlMs }` on resume/foreground (refreshed by a coarse heartbeat)
  and best-effort on pause/background. Relay stores it in a small TTL'd presence store; Option A's
  lookup prefers this self-published state over raw connectedness.
- **Pros:** the **only** mechanism that can express *foreground vs background* (the relay cannot
  infer it — `main.go:143-149`); pairs naturally with A (A reads what C writes); additive
  (`:1712-1713`); bounded, low churn (1 push per fg/bg transition + a slow heartbeat, not a mesh
  flood); the pause-push piggybacks the bounded `beginBackgroundTask` window P1-2 already requires.
- **Cons:** the pause→background push is **best-effort** (iOS may suspend before it lands —
  proposal §6.4 "no network on pause" invariant), so absence still degrades to the connectedness
  fallback; server now holds soft presence state (TTL'd, ciphertext-irrelevant — just a state byte).
- **Cost:** server: ~1 action + TTL'd map (S–M, shares store plumbing with A). Client: hook into
  `handle_app_resumed.dart:136-191` (resume) and the pause path (`main.dart:4314-4316`) + heartbeat
  timer (M).
- **Additive / NET-REL-07:** ✅ additive (new action; old relays return "Unknown action" → client
  simply skips publishing).
- **iOS/Android:** resume/foreground push is reliable on both. **iOS pause push is the open
  feasibility risk** (bounded background task; shared with P1-2/FDC pause-flush spike). Android can
  push on pause more reliably.

---

## Method  (how to validate / measure before locking the values)

All measurement is **device-pair** (two phones, real relay) because connectedness-lag and iOS
background-kill cannot be reproduced on host/sim (sim shares a host network stack;
`kDisableLocalDiscovery` is irrelevant here but the relay path needs real radios). Instruments:

1. **Connectedness-lag (sets Option A's TTL floor).** Devices A,B both online via relay. From A,
   call `presence_lookup(B)` once/second; on B, background the app at t0. Add a relay-side flow
   log on the `EvtPeerConnectednessChanged → NotConnected` for B and a client flow event
   `PRESENCE_LOOKUP_RESULT{state, ageMs}`. **Measure:** wall-clock from B-background to the relay
   flipping B to `NotConnected`. This lag is the minimum honest TTL for "online" derived from
   connectedness alone.
2. **Self-publish accuracy (Option C).** Same pair; B publishes `presence_set{background}` on pause.
   **Measure:** does C's "background" land *before* iOS suspends B (success rate over ~20 trials),
   and how much sooner than the connectedness flip in (1)? If C reliably beats connectedness, C is
   worth deploying; if iOS suspends first >50% of the time, C degrades to connectedness on iOS and
   only Android benefits.
3. **Additive/back-compat (no deploy needed beyond a stale relay).** Point a *new* client at an
   *old* relay build; assert `presence_lookup` returns the `"Unknown action"` error
   (`inbox.go:1712-1713`) and the client maps it to `unknown` (full race) — proves NET-REL-07.
4. **Churn/battery for Option B (only if B is reconsidered).** N=50 synthetic contacts, foreground
   both ends; count beacon publishes/min and measure battery delta over 30 min vs baseline. Expect
   this to *disqualify* B for the always-on case.
5. **Hot-path latency win (Option A vs status quo).** Compare time-to-emphasis-decision:
   `presence_lookup` round-trip (one inbox stream) vs the current `probeRelay`/`DialPeerViaRelay`
   (`node.go:1216`, up to `RelayProbeTimeout=5s`). Flow event `PRESENCE_DECISION_MS`.

Commands are device-driven (no host test proves it). Capture relay logs + client flow events;
screenshot booted state on any stall (per MEMORY hazard). **No app/relay build is run by this
spike — it authors the method; FDC-08/09 execute it.**

---

## Decision Criteria  (concrete thresholds that pick the options)

- **Read signal = A** unless device measurement (Method 1) shows connectedness lag is so large
  (> ~3 min after background) that "online" is meaningless even as a hint. Acceptance: lag is
  bounded and the result is treated as a HINT (never gates the inbox) → **A is chosen**. (Expected:
  lag is seconds-to-tens-of-seconds; well within hint tolerance because the inbox always backstops.)
- **Self-publish = C, not B**, when **any** of: (i) iOS-background must be expressible (it must —
  requirement #2/#3, proposal §6.3); (ii) B's churn/battery (Method 4) exceeds a foreground beacon
  budget; (iii) we want zero new pubsub mesh/validator surface. All three hold → **C chosen, B
  rejected as the presence transport.**
- **Reservation-exact truth is explicitly OUT** unless A's connectedness proxy proves too noisy
  (false "online" rate gated by the always-on inbox makes this tolerable) — avoid go-libp2p
  relay-service internals.
- **TTL / heartbeat starting values (to be confirmed by Method 1/2, encoded by FDC-08/09):**
  presence-entry TTL ≈ **180 s**; foreground heartbeat/refresh ≈ **60 s**; client-side lookup cache
  TTL ≈ **10–15 s** (avoid hammering the relay per keystroke/open). `online` requires
  `ageMs < TTL`; otherwise `unknown` (never silently `offline`).
- **Load-bearing test (hard gate, all options):** with presence forced to a *wrong* value
  (`online` for an offline peer), a message must STILL be delivered via the inbox + push-to-wake.
  If any plan makes delivery depend on presence, that plan is rejected (proposal §6.3, §12
  "presence never load-bearing").

---

## Expected Output  (what FDC-08 / FDC-09 consume)

- **Read signal = Option A — relay presence lookup**, a new additive `presence_get` inbox action
  backed by the relay's existing connectedness map (`main.go:143-149`) **plus** Option C's
  self-published state when available; returns coarse `{ state: online|offline|unknown, ageMs }`.
  Retires the blind 5 s `DialPeerViaRelay`/`probeRelay` from the hot path. Client maps an old-relay
  `"Unknown action"` → `unknown`.
- **Self-publish = Option C — explicit client→relay `presence_set` status push** on resume
  (`handle_app_resumed.dart:136-191`) + slow heartbeat, and best-effort on pause
  (`main.dart:4314-4316`, bounded by the P1-2 `beginBackgroundTask` window). **This is the only
  mechanism that carries an explicit foreground/background *label* (Option B's beacon encodes only
  liveness, not a labeled state); the relay cannot infer it.**
- **Option B (gossipsub beacon) — REJECTED** as the presence transport: continuous churn/battery,
  net-new pubsub mesh, and useless on iOS background. (Pubsub stays group-only.)
- **Semantics consumed by §6.3 / §7:** `reachable==online → inbox lazy (live legs carry)`;
  `==offline → inbox-first + push-to-wake`; `==unknown → full concurrent race + concurrent inbox`.
  **Presence is a HINT, never load-bearing — the inbox is always the guarantee.**
- **Server surface for FDC-09:** two additive inbox actions (`presence_get`, `presence_set`) +
  a TTL'd presence store; deploy alongside/ordered with the P2-2 Redis durability move (proposal
  §9 ordering hazard). No reservation-service internals, no pubsub change.
- **Starting constants (device-tunable):** presence TTL 180 s, fg heartbeat 60 s, client lookup
  cache 10–15 s.

---

## Exit Gate

Spike is done when: (1) the read signal (A) and self-publish (C) are confirmed, with B's rejection
recorded; (2) Method 1/2 device numbers fix the TTL/heartbeat constants (or FDC-08/09 explicitly
inherit the starting values above with a device-tuning task); (3) Method 3 confirms the
`"Unknown action"` back-compat path → NET-REL-07 holds; (4) the load-bearing test (wrong presence
still delivers via inbox) is encoded as a hard acceptance gate for FDC-08. Then FDC-08 and FDC-09
can be finalized against the named actions/semantics.

## Risks / Unknowns

- **iOS pause-push (C) feasibility is shared-open** with the P1-2 / pause-flush spike — if iOS
  suspends before `presence_set{background}` lands, C degrades to A's connectedness fallback on iOS
  (Android still benefits). Not a blocker (A backstops), but it caps C's iOS accuracy.
- **Connectedness ≠ reservation-truth** — a peer with a lingering socket but no reservation reads
  `online`; tolerable because presence is a HINT and the inbox always fires. If false-online proves
  costly (lazy inbox too lazy), revisit reservation-exact tracking (relay-service internals).
- **Bridge serialization** (proposal §10) — `presence_lookup` funnels through the same single Go
  bridge as the user's send; it must be cheap and off the send-critical path (cache-first), or it
  head-of-line-blocks the very send it informs.
- **Relay now holds soft presence state (C)** — a state byte + TTL, no ciphertext; minor metadata
  surface (relay learns fg/bg timing per peer). Acceptable vs the inbox metadata it already holds.
- **Live relay env reproducibility** — the device validation (Methods 1–3,5) needs the real relay;
  per MEMORY the live relay env is gitignored/unverifiable from-repo. FDC-09 must confirm a
  deployable relay before these measurements can run.
