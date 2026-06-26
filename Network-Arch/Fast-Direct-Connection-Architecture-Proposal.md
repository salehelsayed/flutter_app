# Fast, Reliable Direct Connection — Architecture Proposal

**Goal:** when two users are reachable, deliver over the *most direct* path with no perceived
latency; when they're not, guarantee delivery via the inbox. Make notification-tap and
"open app → send one message → close" feel instant and reliable.

**Status:** proposal / design. Grounded in a 13-agent codebase trace + go-libp2p best-practice
research, then adversarially critiqued. File:line anchors are verified against source on
branch `new-orbit` (2026-06).

> **One-line answer:** the slowness is **not one timer to tune — it's a serial cascade with no
> maintained connection and no presence signal.** The fix is to *delete the decision window*:
> warm the peer connection while the human is reading/typing, then on send **race every path
> concurrently while always depositing to the inbox in parallel**, committing on the first ack
> and de-duplicating by `messageId`. But warming must be **LAN-aware**, or it will quietly route
> same-WiFi peers over the relay and defeat the whole point (see §6.1).

---

## 1. What you asked for, and the honest constraints

You want three things, in priority order:

1. **Same-WiFi → talk directly.** Two phones on one WiFi should message each other locally.
2. **Both online + foreground → prefer a direct connection.** Don't go through the relay if a
   direct path exists.
3. **Background → use the inbox.** And in all cases, the message is delivered *eventually,
   guaranteed*, via the most direct path available, with minimal perceived latency.

Before proposing anything, four **constraints from the real system** must be stated, because they
bound what "direct" can honestly mean:

| Constraint | Why it matters | Source |
|---|---|---|
| **Direct is a ~70%-likely *upgrade*, not a guarantee — and our host has it turned OFF.** The Go host runs `ForceReachabilityPrivate()`, so DCUtR is *observation-only* and fires **zero** production hole punches **by configuration** (not because hole-punching fails). | Treat direct as an opportunistic upgrade the relay+inbox always backstop. **Correction (prior art §12):** "~0% on cellular" is a defensible *design assumption* (both peers behind symmetric CGNAT), **not** a citable figure — the published punchr measurement (4.4M attempts) is **70%±7.1% network-wide**, TCP==QUIC, 97.6% of wins first-attempt. A single cone-NAT/public peer rescues most pairs. | `node.go:330`; `holepunch_tracer.go:15-17`; punchr arXiv 2510.27500 |
| **Same-WiFi "direct" is not libp2p — it's a separate WebSocket stack**, and it's **foreground-only**. | LAN-first lives entirely in Dart (bonsoir mDNS + `LocalWsServer`), not in libp2p. iOS drops multicast in background, so LAN works only while the app is foregrounded. | `main.dart:1893-1914`; `local_p2p_service.dart`; §5 |
| **The relay cannot observe "foreground."** It only sees libp2p socket connectedness, which lags reality (an iOS socket lingers briefly after backgrounding). | Any "presence" signal is *"online-ish, TTL-lagged,"* never *"foregrounded."* Foreground/background must be **self-published by the peer**, not inferred. | relay `main.go:143-149` |
| **Relay changes must be additive.** Shipped clients have a hardcoded relay and no version negotiation. | Server-side improvements (presence lookup, durable backend) must not break older apps. | NET-REL-07 |

Everything below respects these. Where a recommendation cannot be honestly validated on
host/sim (anything touching real mDNS or real-wire "live-wins"), it's flagged device-only.

---

## 2. The system in one picture

```
                     ┌──────────────────────────── Dart (owns the path decision) ───────────────────────────┐
                     │                                                                                       │
  send(peer,msg) ──► │  sendChatMessage()  ── the "decision window" lives ENTIRELY here ──────────────────► │
                     │   send_chat_message_use_case.dart                                                     │
                     └───────────────┬───────────────────────────────────────────────┬───────────────────┘
                                     │ message:send (ONE-SHOT, single bridge channel) │ inbox:store
                                     ▼                                                 ▼
        ┌──────────── Go libp2p host (go-mknoon/node) ───────────┐         ┌──── Relay / Inbox server ────┐
        │ RELAY-FIRST: ForceReachabilityPrivate, AutoRelay on    │◄───────►│ rendezvous + circuit-v2      │
        │ static relays, DCUtR inert. NO libp2p mDNS.            │  circuit │ inbox (in-mem default!)      │
        │ Transports: QUIC-v1 + WS + TCP (defaults), Noise/TLS   │         │ FCM push. Dedups by msgId.   │
        └────────────────────────────────────────────────────────┘         └──────────────────────────────┘

        ┌──────────── SEPARATE Dart LAN stack (NOT libp2p) ──────┐
        │ bonsoir mDNS (_mknoon._tcp) ── LocalWsServer (WebSocket)│   ◄── "same WiFi → direct" really lives here
        │ enabled by default; foreground-only; own nonce ACK     │       (and libp2p has no idea it exists)
        └────────────────────────────────────────────────────────┘
```

**The single most important structural fact:** there are **two connectivity systems that don't
share state** — libp2p's connection manager, and the bonsoir/WebSocket LAN stack. The send path
checks them independently and sequentially. That fragmentation — not raw transport speed — is the
root of the slowness. (See §5 for *why* it ended up this way, and why that history matters.)

