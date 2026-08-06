# FDC-S6 - libp2p-LAN soak + WS-transport retirement decision  (Spike / Decision)

Status: **closed — retire-chat = N / retire-media = N / keep-bonsoir = always
(2026-08-06).** The availability-bounded campaign did not meet the retirement
evidence bar, so the explicit thin-or-mixed-data fail-safe keeps both transports.
No WS-removal follow-up and no automatic Plan 341 are authorized.

> ## ⓘ Historical implementation receipt (2026-06-27)
> This block records the pre-campaign instrument state. Its old pending-language
> is superseded by the 2026-08-06 verdict and results receipt below. Landed +
> host-green:
> 1. **Precondition** — `'upgraded'→'direct'` label-bucketing lock added to
>    `test/core/debug/transport_metrics_test.dart` (GREEN; mutation-verified RED-able:
>    removing the FDC-13 fold fails exactly that one test).
> 2. **Instrument 2 (private-IP discriminator, net-new)** — `lanPrivateIp` boolean now
>    rides `P2P_LAN_PEER_FOUND_REQUEST` (`p2p_bridge_client.dart`), computed by the new
>    pure `lib/core/local_discovery/lan_address_classifier.dart` (RFC1918/link-local/ULA).
>    Computed **before** emit because `flow_event_emitter` redacts raw multiaddrs out of
>    the log — so the gate can't be parsed post-hoc; it must be a non-sensitive boolean.
> 3. **Instrument 5 (double-delivery counter, net-new)** — `CHAT_MSG_DOUBLE_DELIVERY`
>    `{id, kept, dropped}` at the messageId-dedup drop in
>    `handle_incoming_chat_message_use_case.dart` (kept=stored leg, dropped=incoming leg).
> 4. **Harness** `fdc-s6-measurement/` (README + `fdc_s6_capture.sh` +
>    `fdc_s6_parse.py` with Wilson-LB win-rate / Newcombe failure-delta CI /
>    double-delivery-by-leg-pair / private-IP gate; self-tested on a sample log) +
>    **`FDC-S6-libp2p-lan-soak-RESULTS.md`** scaffold.
> 5. **Version pin** comment beside go-libp2p in `go-mknoon/go.mod` ("re-run soak on bump").
>
> Current-format logs use `CHAT_MSG_RECEIVE_STORED{from,transport}` as the
> authoritative logical outcome; `MSG_RECEIVED_TRANSPORT{from,transport}` is
> retained as the raw arrival-leg census. **Boundary** (vs the Method's framing):
> `node:lan_peer_found` (Go) carries
> only `{peer, addrCount}` — no multiaddr — so there is no Go-side private-IP source; the
> Dart `lanPrivateIp` boolean is authoritative (a Go-side confirm would need a NEW
> pre-computed boolean in `lan_dial.go`, never the raw multiaddr).

> ## ⓘ Review update (2026-06-27 — /tdd-plan verify→refute, 9-agent)
> The decision FRAME holds (3-component split, false-positive transport-label guard, fail-safe =
> keep-both, FDC-11/S2 gating). The WS/media-stack anchors (`LocalWsServer`/`LocalMediaServer`/
> `LocalMediaSender`/migration 012) all re-confirmed at HEAD. Substantive changes folded in below:
> 1. **HEADLINE WIN-RATE WAS BROKEN post-FDC-12/13 (blocker).** `transportMix()`'s `'direct'` bucket
>    folds in `'reuse'` AND `'upgraded'` (DCUtR relay→direct, `transport_metrics.dart:130-136`), and
>    Go `classifyStreamTransport` labels *any* non-circuit conn `"direct"` with **no private-IP check**
>    (`node.go:150-162`). So `count(direct)` over-counts WAN-direct + DCUtR-upgraded as LAN wins. The
>    win-rate must be derived from the per-send `node:lan_peer_found` trace + a private-IP multiaddr
>    gate, EXCLUDING `reuse`/`upgraded` — NOT from the aggregate bucket. ⇒ the doc's "no new
>    measurement primitive needed" is **false**; a private-IP discriminator + a double-delivery
>    counter are net-new.
> 2. **Statistical rigor.** The 14-day window had no sample floor + a bare point estimate + a
>    sequential ON/OFF A/B + an unsatisfiable "ZERO net-new failures". Replaced with a
>    Wilson-LB-≥95% bar over a ≥385-send-per-platform-direction floor, within-pair concurrent
>    attribution (no sequential A/B), and a non-inferiority margin instead of absolute zero.
> 3. **Data collection was undefined.** All three label stores are non-exporting (local SQLCipher
>    column / session-scoped in-memory `transportMix()` / flow-events gated off in release). Added a
>    Collection-mechanism subsection (`--dart-define=FDC_FLOW_LOG=1` + per-device log capture) and a
>    `FDC-S6-libp2p-lan-soak-RESULTS.md` + `fdc-s6-measurement/` harness, mirroring FDC-S1/S4.
> 4. **Currency.** FDC-S2 is now **CLOSED → Option A (750ms)**, so "if C, shelved" is settled;
>    FDC-11 host-impl is **committed** (D1 device-proof still the open gate); `startAdvertising`
>    already carries `{quicPort,tcpPort}` (FDC-11); FDC-15 is reviewed + scope-EXPANDED. The LAN-dial
>    flag is `EnableLibp2pLANDial` (capital LAN) AND the Dart `'p2p_lan_dial'` gate.
> 5. **~25 file:line anchors re-grounded** (telemetry/Go/discovery + every FDC-11/S2 cross-ref
>    drifted under concurrent churn; the WS/media-stack anchors are unchanged). A measurement-instrument
>    PRECONDITION (lock `'upgraded'→'direct'`, currently untested) and a VERDICT-recording block were
>    added.

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
section `:154-177`, iOS entitlement `:165-168`).

