# Fast-Direct-Connection — Design Q&A (1:1 messaging)

Seven design questions, each **verified against the live codebase + the FDC plan epic** (not from
memory). Scope: **1:1 messaging only.** Authored 2026-06-26.

| # | Question | Verdict |
|---|---|---|
| 1 | iOS/Android mDNS (UDP multicast) limits | ⚠️ **Contradiction → fixed** in FDC-11 |
| 2 | What's measured to pick the fastest route | ✅ **Covered** |
| 3 | Delete inbox copy after the receiver has it | ✅ **Covered** |
| 4 | Transport badge shows the road taken | ⚠️ **Partial** → FDC-13 |
| 5 | Late inbox duplicate corrupting the timeline | ✅ **Covered** |
| 6 | Media (images/video/voice/GIFs) considered | ⚠️ **Partial** (routing yes, byte-path out of scope) |
| 7 | The "online" green dot | ⚠️ **Gap** → FDC-14 + anti-flap notes in FDC-05/06/07 |

---

## Q1 — Did we consider iOS/Android mDNS (UDP multicast) limits? ⚠️ Contradiction → fixed

**Answer.** The honest design (which the proposal §5 and spike FDC-S2 already state): **`bonsoir`
(Bonjour on iOS / NSD on Android) discovers same-WiFi peers UNIFORMLY on both platforms and feeds the
discovered LAN address into libp2p for the direct *dial*.** go-libp2p's own `mdns.NewMdnsService` (raw
UDP multicast) is **not** used on either platform — on Android it would be a redundant second discovery
mechanism (bonsoir already handles it), and on iOS the app lacks Apple's
`com.apple.developer.networking.multicast` entitlement so that lane discovers nothing anyway. So both
the *discovery source* (bonsoir) and the *dial* (libp2p over the discovered LAN address) are the same
everywhere — no platform-split.

**Today.** Discovery is `bonsoir`, not libp2p mDNS. `native-p2p-go-libp2p.md` §"Why not go-libp2p's
built-in mDNS?" documents the entitlement reason. `ios/Runner/Info.plist:42-50` ships
`NSBonjourServices _mknoon._tcp` + `NSLocalNetworkUsageDescription` and **no** multicast entitlement;
Android has `CHANGE_WIFI_MULTICAST_STATE` (`AndroidManifest.xml:2`). The Go host registers no mDNS
today (`node.go:338-347`).

**Fix applied.** FDC-11 now carries an explicit **iOS/Android discovery section** with a **uniform
scope** (both platforms: bonsoir discovers → feed the `AddrInfo` into `host.Connect` for the direct
dial; no libp2p-native `mdns.NewMdnsService` on either), and a corrected D1 device gate (isolate the
libp2p-direct leg by toggling `EnableLibp2pLanDial`, not `DISABLE_LOCAL_DISCOVERY`, since bonsoir now
feeds both LAN legs). The earlier verbal "add libp2p mDNS / Android-only" framing is corrected to
bonsoir-on-both.

---

## Q2 — When finding the fastest route, what is fetched/measured? Built-in or hand-built? ✅ Covered

**Answer.** **Nothing is measured** (no latency probing). The app takes **whichever road completes
first** ("Happy Eyeballs"), with the fast ones started first and the relay handicapped. This happens at
**two layers — answer = both:**
- **(a) Our Dart code (hand-built):** `send_chat_message_use_case` races the big legs (LAN-WebSocket vs
  libp2p-direct vs relay) and commits on the **first leg whose send is ACKed**, tie-broken by a static
  rank (`local > direct > relay`) plus a remembered "last-good-road" head-start. No RTT probe.
- **(b) go-libp2p (built-in):** inside a single dial, `DefaultDialRanker` races the individual
  *addresses* — private/LAN ~30 ms, public ~250 ms, relay delayed by `RelayDelay` ~500 ms — first
  address to finish its handshake wins. Also no latency probing.

`classifyStreamTransport` (`node.go:123-136`) only **labels** the resulting stream `direct`/`relay`
after the fact; it ranks nothing.

