# 187 - Keepalive-informed send: skip the doomed direct dial when the active peer is latched-dropped  (Bug/optimization — Spec)

Status: awaiting-review (spec only — problem + current state + test cases; no solution design).

Relation to earlier work:
- Consumes the **183** active-chat keepalive drop latch (`_dropHandled`) — the positive "this peer is not answering" signal the send path does not currently see.
- Rides the **FDC-03** concurrent durable inbox (`CHAT_MSG_SEND_CONCURRENT_INBOX_BEGIN`) and leaves the **FDC-01/02** budget ladder for unknown-liveness peers UNTOUCHED (this is the whole point — no re-baseline of the FDC-01/02 tests).
- Sibling of **185/186** send-reliability work but a DIFFERENT seam: 186 (FU-185-A) tightens *sender-side* reconnect self-heal (how fast a queued message converges after **our** relay returns); 187 is *send-time* avoidance of a doomed direct dial to a **recipient** the keepalive already knows is down.
- Grounded by the **2026-07-01 keepalive re-measurement** (`183-keepalive-device-proof-runsheet.md`, re-measurement section).

Framing note (expectations): this is **not** a user-visible latency win. Durable custody is already concurrent (~179 ms measured, below). This is a **battery / radio + transport-tier-resolution** optimization: stop spending ~1.5 s dialing a peer we have a fresh positive signal is dead.

---

## Problem Statement

When the user sends to the **active 1:1 peer** whom the **183 keepalive has already latched as dropped**, the send still runs the full direct discover→dial leg and burns it to completion on a peer that cannot answer — even though the keepalive has known the peer is down for many seconds and the concurrent durable inbox has already secured custody.

**Device evidence (2026-07-01 re-measurement, Pixel 6 → iPhone 11).** The keepalive detected Bob's drop and latched at **18:30:04**. A send **87 s later** (18:31:31, Bob still dark) produced:
- `CHAT_MSG_SEND_CONCURRENT_INBOX_BEGIN` 18:31:31.442 → `P2P_SERVICE_INBOX_STORE_SUCCESS` 18:31:31.545 → `CHAT_MSG_SEND_CUSTODY_CONFIRMED` **18:31:31.562** (custody in **178.7 ms**), then
- `P2P_SERVICE_DISCOVER_PEER_BEGIN` 18:31:31.707 → `P2P_SERVICE_DIAL_PEER_BEGIN` 18:31:31.849 → `P2P_SERVICE_DIAL_PEER_ERROR` **18:31:33.362** — a **~1.5 s doomed dial** to a peer the keepalive had latched dropped 87 s earlier.

The custody was already safe at 179 ms; the ~1.5 s direct dial delivered nothing and only spent radio on both devices.

**Root cause:** the 183 keepalive drop latch is **not exposed to the send path**. The send race adds the direct leg unconditionally, blind to the fresh per-peer liveness the keepalive holds for the very peer being sent to.

---

## Verified current state (file:line)

### The send race adds the direct leg unconditionally
- `send_chat_message_use_case.dart:824-871` — `raceFutures` is built with a local/LAN leg (`:833-846`, bounded by `interactiveLocalBudget`) and the **direct discover/dial/send leg** `_tryDirectSend` (`:855-871`, outer-capped by `interactiveDirectAggregateBudget` `:867`; per-step `kDirectDiscoverBudget=2000ms` `:118`, `interactiveDirectBudget=2000ms` `:24`). Neither leg consults any keepalive liveness state.

### The durable inbox is ALREADY concurrent (so skipping direct sacrifices nothing)
- `send_chat_message_use_case.dart:704-766` — for `unknownPresence` (`:704-707`: `!isAlreadyConnected && !isLocalPeer && !isConnectedToPeer`) the durable inbox copy fires CONCURRENTLY (`storeInInbox` `:732`), advancing the row to `inboxed` and emitting `CHAT_MSG_SEND_CUSTODY_CONFIRMED` on a ~110 ms ACK (`:753-762`). FDC-08 presence emphasis (`:768-812`) already tiers `unreachable → inbox-first`; `reachable/unknown → concurrent`. The concurrent inbox future is awaited once in the race-failure tail (`:1230-1231`) — no double relay write.

### The keepalive holds a fresh per-peer drop latch — but keeps it PRIVATE
- `active_peer_keepalive_use_case.dart:59-60` — `_consecutiveMisses`, `_dropHandled` (private). `:124-139` — on `_missThreshold` (2) consecutive misses it sets `_dropHandled=true`, emits `KEEPALIVE_PEER_DROP{peerId}` (`:132-136`), and reuses warmPeer + drainOfflineInbox ONCE (latched). `:97-100,119-121` — a successful ping (`_resetLiveness`) clears the latch. The ONLY public getter is `isProbeActive` (`:71`) — there is **no `livenessOf(peerId)` / `isDropped(peerId)`**.
- `main.dart:3670-3672` — the keepalive is constructed with `activePeerId: () => widget.conversationTracker.activePeerId`; it and the send use case are wired independently, so the send path has no handle on the latch.