The number this spike produces: a **soak dataset** (libp2p-LAN win-rate + LAN-direct delivery
success/failure deltas vs the bonsoir+WS baseline, on real iOS+Android pairs, over a soak window) and a
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
libp2p-LAN **chat** path works (one pass/fail smoke, `FDC-11` D1 `:536-554`); FDC-S2 only decided
**protocol feasibility** (now CLOSED → Option A, `FDC-S2` Options `:170-208`, verdict `:3-9`); and
FDC-11 **explicitly keeps bonsoir+WS** ("bonsoir+WS stays as the proven foreground/iOS fast path",
`FDC-11:108`; Scope Guard "Do **NOT** remove the WS byte path … the `wsPort` advert STAYS",
`FDC-11:762`). FDC-S6 fills that gap.

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

`BonsoirDiscoveryService` (`bonsoir_discovery_service.dart:17`) advertises/browses
`_mknoon._tcp` (`:18`) via OS-blessed Bonjour/NSD; `startAdvertising(peerId, wsPort, {quicPort,
tcpPort})` (`local_discovery_service.dart:182-187`) advertises the **WebSocket port** — and, since
FDC-11, **additively the libp2p QUIC/TCP ports** in the same TXT (`bonsoir_discovery_service.dart:
111-112`). iOS raw UDP multicast
needs Apple's `com.apple.developer.networking.multicast` entitlement the app does NOT hold; bonsoir
is therefore the discovery on **both** platforms (no libp2p-native `mdns.NewMdnsService` on either —
iOS for the entitlement, Android to avoid a redundant second mechanism) and **feeds the discovered
LAN address into libp2p for the dial** (proposal §5 L133-139; FDC-11 `:154-177`; Q1 verdict
`FDC-DESIGN-QA-1to1.md:18-37`). **Retiring the WS *transport* does not retire bonsoir** — they are
different layers (discovery vs transport).
A subtlety to fold into any chat-retirement plan: `startAdvertising` still advertises the **wsPort**
(alongside the libp2p QUIC/TCP ports FDC-11 already added). The "**also carry** the libp2p port"
half is therefore **already done** — the remaining WS-chat-removal work is only to **DROP the
now-dead wsPort advert** (and stop the WS server), not to add the libp2p ports; otherwise discovery
keeps pointing at a dead WS port (FDC-S2 risk `:322-324`; FDC-11 Scope Guard
"do not feed wsPort into the libp2p LAN dial" `:766`).