**Today.** Dart race `send_chat_message_use_case.dart:662-703`; winner `Completer` `:723-748`; static
rank `:71-77`; sticky head-start. go-libp2p's `DefaultDialRanker` is the **implicit swarm default**
(`node.go:361` configures no `swarm.WithDialRanker`). **FDC-02** adds the Dart leg-granularity analog
of `DefaultDialRanker` (the staggered, relay-penalized leg race).

**Nuance.** The Dart layer is **first-to-ACK** (delivery confirmed), not literally first-to-connect;
pure first-to-connect Happy-Eyeballs only happens at the Go *address* layer.

---

## Q3 — Do we delete the inbox copy after the receiver has it? ✅ Covered (within ~30s)

**Answer.** Yes. The recipient **reads then acks**: `retrieve_pending` (read, no delete) →
`ack(entryIds)` → relay **deletes** those entries. The 7-day retention is only a backstop. A
**UI-duplicate is still acked** (ack happens *before* the message-level `messageId` dedup), so the
relay frees the entry even for a copy already delivered live. A **foreground** user re-drains **every
30 s** (health-check), so duplicates of live-delivered messages are reclaimed within ~30 s. FDC-03's
more-frequent concurrent copies ride the **same** retrieve→ack→delete lifecycle (FDC-03 leaves the
relay/ack model untouched). **No accumulation.**

**Today.** Relay `inbox.go`: `retrieve_pending :909-913` (non-destructive) + `ack :915-929`
(delete-by-stable-entryId); both backends prune >7 d (`backend_memory.go:300-315`,
`backend_redis.go:439`). Client: `retrieve_pending` → stage → `callP2PInboxAck` (deletes) → **then**
replay + `messageId` dedup (`p2p_service_impl.dart:1620-1652`). Health-check `Timer.periodic(30s)` →
`_drainOfflineInbox` (`:247, :3204-3206`). Sender double-store is bounded by relay store-dedup
(`inbox.go:840-847`).

**Minor pre-existing edges (harmless, not FDC-introduced):** a move-account skip and a crashed-mid-drain
entry linger to the 7-day TTL. Optional hardening tracked under FDC-10.

---

## Q4 — Does the transport badge show the road taken? ⚠️ Partial → FDC-13

**Answer.** The per-message badge you described **already exists** for **wifi / direct / relay /
inbox** — distinct icons + accessibility labels, on **both sent and received** messages (plan-155
`transportStatusGlyph`, `letter_card.dart`), persisted in a `transport` column. The FDC design
**reuses** these. **Gap:** the *new* **relay→direct upgrade** has **no badge** — an upgraded message
renders as plain `direct` (`_inferTransportForPeer` collapses it), and the upgrade is only counted in a
**debug** diagnostics card.

**Today.** `letter_card.dart _transportIcon :1037-1053` (wifi/local=`wifi`, direct/reuse=`device_hub`,
relay=`cell_tower`, inbox=`inbox`); a11y `message_*_via_* :1165-1195`; `transport` TEXT column (DB
`012`). The upgrade event exists (`p2p_service_impl.dart:2978` `transport:upgraded` →
`recordRelayToDirectUpgrade`) but `_inferTransportForPeer :2991-3012` returns `direct` for it.

**Fix.** **FDC-13** (authored) adds an `'upgraded'` transport value + a distinct `Icons.upgrade` glyph +
`message_*_via_upgraded` a11y in the conversation `letter_card.dart`. **(Correction from FDC-13's
grounding: there is no feed `message_bubble` transport twin — the feed Letters bubble renders no
transport glyph, so `letter_card` is the only renderer.)** **No DB migration** (the `transport` column
is already TEXT). The **incoming** upgraded render is host-testable now via a **synthetic
`transport:upgraded` event**; the **outgoing** badge from real data + the upgrade actually firing are
gated on **FDC-12** (DCUtR).

---

## Q5 — Can a late inbox duplicate corrupt the timeline / received-at order? ✅ Covered (no)

**Answer.** No. A foreground user drains every ~30 s, so the duplicate **is** fetched — but it
**never touches the timeline**. Dedupe checks the message id, sees the row already exists, and returns
**"duplicate" without re-saving** — no new row, no new timestamp. The conversation is ordered by the
**sender's embedded compose-time timestamp**, *not* the receipt/fetch time, so a late copy **cannot
reorder or re-date** anything. The only cost is a wasted fetch+ack+decrypt (the "recipient cost"
already noted in proposal §6.2).