---

## 3. How a send actually works today (the cascade)

The path decision is owned by Dart's `sendChatMessage()`; Go only picks the low-level transport
inside one `message:send` and returns a label (`classifyStreamTransport` `node.go:123-136`).
There is **no maintained connection** and **no presence concept** — reachability is rediscovered
on every cold send.

The send ladder (`send_chat_message_use_case.dart`):

```
 (1) REUSE        peer already in currentState.connections?  → one sendMessageWithReply, 2s budget   :447-465
 (2) STICKY       lastKnownGoodTransport fresh & valid?       → reuse that path, no discover/dial      :528-595
 (3) RACE         leg LOCAL  = mDNS resolve → WS send, cap 1500ms (interactiveLocalBudget)        :21,:671-684
                  leg DIRECT = discover → dial → send, WHOLE future hard-capped at 2000ms       :24,:693-703
                  bias local>direct>relay via 150ms grace + 120ms sticky head-start              :48,:57
 (4) INBOX (lazy) only if "low confidence" (prior send to peer failed/inboxed <30s AND not connected) :608-660
 (5) PROBE TAIL   on race-fail that is relayProbeEligible → SERIAL probeRelay → dial → send, 5s ceiling :1021-1086
 (6) INBOX        final fallback storeInInbox, 3000ms budget                                          :1086
```

**Worst perceived path ≈ race(2s) + probe(5s) + dial(2s) + send(2s) + inbox(3s).** That compound
is the "window that feels slow." The measured offline trace in `UI-14-Conn-Type/online-inbox.md`
showed **~24s** (when there were still 3 dial attempts; now reduced to 1, but the serial shape
remains).

Same-WiFi specifics: on a **cold open** the discovered-peers map is **empty** — bonsoir
advertising/discovery starts only inside the fire-and-forget `warmBackground` (`p2p_service_impl.dart:649`).
So a same-WiFi peer must be (re)discovered *within the 1500ms send budget* or the message
silently falls through to direct/relay. The LAN advantage is routinely missed.

---

## 4. Why it feels slow — root causes (verified)

| # | Root cause | Evidence | Impact |
|---|---|---|---|
| R1 | **No per-peer eager pre-warm.** Opening a conversation / tapping a notification / resuming never dials the *specific* peer, so the first send always pays a full cold discover→dial. `warmBackground` warms LAN discovery + inbox but **never dials the contact**. | `send_chat_message_use_case.dart:1467-1532`; `p2p_service_impl.dart:572-647` | The dominant component of the perceived window on exactly the reported cases. |
| R2 | **The "window" is a single 2s hard cap over a *serial* discover→dial→send.** A slow discover starves dial+send → yields `direct_timeout` → **routes an online peer to the offline inbox** (see §4.1 — this is a real correctness bug, not just latency). | `:24`, `:699-703`, `:1467-1532` | Online-but-slow peer silently inboxed; delivered seconds late, "feels broken." |
| R3 | **No presence signal.** Reachability is inferred per-send via blind discover→dial; the only online/offline signal (relay `NO_RESERVATION`) runs *serially after* the 2s race with a 5s ceiling. | `probeRelay p2p_service_impl.dart:4074-4089`; `RelayProbeTimeout=5s config.go:30` | Even foreground+online sends pay a full discover/dial before they can "know" the peer is reachable. |
| R4 | **No libp2p LAN discovery; DCUtR inert.** Same-WiFi direct is delegated to the separate bonsoir+WS stack whose map is empty on cold open; a relay connection never auto-upgrades to direct. | `node.go:338-347` (no `mdns.NewMdnsService`), `:330`; `holepunch_tracer.go:15-17` | Same-WiFi peers miss the 1500ms budget and fall to relay; relay-first stays relay forever even on one LAN. |
| R5 | **Cold start inherits the 15s relay `DialTimeout`** and blocks discoverability up to 10s; resume re-establishment is serial+awaited on the single Go bridge. | `config.go:28` vs `:39-41`; `personal_rendezvous_refresh.go:17`; `handle_app_resumed.dart:136-191` | The first send in the first ~2s after cold open finds no circuit and no LAN map → inbox even for a reachable peer; resume latency couples onto send latency. |
| R6 | **The durable inbox safety net is gated behind "low confidence" only**, so the common cold notif-tap send waits the *serial* probe→inbox tail instead of getting concurrent custody. | `:608-660` (gate); `:1021-1086` (serial tail) | "Will deliver" custody is several seconds late on the open-send-close path; the user watches a long "sending…". |

### 4.1 The correctness bug worth fixing on its own

`direct_timeout` is produced by the outer `onTimeout` at `:701`, and `relayProbeEligible`
**defaults false** — only `peer_not_found` (`:1483`) and `dial_failed` (`:1500`) set it true.
So a **slow-to-discover but online** peer that burns the 2s budget yields `direct_timeout`,
**skips** the relay-probe tail, and (high-confidence) lands in the **offline inbox** instead of
being delivered live. This is verified against source. It reads as "slow/buggy" and should be
fixed independently of the broader redesign.

---

## 5. The decision we already made (and its cost): WebSocket-over-WiFi vs libp2p