### Liveness latency characteristics (from the re-measurement, informs the gate)
- A reachable ping round-trips fast: `P2P_PEER_PING_RESPONSE.rttMs` p50 **112 ms** (n=61). A dark-peer ping consumes the full **4 s** timeout; the drop latches on the **2nd** consecutive miss (~2×8 s). So the latch is a *lagging but positive* signal — safe to trust for "skip", and it self-clears within one interval (8 s) of the peer answering again.

---

## Test cases

### Group A — the skip (primary): a latched-dropped active peer's send skips the doomed direct dial
- **TC-187-01** — a send whose target IS the keepalive's active peer, the keepalive latch is set (`_dropHandled`), AND the peer is not connected (`!isConnectedToPeer`) → the **direct discover/dial leg is not run** (no `P2P_SERVICE_DISCOVER_PEER_BEGIN`/`DIAL_PEER_BEGIN` for that send; no ~1.5 s doomed dial). Assert via a DISTINCT discriminator event (e.g. `SEND_DIRECT_LEG_SKIPPED_KEEPALIVE_DROP`) so the test proves the skip happened for the *keepalive-drop* reason — NOT presence, NOT budget timeout.
- **TC-187-02** — the concurrent durable inbox still fires and custody is still confirmed (`CHAT_MSG_SEND_CONCURRENT_INBOX_BEGIN` → `CHAT_MSG_SEND_CUSTODY_CONFIRMED`). The skip never trades away durability.
- **TC-187-03** — on peer recovery the queued message delivers (drain → `DELIVERY_RECEIPT_APPLIED`). Skipping direct loses nothing and delays nothing the user sees (custody was already secured).

### Group B — no over-reach: FDC-01/02 stay intact (the guardrails)
- **TC-187-10** — a send to a peer whose keepalive says REACHABLE (recent `PING_SUCCESS`, latch clear) runs the direct leg with its full existing budget. No regression on the warm/near path.
- **TC-187-11** — a send to a peer of UNKNOWN liveness (NOT the currently-pinged active peer — no positive drop signal) runs the direct leg with the FULL existing budget. Explicit: FDC-01's "an unknown-liveness peer's 1900 ms discover must succeed / 2100 ms times out" is UNCHANGED; the FDC-01/02 suites stay green with no re-baseline.
- **TC-187-12** — latch reset: after a `PING_SUCCESS` clears `_dropHandled`, the NEXT send to that peer runs the direct leg again. The skip bites ONLY while the latch is set.

### Group C — connectedness interplay (the skip predicate is conservative)
- **TC-187-20** — if the drop handler's warmPeer re-dial has meanwhile reconnected the peer (`isConnectedToPeer` true), the send takes the reuse/direct path normally — the skip requires not-connected, so a recovered peer is never penalized.
- **TC-187-21** — the skip is gated on the target being the keepalive's tracked active peer; a send to a DIFFERENT peer (item 2 declined — keepalive stays 1:1-chat-scoped) is treated as unknown-liveness → full budget.

### Group D — invariants / no-regress
- **TC-187-30** — never falsely delivered: the skip relies on the concurrent inbox + a receiver receipt; no row is marked `delivered` without a receipt.
- **TC-187-31** — no double relay write: skipping the direct leg does not cause a second inbox store; the existing `concurrentInbox` tail short-circuit (`:811`, `:1230-1231`) still holds (one relay write).
- **TC-187-32 (device/measurement)** — reproduce the captured flow: a send to a latched-dropped active peer shows NO ~1.5 s `DIAL_PEER_ERROR` leg; custody still lands ~179 ms (concurrent inbox); delivery still occurs on peer recovery. The wasted dial is gone.

---

## Scope guard (non-goals)

- **Do NOT** change discover/dial budgets for unknown-liveness peers, and **do NOT** re-baseline FDC-01/02. The skip fires ONLY on a positive 183 keepalive drop latch for the tracked active peer. (This is precisely why the earlier "liveness-tiered budget / unknown→500 ms" idea was dropped: its latency upside is already banked by the concurrent inbox, and it would have overturned FDC-01.)
- **Do NOT** broaden the keepalive beyond the active 1:1 chat (item 2 decided: stay chat-scoped). A send only benefits when its target IS the currently-pinged active peer.
- **Do NOT** skip the local/LAN leg — LAN is an independent transport that could still reach a peer that dropped only its WAN/direct path. Only the WAN direct discover/dial (the measured ~1.5 s waste) is skipped. (A LAN-leg skip is a possible follow-up only if separately measured worthwhile.)
- **Do NOT** build a new liveness mechanism — reuse the 183 drop latch. The only new production surface is exposing that latch READ-ONLY to the send path.
- **Do NOT** frame or test this as a user-latency win — custody is already ~179 ms. Success = the doomed dial is gone (radio/battery), with zero durability or delivery regression.
- 1:1 only (groups have their own send/receipt model).
