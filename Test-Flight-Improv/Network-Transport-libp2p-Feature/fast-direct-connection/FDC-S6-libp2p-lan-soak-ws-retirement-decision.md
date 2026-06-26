# FDC-S6 - libp2p-LAN soak + WS-transport retirement decision  (Spike / Decision)

Status: open

Spec: Network-Arch/Fast-Direct-Connection-Architecture-Proposal.md (§5 "WebSocket-over-WiFi vs
libp2p", L128-160; §6.5 "Unified LAN-direct over libp2p (end-state)", L276-286; §10 "LAN
double-delivery"). Scope: **1:1 messaging only.**

Gates: This is the **last-step decommission decision** for the FDC epic. It **does NOT gate any
current plan** — no FDC plan is blocked on it. It is itself **GATED BY FDC-11** (the libp2p-LAN
chat device-proof must land first) and **transitively by FDC-S2** (the protocol verdict FDC-11
consumes). Its **output** is a per-component keep-vs-retire **verdict** plus the *names* of any
NEW follow-on retirement / media plans required to execute a retirement — those plans are **not**
authored here.

---

## Question

Given libp2p-LAN chat is device-proven (FDC-11 D1 GREEN on both platforms), **should we retire**:

- **(a)** the **WS LAN CHAT transport** (`LocalWsServer` WebSocket + per-message nonce-ACK), and/or
- **(b)** the **WS/HTTP LAN MEDIA server** (`LocalMediaServer` HTTP `PUT /media/<id>` +
  `media_offer`/`media_uploaded` WS signaling),

**or keep them?** Bonsoir discovery (`BonsoirDiscoveryService` `_mknoon._tcp`) is **NOT a
retirement candidate** — iOS raw multicast is entitlement-blocked, so iOS needs bonsoir for
*discovery* regardless of which *transport* wins (proposal §5 L133-139; FDC-11 platform-constraint
section L115-133).

The number this spike produces: a **soak dataset** (libp2p-LAN win-rate + LAN-direct delivery
success/failure deltas vs the bonsoir+WS baseline, on real iOS+Android pairs, over N days) and a
**per-component verdict** keyed to concrete thresholds.

---

## Why it blocks / why it matters

The WS stack and the libp2p-LAN lane (once FDC-11 ships) are **two parallel LAN-direct systems**.
Without an explicit keep-vs-retire decision **owned by some doc**, one of two failures is
guaranteed:

- **Run-both-forever:** the two stacks live side-by-side indefinitely — extra code, extra attack
  surface, two LAN code paths to maintain, double-delivery on every same-WiFi send (bounded but
  not free; receiver pays a wasted decrypt+dedup, proposal §6.2 L236-239), and the §2 "two
  connectivity systems that don't share state" fragmentation never actually closes.
- **Retire-prematurely:** someone deletes `LocalWsServer`/`LocalMediaServer` on the strength of a
  single FDC-11 D1 pass/fail smoke — but D1 only proves the libp2p-LAN **chat dial** *can* form a
  `"direct"` stream once, **not** that it *wins reliably over a soak* and **not** anything about
  **media bytes** (no plan moves LAN media to libp2p). That regresses LAN media to relay-CDN
  latency and risks net-new LAN-direct chat failures the single smoke never measured.

**This conclusion is currently owned by NO plan.** FDC-11/D1 device-proves only that the
libp2p-LAN **chat** path works (one pass/fail smoke, `FDC-11` D1 L333-348); FDC-S2 only decides
**protocol feasibility** (Option A/B/C, `FDC-S2` L111-148); and FDC-11 **explicitly keeps
bonsoir+WS** ("Keep bonsoir+WS as the proven foreground/iOS fast path", `FDC-11:73-76`; Scope
Guard "Do **NOT** remove or alter bonsoir+WS", `FDC-11:506`). FDC-S6 fills that gap.

---

## Background  (grounded in real source)

### The WS stack does TWO jobs (verify before deciding what to retire)

**Job 1 — the LAN CHAT transport.** `LocalWsServer` (`local_ws_server.dart:28`) is *"Local
WebSocket server for direct peer-to-peer messaging on the same WiFi"* (`:14-20`): the sender opens
a WS, sends a JSON chat message with a `nonce`, and the receiver **echoes the nonce back as an
ack** (`_handleInboundMessage` reads `nonce` at `:278`, `_sendLegacyAck(ws, nonce)` at `:294`;
ack timeout 5 s at `:30`). This is the bespoke per-message nonce-ACK the team chose over a direct
libp2p QUIC dial because it gave *"a trivially-reliable ACK ... identical on iOS+Android, no
entitlement"* (proposal §5 L150-155).

**Job 2 — the LAN MEDIA byte server.** The **same** `LocalWsServer` also routes
`HTTP PUT /media/<id>` (`local_ws_server.dart:135-137`, doc'd `:22-24`) into `LocalMediaServer`
(`local_media_server.dart:42`), whose `handleUpload` *"streams body to temp file, verifies
SHA-256"* (`:125-129`). The send side is `LocalMediaSender` (`local_media_sender.dart:17`): its
5-step flow is **`media_offer` via WS → wait `media_offer_accepted` → HTTP PUT to the receiver's
`/media/<id>` → wait `media_uploaded` via WS** (`:12-16`, offer at `:113-115`, PUT at `:162-165`,
uploaded-ack at `:217`). So WS carries the **media signaling** and HTTP carries the **media
bytes** — both on the LAN media server, distinct from the chat transport.

### bonsoir is the DISCOVERY layer — it STAYS on BOTH platforms regardless

`BonsoirDiscoveryService` (`bonsoir_discovery_service.dart:16`) advertises/browses
`_mknoon._tcp` (`:17`) via OS-blessed Bonjour/NSD; `startAdvertising(peerId, wsPort)`
(`local_discovery_service.dart:168-169`) advertises the **WebSocket port**. iOS raw UDP multicast
needs Apple's `com.apple.developer.networking.multicast` entitlement the app does NOT hold; bonsoir
is therefore the discovery on **both** platforms (no libp2p-native `mdns.NewMdnsService` on either —
iOS for the entitlement, Android to avoid a redundant second mechanism) and **feeds the discovered
LAN address into libp2p for the dial** (proposal §5 L133-139; FDC-11 L115-133; Q1 verdict
`FDC-DESIGN-QA-1to1.md:18-37`). **Retiring the WS *transport* does not retire bonsoir** — they are
different layers (discovery vs transport).
A subtlety to fold into any chat-retirement plan: `startAdvertising` advertises the **wsPort**, so
if WS chat is retired, the advertised TXT must switch to (or also carry) the libp2p host port —
otherwise discovery still points at a dead WS port (FDC-S2 risk L260-263; FDC-11 Scope Guard
"do not feed wsPort into the libp2p LAN dial" `:507`).

### FDC-11 device-proves only the libp2p-LAN CHAT dial — never media

FDC-11's device gate **D1** proves a same-WiFi peer becomes a `"direct"` (non-circuit) libp2p
**chat** stream that `DefaultDialRanker` ranks ahead of relay, on **both** platforms (bonsoir-fed
`host.Connect` on both — no libp2p-native mDNS on either) — `FDC-11:333-348`, matrix row
`:363`. It is a **single pass/fail smoke** ("B is discovered ... the resulting send classifies
`"direct"` ... no duplicate delivered"), not a soak. **No FDC plan moves LAN MEDIA bytes onto
libp2p.** The media byte-path is explicitly out of scope: *"the media byte transfer stays on the
existing dedicated channels ... only the small chat envelope rides the new libp2p/mDNS/DCUtR
paths"* (`FDC-00-roadmap.md` SCOPE NOTE; Q6 `FDC-DESIGN-QA-1to1.md:132-149`). So media
bytes today travel **LAN HTTP-PUT (`local_media_sender.dart`) or relay-CDN (`media.go`)**, never
libp2p.

### Transport-label telemetry ALREADY EXISTS to measure which leg won

The soak does not need new measurement primitives — the labels are already live:

- **Go side:** `classifyStreamTransport` (`node.go:123-136`) labels every chat stream `"direct"`
  (non-circuit `RemoteMultiaddr`) vs `"relay"` (circuit addr) — used at `node.go:1411,1619`. A
  libp2p-LAN dial is `"direct"`; a relay circuit is `"relay"`. (It cannot distinguish
  QUIC-direct from TCP-direct — read raw multiaddr for that, FDC-S2 risk L265-267.)
- **Dart side:** the WS LAN path tags its delivered/received messages `'wifi'`/`'local'`
  (`p2p_service_impl.dart:349,3297`), libp2p-direct → `'direct'`, relay → `'relay'`, inbox →
  `'inbox'`; persisted in the `transport` TEXT column (`migrations/012_transport_column.dart:28`,
  free-text `wifi/local/direct/reuse/relay/inbox/NULL`).
- **Aggregation:** `TransportMetrics` (`transport_metrics.dart:87`) canonicalizes raw labels into
  buckets `direct/relay/wifi/inbox` (`:3-8`, `:34-37`, `_canonicalTransport :120-157`) and counts
  them (`recordTransport :161`, `transportMix() :226`); `recordRelayToDirectUpgrade()` (`:219-224`,
  fired from `p2p_service_impl.dart:2978-2979` on `transport:upgraded`) is the upgrade counter.
- **Flow-events:** FDC-13's per-message badge work + the `node:*` flow-events FDC-11's D1 records
  (`node:lan_peer_found` / `EvtPeerIdentificationCompleted` / transport-label, `FDC-11:348,455`)
  give a per-send "which leg won" trace.

**The canonical false-positive caveat applies to the soak too** (proposal §9.1; `FDC-00` Closure caveat): because the receiver **dedupes by `messageId`** (proposal §10 L397-398), a delivered
message tagged `'wifi'` proves the WS leg won *that* send, but a green *delivery* can be satisfied
by the inbox copy even if a live LAN leg never fired. So the soak must read the **transport label
of the winning leg**, not merely "did it deliver." A `'wifi'`/`'local'` win = WS won; a `'direct'`
non-circuit win = libp2p-LAN won; `'relay'`/`'inbox'` = neither LAN leg won.

---

## The three components to decide separately

This is the crux: the WS stack is **not one thing**. Decide each on its own evidence.

| # | Component | Today (file:line) | Retirement gate | Verdict owner |
|---|---|---|---|---|
| **1** | **WS LAN CHAT transport** | `LocalWsServer` WS + nonce-ACK (`local_ws_server.dart:28`, ack `:294`) | **Retire candidate** — gated on FDC-11 chat device-proof (D1) **+ this soak's win-rate/no-net-new-failure bar** | FDC-S6 |
| **2** | **WS/HTTP LAN MEDIA server** | `LocalMediaServer` HTTP PUT (`local_media_server.dart:42`) + `LocalMediaSender` offer/PUT/uploaded (`local_media_sender.dart:17`) | **Covered by FDC-15** (authored, DRAFT — `/mknoon/media-lan/1.0.0` peer-auth stream). Retiring it depends on **FDC-15 device-proof + soak** meeting the 95% / zero-net-new-failure bar, OR an explicit decision to **accept relay-CDN-only LAN media**. FDC-11 carries **zero** media device-proof (chat-only) | FDC-S6 issues the verdict; **FDC-15** executes the media path |
| **3** | **bonsoir DISCOVERY** | `BonsoirDiscoveryService` `_mknoon._tcp` (`bonsoir_discovery_service.dart:16-17`) | **STAYS — never retired.** bonsoir is the discovery on **both** platforms; the libp2p-LAN dial is *fed by* bonsoir on both (iOS entitlement-blocked from raw multicast, Android avoids a redundant second mechanism) | n/a (permanent) |

**Why media must be split out:** FDC-11 proves the **chat** dial is `"direct"`; it proves
**nothing** about moving image/video/voice **bytes** over libp2p. If WS chat is retired but the
WS media server is left in place, that is **fine and safe** (media keeps its dedicated HTTP-PUT
LAN path + relay-CDN fallback). If someone wants to retire the **media** server too, they must
first either (a) author and device-prove a **media-over-libp2p-LAN** plan, or (b) explicitly
accept **relay-CDN-only LAN media** (slower bytes on same-WiFi). Component 2 is therefore **gated behind FDC-15** (now authored, DRAFT — device-proof + soak pending) —
it cannot ride FDC-11.

---

## Method (the soak)

Instrument and collect the **existing** transport-label telemetry on **real device pairs, BOTH
iOS+Android**, over a soak window. No new measurement primitive is needed — read the labels above.

**Population & window.** Real two-device 1:1 pairs on the **same WiFi**, with FDC-11 shipped
(flag `EnableLibp2pLanDial` on per FDC-S2 verdict). Run **N = 14 days** minimum (long enough to
catch intermittent NIC/iOS-throttle behavior the §9 host caveat says is device-only). Cover both
platform *directions*: Android→Android, iOS→iOS, **and the cross pair** Android↔iOS (the
bonsoir-fed dial runs on both platforms and must be exercised both as sender and receiver).

**Instrument points (read, don't add).**
1. **Which leg won a same-WiFi send** — read the persisted `transport` value of the *delivered*
   message (`migrations/012_transport_column.dart:28`) joined to the live leg's label:
   `'direct'` non-circuit (`classifyStreamTransport` `node.go:135`) = **libp2p-LAN won**;
   `'wifi'`/`'local'` (`p2p_service_impl.dart:349,3297`) = **WS LAN won**; `'relay'`/`'inbox'` =
   **neither LAN leg won** (fell to relay/inbox). Bucket via `TransportMetrics.transportMix()`
   (`transport_metrics.dart:226`).
2. **libp2p-LAN win-rate** = `count(direct, non-circuit, same-WiFi) / count(all same-WiFi sends)`
   per platform-direction. (This is the headline retire-chat number.)
3. **LAN-direct delivery success/failure delta vs the bonsoir+WS baseline** — compare the
   same-WiFi *delivery success rate* and *time-to-ack* with the libp2p-LAN lane ON vs a baseline
   window with it OFF (`EnableLibp2pLanDial=false`, WS-only). Net-new failures = sends that
   succeeded on WS-baseline but now fall to relay/inbox or fail with the libp2p lane present.
4. **bonsoir-fed-dial reliability (both platforms)** — per platform, the fraction of same-WiFi sends where the
   bonsoir-discovered LAN addr produced a `"direct"` libp2p stream (vs discovered-but-never-dialed
   → relay). Read the `node:lan_peer_found` → `EvtPeerIdentificationCompleted` → transport-label
   trace (`FDC-11:455`).
5. **Double-delivery rate during the parallel-run window** — count `messageId`-dedup hits where
   *both* a WS-`'wifi'` copy and a libp2p-`'direct'` copy arrived (proposal §10 L397-398; the
   receiver dedup at `handle_incoming_chat_message_use_case.dart` is the safety net,
   `FDC-DESIGN-QA-1to1.md:120-128`).

**How to read which leg won (the false-positive guard).** A delivery alone is NOT evidence the
LAN leg fired — the inbox copy can satisfy delivery via `messageId` dedup (proposal §9.1;
`FDC-00` Closure caveat). The win is the **transport label of the leg that committed first**, captured
per-send via FDC-13's badge data + the `node:*` flow-events. Sims is **N/A** for the win-rate
(iOS sim shares the host mDNS/bonsoir stack → device-only, `e2e_test_mode.dart:2`,
`FDC-11:341-343`) — this is a **manual real-device soak**, exactly like D1.

---

## Decision Criteria (concrete thresholds)

**RETIRE the WS CHAT transport (component 1) ONLY iff ALL hold:**
- **libp2p-LAN chat win-rate ≥ 95%** of same-WiFi 1:1 sends, sustained over **N ≥ 14 days**, on
  **BOTH** platforms (bonsoir-fed-dial on both — no libp2p-native mDNS on either), measured per instrument
  point 2;
- **ZERO net-new LAN-direct delivery failures** vs the bonsoir+WS baseline (instrument point 3 —
  a same-WiFi send that delivered on WS-baseline must not regress to relay/inbox/fail with the
  libp2p lane present);
- **bonsoir-fed dial device-proven on both platforms** at the same bar (instrument point 4 ≥ 95% per platform);
- **FDC-11 D1 GREEN on both platforms** (hard prerequisite — the device-proof landed).

**RETIRE the WS MEDIA server (component 2) ONLY iff:**
- a **libp2p-LAN media path is device-proven** (requires the NEW media-over-libp2p plan, e.g.
  FDC-15, to exist + ship + soak) **AND meets the same 95% / zero-net-new-failure / 14-day bar**
  on both platforms; **OR**
- an explicit product decision **accepts relay-CDN-only LAN media** (no libp2p media path; same-
  WiFi media falls to `media.go` CDN latency) — a deliberate, recorded trade, **not** a default.

**bonsoir DISCOVERY (component 3): KEEP ALWAYS.** Not a candidate. iOS entitlement makes it
permanent; retiring WS transport does not touch it.

**Otherwise KEEP.** If any threshold misses, keep the corresponding WS component.

**Fail-safe (the always-safe default):** **keep BOTH LAN stacks + the ranked race + `messageId`
dedup.** Running both in parallel with the receiver deduping is always correct (proposal §10;
double-delivery is bounded and harmless, only a wasted recipient decrypt). Retirement is a
*code-surface-reduction* optimization, never a correctness requirement — so the bar to remove a
proven-working stack is deliberately high, and "keep" is the safe verdict whenever the data is
thin or mixed.

---

## Expected Output

1. **A per-component verdict:**
   - **retire-chat?** (yes/no, with the measured 14-day win-rate + net-new-failure delta per
     platform);
   - **retire-media?** (yes/no — necessarily *no* unless a media-over-libp2p plan or an explicit
     relay-CDN-only acceptance exists);
   - **keep-bonsoir = always** (stated, not measured).
2. **The list of NEW follow-on plans required to actually execute a retirement** — **named, not
   authored here:**
   - a **media-over-libp2p-LAN plan** (e.g. **FDC-15**) IF media-server retirement is wanted (its
     own device-proof + soak); otherwise the recorded **relay-CDN-only LAN media acceptance**;
   - a **WS-chat-removal plan** (delete `LocalWsServer` chat path, repoint `startAdvertising` off
     `wsPort` to the libp2p host port, drop the nonce-ACK) — **only** once component-1 criteria are
     met.
   These are prerequisites/outputs, authored later via `/tdd-plan` if and when the verdict says
   "retire."

---

## Exit Gate

- The 14-day soak dataset captured (win-rate, net-new-failure delta, bonsoir-fed-dial
  reliability, double-delivery rate) on real iOS+Android pairs.
- A written **per-component verdict** (retire-chat? / retire-media? / keep-bonsoir=always)
  recorded in this doc against the thresholds above, with the soak dataset referenced.
- The named follow-on plans (media-over-libp2p / WS-chat-removal) listed for any "retire" verdict.
- **FDC-11 device-proof is a HARD prerequisite** — this spike cannot close before FDC-11 D1 is
  GREEN on both platforms (and transitively FDC-S2 resolved to Option A/B, not C — if C, FDC-11 is
  shelved and the answer is trivially "KEEP WS, there is no libp2p-LAN lane to retire it for",
  `FDC-S2:139-148`, `FDC-11:7-16`).

---

## Risks / Unknowns

- **iOS background drops multicast — LAN is foreground-only either way.** Both bonsoir and the
  libp2p-LAN dial are foreground LAN mechanisms; background delivery is the inbox's job (proposal §6.4 L273).
  So the soak measures **foreground same-WiFi** win-rate only; retiring WS does not change the
  background story (inbox covers it). Do not over-claim a background win.
- **Retiring the media server without a libp2p media path = LAN media regresses to relay-CDN
  latency.** Component 2 carries real user-visible cost (same-WiFi image/video bytes go to the CDN
  instead of a direct HTTP-PUT). This is the single biggest reason component 2 is **gated behind a
  NEW plan**, not bundled with chat retirement.
- **Double-delivery during the parallel-run window.** While both stacks run, a same-WiFi send may
  deliver twice (WS-`'wifi'` + libp2p-`'direct'`); bounded and harmless via `messageId` dedup
  (proposal §10 L397-398), but it inflates recipient decrypt/ack work (proposal §6.2 L236-239) —
  measured at instrument point 5, and a *reason to eventually retire*, not a blocker.
- **Single-smoke ≠ soak.** FDC-11 D1 is one pass/fail; a green D1 does NOT by itself license
  retirement. The whole point of FDC-S6 is the **sustained** measurement D1 cannot provide
  (`FDC-00` false-positive caveat). Treating D1 as sufficient is the premature-retirement
  failure mode this doc exists to prevent.
- **wsPort advertisement coupling.** `startAdvertising(peerId, wsPort)`
  (`local_discovery_service.dart:169`) advertises the WS port; a WS-chat-removal plan must repoint
  discovery at the libp2p host port or discovery silently points at a dead port (FDC-S2 risk
  L260-263). Folded into the named WS-chat-removal follow-on, not solved here.
- **Cross-version / future go-libp2p bumps** can shift the win-rate (FDC-S2 pins the verdict to
  v0.39.1; `FDC-S2:268-270`) — the soak verdict is pinned to the same version pair and must be
  re-checked on any libp2p bump.