This is worth recording so we build on the real constraints instead of naively saying "just use
libp2p QUIC on the LAN." There were **two separate decisions**, often conflated:

**(A) Discovery — bonsoir, not libp2p mDNS.** Documented in
`native-p2p-go-libp2p/native-p2p-go-libp2p.md` §"Why not go-libp2p's built-in mDNS?" (L399-438):
go-libp2p mDNS uses *raw UDP multicast*, which on **iOS requires Apple's
`com.apple.developer.networking.multicast` entitlement** — rarely approved for App Store apps.
So bonsoir (iOS Bonjour / Android NSD, which wrap the OS's *blessed* multicast services) was used
instead. Android wouldn't have blocked us (just `CHANGE_WIFI_MULTICAST_STATE` + a `MulticastLock`),
but using each OS's official wrapper avoided maintaining an iOS-forbidden raw-multicast path.

**(B) Transport — a WebSocket server, not a direct libp2p QUIC dial on the LAN.** The migration
plan *intended* bonsoir-for-discovery → `dialPeer(peerId, [localMultiaddr])` for a direct **QUIC**
LAN connection (L415-421). **That never shipped.** From the first local-discovery commit
(`de9f8607`, Feb 2026) it was already "mDNS + WebSocket server," and the LAN service advertises a
**`wsPort`**, not the libp2p port (`local_discovery_service.dart:169 startAdvertising(peerId, wsPort)`).
Why:
- **QUIC was unreliable then** — `UI-15-WS-Server/plan.md` (L42-48) records a live *"QUIC identify
  handshake hang"*; `defaultQUICRelayAddress` had been *removed* from client defaults, to be re-added
  only after verifying the handshake didn't hang. Peer-to-peer QUIC on the LAN would be even shakier.
- **WebSocket gave a trivially-reliable ACK** — a bespoke per-message nonce → `{ack:true,nonce}`
  echo (`local_ws_server.dart`, `lan_ack.dart`; `ConnectionManager.md` §2). This is the "ACK for
  WiFi" we remembered. The nuance: it was **not** a UDP limitation (QUIC has reliable streams) —
  it's that a bare TCP WebSocket gave guaranteed per-message confirmation, identical on iOS+Android,
  no entitlement, with media (HTTP PUT) riding the same server, *without fighting the
  QUIC/libp2p/gomobile stack.*

**The cost of that pragmatic choice is exactly the fragmentation in §2** — two connectivity systems
that don't share state. So §6.5's unified libp2p LAN-direct (fed by bonsoir discovery) is the *clean*
end-state, but it carries a hard precondition: **re-validate that the libp2p QUIC/TCP LAN dial (the
identify handshake) is reliable now.** Until then, bonsoir+WS stays the proven foreground LAN path.

---

## 6. Target architecture: delete the window

A **maintained-connection, presence-aware, race-everything** model. Five moving parts.

### 6.1 Eager warm — but LAN-aware (the headline, with the critical caveat)

The moment a conversation opens, a notification is tapped, or the app foregrounds, fire a single
idempotent **`warmPeer(peerId)`** that overlaps connection setup with human reading/typing time.
By send-time the connection is hot and the send hits the existing reuse fast-path
(`:447-465`) → near-instant ack.

> **⚠️ The trap that defeats LAN-first.** The reuse fast-path at `:447-451` fires whenever
> `currentState.connections` contains the peer and sends over that connection **without the local
> race and without checking `isLocalPeer`**. If `warmPeer`'s speculative `dialPeer` lands a
> `/p2p-circuit` **relay** connection to an online same-WiFi peer — the *common* case, since libp2p
> has no mDNS and discovers via relay rendezvous — then the next send sees `isAlreadyConnected=true`
> and sends over **RELAY**, never attempting the LAN leg. Naive warming would make this LAN-bypass
> happen on **every** conversation open. **`warmPeer` must therefore:**
> 1. **Warm the LAN path first/too** — call `discoverLocalPeer` so the bonsoir map is populated
>    *before* the user can hit send; and
> 2. **Keep the send LAN-aware** — gate the reuse/sticky short-circuit behind an `isLocalPeer`
>    check, so a warmed *relay* circuit never satisfies "already connected" when a LAN path is
>    viable. Prefer local even when a relay conn exists.

`warmPeer` must be **single-shot, bounded, and debounced per peer**: `host.Connect` is a no-op when
already connected, but repeated opens/taps/resumes to an **offline** peer each fire a *fresh failing
dial*, which accrues libp2p swarm per-address backoff (5s → 5m). Add a short per-peer warm cooldown;
do not tight-loop a failing dial.

**Honest scope:** warm helps the **warm-open** case (app already running, node started). On a
**cold notif-tap the Go node isn't started yet** (`node:start` is gated behind deferred
Firebase + bridge + ~25 startup listeners), so `warmPeer` cannot dial before node-start +
reservation exist — the dial can't fully overlap reading time on the coldest path. There, the win
comes from §6.4 (fast node-start + early reserve), not from warming. Don't oversell P0 latency on
cold starts.

### 6.2 Staggered ranked race + parallel durable inbox (no window)