**Today.** `handle_incoming_chat_message_use_case.dart:303` (`getMessage(payload.id)`); duplicate
branch `:312-344` (re-mint receipt, **no `saveMessage`**); list order
`messages_db_helpers.dart:170` (`orderBy 'timestamp ASC'`); embedded sender timestamp
`message_payload.dart:204`. FDC-03 names receiver `messageId` dedup as the explicit backstop
(FDC-03-06 asserts exactly one copy after drain).

**Caveat (orthogonal, unchanged by FDC):** timeline order uses the *sender's* clock, so cross-device
clock skew can mis-order — but that is independent of this duplicate question.

---

## Q6 — Is media considered, or only text? ⚠️ Partial (routing yes; byte-path out of scope)

**Answer.** Media **is** considered — but as a **routing constraint**, not a re-planned byte-path. The
proposal forbids media over the **live relay** (capped 2 min / 128 KB), and **FDC-02** enforces this
with a real gate `_liveRelayEligible(hasAttachments, payloadBytes)` + RED tests (TC-02-03/04/12) →
media routes **direct-or-inbox**, never live-relay. **But** the actual media **byte** transfer stays on
the **existing dedicated channels** and is **out of scope** for the new roads — only the small chat
*envelope* (the `MediaAttachment` reference) rides the new libp2p/mDNS/DCUtR paths.

**Today.** Media is encrypted once into an `EncryptedMediaArtifact`; bytes travel two dedicated
channels — **LAN HTTP-PUT** (`local_media_sender.dart` → peer media server) and **relay-CDN**
(`media.go` / `uploadMedia`); the recipient renders via `resolveStoredPathSync`. The chat message
carries only the reference.

**Fix.** **Scope note added to FDC-00:** the legacy media dual-channel stays the byte path; new roads
carry only the envelope. **Preservation floor:** re-run
`integration_test/media_stable_id_smoke_test.dart` (already in `TRANSPORT_TESTS`) as a Phase-0 gate
after FDC-02/04 to prove media bytes still deliver.

---

## Q7 — Is the "online" green dot considered? ⚠️ Gap → FDC-14 + anti-flap notes

**Answer.** The dot is real and **already encodes exactly** the distinction you described: it's driven
entirely by *your own* node state — **grey = offline**, **amber = connecting**, **green "Online" =
send + inbox ready**, **green dotted = also holding a relay reservation**. But **no plan touched it**,
yet the design **changes when those states flip** (FDC-05/06/07 alter resume/pause/cold-start timing),
so the dot's transitions shift as a side effect and could flap. The design also adds a **new** concept
the dot doesn't express: **"reachable for a direct connection"** (LAN/DCUtR).

**Today.** `ConnectionStatusIndicator` (`connection_status_indicator.dart:75/:97/:101`) →
`NodeState.badgeReadinessState` (`node_state.dart:144-153`: `usabilityReady` = `isStarted &&
sendCapabilityReady && inboxCapabilityReady`; `relayReady` = `relayState==online ||
circuitAddresses non-empty`); mounted in `feed_header.dart:48`. All inputs are my own node lifecycle —
peer presence is **not** involved.

**Fix.** **(a)** Added **anti-flap acceptance notes** to FDC-05/06/07 (each asserts no spurious
`connecting`/`offline` regression on its transition). **(b) FDC-14** (authored) adds a new
`onlineDirect` badge tier driven by a "directly-reachable" signal (provisional, gated on FDC-02/11) +
an anti-flap test. Note: **peer-presence (FDC-08/09) is a different axis** that never feeds this dot.

---

### Net

Q2/Q3/Q5 are **sound as designed**. Q1 was a real **contradiction**, now fixed in FDC-11. Q4/Q6/Q7
were **gaps**, now logged in FDC-00 and addressed by **FDC-13** (upgraded badge), the **media scope
note + preservation floor**, and **FDC-14** (directly-reachable dot) + the **anti-flap notes** in
FDC-05/06/07.