### FDC-11 device-proves only the libp2p-LAN CHAT dial — never media

FDC-11's device gate **D1** proves a same-WiFi peer becomes a `"direct"` (non-circuit) libp2p
**chat** stream that `DefaultDialRanker` ranks ahead of relay, on **both** platforms (bonsoir-fed
`host.Connect` on both — no libp2p-native mDNS on either) — `FDC-11:536-554`, matrix row
`:573`. It is a **single pass/fail smoke** ("B is discovered ... the resulting send classifies
`"direct"` ... no duplicate delivered"), not a soak. **No FDC plan moves LAN MEDIA bytes onto
libp2p.** The media byte-path is explicitly out of scope: *"the media byte transfer stays on the
existing dedicated channels ... only the small chat envelope rides the new libp2p/mDNS/DCUtR
paths"* (`FDC-00-roadmap.md` SCOPE NOTE `:462-468`; Q6 `FDC-DESIGN-QA-1to1.md:132-149`). So media
bytes today travel **LAN HTTP-PUT (`local_media_sender.dart`) or relay-CDN (`media.go:327`
`MediaUpload`/`:420` `MediaDownload`)**, never libp2p.

### Transport-label telemetry ALREADY EXISTS to measure which leg won

The soak reuses the live transport labels — but, post-FDC-12/13, the labels alone are **not enough**
to isolate a genuine LAN win (see the ⚠ caveat below):

- **Go side:** `classifyStreamTransport` (`node.go:150-162`) labels every chat stream `"direct"`
  (non-circuit conn) vs `"relay"` (circuit addr on EITHER local or remote multiaddr) — used at
  `node.go:1520,1728`, non-circuit fall-through at `:162`. A relay circuit is `"relay"`; **anything
  else is `"direct"`** — including a WAN/public-IP direct dial and a DCUtR-upgraded (FDC-12)
  relay→direct conn, **not only a LAN dial**. There is **no private-IP/RFC1918 check** in the
  function (the nearest helper `isNonRoutableAddr` `node.go:180` covers only loopback/link-local and
  isn't called here). It also cannot distinguish QUIC-direct from TCP-direct — read the raw multiaddr
  for both distinctions (FDC-S2 risk `:327`).
- **Dart side:** the WS LAN path tags its delivered/received messages `'wifi'`
  (`p2p_service_impl.dart:400/:410/:421/:430` received, `:3743/:3751` delivered); the inbound
  libp2p/relay label comes from `msg.transport` (Go `classifyStreamTransport`) recorded at `:369`
  → `'direct'`/`'relay'`; inbox → `'inbox'`. (`'local'` is **not** a delivered tag — it is a
  learned-reachability label that canonicalizes → `'wifi'`.) Persisted in the `transport` TEXT column
  (`migrations/012_transport_column.dart:28`, free-text `wifi/local/direct/reuse/relay/inbox/NULL`).
- **Aggregation:** `TransportMetrics` (`transport_metrics.dart:87`) canonicalizes raw labels into
  **five** buckets `direct/relay/wifi/inbox/unknown` (`kTransportBuckets :4-10`; `_canonicalTransport
  :123-145`) and counts them (`recordTransport :168`, `transportMix() :233`);
  `recordRelayToDirectUpgrade()` (`:227`, fired from `p2p_service_impl.dart:3389-3391` on
  `transport:upgraded`) is the upgrade counter.
- **Flow-events:** FDC-13's per-message badge work + the `node:*` flow-events FDC-11's D1 records
  (`node:lan_peer_found` / `EvtPeerIdentificationCompleted` / transport-label, `FDC-11:553`) give a
  per-send "which leg won" trace — and are the **only** source that isolates a bonsoir-fed LAN dial
  from a WAN/DCUtR `"direct"` (see caveat). NOTE: flow-events emit only when `flowEventLoggingEnabled`
  is true, which defaults to `kDebugMode` and is **off in profile/TestFlight builds** — the soak
  binary MUST be built `--dart-define=FDC_FLOW_LOG=1` (see "Collection mechanism" below).

> ⚠ **The `'direct'` bucket is NOT "libp2p-LAN-direct".** `_canonicalTransport` folds **`'reuse'`**
> (`:128-129`) AND **`'upgraded'`** (`:130-136`, FDC-13's DCUtR relay→direct fold) into `'direct'`,
> and Go labels WAN-direct/DCUtR-direct identically to a LAN dial. So `count(direct)` via
> `transportMix()` **over-counts** the libp2p-LAN win. The headline win-rate must instead be derived
> from the per-send `node:lan_peer_found → EvtPeerIdentificationCompleted → transport` trace (gated
> on a **private-IP** `RemoteMultiaddr`), and must **exclude** raw `reuse`/`upgraded` sends and any
> send that fired `transport:upgraded`. This is a **net-new discriminator** — contradicting the "no
> new measurement primitive needed" claim. (`transportMix()` is also session-scoped + resets each
> launch + read only by the Settings debug card — it cannot accumulate the soak dataset.)

**The canonical false-positive caveat applies to the soak too** (proposal §9.1; `FDC-00` Closure caveat): because the receiver **dedupes by `messageId`** (proposal §10 L397-398), a delivered
message tagged `'wifi'` proves the WS leg won *that* send, but a green *delivery* can be satisfied
by the inbox copy even if a live LAN leg never fired. So the soak must read the **transport label
of the winning leg**, not merely "did it deliver." A `'wifi'`/`'local'` win = WS won; a
**bonsoir-fed, private-IP, non-circuit `'direct'` win** = libp2p-LAN won (a bare `'direct'` alone is
ambiguous — it can be WAN/DCUtR-direct, ⚠ above); `'relay'`/`'inbox'`/`'reuse'`/`'upgraded'` =
neither LAN leg won.

---

## The three components to decide separately

This is the crux: the WS stack is **not one thing**. Decide each on its own evidence.

| # | Component | Today (file:line) | Retirement gate | Verdict owner |
|---|---|---|---|---|
| **1** | **WS LAN CHAT transport** | `LocalWsServer` WS + nonce-ACK (`local_ws_server.dart:28`, ack `:294`) | **Retire candidate** — gated on FDC-11 chat device-proof (D1) **+ this soak's win-rate/no-net-new-failure bar** | FDC-S6 |
| **2** | **WS/HTTP LAN MEDIA server** | `LocalMediaServer` HTTP PUT (`local_media_server.dart:42`) + `LocalMediaSender` offer/PUT/uploaded (`local_media_sender.dart:17`) | **Covered by FDC-15** (reviewed + scope-EXPANDED 2026-06-27, still pre-device-proof — `/mknoon/media-lan/1.0.0` peer-auth stream; the review added a **receive→render leg + Dart non-circuit-direct predicate + 5-layer bridge wiring**, none built yet). Retiring it depends on **FDC-15 device-proof + soak** meeting the same bar (below), OR an explicit decision to **accept relay-CDN-only LAN media**. FDC-11 carries **zero** media device-proof (chat-only) | FDC-S6 issues the verdict; **FDC-15** executes the media path |
| **3** | **bonsoir DISCOVERY** | `BonsoirDiscoveryService` `_mknoon._tcp` (`bonsoir_discovery_service.dart:17-18`) | **STAYS — never retired.** bonsoir is the discovery on **both** platforms; the libp2p-LAN dial is *fed by* bonsoir on both (iOS entitlement-blocked from raw multicast, Android avoids a redundant second mechanism) | n/a (permanent) |

**Why media must be split out:** FDC-11 proves the **chat** dial is `"direct"`; it proves
**nothing** about moving image/video/voice **bytes** over libp2p. If WS chat is retired but the
WS media server is left in place, that is **fine and safe** (media keeps its dedicated HTTP-PUT
LAN path + relay-CDN fallback). If someone wants to retire the **media** server too, they must
first either (a) author and device-prove a **media-over-libp2p-LAN** plan, or (b) explicitly
accept **relay-CDN-only LAN media** (slower bytes on same-WiFi). Component 2 is therefore **gated behind FDC-15** (reviewed + scope-EXPANDED 2026-06-27 — receive→render leg + Dart predicate + 5-layer bridge wiring now required; device-proof + soak still pending) —
it cannot ride FDC-11.

---

## Method (the soak)

Collect transport-label telemetry only on eligible targets from the live,
availability-bounded matrix. A future retirement attempt must explicitly state
whether it needs Android-only evidence or an Android/iOS parity claim.

**Population & window.** Resolve the matrix at execution time. For a non-iOS-
specific two-peer leg, default to one USB Android plus one available Android
emulator, pinned by explicit IDs; if they cannot share the required L2/mDNS LAN,
record that leg `N/A (target topology unavailable by project policy)` rather
than substituting an iPhone. Use an iPhone only for a separately justified iOS
boundary or parity claim. A LAN dial requires BOTH the Go
flag **`EnableLibp2pLANDial`** (capital LAN; `feature_flags.go:44`, default false `:83`) AND the
Dart **`'p2p_lan_dial'`** runtime gate (`p2p_service_impl.dart:888-902`) open. Run until the
minimum sample floor (Decision Criteria) is cleared — long enough to catch intermittent
NIC behavior the §9 host caveat says is device-only. Cover every eligible
direction required by the explicit claim; unavailable hardware/version legs
are N/A, not blockers or failed gates.

**Instrument points.**
1. **Which leg won a same-WiFi send** — use
   `CHAT_MSG_RECEIVE_STORED{from,transport}` as the one logical outcome, joined
   within the same trial to `node:lan_peer_found` /
   `P2P_LAN_PEER_FOUND_REQUEST`. Keep `MSG_RECEIVED_TRANSPORT` only as the raw
   parallel-arrival census. A **bonsoir-fed,
   private-IP, non-circuit `'direct'` stream** = **libp2p-LAN won**; `'wifi'`
   (`p2p_service_impl.dart:400/:3743`) = **WS LAN won**; `'relay'`/`'inbox'` = **neither LAN leg
   won**. Do **NOT** read the leg from `TransportMetrics.transportMix()` (`transport_metrics.dart:233`)
   — its `'direct'` bucket folds in `reuse`/`upgraded` and is session-scoped (⚠ above).
2. **libp2p-LAN win-rate** = `count(bonsoir-fed private-IP non-circuit 'direct' wins, same-WiFi,
   EXCLUDING reuse/upgraded/transport:upgraded sends) / count(all same-WiFi sends)`, per
   platform-direction. (Headline retire-chat number — see the CI bar in Decision Criteria; a bare
   `count(direct)` over-counts WAN/DCUtR-direct.)
3. **LAN-direct delivery success/failure delta — WITHIN-pair, not a sequential A/B.** A sequential
   ON-window-then-flag-OFF-window comparison is **confounded** by network/app-version/device/
   location/time-of-day. Prefer (a) **concurrent parallel-run attribution** — keep BOTH lanes live
   (already required by point 5) and attribute per-send on the winning-leg label, so each send is its
   own control; a net-new failure = a send whose WS-`'wifi'` leg would have committed but that
   instead fell to relay/inbox/failed with the libp2p lane present; or (b) **per-pair interleaved**
   randomization of the runtime flag on the SAME pairs in the SAME window/location; (c) only if
   neither is feasible, a sequential A/B **with a recorded confound caveat** and ON/OFF windows
   matched on app-version, device set, location, time-of-day.
4. **bonsoir-fed-dial reliability (both platforms)** — per platform, the fraction of same-WiFi sends
   where the bonsoir-discovered LAN addr produced a `"direct"` libp2p stream (vs discovered-but-
   never-dialed → relay). Read the `node:lan_peer_found` → `EvtPeerIdentificationCompleted` →
   transport-label trace (`FDC-11:553`).
5. **Double-delivery rate during the parallel-run window** — count `messageId`-dedup collisions,
   **keyed by the `(first-leg, second-leg)` transport-label pair** (under FDC-12 the co-arrival can
   be relay+direct or inbox+direct, not only WS-`'wifi'`+libp2p-`'direct'`). The
   counter now exists as `CHAT_MSG_DOUBLE_DELIVERY{kept,dropped}` at the
   receiver dedup return. Receiver dedup remains the safety net
   (`FDC-DESIGN-QA-1to1.md:120-128`).

**Collection mechanism (net-new — the labels exist but do not export).** All three label stores are
non-exporting: the `transport` column lives only in each device's local SQLCipher `messages` DB; the
`node:*`/FDC-13 flow-events emit only when `flowEventLoggingEnabled` (defaults `kDebugMode`, off in
profile/TestFlight); `transportMix()` is session-scoped + display-only. So:
- Build the soak binary (profile/TestFlight) with **`--dart-define=FDC_FLOW_LOG=1`** (forces
  `flowEventLoggingEnabled=true` + synchronous print so bursty `node:*` lines aren't dropped;
  `main.dart:360-369`) — observation-only, inert in a normal build (the FDC-S1/S4 measurement-flag
  precedent).
- Capture per device via `adb logcat -v time` (Android) / `idevicesyslog` (iOS), as
  `fdc-s1-measurement/scripts/fdc_{android,ios}_trials.sh` do.
- Run it as an **automated, attended multi-session N-trial campaign** (per-trial
  log files). The harness owns setup, permissions, navigation, sends, and
  assertions; do not require user taps or recursively repair an iPhone harness
  inside the campaign. The trials supply the sample floor
  (duration floor removed by decision 2026-06-29 — no 14-day soak; the ≥385-sample Wilson-LB
  criterion is the sole gate). There is **no durable on-device export** today (the `transport`
  column is queryable but un-exported; `transportMix()` is display-only).
- **Per-platform-direction attribution is NOT in the persisted column** (it has no peer/platform/
  same-WiFi dimension) — pair the ephemeral flow-event trace to the known two-device platform pair
  per trial. The **baseline arm must log the SAME trace**, else the delta has no comparable baseline.
- Record results in a **`FDC-S6-libp2p-lan-soak-RESULTS.md`** + a **`fdc-s6-measurement/`** harness
  (`scripts/` adapted from `fdc-s1-measurement/scripts/`, keyed on a win-leg `DONE_EVENT` =
  `node:lan_peer_found`/transport-label line; `fdc_s6_parse.py` from `fdc_parse.py`; plus `logs/`,
  `results/`), mirroring FDC-S1/S4.

**How to read which leg won (the false-positive guard).** A delivery alone is NOT evidence the
LAN leg fired — the inbox copy can satisfy delivery via `messageId` dedup (proposal §9.1;
`FDC-00` Closure caveat). The win is the **transport label of the leg that committed first**, captured
per-send via FDC-13's badge data + the `node:*` flow-events. Sims is **N/A** for the win-rate
(iOS sim shares the host mDNS/bonsoir stack → device-only, `e2e_test_mode.dart:2` disable-flag;
mDNS-sharing rationale `FDC-11:545,552`) — this is a **manual real-device soak**, exactly like D1.

---

## Decision Criteria (concrete thresholds)

**RETIRE the WS CHAT transport (component 1) ONLY iff ALL hold:**
- **libp2p-LAN chat win-rate clears a confidence bound, not a point estimate:** the **Wilson score
  95% lower bound** of instrument-point-2's win-rate must be **≥ 95%**, computed **per
  platform-direction** (Android→Android, iOS→iOS, Android↔iOS). (A
  bare ≥95% point estimate is NOT sufficient — 95% over 20 sends has a Wilson LB ≈ 75%.)
- **Minimum sample floor: ≥ 385 successfully-attempted same-WiFi sends per platform-direction**
  (≈ ±5 pp at 95% conf; clearing a Wilson LB ≥ 95% at this n needs an observed rate ≈ ≥ 97%). This
  **≥385-sample floor is the sole gate** — this
  operationalizes the qualitative "keep when data is thin" fail-safe below into a hard rule.
  *(Duration floor removed by decision 2026-06-29 — no 14-day soak; the ≥385-sample Wilson-LB
  criterion is the sole gate. The verdict may be issued once the sample floor + statistical bars
  are met, regardless of calendar span.)*
- **No statistically-significant increase in LAN-direct delivery failure rate** vs the bonsoir+WS
  baseline (instrument point 3): the **upper 95% CI (Newcombe/Wilson) of
  [failureRate(libp2p-ON) − failureRate(baseline)] ≤ +1.0 pp** (a non-inferiority margin), per
  platform-direction. Every observed failure is still root-caused; the **gate is the CI on the
  difference, not an absolute zero count** — a single flaky-NIC/iOS-throttle drop must not veto.
- **bonsoir-fed dial device-proven on both platforms** at the same Wilson-LB-≥95% + ≥385-send bar
  (instrument point 4).
- **FDC-11 D1 GREEN on both platforms** (hard prerequisite — the device-proof landed).

These are **retirement-authorization** thresholds. They are not a requirement to
keep a proven path: a documented `retire = N` decision may close when the live
matrix is availability-bounded or the data is thin/mixed, provided the results
record the attempted matrix, exclude invalid setup runs, and make no successful
soak claim. This is the operational meaning of the fail-safe below.

**RETIRE the WS MEDIA server (component 2) ONLY iff:**
- a **libp2p-LAN media path is device-proven** (requires the NEW media-over-libp2p plan, e.g.
  FDC-15, to exist + ship + soak) **AND meets the same Wilson-LB-≥95% win-rate + ≥385-send sample
  floor + non-inferiority (≤ +1.0 pp) failure-delta bar** on both platforms; **OR**
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

## Soak preconditions (lock the instrument before trusting the data)

The entire dataset rests on the transport labels bucketing correctly, so lock the instrument first:

- **`test/core/debug/transport_metrics_test.dart` MUST stay GREEN** before and throughout the soak —
  it is the label-bucketing sentinel (it already locks `local→wifi`, `reuse→direct`, and
  `direct/relay/inbox` stability, `:21-70`).
- **ADD one net-new RED/GREEN case locking `'upgraded'→'direct'`** — that fold
  (`transport_metrics.dart:130-136`, FDC-13) is **currently untested** (zero `upgraded` hits in the
  test file), so a refactor could silently re-bucket the LAN-win signal and corrupt the dataset.
  This is the one place this decision spike legitimately needs a RED/GREEN test, and it is a hard
  precondition, not the soak itself.
  - Gate: `flutter test test/core/debug/transport_metrics_test.dart` (host floor, AUTO-glob under
    `test/core/**`).
- **Build flag:** `--dart-define=FDC_FLOW_LOG=1` set on every soak + baseline binary (else the
  win-leg trace is silent on profile/TestFlight — see Collection mechanism).

---

## Expected Output

1. **A per-component verdict:**
   - **retire-chat?** (yes/no, with the measured win-rate + net-new-failure delta per
     platform);
   - **retire-media?** (yes/no — necessarily *no* unless a media-over-libp2p plan or an explicit
     relay-CDN-only acceptance exists);
   - **keep-bonsoir = always** (stated, not measured).
2. **The list of NEW follow-on plans required to actually execute a retirement** — **named, not
   authored here:**
   - a **media-over-libp2p-LAN plan** (e.g. **FDC-15**) IF media-server retirement is wanted (its
     own device-proof + soak); otherwise the recorded **relay-CDN-only LAN media acceptance**;
   - a **WS-chat-removal plan** (delete `LocalWsServer` chat path, **drop the now-dead `wsPort` TXT
     advert** — the libp2p QUIC/TCP ports are already advertised since FDC-11, so no port needs
     *adding* — and drop the nonce-ACK) — **only** once component-1 criteria are met.
   These are prerequisites/outputs, authored later via `/tdd-plan` if and when the verdict says
   "retire."

---

## VERDICT (RECORDED 2026-08-06)

> **Status:** closed — retire-chat = **N** / retire-media = **N** /
> keep-bonsoir = **always**.
> **Dataset:** `FDC-S6-libp2p-lan-soak-RESULTS.md` (parser and admitted
> legacy logs under `fdc-s6-measurement/`).
> **Version context:** go-libp2p `v0.39.1` / quic-go `v0.49.0`.
>
> | metric | A→A | i→i | A→i legacy | i→A legacy |
> |---|---|---|---|---|
> | logical sends | N/A: Android targets do not share L2 | not admitted: harness boundary | 107 | 97 |
> | clean-LAN Wilson 95% LB | — | — | 41.1% | 0.0% |
> | matched-baseline Newcombe upper CI | N/A | N/A | N/A: no baseline | N/A: no baseline |
> | bonsoir-fed reliability | — | — | 54/54; LB 93.4% | 0/0; N/A |
> | double delivery | — | — | 1/107 = 0.9% (`direct+inbox`) | 10/97 = 10.3% (`wifi+direct` 9, `direct+wifi` 1) |
>
> **Verdict:** retire-chat = **N** because no required direction reached
> n ≥ 385, A→A is N/A under the live topology, and no matched baseline exists;
> the legacy cross-pair data is explicitly underpowered. Retire-media = **N**
> because there is no retirement-grade matched media soak or relay-CDN-only
> acceptance. Keep-bonsoir = **always**.
> **Follow-on plans:** none. In particular, do not create a WS-chat-removal plan
> or infer Plan 341. Connection single-flight, relay classification, cross-FFI
> cancellation, DCUtR, and timing retuning remain telemetry-gated separately.

---

## Exit Gate

- **Retire branch:** requires the full ≥385-per-direction Wilson/Newcombe
  dataset, matched baseline, and all FDC-11/device prerequisites above.
- **Keep branch:** may close by fail-safe when the results receipt records the
  availability-bounded matrix, excludes invalid setup runs, names every missed
  retirement threshold, and makes no successful-soak claim. **Satisfied
  2026-08-06.**
- The observation precondition and corrected parser tests are green; the
  admitted legacy pilot summaries are reproducible from checked-in logs.
- The per-component verdict is filled above. No follow-on retirement plan is
  named because neither retirement verdict is positive.

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
- **wsPort advertisement coupling (already half-solved).** `startAdvertising(peerId, wsPort,
  {quicPort, tcpPort})` (`local_discovery_service.dart:182-187`) advertises the WS port **and** the
  libp2p QUIC/TCP ports (FDC-11). So the WS-chat-removal follow-on must **drop the now-dead wsPort
  advert** (not *add* the libp2p ports — already there), else discovery silently points at a dead
  port (FDC-S2 risk `:322-324`). Folded into the named follow-on, not solved here.
- **Cross-version / future go-libp2p bumps** can shift the win-rate (FDC-S2 pins the verdict to
  go-libp2p `v0.39.1` / quic-go `v0.49.0`; `FDC-S2:330-332`) — the soak verdict is pinned to the same
  pair and must be re-checked on any bump. Because "re-check on bump" is otherwise an untested
  assumption, make the trigger concrete: embed the exact version pair in the **VERDICT block** above,
  add a `// FDC-S6 soak verdict pinned to v0.39.1 — re-run soak on bump` comment beside go-libp2p in
  `go-mknoon/go.mod`, and a line item in any libp2p-bump PR checklist pointing back to FDC-S6/FDC-S2.