> **Correction from prior art (§12):** "race *everything* in parallel" is the exact anti-pattern
> libp2p deprecated in v0.28 (blind fan-out cost ~30% extra dials). Replace it with a **staggered,
> relay-penalized ranked race** modeled on go-libp2p's `DefaultDialRanker`, and **keep two tiers
> strictly separate**: the *transport race* (a speed optimization) and the *durable inbox deposit*
> (the delivery guarantee). They are not the same mechanism.

On send: persist the envelope (crash-safe — already done) and render the optimistic bubble
(instant — already done). Then:

**(a) Transport race — staggered, not blind fan-out.** Dial LAN-direct + libp2p-direct first;
**penalize the relay-live leg by ~500ms** and give private/LAN addrs a ~30ms Happy-Eyeballs tail
(public ~250ms). Commit on the first ack, then **migrate onto the winner and collapse the losers**
(iroh/Tailscale/WebRTC all collapse onto the chosen path — they do *not* permanently dual-send).
**This ranked race *is* the LAN-first fix from §6.1 — by priority, not suppression:** rank the
mDNS/LAN lane highest and let the relay leg *race but lose*. You can drop the explicit `isLocalPeer`
gate in favor of ranking (keep it only as a belt-and-suspenders).

**(b) Durable inbox — always, in parallel, a *separate tier*.** Deposit to the relay inbox
regardless of the race; this is the guarantee, and it's the part the transport systems (iroh,
Tailscale) don't give you (their relays need both peers online). **Critical separation:** a libp2p
circuit-v2 *live* relay connection is "limited" — **2 min / 128 KB per direction, reset on
violation, 1 reservation/peer** — so the live-relay leg is only an opportunistic accelerator;
**media and any large/long payload must go direct-or-inbox, never over the live relay socket.**
(SSB independently split these as *rooms* = live tunnels vs *pubs* = store.)

Merge rule when the inbox and a live leg both deliver the same id: **newest-timestamp-wins /
max-status** (Jami `commitId`). Receiver **dedupes by `messageId`**, so the parallel inbox copy is
harmless.

Two honesty notes from the critique:
- **"Cancel the losing legs" is mostly aspirational.** Dart Futures aren't cancellable and
  `message:send` is a one-shot Go call — an in-flight losing direct/relay leg can't be reliably
  cancelled, so a duplicate *may* still be delivered. Correctness leans on **receiver `messageId`
  dedup** (present), not on cancellation.
- **Recipient cost rises.** Every extra inbox deposit means the recipient, on wake, does an extra
  retrieve+ack round-trip (the inbox is one-request-per-stream, no long-poll) plus a UI-deduped
  decrypt. Only the **sender's** perceived latency improves; net relay + recipient work increases.
  Worth it for reliability, but measure it.

### 6.3 Presence-aware emphasis — "online-ish," never "foreground"

A cheap presence signal lets the sender pick *direct-race vs inbox-first* up front instead of
paying a blind discover/dial/probe. **But the relay can only report "has a live relay
connection/reservation" ≈ *online-ish, TTL-lagged* — it cannot report foreground/background**
(`main.go:143-149` tracks socket connectedness only). So:

- **`reachable` (relay says reserved/connected, recently):** emphasize the live legs; fire the
  inbox lazily as a safety net.
- **`unreachable` (no reservation):** inbox-**first** (custody immediately) + push-to-wake; live
  legs best-effort.
- **`unknown`:** today's full concurrent race + concurrent inbox.

Presence is an **emphasis hint, never a replacement for the inbox** (the peer may background
between lookup and send). If you genuinely need foreground/background gating (your requirement #2/#3),
the peer must **self-publish** it — either a lightweight gossipsub heartbeat beacon (the node already
inits pubsub at `node.go:379`, no relay change) or an explicit client→relay status push on
pause/resume. Inferring it from connectedness will be wrong on iOS.

### 6.4 Lifecycle handshake + graceful handoff

- **On pause/hidden:** flush every in-flight `sending` message to the inbox **before** the OS
  suspends the process, so a mid-send app-close still delivers (your "send one message then close"
  case). **Mechanism caveat:** `handleAppPaused` today is *local-DB-only, no network*
  (`main.dart:4314-4316`), and iOS gives no guaranteed window on the pause transition. A network
  flush on pause needs an explicit `UIApplication beginBackgroundTask` (or an APNs-backed path) and
  must be **bounded and inbox-store-only** so it completes before freeze. This is a real iOS
  feasibility question, not a given.
- **On resume/notif-tap:** run relay re-prime + mDNS restart + peer warm + inbox drain **in
  parallel** with foreground 3s budgets — **not** serialized behind an awaited drain as today
  (`handle_app_resumed.dart:136-191`). Keep the existing "catching up…" affordance for the unawaited
  drain.
- **Never hold a direct connection alive in background** — battery cost with ~0 benefit; background
  is the inbox's job.

### 6.5 Unified LAN-direct over libp2p (end-state)

Bonsoir discovers same-WiFi peers **uniformly on both iOS and Android** (one code path; no
libp2p-native `mdns.NewMdnsService` on either platform — on Android it would be a redundant second
discovery mechanism, on iOS raw multicast is entitlement-blocked), feeding the discovered `AddrInfo` /
LAN multiaddr into `host.Connect` so a same-WiFi peer becomes a **direct libp2p dial that
`DefaultDialRanker` races ahead of relay** (LAN ~30ms vs relay-delay ~500ms), with
identify/`IdentifyPush` keeping the LAN address hot and `WithForceDirectDial` upgrading a relay
connection once a LAN address is known — the relay→direct upgrade DCUtR cannot deliver under
`ForceReachabilityPrivate`. Keep bonsoir+WS as the proven foreground/iOS fast path; dedupe by
`messageId`. **Precondition:** the §5 QUIC-identify-hang re-validation. **Validation:** device-only
(iOS sim shares a host mDNS stack → forces `DISABLE_LOCAL_DISCOVERY`), so this cannot be proven on
host/sim.

---

## 7. Proposed connection state machine

```text
// ===== APP-LEVEL =====
COLD → STARTING → ONLINE_FG ; ONLINE_FG ↔ ONLINE_BG_BRIEF → OFFLINE_BG
//  STARTING = node:start fired; relay warming with FOREGROUND budgets (config.go:39-41), not the 15s DialTimeout

// ===== PER-PEER (maintained while conversation open / recently active) =====
// UNKNOWN | WARMING | HOT_LAN | HOT_DIRECT | HOT_RELAY | COLD_OFFLINE
reachable(peer) = presenceCache.lookup(peer)   // "online-ish, TTL-lagged" — NOT foreground; falls back to UNKNOWN

// ===== EAGER WARM (LAN-aware, debounced) =====
on CONVERSATION_OPEN(peer) | NOTIF_TAP(peer) | RESUME:
    warmPeer(peer)                                  // fire-and-forget, idempotent, per-peer cooldown
    if RESUME or NOTIF_TAP: fastReprime()           // parallel: relay reserve(3s), restart mDNS, drain inbox (unawaited, banner)

fun warmPeer(peer):
    if recentlyWarmed(peer): return                 // debounce → avoid swarm backoff on offline peers
    par:
        discoverLocalPeer(peer, 1.5s)               // seed the LAN map FIRST → HOT_LAN  (prevents the §6.1 relay-bypass)
        if !isLocalPeer(peer): dialPeer(peer)       // speculative discover+dial, NO send → HOT_DIRECT/HOT_RELAY
    // never tight-loop a failing dial

// ===== SEND (replaces the window) =====
fun send(peer, msg):
    persistEnvelope(msg); renderOptimisticBubble(msg)        // already done

    // FAST PATH — but LAN-aware: a warmed RELAY circuit must NOT bypass an available LAN path
    if isLocalPeer(peer):           prefer LAN leg first
    elif peerState in {HOT_DIRECT, reuse}:  ack = sendOver(peerState, msg, 1s); if ack: return delivered(live)

    // CONCURRENT RACE — first live ack wins; dedupe by msg.id
    live = race(first-success-wins):
        legLAN    = resolveLAN(peer,1.5s) → wsSend                 // 'local'
        legDirect = dialPeer(peer) → streamSend(per-step budgets)  // NOT collectively 2s-capped (fixes R2/§4.1)
        legRelay  = if circuitLive: sendOverCircuit               // 'relay'
        prefer local>direct>relay within 150ms grace

    // SAFETY NET — always parallel, NOT a race participant (generalizes today's low-confidence inbox)
    inbox = storeInInbox(peer, msg, 3s)             // relay already dedupes by msg.id on store

    if reachable(peer)==true:  inbox = lazy (fire, don't await)    // live legs carry it
    elif reachable(peer)==false: commit on inbox first + pushToWake; live legs best-effort
    // else UNKNOWN: full race + concurrent inbox

    on FIRST live ack:  return delivered(live)       // losers can't be cancelled → rely on receiver dedup
    elif inbox ok:      return delivered(inbox) + pushToWake
    else:               return failed (retain envelope for retriers)

// ===== BACKGROUND / GRACEFUL HANDOFF =====
on PAUSE | HIDDEN:
    beginBackgroundTask:                            // iOS: needed for any network on pause
        for each in-flight 'sending' msg: ensureCommittedToInbox(msg)   // bounded, inbox-store-only
    // do NOT hold direct conns alive in background
```

---

## 8. Recommendations (prioritized; corrected vs the raw proposal)

| P | Title | What | Effort | Impact |
|---|---|---|---|---|
| **P0-1** | **LAN-aware eager `warmPeer`** | New idempotent, **debounced** `warmPeer(peerId)` = `discoverLocalPeer` (seed LAN map first) + speculative `dialPeer` (no send); call on conversation-open, notif-tap, resume (top-N). **Gate reuse/sticky behind `isLocalPeer`** so a warmed relay circuit never bypasses LAN (§6.1). | M | high |
| **P0-2** | **Generalize the concurrent inbox** | Lift the durable inbox deposit out of the "low confidence only" gate → fire `storeInInbox` **concurrently** with the live race for all unknown-presence sends; drop the serial probe→inbox tail. Dedup by `messageId` (already enforced server-side). | S | high |
| **P0-3** | **Fix the 2s-serial starvation / online→inbox mis-route (§4.1)** | Give discover/dial/send **independent** budgets instead of one 2s cap over the serial leg; make `direct_timeout` relay-probe-eligible (or lean on the always-on concurrent inbox + a continuing live attempt). | M | high |
| **P1-1** | **Relay presence lookup (additive)** | Additive inbox action returning "does this peer hold a live reservation?" Cache client-side (short TTL). Use to pick direct-race vs inbox-first up front, replacing the blind 5s `DialPeerViaRelay` probe. **Report "online-ish," not "foreground."** Note: exposing reservation-truth (vs raw connectedness) may need go-libp2p relay-service internals. | M | high |
| **P1-2** | **Lifecycle split + graceful handoff** | Parallel (not serial) resume re-prime with 3s foreground budgets; bounded inbox-store-only **pause flush** via `beginBackgroundTask` (resolve the iOS "no network on pause" invariant); encode background→inbox-first explicitly. | M | high |
| **P1-3** | **Cold-start: earlier mDNS/reserve (measure before re-timing)** | Start mDNS advertise/discover + relay reservation **earlier** (not buried in the post-startup fire-and-forget warm). **Do NOT blindly cap the cold relay dial at 3s** — the 15s `DialTimeout` is consumed by a *background* goroutine that doesn't block sends; capping a genuinely-cold QUIC/TLS handshake risks *more* abandoned reservations → *more* inbox fallback. Measure cold time-to-circuit first. | M | medium |
| **P2-1** | **Unified libp2p LAN-direct (bonsoir-fed)** | Bonsoir (uniform on both iOS & Android) discovers same-WiFi peers and feeds the AddrInfo/LAN multiaddr into `host.Connect` (no libp2p-native mDNS on either platform); `DefaultDialRanker` races LAN ahead of relay; `WithForceDirectDial` to upgrade relay→direct. Keep bonsoir+WS as fallback; dedup by `messageId`. **Precondition: §5 QUIC-identify-hang re-validation.** Device-only validation. | L | medium |
| **P2-2** | **Durable inbox backend** (NOT idempotency — that exists) | Move the relay inbox off the in-memory default to the **existing Redis backend** so the queue+tokens+reservations survive a relay bounce. **Store dedup by `messageId` is already implemented** (`backend_memory.go:121-142`, `backend_redis.go:272-295`, `inbox_store.go:7,14`) — do *not* re-build it. | M | medium |
| **P2-3** | **Opportunistic DCUtR upgrade (flagged)** | Behind a flag, let DCUtR upgrade a relay conn to direct; keep relay+inbox as the carrier so the user never waits. **Payoff is higher than first rated** — punchr shows ~70% network-wide (near-0 only for symmetric-CGNAT cellular↔cellular), so this is worth a real measurement spike. **Build a stable peer-identity session layer**: DCUtR hands you a *second* connection (unlike iroh/Tailscale in-place migration), so re-point "the peer" to the new direct conn + dedupe by `messageId`. Include a **TCP-direct lane** (punchr: TCP==QUIC); spend effort on RTT-sync precision + UPnP/PMP reversal, **not retries** (97.6% of wins are first-attempt). | L | low→med |

---

## 9. Sequenced rollout

1. **Phase 0 — Dart-only, no relay/Go deploy (P0-1, P0-2, P0-3).** Deletes the perceived window
   for the common warm-open case and fixes the online→inbox mis-route. Validatable against the
   existing NET-REL host fakes — **but note** real-wire "live-wins" and over-the-Go-wire concurrent
   liveness are host-fake-only with a known false-positive risk (a test can pass via dedup even if
   the live path never fired). "Host-testable" ≠ "validated"; pair with a device smoke.
2. **Phase 1 — lifecycle + cold-start (P1-2, P1-3, mostly Dart + small Go timeout reuse).** Tightens
   resume and open-app. Measure cold time-to-circuit before re-timing anything (P1-3).
3. **Phase 2 — additive relay deploy (P1-1 presence, P2-2 durable Redis).** **Ordering matters:**
   P0-2 raises inbox volume *before* P2-2 makes the inbox durable, so for that window the extra
   copies sit in the restart-losable in-memory backend. Consider pulling **P2-2 (Redis) earlier**,
   alongside or before P0-2, to shrink the blast radius of a relay bounce. (Idempotency is already
   fine; it's *durability* ordering that's the hazard.)
4. **Phase 3 — Go host change + device validation (P2-1 libp2p LAN-direct (bonsoir-fed), P2-3 flagged DCUtR).** Gated on
   the QUIC-identify-hang re-validation; device-only.

---

## 10. Honest limitations & risks

- **Cold notif-tap can't fully overlap dial with reading time** (node not started yet). The cold
  path's win is fast node-start + early reserve (P1-3), not warming. Don't promise instant on cold.
- **`warmPeer` to offline peers can trip swarm backoff** (5s→5m) without a per-peer cooldown —
  debounce is mandatory, not optional.
- **The single Go bridge is a serialization point.** `warmPeer` + `fastReprime` + the user's send
  all funnel through one bridge channel; Dart `Future.wait` parallelism does **not** yield Go-level
  concurrency, so they can head-of-line block each other. Prioritize the user's send over speculative
  warm/reprime on the bridge, or the warm work can *delay* the very send it's meant to speed up.
- **Presence is TTL-lagged and never "foreground."** It can only emphasize a path; the inbox stays
  the always-works backstop. Foreground/background gating needs peer self-publishing.
- **iOS pause-flush feasibility is unresolved** — needs `beginBackgroundTask`/APNs and breaks the
  current "no network on pause" invariant; must be bounded.
- **LAN double-delivery** if the libp2p LAN-direct leg and the bonsoir+WS leg both deliver — dedup by `messageId`, pick one
  authoritative path.
- **Cross-network direct ≈ 0%** — relay is the honest cross-network path; over-investing in DCUtR
  yields near-zero payoff.
- **Budget/timeout changes risk regressing validated NET-REL test locks** — each needs a
  mutation-verified RED test and a re-run of the 1to1/feed gates.

---

## 11. What to measure first (open questions)

1. On iOS cold notif-tap, **where is `peerId` first available**, and can `warmPeer` fire from the
   notification handler *before* the Flutter engine/chat screen builds (NSE vs main isolate)?
2. **Presence: relay lookup (additive action; needs deploy) vs gossipsub beacon (no relay change,
   adds churn)?** Which is the right "online-ish" signal, and how do we self-publish foreground?
3. **Measured cold-open time-to-circuit-address and time-to-first-mDNS-resolve on real devices** —
   the input that sets realistic foreground budgets and decides how aggressively to warm. (Several
   P1 recommendations are gated on this; don't re-time blind.)
4. **Unify the two LAN stacks (bonsoir-fed libp2p LAN dial) or keep them parallel with dedup?** Gated on the §5
   QUIC-identify-hang re-validation.
5. **Can the relay pipeline ship additive presence + Redis without breaking older clients
   (NET-REL-07)?** Is the live relay env reproducible from-repo for validation?
6. **iOS pre-suspension budget for the pause-flush** — how many in-flight sends must it cover?

---

## 12. Prior art — what the field already proved (and two corrections)

A sourced survey of real libp2p/P2P systems (Berty/Wesh, Status+go-waku, Jami, Briar, Session,
SSB, Delta Chat, Quiet, Tailscale, iroh, WebRTC, and the punchr DCUtR measurement). **The core
shape — warm-by-identity, ranked race, durable inbox as the guarantee, presence-as-hint,
push-to-wake — is well-trodden.** Two of our decisions needed correcting (folded into §6.2 and §1).

### Closest references (study these)

| System | Why it's the reference | Link |
|---|---|---|
| **iroh / n0** | Closest to our *transport ideal*: dial-by-identity, persistent relay carries the first bytes, background hole-punch, **migrate the connection to direct** ("data never stops flowing"). Honest budget ~90% punch / ~95% bytes-direct (favorable, non-mobile). Note: true multipath is still WIP → **migrate, don't permanently dual-send.** | iroh.computer/blog/healing-connections |
| **Status (status-go + go-waku + SPN)** | Closest to our *whole mobile reality*: single gomobile bridge, **store-node = our inbox**, **lightpush-ack = commit signal**, Store-v3 **message-ID reconciliation**, no native presence, access-token-gated **visible** push-to-wake. | status.app/blog/status-app-notifications-on-ios |
| **Jami** | Canonical **presence-as-hint** precedent: DHT presence TTL ~10 min (hours with push), ICE candidate race in one negotiation, channel-reuse warm, `commitId` newest-wins merge. | jami.net/improved-reliability-presence-and-message-status |
| **Berty / Wesh** | Our nearest **gomobile-libp2p sibling**: relay-only-on-cellular, **ciphertext-only** stores, Zero-Push opaque-token wake — and the pitfalls below. | berty.tech/docs/zeropush |
| **go-libp2p `DefaultDialRanker`** | The exact "race but LAN-aware without letting relay bypass direct" machinery we were reinventing (`RelayDelay=500ms`, private 30 ms / public 250 ms). | pkg.go.dev/.../p2p/net/swarm |
| **punchr (arXiv 2510.27500)** | Empirical ground truth: **70%±7.1%** hole-punch, **TCP==QUIC**, 97.6% first-attempt, ~29% can't even reach the punch. Corrects our "~0%" framing. | arxiv.org/html/2510.27500v1 |
| **SSB rooms-vs-pubs / Quiet** | SSB independently split **relay-LIVE (rooms) vs relay-INBOX (pubs)** — validates §6.2's tier separation. Quiet is the counter-example: *no* always-on store → delivery fails unless peers overlap online → proves the inbox is non-negotiable. | manyver.se/blog/announcing-ssb-rooms |

### The two corrections (now in the doc)

1. **"Race everything" → staggered, relay-penalized *ranked* race** (§6.2). Blind parallel fan-out
   is a libp2p **anti-pattern deprecated in v0.28** (cost ~30% extra dials). The ranked race *also
   solves §6.1's LAN-bypass by priority, not suppression* — rank LAN first, let relay race-but-lose.
2. **"~0% on cellular" → a ~70%-likely upgrade** (§1, P2-3). It's a defensible *design assumption*
   for symmetric-CGNAT cellular↔cellular, **not** a citable number. Our host shows zero punches
   because `ForceReachabilityPrivate` turns DCUtR **off** — config, not capability. So DCUtR-upgrade
   is worth more than first rated (include a TCP lane; precision over retries).

### Strongly-validated patterns to borrow verbatim

- **Durable inbox = THE guarantee, everything else is speed** (universal: Berty/Waku/Briar/Session/
  Jami/SSB/Delta). Store **ciphertext only** (forwarder can't decrypt); **ID-first reconciliation**
  (Waku Store-v3 — sync IDs, fetch bodies lazily) to cut mobile bandwidth; keep acks **coarse**
  (Waku MVDS: per-message E2E acks "cannot scale"); deposit to a **relay pool**, not one relay.
- **Presence is strongest-validated as hint-only** (Jami's exact model; Session/SSB/Delta ship
  *zero* presence and stay correct). Never load-bearing for delivery. `identify/push` only reaches
  *already-connected* peers, so a backgrounded peer's freshness is bounded by connectivity.
- **Warm by peer-identity + a small FIXED relay pool** (iroh NodeId, AutoRelay `desiredRelays=2`,
  inject our own static relays to skip the 3-min bootDelay & the public-relay 1-reservation cap).
  **Bound every warm dial** with per-`(peerId,transport)` backoff (libp2p quadratic 5s→5min). Warm
  **only the per-peer you'll use, never the roster** (Berty: hundreds of peers cripples even
  high-end phones). **Add network-change (WiFi↔cellular) as a re-warm trigger; prefer QUIC** (a
  network switch "closes ALL connections except QUIC").
- **Push-to-wake hardening:** per-recipient **access-token** gate (only contacts can wake you —
  anti-spam), **opaque-token routing** with the push path decoupled from the message path
  (unlinkable), and a **visible** push (iOS throttles silent pushes to ~1–2/hr, no execution
  guarantee). The push is only a wake signal; content is pulled from the inbox.
- **On pause, issue the inbox deposit *before* the direct attempts** so durability lands even if iOS
  suspends mid-send; the early deposit (not the best-effort flush) is the guarantee.

### Risks prior art confirms we'll hit

- **Bridge serialization** — Berty (`bertybridge`), status-go, go-waku all funnel through one
  serialized FFI. Their mitigation: heavy work (decrypt/store-diff) **inside Go behind coarse,
  batched calls**; keep warm/probe dials **off the send-critical path**. (Matches §10.)
- **Network transition drops all-but-QUIC connections** (Berty); iroh must re-run discovery after an
  address change → a window back on relay.
- **Live relay circuit is not a durable pipe** — circuit-v2 caps 2 min/128 KB, resets on violation,
  1 reservation/peer → media must go direct-or-inbox (now explicit in §6.2).
- **iOS background** — Berty's node is killed within seconds of backgrounding (tens of seconds to
  reconnect on resume); only VOIP-class apps hold a bg socket; Briar had no usable iOS client for
  years. You cannot be the always-on node on iOS — the push-woken inbox covers backgrounded peers.

---

### Appendix — key evidence index

- **Send ladder / window:** `lib/features/conversation/application/send_chat_message_use_case.dart`
  — reuse `:447-465`, sticky `:528-595`, low-confidence inbox `:608-660`, race + 2s outer timeout
  `:693-703`, serial probe→inbox tail `:1021-1086`, `_tryDirectSendInner` `:1467-1532`; budgets
  `:21`/`:24`/`:48`/`:57`; `relayProbeEligible` set only at `:1483`/`:1500`, `direct_timeout` at `:701`.
- **Dart P2P service:** `lib/core/services/p2p_service_impl.dart` — `warmBackground` `:572-647`,
  circuit poll `:596-622`, advertising-in-warm `:649`, `probeRelay` `:4074-4089`, `isConnectedToPeer`
  `:4092`, `isLocalPeer` `:4097`, `lastKnownGoodTransport` `:4100`, `discoverLocalPeer` `:4132`.
- **Go host:** `go-mknoon/node/node.go` — `Node.Start` `:218-468`, listen addrs `:298-315`,
  `ForceReachabilityPrivate` `:330`, host opts (no mDNS) `:338-347`, AutoRelay `:349-358`, connmgr
  `:247`, NATPortMap `:344`, background relay warm `:429-439`, `classifyStreamTransport` `:123-136`;
  `holepunch_tracer.go:15-17`; `config.go` `DialTimeout=15s :28`, `RelayProbeTimeout=5s :30`,
  foreground budgets `:39-41`; `personal_rendezvous_refresh.go:17`.
- **Lifecycle:** `lib/core/lifecycle/handle_app_resumed.dart:136-191`; `lib/main.dart`
  LocalP2PService `:1893-1914`, `handleAppPaused` `:4314-4316`; `lib/core/debug/e2e_test_mode.dart:2`.
- **LAN stack:** `lib/core/local_discovery/{local_p2p_service,local_ws_server,bonsoir_discovery_service,lan_ack}.dart`;
  `local_discovery_service.dart:169`.
- **Relay/inbox:** `go-relay-server/` — connectedness (NOT foreground) `main.go:143-149`, store dedup
  `backend_memory.go:121-142` / `backend_redis.go:272-295` / `inbox_store.go:7,14`.
- **Decision history:** `native-p2p-go-libp2p/native-p2p-go-libp2p.md` L399-438 & L415-421;
  `UI-15-WS-Server/plan.md` L42-48; `UI-14-Conn-Type/{ConnectionManager,Connection-Steps,online-inbox,gap-edgecase,FutureImprovments}.md`.
```
