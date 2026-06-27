# FDC-15 — 1:1 media over a peer-authenticated libp2p LAN stream  (New Feature)

Status: awaiting-review — **reviewed + re-grounded 2026-06-27 (5-agent verify→refute)**; **FDC-S2 RESOLVED (Option A, QUIC, 750ms; `<from FDC-S2>` values threaded)**; STILL gated by **FDC-11 device-proof**. Scope EXPANDED: the **receive→render leg** + a **Dart non-circuit-direct predicate** + the **5-layer bridge wiring** are now required (were missing). See **Review Findings (2026-06-27)** below.

> # ⚠ DRAFT — reviewed 2026-06-27; FDC-S2 RESOLVED (Option A); STILL gated by FDC-11 (direct LAN conn device-proven)
> **FDC-S2 closed Option A** (2026-06-27): direct LAN **QUIC** + identify is reliable (budget **750ms** =
> the already-landed `LANDirectIdentifyBudget`, `config.go:97` — FDC-15 **reuses** it, does NOT mint a
> duplicate `LANMediaOpenBudget`), so the `<from FDC-S2>` transport/budget values are threaded below
> (QUIC, `/tcp` fallback lane). The Option-C "shelve this plan / KEEP the WS media server" branch did
> **NOT** fire. **This plan still cannot finalize until FDC-11 ships a device-proven direct libp2p LAN
> connection** (D1 GREEN on both platforms) — FDC-15 streams media *over* that conn, so the
> `EnableLibp2pLANMedia` flag stays **default-OFF until FDC-11 lands + is device-proven**. The **Go
> protocol/framing/handler/SHA-256-verify** core and the **Dart leg-selection /
> relay-CDN-still-unconditional** guards are **host-testable now**; the **real two-phone LAN media
> transfer** is the **device-only** closure gate.
>
> **⚠ Review re-scoping (2026-06-27).** Verify→refute found the original draft was **send-only** and
> assumed Dart facts that do not exist. NOW REQUIRED (see Review Findings): (1) a **receive→render leg**
> (Go `media:lan_received` → `go_bridge_client` route → Dart consumer → `linkIncomingLocalMedia` →
> decrypt-adopt) — without it D1 "receiver renders" is unreachable AND an unrouted event can **regress
> the 1:1 gate**; (2) the **Dart `hasNonCircuitDirectConn` predicate is net-new** (the cited `:4092-4097`
> anchor is fictional) — build it from `currentState.connections[].multiaddrs` reusing FDC-02's
> `_isCircuitOnlyConnected`, and **never** reuse `_inferTransportForPeer` (it short-circuits to `relay`
> when a circuit + a direct conn coexist — the exact FDC-15 window); (3) the **bridge command is 5
> layers** (Go in the **already-existing** `bridge_lan.go` + `_cmdMap` + GoBridge.swift + GoBridge.kt +
> gomobile rebuild) and the native legs are **device-deferred** (FDC-11 left them unbuilt too).

---

## Review Findings (verify→refute, 2026-06-27)

> 5-agent Workflow over current `new-orbit` source (Go node/config/flags, Go media + test harnesses,
> FDC-11 landed reality, Dart send-side + the direct-conn predicate, Dart receive-side + WS sentinels).
> **Core Go design HELD** (NEW `/mknoon/media-lan/1.0.0`, non-circuit-only, SHA-256 verify, dedup,
> relay-CDN unconditional, encrypt-once reuse all CONFIRMED). The items below are the survivors of the
> adversarial pass and have been folded into the sections that follow.

**CONFIRMED (do not re-litigate):** the node registers **no** peer-facing `MediaProtocol` handler
(`node.go:418-419` = Chat + GroupValidationFeedback only; `MediaProtocol` is relay-only at
`media.go:225`) → a NEW protocol + NEW `SetStreamHandler` is warranted. `isCircuitAddr` (`node.go:130`)
is a real reusable primitive. `classifyStreamTransport` (`node.go:134-147`) labels a non-circuit stream
`"direct"` unchanged (TL6 valid). `uploadMedia` is **unconditional** at two layers (the func body
`upload_media_use_case.dart:359` + the call site `share_batch_delivery_coordinator.dart:323` runs it
regardless of LAN outcome) → TD2 is correctly grounded. Encrypt-once artifact reuse (TD5) holds.
FDC-S2 = Option A/QUIC/750ms and FDC-S6 "FDC-15 is the named media plan" both confirmed.

### BLOCKER — the receive→render half was entirely unaddressed (the plan was send-only)

The Go `handleIncomingLANMedia` stages a temp ciphertext and **emits `media:lan_received`**, but
**nothing consumes it in Dart**:
- No `media:lan_received` case in `go_bridge_client.dart` `_handleEvent` switch (`:615`) → it falls to
  the default `_recordUnknownPushEvent` (`:444`/`:808`), which bumps `_unknownPushEventCount` and emits
  `GO_BRIDGE_UNKNOWN_PUSH_EVENT`. **`go_bridge_client_test.dart` is in `ONE_TO_ONE_TESTS`
  (`run_test_gates.sh:61`)** → an unrouted event can **REGRESS the 1:1 gate**, not merely fail to render.
- The WS receive path is 100% Dart today: `LocalMediaServer` → `LocalMediaReady` (`local_media_server.dart:384`)
  → `_localMediaSub` (`p2p_service_impl.dart:428`) → `incomingLocalMediaStream` (`:471`) →
  `main.dart:2418` `linkIncomingLocalMedia`. FDC-15 moves the receive into Go but never re-wires Go→Dart.
- D1's "**receiver renders the decrypted media**" is therefore **unreachable** as originally planned.

**Reuse path (now REQUIRED scope):** map the Go event into a `LocalMediaReady`
(`local_discovery_service.dart:59-92`, incl. `enc:74`/`encScheme:77`), publish it on the existing
`_incomingLocalMediaController` (`p2p_service_impl.dart:178/428/471`), and let the existing
`linkIncomingLocalMedia` (`link_incoming_local_media_use_case.dart:65` — moves enc bytes to
`<canonical>.enc` :119-135) → `decryptAndPromoteStagedDirectBlob` (`download_media_use_case.dart:974`)
pipeline render it with **zero new downstream wiring**. **The `media:lan_received` payload schema must be
defined** — it must carry the Go-staged **temp path** (Dart cannot guess a Go temp dir), `id`, `from`,
opaque `mime`, `size`, `sha256`, `enc`/`encScheme` — i.e. the full `LocalMediaReady` shape. New tests:
**TL11** (Go emits the full payload), **TD8** (`go_bridge_client` routes `media:lan_received` and does
NOT hit the unknown-event sink), **TD9** (the Dart consumer stages `<canonical>.enc` + feeds
`linkIncomingLocalMedia`).

### HIGH — the Dart `hasNonCircuitDirectConn` predicate is fictional (but implementable)

TD1/TD4/Step-8 gate on `hasNonCircuitDirectConn(peerId)` and cite `:4092-4097` — that anchor is a
`RELAY_OUTAGE_TIMING` `emitFlowEvent`, **not a predicate**. The real accessors are `isConnectedToPeer`
(`:4569`, status-only, **circuit-agnostic**) and `isLocalPeer` (`:4574`, **bonsoir/mDNS visibility, NOT
a libp2p direct conn**). No `hasNonCircuitDirectConn`/`hasDirectConn` exists anywhere in `lib/`.
- **It IS implementable from existing state** — `currentState.connections[].multiaddrs` carries the
  addrs. **Reuse FDC-02's prior art:** `_isCircuitOnlyConnected` (`send_chat_message_use_case.dart:1445`),
  `_hasLiveCircuitConnection` (`:1431`), `_inferDirectVsRelayForConnectedPeer` (`:1402`). Define
  `hasNonCircuitDirectConn(p) == isConnectedToPeer(p) && !_isCircuitOnlyConnected(p)` (i.e. **≥1
  non-`/p2p-circuit` multiaddr**). Add a **TD7** unit test for the predicate itself.
- **DO-NOT-REUSE TRAP:** `_inferTransportForPeer` (`:3401-3426`) returns `'relay'` and **short-circuits
  on the FIRST `/p2p-circuit` multiaddr** (`:3417`). In FDC-15's core scenario a peer holds **both** a
  relay reservation **and** a fresh FDC-11 LAN-direct conn → reusing it yields `'relay'` → the leg
  **never fires** (false-negative). Gate semantics must be **"has ≥1 NON-circuit conn"**, never "has no
  circuit conn". (Same on the Go side: `SendLANMedia` must scan `h.Network().ConnsToPeer(pid)` for
  `!c.Stat().Limited && !isCircuitAddr(c.RemoteMultiaddr())` — **not** negate FDC-11's `hasCircuitConn`
  at `lan_dial.go:64`, since circuit + direct can coexist.)
- **Device-gated caveat:** the predicate's correctness depends on Go `node:status` surfacing FDC-11's
  LAN-direct conn with its **real direct multiaddr** — and `p2p_service_impl.dart:3402-3405` warns libp2p
  does **not** re-fire connectedness on an upgrade (a stale `/p2p-circuit` addr can persist). TD1/TD4
  host-fakes **fabricate** the `connections` list, so host-green does NOT validate real surfacing → that
  residue is **D1**. (`ConnectionState.fromJson` also currently **drops** the Go `connectionInfo.Limited`
  flag, `connection_state.dart` vs `node.go:126` — multiaddr-scan is the only available signal.)

### HIGH — the bridge command is 5 layers, not 2 (and the native legs are device-deferred)

A callable `MediaLANSend` needs: (1) the Go bound func in **the already-existing `bridge_lan.go`**
(FDC-11, 56 lines — the Scope-Guard's "NEW file" is **stale**; `bridge.go` is 2880 lines, not 2878),
(2) a `_cmdMap` entry `'media:lan_send': _CmdSpec('mediaLanSend', true)` in `go_bridge_client.dart`,
(3) an iOS `GoBridge.swift` case, (4) an Android `GoBridge.kt` case, (5) a **gomobile framework rebuild**
(`GoMknoon.xcframework`/`.aar`). FDC-11's **own** native cases for `lan:peer_found` are **absent** from
both `GoBridge.swift`/`GoBridge.kt` — FDC-15 inherits that unbuilt native leg, so **schedule native
dispatch + framework rebuild under D1** (same deferral pattern as FDC-08's LR1). Real Scope, Files-To-
Inspect, and Step 7 must point at `bridge_lan.go` (currently contradict the Scope-Guard by naming
`bridge.go`). Mirror `bridge_lan.go`'s `HandleLANPeerFound` (`:25`) envelope verbatim (panic-recover +
`nodeMu` + `okJSON`/`errJSON`).

### MEDIUM — test-catalog corrections (the original RED catalog has un-RED-able / mis-registered rows)

- **TL8 RemoveStreamHandler premise is UNSOUND.** `Stop` (`node.go:518`) never calls
  `RemoveStreamHandler` anywhere in `node/`; it does `host.Close()` + `host=nil` (`:558-567`) and every
  `Start` builds a **fresh host** (`libp2p.New :383`), so a dropped `RemoveStreamHandler` **cannot go
  RED**. **Re-anchor TL8** to the genuinely testable Stop hygiene: **reset `lanMediaSeenIds` across
  Stop/Start** (mirror the FDC-11 `lanDialHandler` cooldown→nil reset at `node.go:571-575`).
- **TL10 max-size bound is NET-NEW**, not a reuse. No Go max-media-size constant exists (only
  `MaxFrameLen = 128KB`, `config.go:72`, which caps the **header/ack**, not the body). FDC-15 must
  **introduce** one (e.g. `MaxLANMediaBytes`) and state its value. The WS analog the plan should mirror
  is `maxFileSize = 5GB` (`local_media_server.dart:43`) + the **pre-stream** reject in `acceptOffer`
  (`:102`, NOT `:202` which is the **token** check) + the in-stream overrun guard (`:271`).
- **TD6 (group scope-lock) is registered to the wrong family.** It lives in
  `p2p_service_impl_lan_media_test.dart`, which TD1's note appends only to `ONE_TO_ONE_TESTS` +
  `TRANSPORT_TESTS` — so `./scripts/run_test_gates.sh groups` **never runs it**. Either add the file to
  `GROUP_TESTS` or move TD6 to a group test file.
- **WS-preservation sentinels run in NO listed gate.** `local_media_{sender,server}_test.dart` live in
  `test/core/local_discovery/` → auto-glob `core-host-all`/`host-all`, **NOT** the "1to1 family" (the
  Existing-Tests section is wrong). **Add `./scripts/run_host_test_gates.sh core-host-all`** to the
  Acceptance Gates so the sentinels the plan promises to keep green are actually exercised.
- **`LANMediaOpenBudget = 750ms` duplicates the landed `LANDirectIdentifyBudget = 750ms`**
  (`config.go:97`). FDC-15 consumes an **existing** direct conn (no dial), so **reuse it** (or justify a
  distinct stream-open budget) rather than mint a redundant literal that drifts if FDC-S2 is retuned.
- **`featureFlagsStatusMap` is a 3rd flag-add site** (`feature_flags_runtime.go:33-42`) the plan omits.
  Adding `EnableLibp2pLANMedia` without an `'enableLibp2pLANMedia'` status entry leaves the runtime/JSON
  status surface inconsistent and may break `feature_flags_runtime_test.go`.
- **TL3 cites the wrong harness.** `holepunch_feasibility_test.go` is circuit-relay DCUtR-only (opens no
  custom stream, asserts no app event). Use **`quic_identify_revalidation_test.go`** (`s2BuildHost:58`/
  `s2PickListenAddr:95`/`s2WaitIdentify:120` — the FDC-S2 M1 two-host QUIC loopback, already reused by
  `lan_dial_test.go`) + `startLocalNodeForMultiRelayTestWithCollector` (`pubsub_delivery_test.go:28`) +
  `testEventCollector`/`waitForCollectedEvent` for the `media:lan_received` assertion. Only
  `firstDirectConn:139`/`classifyStreamTransportConn:158` from the holepunch file are reusable.
- **Go streaming SHA-256 verify is NET-NEW**, not a reuse. `copyMediaDownloadToFile` (`media.go:290`)
  does idle-timeout `io.CopyN` with **no hashing** (the Go media path imports no `crypto/sha256`). TL3/TL4
  must add `io.TeeReader → sha256.New` + constant-time compare; only the idle-timeout/CopyN scaffolding
  is reused.
- **`sha256`/`contentHash` is not threaded into `sendLocalMedia`.** Its signature has no `sha256` param;
  `artifact.contentHash` (`upload_media_use_case.dart:187-189`) is computed in `prepare` but only
  `encryptedPath` is passed to `sendLocalMedia` (`share_batch:309`). Decide: **thread `contentHash`
  through `sendLocalMedia`/`sendMedia`**, or have **Go compute it from the file** (the WS
  `LocalMediaSender` computes its own at `:97`). The leg's header `sha256` (TL3/TL4/TD5) depends on this.

### Anchor drift (re-grounded; the structure matched, the line numbers were stale on new-orbit)

| Symbol | Plan | Actual | Symbol | Plan | Actual |
|---|---|---|---|---|---|
| `SetStreamHandler` block | `node.go:391-392` | **`:418-419`** | `sendLocalMedia` | `:4184-4216` | **`:4661-4693`** (+477) |
| `classifyStreamTransport` | `:123-136` | **`:134-147`** (`isCircuitAddr` `:130`) | account gate | `:4196` | **`:4674`** |
| `Stop` | `:471+` | **`:518`** (FDC-11 teardown `:569-575`) | `_localP2P==null` | `:4203` | **`:4680`** |
| `SendMessageWithTransport` | `:1384-1440` | **`:1441`** (`:1384`=`openChatStreamForSend`) | `isConnectedToPeer`/`isLocalPeer` | `:4092-4097` | **`:4569`/`:4574`** |
| `writeFrame`/`readFrame` | (in send path) | **`:2055`/`:2039`** (128KB cap; header/ack only) | `_sendMediaTransferWithWatchdog` | `:676` | **`:803`** |
| `setStreamDeadline` | media.go | **`node.go:1548`** | `callP2PMediaUpload` | `:791/:837` | **`:889`** |
| bridge `MediaUpload` | `:1426-1458` | **`:1431-1468`** (no Go watchdog) | `conversation_wired` sendLocalMedia | `:2266/:3192` | **`:2292/:3220`** |

`upload_media_use_case` (`:142/:176/:224/:359/:367/:371`), `share_batch` (`:307/:323`), and
`local_media_{server,sender}` anchors all **MATCH** (FDC-15 does not edit these). GOTOOLCHAIN=go1.25.0
for all Go gates (quic-go panic under Go 1.26.x).

---

## Source Of Truth

- **Proposal** `Network-Arch/Fast-Direct-Connection-Architecture-Proposal.md`:
  §5 "WebSocket-over-WiFi vs libp2p" (L128-160 — the WS media server rode HTTP-PUT to dodge the
  QUIC/libp2p stack, the §2 fragmentation cost); §6.2 "media and any large/long payload must go
  **direct-or-inbox, never over the live relay socket**" (L222-224, circuit-v2 = 2 min / 128 KB);
  §6.5 "Unified LAN-direct over libp2p" (L276-286); §10 "LAN double-delivery → dedup by `messageId`"
  (L397-398); §12 SSB rooms-vs-pubs tier split (L440), "live relay circuit is not a durable pipe …
  media must go direct-or-inbox" (L481-482).
- **FDC-00 roadmap** SCOPE NOTE: the media **byte** transfer (LAN HTTP-PUT
  `local_media_sender.dart`, relay-CDN `media.go`, inbox) stays on the existing dedicated channels;
  the new libp2p roads carried **only the chat envelope** — **FDC-15 is exactly the plan that lifts
  the LAN media *byte* leg onto libp2p**, the follow-on FDC-S6 named.
- **FDC-S6** (the decision this enables): component 2 "WS/HTTP LAN MEDIA server" is **NOT covered by
  any plan** and "Retiring it **REQUIRES a NEW 'media over libp2p LAN' plan** … (e.g. **FDC-15**)"
  (`FDC-S6:145,212-217,238-244`). FDC-15 is that prerequisite; it does **not** itself retire the WS
  media server (that is FDC-S6's verdict + a later removal plan after a 14-day soak).
- **FDC-11** (the gate): proves a same-WiFi peer becomes a **`"direct"` non-circuit libp2p conn** the
  ranker prefers over relay (`FDC-11:61-67,248-262`); explicitly **keeps bonsoir+WS** and carries
  **zero media device-proof** (`FDC-11:73-76,96-107`). FDC-15 mirrors FDC-11's `HandleLANPeerFound`/
  direct-conn for a **media byte** stream.
- **FDC-S2**: supplies the Option A/B/C verdict + the direct-LAN transport (QUIC vs TCP) + identify
  budget the Go media stream consumes.
- `scripts/run_test_gates.sh` wins over prose for which tests run in which family (transport array;
  Go gate `cd go-mknoon && go test ./...`; the **groups** + **1to1** preservation families).

## Session Classification

**evidence-gated** (DRAFT). The protocol/transport question is answered by FDC-S2; the existence of a
direct LAN conn is answered by FDC-11. The Go-unit tier (protocol id, handler registration, framed
header + ciphertext stream, SHA-256 verify, circuit-refusal, label, dedup, lifecycle) is
implementation-ready (FDC-S2 = **Option A**, resolved); the remaining hard gate is FDC-11's **device-proven** direct conn. The **real-NIC two-phone media transfer** is
**device-only** and is the closure gate (sim shares the host mDNS stack →
`DISABLE_LOCAL_DISCOVERY`, `e2e_test_mode.dart:2`).

## Exact Problem Statement

**What must improve (the headline value — peer-AUTH + metadata protection + one LAN stack).** Today a
same-WiFi 1:1 media transfer trusts a **bonsoir TXT-record `peerId`** and ships ciphertext over a
**plaintext `ws://` + HTTP-PUT** transport (`local_media_sender.dart:165` `http://$host:$port/media/`,
`local_discovery_service.dart:169` advertises the **wsPort**). The remote is **never cryptographically
proven** to be the claimed peerId — any host on the LAN that answers the advertised port and presents
the bearer token (sent in the same plaintext channel) is trusted. FDC-15 streams the **same**
`EncryptedMediaArtifact` ciphertext over a **Noise-authenticated libp2p direct stream** (the FDC-11
direct LAN conn), so:
- **Peer auth:** the remote is proven to hold the peerId's private key (libp2p Noise handshake), not
  merely to have grabbed an advertised port + an echoed token.
- **Metadata protection:** the offer header (id/mime/size/sha256) rides the encrypted libp2p stream
  instead of plaintext WS JSON + a plaintext HTTP request line that exposes `/media/<id>`.
- **One LAN stack:** collapses the §2 "two connectivity systems that don't share state" — the media
  bytes now ride the **same** libp2p conn the chat envelope already uses, instead of a second
  WS/HTTP server.

Confidentiality is **unchanged** — media is already app-encrypted **once** into the
`EncryptedMediaArtifact` (`upload_media_use_case.dart:142-161`, "encrypt once, send the same ciphertext
on relay AND LAN") and the WS leg already sends `enc=true` opaque ciphertext
(`local_media_sender.dart:49,112-128`). FDC-15 does **not** re-encrypt; it re-**transports** the same
bytes.

**What must stay unchanged → preserved sentinels.**
- **The relay-CDN upload stays UNCONDITIONAL.** `uploadMedia` (`upload_media_use_case.dart:224,359`)
  always runs `callP2PMediaUpload` and is the durable recovery copy **AND** the source of the
  attachment's encryption metadata. The 112-Phase-2.4 bug was a LAN-success `continue` that skipped
  `uploadMedia`, building a metadata-free attachment the G5 gate rejects
  (`share_batch_delivery_coordinator.dart:290-307` comment). PRESERVE: adding a libp2p-LAN leg must
  **NOT** gate, skip, or short-circuit the relay-CDN upload — exactly as the WS leg does not today.
- **bonsoir+WS LAN media server stays as the proven fallback** (`LocalMediaServer`,
  `LocalMediaSender`, `LocalWsServer.sendMedia`) — additive, parallel, idempotent by blob id /
  SHA-256; receiver dedups. FDC-15 is **additive**, not a removal (removal is FDC-S6's later
  verdict). PRESERVE: WS/HTTP media path untouched and still reachable when the flag is off / no
  direct conn exists.
- **Media never rides the live relay socket.** Proposal §6.2 L222-224: circuit-v2 is 2 min / 128 KB.
  PRESERVE: the libp2p-LAN media stream is opened **only over a non-circuit (direct) conn** and
  **refuses a circuit conn** (locked by TL5/TD4).
- **`/mknoon/media/1.0.0` is the relay-CDN protocol — do NOT reuse it.** It is node→relay
  (`media.go:225`); the node registers **no peer-facing** MediaProtocol handler. FDC-15 uses a **NEW**
  protocol id (`MediaLANProtocol = "/mknoon/media-lan/1.0.0"`).
- **`classifyStreamTransport` label contract** (`node.go:123-136`): a LAN media stream is non-circuit
  → `"direct"` (TL6).
- **Group media path is untouched** — group media is relay-CDN only; it has **no** LAN byte path
  (Scope Guard + TD6).
- **Account network-side-effect gate preserved** — `sendLocalMedia` already guards behind
  `_allowsAccountNetworkSideEffects('p2p_send_local_media', …)` (`p2p_service_impl.dart:4196`); the
  libp2p-LAN leg sits **inside** the same gate.

## Root Cause / Background (verify→refute, file:line)

**The LAN media byte path today (1:1 only) — verified by Read:**
1. `conversation_wired.dart:2266,3192` (1:1 conversation screen) and
   `share_batch_delivery_coordinator.dart:307` call `p2pService.sendLocalMedia(...)`.
2. `sendLocalMedia` (`p2p_service_impl.dart:4184-4216`) — guarded by
   `_allowsAccountNetworkSideEffects` (`:4196`), early-returns if `_localP2P == null` (`:4203`), then
   `_localP2P.sendMedia(...)`.
3. `LocalP2PService.sendMedia` (`local_p2p_service.dart:139-168`) — resolves **host/port via bonsoir**
   `_discovery.getLocalPeer(peerId)` (`:151`, null ⇒ not on LAN ⇒ false), then `_wsServer.sendMedia`.
4. `LocalWsServer.sendMedia` (`local_ws_server.dart:619-671`) — pooled WS conn for signaling
   (`_getOrCreateConnection`), then `LocalMediaSender.sendMedia`.
5. `LocalMediaSender.sendMedia` (`local_media_sender.dart:32-246`): SHA-256 over the ciphertext file
   (`:97`), `media_offer` via WS (`:114-131`, `enc=true` opaque, drops waveform/filename for metadata
   minimization), wait `media_offer_accepted` (`:140`, 5 s), **HTTP PUT** to
   `http://$host:$port/media/<id>` with `Authorization: Bearer <token>` (`:165-183`), wait
   `media_uploaded` (`:218`, 30 s).
6. Receiver: `LocalMediaServer.handleUpload` (`local_media_server.dart:129-430`) — token check
   (`:202`), size check, **streaming SHA-256 verify** (`:336`), emits `LocalMediaReady` (`:384`);
   `acceptOffer` rejects **duplicate id** (`:76`).

**The encrypt-once artifact — verified:** `EncryptedMediaArtifact` (`upload_media_use_case.dart:142`),
`prepareEncryptedMediaArtifact` (`:176-198`) does blob keygen + encrypt + SHA-256 of the **encrypted**
bytes; the LAN leg streams `artifact.encryptedPath` and `uploadMedia` consumes the **same** artifact
(`:347-352,371`). The relay-CDN upload `callP2PMediaUpload` (`:359`) advertises an **opaque** mime
(`kOpaqueMediaTransportMime`, `:367`) and a **structurally ciphertext-only** `filePath`
(`:371`, no `?? localFilePath` fallback).

**The relay-CDN byte path (the durable recovery — stays unchanged) — verified:** `media.go`
`MediaUpload` (`:327`) → `openMediaStream` → `h.NewStream(ctx, relay.ID, MediaProtocol)`
(`media.go:225`, **to the relay**), framed JSON request/response (`sendMediaRequest:267`).

**`/mknoon/media/1.0.0` is already taken — verified (refute "reuse the constant"):**
`MediaProtocol = "/mknoon/media/1.0.0"` (`config.go:24`) is used **only** at `media.go:225` to open a
stream **to the relay**; `node.go:391-392` registers handlers for **`ChatProtocol`** and
**`GroupValidationFeedbackProtocol`** and **no** `MediaProtocol` handler — the node never receives
peer-to-peer media streams today. So FDC-15 must add a **NEW** protocol + a **NEW** `SetStreamHandler`,
not reuse the relay protocol.

**The chat stream pattern FDC-15 mirrors — verified:** `node.go:391`
`h.SetStreamHandler(ChatProtocol, n.handleIncomingMessage)`; `openChatStream` (`:1291-1296`)
`h.NewStream(ctx, pid, ChatProtocol)`; `SendMessageWithTransport` (`:1384-1440`) writes a **4-byte
BE-framed** payload (`writeFrame`), reads a framed reply, `classifyStreamTransport(s)` labels the
transport. FDC-15's media stream reuses `writeFrame`/`readFrame` framing + `classifyStreamTransport`.

**Refuted / do-NOT-re-introduce:**
- **Do NOT skip / gate the relay-CDN upload on the LAN leg** — that is the 112-Phase-2.4
  dangling-attachment regression (`share_batch_delivery_coordinator.dart:290-307`). The relay-CDN
  upload is **unconditional**; the LAN leg (WS or libp2p) is best-effort acceleration only.
- **Do NOT reuse `/mknoon/media/1.0.0`** — it is the relay-CDN upload protocol (above).
- **Do NOT open the media stream over a circuit/relay conn** — proposal §6.2 (128 KB cap). Non-circuit
  only.
- **Do NOT re-encrypt** — reuse the existing `EncryptedMediaArtifact` ciphertext; a second encryption
  mints a key the relay/other LAN copy doesn't have (`upload_media_use_case.dart:243-246`).
- **Do NOT add store dedup/idempotency to the relay** — already exists; LAN double-delivery leans on
  the receiver's blob-id / `messageId` dedup (proposal §10, `FDC-11:101-103`).
- **Do NOT touch bonsoir discovery** — it stays (iOS entitlement; `FDC-S6:146,219`).

## Real Scope

**In scope**
- **(Go)** NEW `MediaLANProtocol = "/mknoon/media-lan/1.0.0"` (`config.go`); flag-gated
  `SetStreamHandler(MediaLANProtocol, n.handleIncomingLANMedia)` in `Node.Start`; a receiver that
  reads a framed header (id, opaque mime, size, sha256), streams the ciphertext to a temp file with
  **incremental SHA-256 verify** (mirror `LocalMediaServer.handleUpload` semantics), replies a framed
  ack (`{ok, sha256Verified}`), dedups by **id**, emits `media:lan_received`.
- **(Go)** `SendLANMedia(peerId, filePath, mediaId, opaqueMime, sizeBytes, sha256)`: open
  `NewStream(ctx, pid, MediaLANProtocol)` **only over a non-circuit (direct) conn** — **refuse** when
  the only conn is a circuit (return a typed `errMediaLANRequiresDirect`); write header + stream
  ciphertext; read ack; label `"direct"`.
- **(Bridge — 5 layers, see Review Findings)** NEW bridge command `MediaLANSend` added to the
  **already-existing** `go-mknoon/bridge/bridge_lan.go` (FDC-11) + `_cmdMap` entry
  `'media:lan_send': _CmdSpec('mediaLanSend', true)` (`go_bridge_client.dart`) + iOS `GoBridge.swift`
  case + Android `GoBridge.kt` case + **gomobile framework rebuild**; Dart `callP2PLanMediaSend`
  (`p2p_bridge_client.dart`) mirroring the Dart `_sendMediaTransferWithWatchdog` watchdog (Go `MediaUpload`
  has **no** Go-side watchdog). **The native `GoBridge.swift`/`.kt` cases + the rebuild are
  device-deferred** (FDC-11 left its own native legs unbuilt; close them at D1).
- **(Dart — send leg)** behind flag `EnableLibp2pLANMedia` (default false), `sendLocalMedia`
  (`p2p_service_impl.dart:4661`) gains a **libp2p-LAN leg**: when the flag is on **and**
  `hasNonCircuitDirectConn(peerId)` is true (a **NET-NEW** predicate — `currentState.connections[].multiaddrs`
  has ≥1 non-`/p2p-circuit` addr, reusing FDC-02's `_isCircuitOnlyConnected`; the cited `:4092-4097`
  predicate is fictional), invoke `callP2PLanMediaSend` with the **ciphertext artifact path** (never
  plaintext) + the **`sha256` content hash** (thread `artifact.contentHash` through `sendLocalMedia`, or
  compute it in Go) **in addition to** the WS HTTP-PUT; the relay-CDN `uploadMedia` stays
  **unconditional** at the call sites. Idempotent by blob id / SHA-256.
- **(Dart — receive leg, NEW required scope)** add a `media:lan_received` case to
  `go_bridge_client.dart` `_handleEvent` (`:615`, else it hits `_recordUnknownPushEvent` and can regress
  1to1), surface it as a `LocalMediaReady` on `_incomingLocalMediaController`
  (`p2p_service_impl.dart:178/428/471`), and let the existing `linkIncomingLocalMedia` →
  `decryptAndPromoteStagedDirectBlob` pipeline render it (zero new downstream wiring). **Define the
  `media:lan_received` payload schema** (staged temp path, id, from, opaque mime, size, sha256,
  enc/encScheme = the `LocalMediaReady` shape).
- **(Go)** `Stop` **resets the `lanMediaSeenIds` dedup map** (NOT `RemoveStreamHandler` — `Stop` rebuilds
  a fresh host, so handler removal is a no-op; mirror the FDC-11 cooldown reset `node.go:571-575`).
- The **feature flag** in `feature_flags.go` (struct + `DefaultFeatureFlags()` **+ `featureFlagsStatusMap`
  in `feature_flags_runtime.go`** — the 3rd flag-add site) and a **NEW `MaxLANMediaBytes` size bound**
  (no existing Go const; pick a value vs the WS `maxFileSize=5GB`). **Reuse** `LANDirectIdentifyBudget`
  (`config.go:97`, already 750ms) + `MediaIdleTimeout`/`MediaTimeout` — do **not** mint
  `LANMediaOpenBudget`.

**Out of scope → owning FDC-xx**
- Establishing the libp2p LAN-direct dial (bonsoir-fed) / the direct LAN conn itself → **FDC-11** (FDC-15 consumes its direct conn +
  bonsoir-discovered (`HandleLANPeerFound`) peerstore seeding).
- The "directly reachable" presence surfacing / badge → **FDC-14** (FDC-15 only needs the Go-side
  non-circuit-conn fact, which the node already knows).
- DCUtR cross-NAT relay→direct upgrade → **FDC-12** (media still goes inbox/relay-CDN across
  networks).
- **Retiring** the WS/HTTP LAN media server → **FDC-S6 verdict + a later WS-media-removal plan**
  (needs the 14-day soak; FDC-15 only makes the lane exist + device-proves it).
- Group media over libp2p → **explicitly OUT** (group has no LAN byte path; Scope Guard).

## Files To Inspect Next

**Go (production)**
- `go-mknoon/node/config.go` — add `MediaLANProtocol` + **NEW `MaxLANMediaBytes`** (state a value);
  **reuse** `LANDirectIdentifyBudget:97` (already 750ms — do NOT mint `LANMediaOpenBudget`); existing
  `MediaProtocol:24`, `MediaTimeout:34`, `MediaIdleTimeout:35`, `PeerDialTimeout:29`, `MaxFrameLen:72`.
- `go-mknoon/node/node.go` — `SetStreamHandler` block **`:418-419`** (add media-lan handler, flag-gated),
  `Stop` (**`:518`**, reset `lanMediaSeenIds` beside the FDC-11 teardown `:569-575` — NOT
  RemoveStreamHandler), `SendMessageWithTransport` **`:1441`** + `writeFrame:2055`/`readFrame:2039`/
  `setStreamDeadline:1548`/`classifyStreamTransport:134`/`isCircuitAddr:130` (framing/label/circuit
  helpers to reuse), `Node` struct **`:39-120`** (`n.ctx:42`; add the `lanMediaSeenIds` map+mutex beside
  `lanDialHandler:119`, mirroring `pubsubRejectDiagMu:78` / FDC-11 cooldown `lan_dial.go:39`).
- **NEW** `go-mknoon/node/media_lan.go` — `handleIncomingLANMedia` (framed header → `MaxLANMediaBytes`
  guard → streamed SHA-256 verify via **net-new** `io.TeeReader→sha256.New` over the `copyMediaDownloadToFile`
  idle scaffolding → staged temp → framed ack → full `media:lan_received` payload), `SendLANMedia`
  (≥1-non-circuit gate via `ConnsToPeer`+`isCircuitAddr` + header + ciphertext stream + ack).
- `go-mknoon/node/feature_flags.go` — add `EnableLibp2pLANMedia` to `FeatureFlags` + `DefaultFeatureFlags()`
  (default **false**) **AND `feature_flags_runtime.go:33-42` `featureFlagsStatusMap`** (the 3rd add site).
- `go-mknoon/node/media.go` — `mediaUploadProgressReader:118`, `copyMediaDownloadToFile:290` (idle-CopyN,
  **no hash** — add the sha256 sink), `sendMediaRequest:267` to mirror.
- `go-mknoon/bridge/bridge_lan.go` — **existing** (FDC-11); add `MediaLANSend` mirroring
  `HandleLANPeerFound:25` (NOT `bridge.go` — see Scope Guard; `bridge.go` `MediaUpload:1431` for the
  request/dispatch shape only).

> All Dart/Go line anchors below are **re-grounded** in the Review Findings drift table (2026-06-27);
> the worst drift is `sendLocalMedia` (`:4184`→**`:4661`**, +477).

**Dart (production — send leg)**
- `lib/core/services/p2p_service_impl.dart` — `sendLocalMedia:4661` (add the libp2p-LAN leg inside the
  existing account-gate `:4674`), `isConnectedToPeer:4569`/`isLocalPeer:4574` (building blocks), and the
  **NEW `hasNonCircuitDirectConn`** predicate (the cited `:4092-4097` is fictional). **Do NOT reuse
  `_inferTransportForPeer:3401`** (relay short-circuit trap).
- `lib/features/conversation/application/send_chat_message_use_case.dart` — FDC-02 prior art
  `_isCircuitOnlyConnected:1445` / `_hasLiveCircuitConnection:1431` to lift for the predicate.
- `lib/core/bridge/p2p_bridge_client.dart` — `_sendMediaTransferWithWatchdog:803`,
  `callP2PMediaUpload:889` (mirror for `callP2PLanMediaSend`).
- `lib/features/conversation/application/upload_media_use_case.dart` — `EncryptedMediaArtifact:142`,
  `prepareEncryptedMediaArtifact:176`, `uploadMedia:224` (**unconditional** relay-CDN upload — must stay),
  `artifact.contentHash:187` (the sha256 to thread into the leg header), `kOpaqueMediaTransportMime:367`.
- `lib/features/share/application/share_batch_delivery_coordinator.dart:307-323` — the encrypt-once
  LAN-then-unconditional-relay pattern to mirror.

**Dart (production — receive leg + 5-layer bridge wiring, NEW)**
- `lib/core/bridge/go_bridge_client.dart` — `_handleEvent` switch `:615` (add the `media:lan_received`
  case; default `_recordUnknownPushEvent:444/:808` is the regression trap) and `_cmdMap`/`_CmdSpec`
  (add `'media:lan_send'`).
- `lib/core/services/p2p_service_impl.dart` — `_incomingLocalMediaController:178` / `_localMediaSub:428`
  / `incomingLocalMediaStream:471` (publish the received LAN blob here).
- `lib/features/conversation/application/link_incoming_local_media_use_case.dart:65` — the receive→stage
  (`<canonical>.enc` `:119-135`)→link seam to feed.
- `lib/features/conversation/application/download_media_use_case.dart:974` —
  `decryptAndPromoteStagedDirectBlob` (the decrypt-adopt that renders the staged ciphertext).
- `lib/core/local_discovery/local_discovery_service.dart:59-92` — `LocalMediaReady` (the exact payload
  shape `media:lan_received` must carry; `enc:74`/`encScheme:77`).
- `lib/main.dart:2418` — the existing `linkIncomingLocalMedia` listener (unchanged downstream).
- `ios/Runner/GoBridge.swift` + `android/app/src/main/kotlin/.../GoBridge.kt` — add the `mediaLanSend`
  dispatch case **and** the `media:lan_received` EventChannel emit; **device-deferred** + gomobile rebuild.

**Go (production — also)**
- `go-mknoon/node/feature_flags_runtime.go:33-42` — `featureFlagsStatusMap` (the 3rd flag-add site) +
  `currentFeatureFlags():3` (the mutex-safe read for the TL2 gate).
- `go-mknoon/bridge/bridge_lan.go:25` — **existing** `HandleLANPeerFound` envelope to mirror for
  `MediaLANSend` (NOT a new file).

**Dart (verify untouched — preserved sentinels)**
- `lib/core/local_discovery/{local_p2p_service,local_ws_server,local_media_sender,local_media_server}.dart`
  — WS/HTTP media fallback (must stay functional + parallel; dedup by id).
- `lib/core/debug/e2e_test_mode.dart:2` `kDisableLocalDiscovery` (the device-gate isolation switch).

**Tests (context / siblings)**
- `go-mknoon/node/protocol_version_test.go` — protocol-id locks (`:24,:43-44`) to mirror for
  `MediaLANProtocol`.
- `go-mknoon/node/transport_label_test.go` — `classifyStreamTransport` label assertions to preserve.
- `go-mknoon/node/holepunch_feasibility_test.go` — two-host loopback dial + event harness to reuse.
- `go-mknoon/node/feature_flags_runtime_test.go` — flag-gating pattern.
- `integration_test/media_stable_id_smoke_test.dart` (TRANSPORT family) — the media-bytes-deliver
  preservation floor (FDC-00 SCOPE NOTE).

## Existing Tests Covering This Area

- `go-mknoon/node/protocol_version_test.go` — **exists**; locks chat/media/group protocol ids; FDC-15
  adds a `MediaLANProtocol` lock here (or in the new file). Runs `cd go-mknoon && go test ./...`.
- `go-mknoon/node/transport_label_test.go` — **exists**; locks direct-vs-relay labels; keep green.
- `go-mknoon/node/feature_flags_runtime_test.go` — **exists**; flag default + gating pattern.
- Dart media: `local_media_sender_test.dart`, `local_media_server_test.dart`,
  `local_ws_server_*_test.dart` — **exist** at `test/core/local_discovery/` → **auto-glob `core-host-all`,
  NOT the 1to1 family** (corrected; the original "1to1 family" claim was wrong — they run in NONE of the
  plan's originally-listed gates). The WS path locks to keep green (preservation) → run `core-host-all`.
- `integration_test/media_stable_id_smoke_test.dart`, `transport_e2e_test.dart` — **exist**
  (TRANSPORT family); the LAN-direct **media** device assertion is **MISSING** (device-only).
- **MISSING (this plan adds):** `go-mknoon/node/media_lan_test.go` (Go-unit) + Dart leg-selection
  tests in `p2p_service_impl` media test files + a device smoke scenario.

## RED Test Catalog

> Go-unit tests are **host-runnable** (loopback two-host, conditional on FDC-S2 = A/B). Dart leg tests
> are **host-runnable** with bridge fakes. The device row is the **closure gate**, not host-closable.
> New Go file: `go-mknoon/node/media_lan_test.go`.

### TL1 — MediaLANProtocol id is `/mknoon/media-lan/1.0.0` and ≠ MediaProtocol (protocol-id lock)
- **file::name** `go-mknoon/node/media_lan_test.go::TestMediaLANProtocol_Id`
- **Tier:** Go unit. **Shape:** assert `MediaLANProtocol == "/mknoon/media-lan/1.0.0"` and
  `MediaLANProtocol != MediaProtocol` (mirror `protocol_version_test.go:43-44`).
- **RED-on-HEAD:** the constant does not exist (won't compile).
- **GREEN:** constant present + distinct from the relay protocol.
- **Mutation:** set `MediaLANProtocol = MediaProtocol` → equality fails → RED.
- **Discriminator:** the **distinctness** assertion (proves the relay protocol wasn't reused).

### TL2 — Start registers the media-lan handler when flag on; not when off (gate / rollout)
- **file::name** `…::TestStart_RegistersMediaLANHandler_FlagGated`
- **Tier:** Go unit. **Shape:** Start with `FeatureFlags{EnableLibp2pLANMedia:true}` then `:false`;
  assert `host.Mux().Protocols()` contains `MediaLANProtocol` only when on. Mirror
  `feature_flags_runtime_test.go`.
- **RED-on-HEAD:** flag field + handler registration absent (won't compile).
- **GREEN:** handler present iff flag on; node otherwise starts normally (baseline preserved).
- **Mutation:** make registration unconditional (ignore flag) → present under flag-off → RED.
- **Discriminator:** presence of `MediaLANProtocol` in the host's protocol switch.

### TL3 — SendLANMedia over a DIRECT loopback conn stages ciphertext + SHA-256 verified (headline)
- **file::name** `…::TestSendLANMedia_DirectConn_StagesAndVerifies`
- **Tier:** Go unit (two in-process hosts, `/ip4/127.0.0.1/udp/0/quic-v1` — QUIC per FDC-S2 Option A).
  **Harness (corrected):** mirror `quic_identify_revalidation_test.go` (`s2BuildHost:58`/
  `s2PickListenAddr:95`/`s2WaitIdentify:120` — the FDC-S2 M1 two-host QUIC loopback already reused by
  `lan_dial_test.go`) + `startLocalNodeForMultiRelayTestWithCollector` (`pubsub_delivery_test.go:28`) +
  `testEventCollector`/`waitForCollectedEvent` for the `media:lan_received` assertion. **NOT**
  `holepunch_feasibility_test.go` (circuit-relay DCUtR only; opens no custom stream, fires no app event —
  only `firstDirectConn:139`/`classifyStreamTransportConn:158` are reusable from it). The receiver's
  streaming SHA-256 is **net-new** Go (`io.TeeReader → sha256.New`; `copyMediaDownloadToFile:290` does
  the idle-CopyN staging but **no** hashing). **Shape:** hostA `host.Connect`s hostB (non-circuit); write
  a temp ciphertext blob + its sha256; `A.SendLANMedia(Bid, path, id, opaqueMime, size, sha256)`.
- **RED-on-HEAD:** no `SendLANMedia` / `handleIncomingLANMedia` symbol.
- **GREEN:** receiver wrote a staged temp file of exactly `size` bytes; recomputed sha256 == sent
  sha256; `SendLANMedia` returns acked with `sha256Verified==true`; a `media:lan_received` event fired
  for `id`; the stream classified `"direct"`.
- **Mutation:** drop the receiver's `writeFrame(ack)` (or the `io.CopyN` to disk) → no verified ack /
  no staged file → RED.
- **Discriminator:** **staged-file bytes + recomputed sha256 match** (not merely "ack returned").

### TL4 — SHA-256 mismatch ⇒ receiver rejects, no staged file promoted, ack failure
- **file::name** `…::TestSendLANMedia_Sha256Mismatch_Rejected`
- **Tier:** Go unit. **Shape:** send a header sha256 that does **not** match the streamed bytes (corrupt
  one byte).
- **RED-on-HEAD:** no verify path.
- **GREEN:** receiver deletes the temp file, replies `{ok:false, reason:"sha256_mismatch",
  sha256Verified:false}`; `SendLANMedia` returns not-acked; no `media:lan_received` for the id (mirror
  `local_media_server.dart:337-366`).
- **Mutation:** skip the `computedHex != sha256` check → corrupt blob accepted → RED.
- **Discriminator:** absence of a promoted/staged file + `sha256Verified:false`.

### TL5 — SendLANMedia REFUSES when NO non-circuit conn exists — media never on the live relay (critical invariant)
- **file::name** `…::TestSendLANMedia_RefusesCircuitConn`
- **Tier:** Go unit (a circuit/limited conn to B, or a conn whose only addr `isCircuitAddr`; if a full
  circuit harness is infeasible host-side, assert the **non-circuit precondition** is enforced before
  `NewStream`). **Shape:** A holds **only** a circuit conn to B; call `SendLANMedia`.
- **Gate semantics (critical):** the gate is **"has ≥1 NON-circuit conn"**, NOT "has no circuit conn".
  Scan `h.Network().ConnsToPeer(pid)` for `!c.Stat().Limited && !isCircuitAddr(c.RemoteMultiaddr())`.
  Do **NOT** implement it as `!hasCircuitConn` (FDC-11 `lan_dial.go:64`) — a peer can hold a circuit
  reservation **and** a direct LAN conn simultaneously, and that case **must SEND over the direct**.
- **RED-on-HEAD:** no non-circuit gate exists.
- **GREEN:** with only a circuit conn → returns a typed `errMediaLANRequiresDirect`; **no**
  `MediaLANProtocol` stream is opened over the circuit; no bytes written (proposal §6.2 128 KB cap).
- **Mutation:** remove the non-circuit scan (open over any conn) → stream opens over circuit → RED.
- **Discriminator:** the typed refusal error + zero stream-open over a circuit addr.
- **TL5b (coexisting conns):** A holds **both** a circuit conn AND a direct conn to B → `SendLANMedia`
  **succeeds over the direct** (labels `"direct"`), proving the gate is not a naive `hasCircuitConn`
  negation. **Mutation:** switch the gate to `!hasCircuitConn` → refuses despite the live direct conn → RED.

### TL6 — A media-lan stream classifies "direct" (label contract preserved)
- **file::name** `…::TestMediaLANStream_ClassifiesDirect`
- **Tier:** Go unit. **Shape:** after TL3's direct conn, run `classifyStreamTransport` on the media-lan
  stream.
- **RED-on-HEAD:** N/A on HEAD (no media-lan stream exists) — **preservation lock**; goes RED only
  under a mislabel mutation.
- **GREEN:** returns `"direct"` (non-circuit).
- **Mutation:** route the media-lan stream through a circuit addr (or hardcode `"relay"`) → RED.
- **Discriminator:** non-circuit `RemoteMultiaddr`.

### TL7 — duplicate media id on the receiver is deduped (both legs may deliver)
- **file::name** `…::TestHandleIncomingLANMedia_DedupesDuplicateId`
- **Tier:** Go unit. **Shape:** deliver the same `id` twice (simulating WS-leg-already-staged or a
  retransmit).
- **RED-on-HEAD:** no dedup map / no handler.
- **GREEN:** the second delivery is rejected/ignored (no second `media:lan_received`, no second staged
  temp overwrite-corruption), mirroring `LocalMediaServer.acceptOffer` duplicate-id reject (`:76`).
- **Mutation:** remove the duplicate-id guard → second delivery re-emits / clobbers → RED.
- **Discriminator:** exactly one `media:lan_received` per id.

### TL8 — Stop resets the lanMediaSeenIds dedup map (lifecycle durability) — RE-ANCHORED
> **Original "Stop removes the media-lan handler" premise is UNSOUND** (Review Findings): `Stop`
> (`node.go:518`) never calls `RemoveStreamHandler` (none exists in `node/`); it `host.Close()`s +
> nils the host, and every `Start` builds a **fresh host** — so a dropped `RemoveStreamHandler` cannot
> go RED. The real, testable Stop hygiene is **resetting the dedup map** so a duplicate `id` from a
> prior session does not suppress a legit delivery after restart.
- **file::name** `…::TestStop_ResetsLanMediaSeenIds`
- **Tier:** Go unit. **Shape:** Start (flag on) → deliver `id=X` (seen) → `Stop()` → `Start()` again →
  deliver `id=X` → assert it is **accepted + emits `media:lan_received`** (the map was cleared); a clean
  restart registers the handler with no panic. Mirror the FDC-11 cooldown reset (`node.go:571-575`).
- **RED-on-HEAD:** no `lanMediaSeenIds` map / no reset.
- **GREEN:** `Stop` resets `lanMediaSeenIds` (nil/`make(...)`, mirror `n.connections` reset `:565`);
  post-restart re-delivery of `X` succeeds; no double-register panic.
- **Mutation:** drop the `lanMediaSeenIds` reset in `Stop` → stale `id=X` suppresses the post-restart
  delivery (no `media:lan_received`) → RED.
- **Discriminator:** a `media:lan_received` for `X` AFTER Stop/Start (proves the reset, not the handler).

### TL9 — two concurrent incoming streams with the same id dedup correctly under `-race`
- **file::name** `…::TestHandleIncomingLANMedia_ConcurrentDuplicateId_RaceClean`
- **Tier:** Go unit (`-race`). **Shape:** two goroutines deliver the **same** `id` simultaneously over
  two streams; run under `go test -race ./node/...`.
- **RED-on-HEAD:** no handler / `lanMediaSeenIds` map unguarded.
- **GREEN:** exactly one `media:lan_received` for the id; `-race` reports **no** data race on the shared
  `lanMediaSeenIds` map (mutex-guarded).
- **Mutation:** drop the mutex around `lanMediaSeenIds` → `-race` flags the concurrent map access → RED.
- **Discriminator:** clean `-race` **and** single emit under concurrency (extends TL7's serial dedup).

### TL10 — a framed-header `size` over the max bound is rejected BEFORE `io.CopyN` (disk-fill / OOM guard)
- **file::name** `…::TestHandleIncomingLANMedia_OversizeHeader_RejectedBeforeCopy`
- **Tier:** Go unit. **Shape:** send a header whose `size` exceeds the max-blob bound; assert the
  handler refuses **before** allocating/streaming the body.
- **RED-on-HEAD:** no size-bound guard on the framed header.
- **GREEN:** handler replies `{ok:false, reason:"size_exceeds_max"}`, writes **no** temp file, and never
  enters `io.CopyN` (guards disk-fill / OOM from a malicious header). The bound is a **NET-NEW** Go
  constant `MaxLANMediaBytes` (config.go) — **no Go max exists today** (`MaxFrameLen=128KB` only caps the
  header/ack). Mirror the WS analog: the **pre-stream** reject in `acceptOffer`
  (`local_media_server.dart:102`, `offer.size > maxAcceptedFileSizeBytes`; `maxFileSize=5GB` `:43`),
  **NOT** `:202` (that is the token check), plus the in-stream overrun abort+delete (`:271`).
- **Mutation:** remove the `MaxLANMediaBytes` check (trust the header `size`) → `io.CopyN` runs on the
  oversize header → RED.
- **Discriminator:** zero bytes streamed + no temp file created when `size > MaxLANMediaBytes`.

### TL11 — `media:lan_received` carries the full render payload (receive-leg contract) — NEW
- **file::name** `…::TestHandleIncomingLANMedia_EmitsFullPayload`
- **Tier:** Go unit. **Shape:** after a verified TL3 delivery, capture the emitted `media:lan_received`
  event and assert its payload.
- **RED-on-HEAD:** no handler / no event.
- **GREEN:** the event carries **every field the Dart receive consumer needs to render**: the Go-staged
  **temp file path** (Dart cannot guess a Go temp dir), `id`, `from` peer, opaque `mime`, `size`,
  `sha256`, and `enc`/`encScheme` — i.e. the `LocalMediaReady` shape (`local_discovery_service.dart:59-92`).
- **Mutation:** drop the staged-path (or `enc`) field from the payload → the receive consumer (TD9)
  cannot locate/stage the blob → RED (and TD9 goes RED downstream).
- **Discriminator:** the **staged temp path** present in the payload (not just `{id, ok}`).

### TD1 — flag ON + peer directly libp2p-connected ⇒ libp2p-LAN leg is invoked with the ciphertext path
- **file::name** `test/core/services/p2p_service_impl_lan_media_test.dart::libp2pLanLeg_invoked_whenFlagOnAndDirect`
- **Tier:** Dart unit (fake bridge / fake LocalP2P). **Shape:** flag on; fake reports a **non-circuit
  direct** conn to peer; call `sendLocalMedia` with the ciphertext `artifact.encryptedPath`.
- **RED-on-HEAD:** `sendLocalMedia` has no libp2p-LAN leg → `callP2PLanMediaSend` never called.
- **GREEN:** `callP2PLanMediaSend` invoked once with the ciphertext path + opaque mime + the blob id.
- **Mutation:** remove the leg → never invoked → RED.
- **Discriminator:** the spy on `callP2PLanMediaSend` (path == ciphertext, not plaintext).

### TD2 — the relay-CDN `uploadMedia` stays UNCONDITIONAL regardless of the libp2p-LAN leg (112-P2.4 guard)
- **file::name** `…::relayCdnUpload_unconditional_evenWhenLanLegSucceeds`
- **Tier:** Dart unit (at the call site `share_batch_delivery_coordinator` / conversation send path
  using fakes). **Shape:** libp2p-LAN leg returns success; assert `uploadMedia` still runs.
- **RED-on-HEAD:** N/A on HEAD (no LAN leg yet) — **preservation lock**; goes RED under the regression
  mutation.
- **GREEN:** `callP2PMediaUpload` invoked exactly once even when the libp2p-LAN leg succeeded; the
  built `MediaAttachment` carries encryption metadata.
- **Mutation:** gate `uploadMedia` behind `!lanLegSucceeded` (re-introduce the 112-P2.4
  dangling-attachment `continue`) → upload skipped → metadata-free attachment → RED.
- **Discriminator:** `callP2PMediaUpload` call count == 1 under LAN-success.

### TD3 — flag OFF ⇒ no libp2p-LAN leg; WS HTTP-PUT path unchanged (gate / rollback)
- **file::name** `…::flagOff_noLibp2pLanLeg_wsPathUnchanged`
- **Tier:** Dart unit. **Shape:** flag off; direct conn present; call `sendLocalMedia`.
- **RED-on-HEAD:** flag absent (won't compile until added).
- **GREEN:** `callP2PLanMediaSend` **never** called; `_localP2P.sendMedia` (WS) still invoked exactly as
  today.
- **Mutation:** ignore the flag (always run the leg) → leg fires under flag-off → RED.
- **Discriminator:** WS `sendMedia` invoked + LAN-leg spy zero.

### TD4 — peer only relay/circuit-connected (no direct conn) ⇒ no libp2p-LAN leg (Dart non-circuit gate)
- **file::name** `…::noDirectConn_noLibp2pLanLeg`
- **Tier:** Dart unit. **Shape:** flag on; fake reports **only** a circuit/relay conn (no non-circuit
  direct) to peer.
- **RED-on-HEAD:** no gate.
- **GREEN:** `callP2PLanMediaSend` not called (mirrors Go TL5 at the Dart layer); WS + relay-CDN still
  run.
- **Mutation:** drop the direct-conn precondition (call the leg on any conn) → leg fires on relay →
  RED.
- **Discriminator:** LAN-leg spy zero when only circuit conn exists.

### TD5 — the libp2p-LAN leg streams the CIPHERTEXT artifact, never the plaintext source (fail-closed)
- **file::name** `…::libp2pLanLeg_streamsCiphertext_neverPlaintext`
- **Tier:** Dart unit. **Shape:** provide `EncryptedMediaArtifact`; assert the path handed to
  `callP2PLanMediaSend` is `artifact.encryptedPath` and the mime is `kOpaqueMediaTransportMime`; if no
  artifact, the leg is skipped (no plaintext fallback), mirror `share_batch:300-321`.
- **RED-on-HEAD:** no leg.
- **GREEN:** path == ciphertext, mime opaque; null-artifact ⇒ leg skipped.
- **Mutation:** pass `localFilePath` (plaintext) when artifact present → plaintext path observed → RED.
- **Discriminator:** the path argument equals the ciphertext temp, not the picker source.

### TD6 — group media NEVER invokes the libp2p-LAN leg (scope lock)
- **file::name** `…::groupMedia_neverInvokesLibp2pLanLeg`
- **Tier:** Dart unit. **Shape:** a group media upload (`allowedPeers != null`) through `uploadMedia`;
  assert `callP2PLanMediaSend` and `sendLocalMedia` are **never** called (group is relay-CDN only).
- **RED-on-HEAD:** N/A on HEAD — **scope preservation lock**; goes RED only if a future edit wires the
  group path into the LAN leg.
- **GREEN:** group upload calls **only** `callP2PMediaUpload`; LAN-leg + `sendLocalMedia` spies zero.
- **Mutation:** add a group→`sendLocalMedia` call → spy non-zero → RED.
- **Discriminator:** group path touches **only** the relay-CDN upload.

### TD7 — `hasNonCircuitDirectConn` is true iff a non-`/p2p-circuit` conn exists (predicate unit) — NEW
- **file::name** `…::hasNonCircuitDirectConn_trueOnlyForNonCircuitConn`
- **Tier:** Dart unit. **Shape:** drive `currentState.connections` via a fake with four cases for peer P:
  (a) only a `/p2p-circuit/...` multiaddr; (b) only a direct `/ip4/.../udp/.../quic-v1`; (c) **both** a
  circuit AND a direct conn; (d) not connected.
- **RED-on-HEAD:** the predicate does not exist (the cited `:4092-4097` anchor is a `RELAY_OUTAGE_TIMING`
  block; only `isConnectedToPeer:4569`/`isLocalPeer:4574` exist, neither circuit-aware).
- **GREEN:** false for (a)/(d), **true** for (b) **and (c)** — the coexisting case must be true (mirror
  FDC-02 `_isCircuitOnlyConnected` `send_chat_message_use_case.dart:1445`; `== isConnectedToPeer(p) &&
  !_isCircuitOnlyConnected(p)`).
- **Mutation:** implement it by reusing `_inferTransportForPeer` (`:3401`, short-circuits to `'relay'`
  on the first circuit addr) → case (c) returns false → RED. **This is the do-not-reuse trap; the test
  exists to forbid it.**
- **Discriminator:** case (c) (circuit + direct coexist) is **true** — the exact FDC-15 window.

### TD8 — `go_bridge_client` routes `media:lan_received` (not the unknown-event sink) — NEW (receive leg)
- **file::name** `test/core/bridge/go_bridge_client_lan_media_test.dart::routesMediaLanReceived_notUnknownSink`
- **Tier:** Dart unit. **Shape:** push a fake `media:lan_received` event through `_handleEvent` (`:615`).
- **RED-on-HEAD:** no case → hits the default `_recordUnknownPushEvent` (`:444`/`:808`), bumping
  `_unknownPushEventCount` + emitting `GO_BRIDGE_UNKNOWN_PUSH_EVENT` (**can regress the 1:1 gate** —
  `go_bridge_client_test.dart` is in `ONE_TO_ONE_TESTS`).
- **GREEN:** the event is routed to the LAN-media consumer; `_unknownPushEventCount` **unchanged**; no
  `GO_BRIDGE_UNKNOWN_PUSH_EVENT`.
- **Mutation:** delete the `media:lan_received` case → unknown-event counter increments → RED.
- **Discriminator:** assert `…UNKNOWN_PUSH_EVENT` **NOT** emitted AND the LAN-media consumer **was** fed.

### TD9 — Dart receive consumer stages `<canonical>.enc` + feeds the decrypt-adopt pipeline — NEW (receive leg)
- **file::name** `test/.../link_incoming_lan_media_test.dart::lanReceived_stagesEnc_andLinks`
- **Tier:** Dart unit/integration (fakes + real temp dir). **Shape:** emit a `media:lan_received` carrying
  a staged ciphertext temp path + the `LocalMediaReady` fields (TL11) onto `_incomingLocalMediaController`.
- **RED-on-HEAD:** no receive consumer exists — the libp2p-LAN blob never reaches
  `linkIncomingLocalMedia` (the receive path is WS-only today).
- **GREEN:** the consumer builds a `LocalMediaReady` and the existing `linkIncomingLocalMedia`
  (`link_incoming_local_media_use_case.dart:65`) moves the bytes to `<canonical>.enc`
  (`:119-135`, stagedForDecrypt) so `decryptAndPromoteStagedDirectBlob` (`download_media_use_case.dart:974`)
  promotes/renders — single render, blob-id dedup with the WS/relay copies (proposal §10).
- **Mutation:** drop the `enc`/`encScheme` mapping (stage the ciphertext as plaintext) → decrypt-adopt
  never fires / renders raw ciphertext → RED.
- **Discriminator:** the file lands at `<canonical>.enc` (not a plaintext render path).

### D1 — DEVICE-ONLY two-phone same-WiFi LAN media over libp2p (closure gate)
- **file::name** device smoke (e.g. `transport_e2e` LAN-media variant) — **MISSING**, authored at
  FDC-11-D1-GREEN + FDC-S2-A/B.
- **Tier:** device-proof (two physical phones, one WiFi). Discovery is **bonsoir on both platforms**
  feeding the FDC-11 libp2p LAN dial (`FDC-11:115-133`); `DISABLE_LOCAL_DISCOVERY` can't isolate one
  leg (it kills the shared bonsoir feed). Isolate the libp2p **media** leg by toggling
  `EnableLibp2pLANMedia` (ON = `/mknoon/media-lan/1.0.0`; OFF = WS HTTP-PUT baseline), with the FDC-11
  `EnableLibp2pLANDial` ON so the LAN conn exists.
- **Asserts (closure):** an image/video sent same-WiFi streams over the **`/mknoon/media-lan/1.0.0`**
  protocol on a **`"direct"` non-circuit** conn; the receiver renders the decrypted media; the
  relay-CDN copy still uploaded (durable recovery present); **single render** (blob-id dedup with the
  WS/relay copies); WS/HTTP media path still works when the flag is off.
- **Why device-only:** real-NIC iOS QUIC-over-WiFi + multicast behavior is unobservable host-side
  (`FDC-11:341-343`, FDC-S2 risk). `/sims 1to1 --only <D1>` is **N/A** (sim shares the host mDNS
  stack) → **manual two-phone** run; record `media:lan_received` + transport-label flow-events.

## Test Coverage Matrix

| Spec case | Behavior props | Tier | Test file::name | RED reason on HEAD | Mutation revert | Acceptance gate cmd | Harness registration |
|---|---|---|---|---|---|---|---|
| New protocol id, ≠ relay | id == media-lan, distinct | Go unit | `media_lan_test.go::TestMediaLANProtocol_Id` | constant absent | set == MediaProtocol | `cd go-mknoon && go test ./...` | Go `./...` |
| Handler flag-gated | present iff flag on | Go unit | `…::TestStart_RegistersMediaLANHandler_FlagGated` | flag/handler absent | unconditional register | `cd go-mknoon && go test ./...` | Go `./...` |
| Direct send stages+verifies | bytes+sha256 match, "direct" | Go unit | `…::TestSendLANMedia_DirectConn_StagesAndVerifies` | no SendLANMedia symbol | drop ack/CopyN | `cd go-mknoon && go test ./...` | Go `./...` |
| SHA-256 mismatch rejected | no staged file, ack false | Go unit | `…::TestSendLANMedia_Sha256Mismatch_Rejected` | no verify path | skip hash check | `cd go-mknoon && go test ./...` | Go `./...` |
| Refuse circuit conn | typed err, no stream | Go unit | `…::TestSendLANMedia_RefusesCircuitConn` | no non-circuit gate | remove isCircuitAddr refusal | `cd go-mknoon && go test ./...` | Go `./...` |
| Label = "direct" | non-circuit | Go unit | `…::TestMediaLANStream_ClassifiesDirect` | preservation | mislabel as relay | `cd go-mknoon && go test ./...` | Go `./...` |
| Duplicate-id dedup | one lan_received | Go unit | `…::TestHandleIncomingLANMedia_DedupesDuplicateId` | no dedup map | remove guard | `cd go-mknoon && go test ./...` | Go `./...` |
| Stop resets dedup map (re-anchored) | post-restart re-deliver ok | Go unit | `…::TestStop_ResetsLanMediaSeenIds` | no map/reset (RemoveStreamHandler premise UNSOUND) | drop `lanMediaSeenIds` reset | `cd go-mknoon && go test ./...` | Go `./...` |
| Concurrent dup-id dedup (-race) | one lan_received, race-clean | Go unit (`-race`) | `…::TestHandleIncomingLANMedia_ConcurrentDuplicateId_RaceClean` | unguarded `lanMediaSeenIds` map | drop the mutex | `cd go-mknoon && go test -race ./node/...` | Go `./node/...` `-race` |
| Oversize header rejected pre-CopyN | no temp, no `io.CopyN` | Go unit | `…::TestHandleIncomingLANMedia_OversizeHeader_RejectedBeforeCopy` | no size-bound guard | trust header `size` | `cd go-mknoon && go test ./...` | Go `./...` |
| Leg invoked when direct | ciphertext path call | Dart unit | `p2p_service_impl_lan_media_test.dart::libp2pLanLeg_invoked_whenFlagOnAndDirect` | no leg | remove leg | `./scripts/run_test_gates.sh 1to1` | **append `p2p_service_impl_lan_media_test.dart` to `ONE_TO_ONE_TESTS`** (+ `TRANSPORT_TESTS`) — curated arrays, NOT auto-globbed into `1to1`/`transport` |
| Relay-CDN unconditional | upload count==1 on LAN win | Dart unit | `…::relayCdnUpload_unconditional_evenWhenLanLegSucceeds` | preservation (112-P2.4) | gate upload on !lanSuccess | `./scripts/run_test_gates.sh 1to1` | 1to1 |
| Flag off ⇒ no leg | WS unchanged | Dart unit | `…::flagOff_noLibp2pLanLeg_wsPathUnchanged` | flag absent | ignore flag | `./scripts/run_test_gates.sh 1to1` | 1to1 |
| No direct conn ⇒ no leg | leg skipped on circuit | Dart unit | `…::noDirectConn_noLibp2pLanLeg` | no gate | drop precondition | `./scripts/run_test_gates.sh 1to1` | 1to1 |
| Ciphertext-only | path==ciphertext, opaque mime | Dart unit | `…::libp2pLanLeg_streamsCiphertext_neverPlaintext` | no leg | pass plaintext path | `./scripts/run_test_gates.sh 1to1` | 1to1 |
| Refuse iff no non-circuit; coexist sends direct | ≥1 non-circuit gate | Go unit | `…::TestSendLANMedia_RefusesCircuitConn` (+TL5b coexist) | no non-circuit scan | `!hasCircuitConn` negation | `cd go-mknoon && go test ./...` | Go `./...` |
| Stop resets dedup map | post-restart re-deliver ok | Go unit | `…::TestStop_ResetsLanMediaSeenIds` | no map/reset | drop `lanMediaSeenIds` reset | `cd go-mknoon && go test ./...` | Go `./...` |
| `media:lan_received` full payload | staged path+enc+sha+id | Go unit | `…::TestHandleIncomingLANMedia_EmitsFullPayload` | no handler/event | drop staged-path field | `cd go-mknoon && go test ./...` | Go `./...` |
| **Predicate ≥1 non-circuit conn** | coexist circuit+direct ⇒ true | Dart unit | `…::hasNonCircuitDirectConn_trueOnlyForNonCircuitConn` | predicate fictional | reuse `_inferTransportForPeer` | `./scripts/run_test_gates.sh 1to1` | append file to `ONE_TO_ONE_TESTS` |
| **Receive routes (not unknown sink)** | no `UNKNOWN_PUSH` regress | Dart unit | `go_bridge_client_lan_media_test.dart::routesMediaLanReceived_notUnknownSink` | no router case | delete case | `./scripts/run_host_test_gates.sh core-host-all` + `1to1` | AUTO (`test/core/**`); also append to `ONE_TO_ONE_TESTS` |
| **Receive consumer stages `<canonical>.enc`** | feeds decrypt-adopt | Dart unit/integration | `link_incoming_lan_media_test.dart::lanReceived_stagesEnc_andLinks` | no receive consumer | drop enc/encScheme map | `./scripts/run_host_test_gates.sh feature-host-all` | AUTO (`test/features/**`) |
| WS sentinels stay green (preservation) | LocalMediaSender/Server | Dart unit | `test/core/local_discovery/local_media_{sender,server}_test.dart` (EXIST) | preservation | n/a | `./scripts/run_host_test_gates.sh core-host-all` | **AUTO (`test/core/**`) — NOT 1to1** (correct the Existing-Tests claim) |
| Group never uses leg | relay-CDN only | Dart unit | `…::groupMedia_neverInvokesLibp2pLanLeg` | scope preservation | wire group→leg | `./scripts/run_test_gates.sh groups` | **add `p2p_service_impl_lan_media_test.dart` to `GROUP_TESTS`** (TD1's note only appends it to 1to1/transport → else this never runs in `groups`) |
| **Two-phone LAN media** | media-lan + direct + dedup + relay copy + receiver renders | **device-proof** | device smoke (MISSING; author at gates GREEN) | host can't see real NIC/multicast; native dispatch unbuilt | n/a (device) | manual 2-phone, toggle `EnableLibp2pLANMedia` | TRANSPORT array + `classify_path()` if a sim variant added |

## Blind-Spot Sweep

- **Lifecycle / derived-state durability:** the receiver's `lanMediaSeenIds` dedup map must be **reset on
  Stop** (NOT leak across a restart, else a recycled `id` suppresses a legit post-restart delivery) →
  TL7 + TL8 (re-anchored). The media-lan handler does **not** need explicit removal — `Stop` rebuilds a
  fresh host.
- **Receive→render completeness (the headline blind spot found in review):** moving the receive into Go
  changes the receive transport from pure-Dart-WS to a Go event, so the *render* path is a fresh in-memory
  derivation that must reconstruct from `media:lan_received` — locked by TL11 (payload) + TD8 (routing,
  no unknown-event regression) + TD9 (stage-`.enc` + decrypt-adopt). Host-green proves routing/staging;
  **real render is D1** (the Go staged-path must resolve on-device + native EventChannel must emit).
- **Sibling-surface consistency:** the WS/HTTP media server runs **in parallel**; both legs + the
  relay-CDN copy may deliver the same ciphertext blob → receiver **blob-id / `messageId` dedup** keeps
  it correct (proposal §10) — single-render locked at D1 (host fakes can pass via dedup even if the
  live libp2p leg never fired — the canonical false-positive, `FDC-S6:129-134`).
- **Destructive-action side-effects:** none (additive lane). The relay-CDN upload, encrypt-once
  artifact, WS path, account network-side-effect gate are all preserved → TD2/TD3/TD5 + the diff
  guard.
- **Invariant re-verification under new transitions:** the **NET-REL** transport-label invariant
  (`classifyStreamTransport` direct-vs-relay) re-verified under the new media-lan stream → TL6; the
  **media-never-on-live-relay** invariant (§6.2) re-verified for the new byte lane → TL5/TD4.
- **Bridge serialization (proposal §10 L389-392):** `SendLANMedia` streams a potentially large blob
  through the single Dart→Go bridge — it can head-of-line-block the user's **chat** send on the bridge.
  Mitigation: the media leg is best-effort + bounded by `MediaIdleTimeout`/`MediaTimeout`, and the
  relay-CDN copy already streams off the bridge today — so media on the bridge is **not new** (the WS
  HTTP-PUT path is also off the chat-send critical path). Flagged as a **device measurement** in the
  proof profile, not a host test.
- **Metadata-minimization parity:** the WS offer drops `waveform`/`filename` for enc offers
  (`local_media_sender.dart:126-128`); the media-lan header must mirror this (opaque mime, no
  cleartext waveform/filename) — folded into TD5 (opaque mime) + the header spec.

## Invariants (locked by tests)

1. The media-lan protocol is a **NEW** id `/mknoon/media-lan/1.0.0`, **distinct** from the relay
   `/mknoon/media/1.0.0` (TL1).
2. The handler is **flag-gated** (`EnableLibp2pLANMedia`) — present iff on (TL2); Dart leg gated by the
   same flag (TD3).
3. A direct-conn send **stages the ciphertext + verifies SHA-256** and labels `"direct"` (TL3/TL6);
   a mismatch is **rejected** (TL4); a duplicate id is **deduped** (TL7).
4. Media **never rides a circuit/relay conn** — `SendLANMedia` refuses (TL5); the Dart leg only fires
   on a non-circuit direct conn (TD4).
5. The relay-CDN upload stays **unconditional** — the LAN leg never gates/skips it (TD2, the 112-P2.4
   guard).
6. The libp2p-LAN leg streams **ciphertext only**, never plaintext (TD5).
7. **Group media never uses the LAN leg** (TD6); WS/HTTP media + bonsoir untouched (TD3 + Scope Guard).
8. The `lanMediaSeenIds` dedup map is **reset on Stop** so a post-restart re-delivery succeeds (TL8,
   re-anchored — NOT `RemoveStreamHandler`, which `Stop` never does).
9. The leg gate is **"≥1 non-circuit conn"**, so a peer holding a circuit reservation **and** a direct
   conn still sends over the direct (TL5b/TD7); `_inferTransportForPeer` is **forbidden** as the gate.
10. A LAN-received blob is **routed** (`media:lan_received`, not the unknown-event sink) and **rendered**
    via the staged-`<canonical>.enc` → decrypt-adopt pipeline (TL11/TD8/TD9) — single render, blob-id
    dedup with the WS/relay copies.

## Step-By-Step Implementation Plan (RED first; name the seam)

> RED-first. Do not write a production line before its RED test fails for the real reason.
> **Stop-if:** FDC-11 has not device-proven the direct LAN conn **or** FDC-S2 = Option C → **halt and
> shelve** (no direct LAN conn to stream over; FDC-S6 answer = "KEEP WS media server").

1. **Author the Go RED catalog** `media_lan_test.go` (TL1-TL11, incl. TL5b). Confirm each fails for the
   stated reason (missing constant/symbol/handler). Seam names: `MediaLANProtocol`, `MaxLANMediaBytes`,
   `Node.handleIncomingLANMedia`, `Node.SendLANMedia`, `errMediaLANRequiresDirect`, `lanMediaSeenIds`
   dedup map. Harness: `quic_identify_revalidation_test.go` two-host QUIC + `testEventCollector`.
2. **Add the constants + flag** — `config.go`: `MediaLANProtocol`, **`MaxLANMediaBytes`** (state value),
   **reuse `LANDirectIdentifyBudget:97`** (no new `LANMediaOpenBudget`); `feature_flags.go`:
   `EnableLibp2pLANMedia` default **false** **+ `feature_flags_runtime.go` `featureFlagsStatusMap`**.
   Greens TL1 + TL2 compile.
3. **Create `media_lan.go`** — `handleIncomingLANMedia`: read framed header (id/opaque-mime/size/
   sha256) → dedup by id (TL7) → stream body to temp with incremental SHA-256 (reuse
   `copyMediaDownloadToFile` idle-timeout reader) → verify (TL4) → framed ack `{ok,sha256Verified}` →
   emit `media:lan_received` (TL3). `SendLANMedia`: **non-circuit gate** (refuse circuit →
   `errMediaLANRequiresDirect`, TL5) → `NewStream(ctx, pid, MediaLANProtocol)` → write header + stream
   ciphertext (reuse `mediaUploadProgressReader`) → read ack. Greens TL3/TL4/TL5/TL7.
4. **Register in `Start`** — `node.go:~391`: if `flags.EnableLibp2pLANMedia`,
   `h.SetStreamHandler(MediaLANProtocol, n.handleIncomingLANMedia)`. Greens TL2.
5. **Preserve the label** — confirm no change to `classifyStreamTransport`; TL6 green by the media-lan
   conn being non-circuit.
6. **Stop hygiene** — `node.go` `Stop` (`:518`, alongside the FDC-11 `lanDialHandler` teardown
   `:569-575`): **reset `lanMediaSeenIds`** (nil/`make(...)`). **Do NOT add `RemoveStreamHandler`** —
   `Stop` closes + rebuilds a fresh host, so handler removal is a no-op (the un-RED-able original premise).
   Greens TL8 (re-anchored).
7. **Bridge command (5 layers)** — add `MediaLANSend` to the **existing** `go-mknoon/bridge/bridge_lan.go`
   (mirror `HandleLANPeerFound:25` envelope) → `n.SendLANMedia(...)`; `_cmdMap`
   `'media:lan_send': _CmdSpec('mediaLanSend', true)` (`go_bridge_client.dart`); Dart `callP2PLanMediaSend`
   (mirror `callP2PMediaUpload:889`/`_sendMediaTransferWithWatchdog:803`, accepting a stall-only watchdog
   — there is no LAN progress stream yet). **Native `GoBridge.swift`/`GoBridge.kt` cases + gomobile
   rebuild are device-deferred** (schedule at D1; FDC-11's own native legs are likewise unbuilt).
8. **Dart send leg** — author the predicate `hasNonCircuitDirectConn` (`isConnectedToPeer(p) &&
   !_isCircuitOnlyConnected(p)`, reuse FDC-02 `send_chat_message_use_case.dart:1445`; **never**
   `_inferTransportForPeer`) with its TD7 RED. Thread `artifact.contentHash` (`upload_media_use_case.dart:187`)
   into `sendLocalMedia`/`sendMedia` (or compute the sha256 in Go). Then add the leg to `sendLocalMedia`
   (`p2p_service_impl.dart:4661`): inside the existing account gate, `if EnableLibp2pLANMedia &&
   hasNonCircuitDirectConn(peerId)` → `callP2PLanMediaSend(ciphertextPath, opaqueMime, id, sha256)`
   **in addition to** the WS leg; **leave the relay-CDN `uploadMedia` call sites unconditional** (TD2).
   Greens TD1/TD3/TD4/TD5/TD7; TD2/TD6 stay green as preservation locks.
8b. **Dart receive leg (NEW)** — author TD8/TD9 RED. Add a `media:lan_received` case to
   `go_bridge_client.dart` `_handleEvent` (`:615`) → map the payload (TL11) to a `LocalMediaReady` →
   publish on `_incomingLocalMediaController` (`p2p_service_impl.dart:178/428/471`); the existing
   `linkIncomingLocalMedia` (`:65`) → `<canonical>.enc` → `decryptAndPromoteStagedDirectBlob`
   (`download_media_use_case.dart:974`) renders it. Greens TD8/TD9; the receiver-renders half of D1 is
   now reachable. (Stage as `.enc`; never render raw ciphertext.)
9. **Mutation pass** — apply each catalogued mutation (incl. TL5b `!hasCircuitConn`, TL8 drop-reset,
   TL11 drop-staged-path, TD7 `_inferTransportForPeer`), confirm RED, revert.
10. **Gates** — `GOTOOLCHAIN=go1.25.0 go test ./...` + `-race ./node/...`; `go-relay-server` unchanged +
    green; `1to1`, `groups`, `transport` families **+ `core-host-all` + `feature-host-all` globs**
    (WS sentinels + receive leg); `flutter analyze`; `git diff --check`. **Device D1** (incl. native
    dispatch + framework rebuild + receiver-renders) scheduled as the closure gate.

## Risks And Edge Cases

- **FDC-11 / FDC-S2 not landed** — this plan **shelves** (no direct LAN conn / Option C). Hard stop-if.
- **Large blob on the single Go bridge head-of-line-blocks chat sends** (proposal §10 L389-392) —
  bounded by `MediaIdleTimeout`/`MediaTimeout`; media-on-bridge is not new (relay-CDN + WS HTTP-PUT
  already do it); device-measured, not host-asserted.
- **iOS QUIC-over-WiFi NIC behavior** for a multi-MB media stream (path MTU / UDP throttling) —
  host loopback can't prove it → **D1**; if FDC-S2 = Option B, dial TCP (config swap).
- **LAN double-delivery** (WS + libp2p both deliver the same blob) — bounded/harmless via receiver
  blob-id dedup; the *live-wins* claim is device-only (host fakes pass via dedup).
- **Relay-CDN regression (112-P2.4)** — the single biggest correctness risk; locked by TD2 (upload
  stays unconditional).
- **Circuit-conn leak** — a media stream must never open over a relay circuit (128 KB cap) → TL5/TD4.
- **Partial-stream / abort** — receiver must delete the temp on size/hash mismatch (TL4) and not
  promote a partial blob (mirror `local_media_server.dart:271-333`).

## Device/Relay Proof Profile

- **Host-only closure:** TL1-TL11 (incl. TL5b) + TD1-TD9 close host-side (`GOTOOLCHAIN=go1.25.0 go test
  ./...`; `./scripts/run_test_gates.sh 1to1 groups transport`; `./scripts/run_host_test_gates.sh
  core-host-all feature-host-all`). TL3/TL5 use loopback two-host QUIC dials (FDC-S2 M1
  `quic_identify_revalidation_test.go` shape) — they prove the **protocol/framing/verify/refusal/gate**
  seam; TD8/TD9 prove **receive routing + `.enc` staging** with fakes. **Not** closed host-side: the
  native `mediaLanSend` dispatch + the `media:lan_received` EventChannel emit + the Go staged-path
  resolving + the **receiver actually rendering** — those are **D1**.
- **Requires device:** **D1** — two physical phones, one WiFi. Both platforms dial the libp2p LAN conn
  via bonsoir discovery; isolate the libp2p **media** leg by toggling `EnableLibp2pLANMedia` (ON =
  `/mknoon/media-lan/1.0.0`, OFF = WS HTTP-PUT baseline) rather than `DISABLE_LOCAL_DISCOVERY` (which
  kills the shared bonsoir feed both LAN legs depend on). Captures `media:lan_received`,
  transport-label `"direct"`, single-render dedup, relay-CDN copy present, bridge head-of-line timing
  vs a concurrent chat send. **The sim cannot run this** (shares host mDNS/bonsoir → device-only).
  **Relay deploy NOT required** (client-host-only; NET-REL-07 unaffected; relay-CDN `media.go` untouched).
- **Soak feeds FDC-S6:** D1 is a single pass/fail; the **14-day media win-rate + zero-net-new-failure**
  bar that licenses retiring the WS media server is **FDC-S6's** soak (`FDC-S6:212-217`), not this plan.

## Acceptance Gates

```bash
# Go host (core gate) — expected: PASS, +11 new Go-unit tests (TL1-TL11, incl TL5b), 0 regress
# (run under go1.25.0 — quic-go panics under Go 1.26.x)
cd /Users/I560101/Project-Sat/mknoon-2/flutter_app/go-mknoon && GOTOOLCHAIN=go1.25.0 go test ./...

# Go lint + race detector (the shared lanMediaSeenIds dedup map) — expected: PASS, 0 lint, 0 race
cd go-mknoon && make lint
cd go-mknoon && GOTOOLCHAIN=go1.25.0 go test -race ./node/...   # lanMediaSeenIds shared map

# Relay must be UNTOUCHED (preserved; relay-CDN media.go unchanged) — expected: PASS, 0 changed
cd /Users/I560101/Project-Sat/mknoon-2/flutter_app/go-relay-server && go test ./...

# 1:1 family (send leg + predicate TD7 + relay-CDN-unconditional + go_bridge routing TD8) — PASS, +9
#   NOTE: append p2p_service_impl_lan_media_test.dart + go_bridge_client_lan_media_test.dart to ONE_TO_ONE_TESTS
./scripts/run_test_gates.sh 1to1

# core-host-all glob (WS sentinels local_media_{sender,server}_test.dart + go_bridge routing TD8) — PASS, 0 regress
#   These are test/core/** — auto-globbed here, NOT in the 1to1 family (corrects the Existing-Tests claim)
./scripts/run_host_test_gates.sh core-host-all

# feature-host-all glob (the receive consumer TD9 under test/features/**) — PASS
./scripts/run_host_test_gates.sh feature-host-all

# GROUPS preservation gate (group media must stay relay-CDN-only, never touch the LAN leg) — PASS, 0 regress
#   NOTE: add p2p_service_impl_lan_media_test.dart to GROUP_TESTS so TD6 actually runs here
./scripts/run_test_gates.sh groups

# Transport family (host-side; the live two-phone media row is device-only) — expected: PASS
./scripts/run_test_gates.sh transport

# Hygiene
flutter analyze            # expected: 0 new
git diff --check           # expected: clean

# DEVICE CLOSURE (manual, two phones, one WiFi) — NOT host-closable:
#   Both platforms: keep DISABLE_LOCAL_DISCOVERY unset (bonsoir feeds the libp2p LAN dial on both;
#   disabling discovery breaks the path). Isolate the media leg by toggling EnableLibp2pLANMedia
#   (ON = libp2p /mknoon/media-lan/1.0.0, OFF = WS HTTP-PUT baseline); see D1 above. Send one
#   image; assert transport-label "direct" over /mknoon/media-lan/1.0.0 + single render + relay-CDN copy present. (FDC-11 D1 + FDC-S2 M3.)
```

## Known-Failure Interpretation

- A **host-green** run does **NOT** validate LAN media in the field — host fakes can pass via blob-id
  dedup even if the live libp2p leg never fired (proposal §9.1; `FDC-S6:129-134`). "Host-green" means
  the **protocol / framing / SHA-256-verify / circuit-refusal / leg-selection / relay-unconditional**
  logic is correct; the **live-wins** + **iOS-QUIC-over-WiFi multi-MB** claims are **only** closed by
  D1.
- If TL3 is RED **only** on the `ForceReachabilityPrivate` variant but GREEN on public, that is the
  FDC-S2 "reachability-private implicated" escalation, not a test bug (same as FDC-11).
- Pre-existing TRANSPORT/1to1/groups flakes are interpreted per the run's baseline, not this plan.

## Done Criteria

- [x] FDC-S2 verdict written (**Option A**, QUIC, 750ms — every `<from FDC-S2>` replaced).
- [ ] FDC-11 direct LAN conn **device-proven** (D1 GREEN both platforms) — still owed.
- [ ] (If A/B) **TL1-TL11 (incl. TL5b) + TD1-TD9** authored RED-first, GREEN, each mutation re-reds.
- [ ] **Send leg**: `hasNonCircuitDirectConn` authored (≥1-non-circuit semantics, TD7);
      `_inferTransportForPeer` NOT reused; sha256 threaded into the leg header.
- [ ] **Receive leg**: `media:lan_received` routed in `go_bridge_client` (no unknown-event regression,
      TD8) + consumed into `linkIncomingLocalMedia` → `<canonical>.enc` → decrypt-adopt (TD9).
- [ ] **Bridge**: `MediaLANSend` in the existing `bridge_lan.go` + `_cmdMap` + `callP2PLanMediaSend`;
      native `GoBridge.swift`/`.kt` dispatch + EventChannel emit + gomobile rebuild **scheduled at D1**.
- [ ] `GOTOOLCHAIN=go1.25.0 go test ./...` PASS; `go-relay-server` + `media.go` unchanged + PASS.
- [ ] `./scripts/run_test_gates.sh 1to1` PASS (+9); `groups` PASS (0 regress — TD6 added to `GROUP_TESTS`);
      `transport` host-side PASS; **`core-host-all` + `feature-host-all`** PASS (WS sentinels + receive leg).
- [ ] No `LANMediaOpenBudget` minted (reuse `LANDirectIdentifyBudget`); `featureFlagsStatusMap` updated;
      `MaxLANMediaBytes` introduced with a stated value.
- [ ] `flutter analyze` 0-new; `git diff --check` clean.
- [ ] Every new **exported** Go identifier carries a doc comment — `MediaLANProtocol`, the send func
      (`MediaLANSend`/`SendLANMedia`), `handleIncomingLANMedia`, `errMediaLANRequiresDirect` —
      `cd go-mknoon && make lint` clean (godoc/revive on exported symbols).
- [ ] Relay-CDN upload **unconditional**, encrypt-once artifact, WS/HTTP media + bonsoir, account gate,
      `classifyStreamTransport`, group media path all **unchanged** (preserved-sentinel diff review).
- [ ] D1 device smoke scheduled (two-phone, `DISABLE_LOCAL_DISCOVERY`) — DEFERRED-not-waived; feeds the
      FDC-S6 14-day media soak.
- [ ] (If C / FDC-11 not landed) plan shelved; WS/HTTP LAN media remains the byte path; doc marked
      superseded; FDC-S6 media verdict = "KEEP".

## Scope Guard (hard Do-not)

- **Do NOT touch the group media path** — group media is **relay-CDN only** (`callP2PMediaUpload`); it
  has **no** LAN byte path. FDC-15 adds the libp2p-LAN leg **only** to the 1:1 `sendLocalMedia` path.
  Group screens/use-cases, `group_*` media, and the group preservation gate must be **untouched**
  (TD6 + `./scripts/run_test_gates.sh groups`).
- **Do NOT gate / skip / short-circuit the relay-CDN `uploadMedia`** on the LAN leg — re-introducing
  the 112-Phase-2.4 dangling-attachment `continue` is forbidden (TD2).
- **Do NOT reuse `/mknoon/media/1.0.0`** (the relay-CDN protocol) — use the new
  `/mknoon/media-lan/1.0.0`.
- **Do NOT open the media stream over a circuit/relay conn** (proposal §6.2 128 KB cap) — non-circuit
  only.
- **Do NOT re-encrypt media** — reuse the existing `EncryptedMediaArtifact` ciphertext.
- **Do NOT remove or alter** `LocalMediaSender`/`LocalMediaServer`/`LocalWsServer`/bonsoir — they stay
  as the parallel fallback (removal is FDC-S6's later verdict, not this plan).
- **Do NOT edit `go-relay-server/` or `media.go`** (relay-CDN unchanged; NET-REL-07; no relay deploy).
- **Naming contract (pin):** the LAN media send path has ONE canonical name per layer — bridge cmd =
  **`MediaLANSend`** → node func = **`Node.SendLANMedia`** → Dart binding = **`callP2PLanMediaSend`**
  (Dart keeps `Lan` per the Flutter acronym convention; Go exports the acronym all-caps as `LAN`). The
  bridge cmd `MediaLANSend` and the node func `SendLANMedia` are the canonical exported pair, and
  `callP2PLanMediaSend` is the only `Lan`-cased identifier on this path. Use exactly these three names
  everywhere (Real Scope, Files To Inspect, Step 7, TL3).
- **Do NOT flip `ForceReachabilityPrivate`** in production.
- **The `lanMediaSeenIds` dedup map MUST be mutex-guarded** — both incoming streams and `Stop`'s
  reset touch it concurrently; an unguarded map is a data race (caught by `go test -race ./node/...`,
  TL9).
- **`SendLANMedia`'s `NewStream` context MUST derive from `n.ctx`** (not `context.Background()`) so
  `Stop` cancels any in-flight media dial — mirror `openChatStream`'s context lineage (TL8 lifecycle).
- **The bridge send entrypoint goes in the EXISTING `go-mknoon/bridge/bridge_lan.go`** (FDC-11 already
  created it, 56 lines — the "NEW file" wording was stale) — ADD `MediaLANSend` beside
  `HandleLANPeerFound`; do NOT grow the 2880-line `bridge.go` (supersedes the `bridge.go` location named
  in Real Scope / Files To Inspect / Step 7). Remember it is **5 layers**: Go + `_cmdMap` +
  `GoBridge.swift` + `GoBridge.kt` + gomobile rebuild (the native two are **device-deferred**).
- **Do NOT reuse `_inferTransportForPeer` (`p2p_service_impl.dart:3401`) for the leg gate** — it
  short-circuits to `'relay'` on the FIRST `/p2p-circuit` multiaddr, so a peer holding a circuit
  reservation **and** a fresh LAN-direct conn (the exact FDC-15 window) is mis-read as `'relay'` and the
  leg never fires. Use the **"≥1 non-circuit conn"** predicate (`!_isCircuitOnlyConnected`, FDC-02
  `send_chat_message_use_case.dart:1445`); locked by TD7.
- **Do NOT leave the receive leg as a Go-only emit** — `media:lan_received` MUST be routed in
  `go_bridge_client.dart` `_handleEvent` (else it hits `_recordUnknownPushEvent` and can regress the 1:1
  gate) and consumed into the `linkIncomingLocalMedia` → `<canonical>.enc` → decrypt-adopt pipeline
  (TD8/TD9). A staged ciphertext must never be rendered raw (stage as `.enc`).

## Accepted Differences

- TL3/TL5 use **loopback two-host** dials (FDC-S2 M1 shape) — they prove the media protocol/framing/
  verify/refusal **seam**, not real-NIC/iOS multi-MB behavior; that residue is **D1** by design.
- `classifyStreamTransport` cannot distinguish QUIC-direct vs TCP-direct (`node.go:129-135`) — tests
  read the **raw multiaddr** (`isCircuitAddr`) for the direct-vs-circuit assertion.
- The libp2p-LAN leg and the WS leg may **both** stream the same blob during the parallel-run window —
  bounded/harmless via receiver blob-id dedup; collapsing to one leg is **FDC-S6's** retirement
  decision, not this plan.

## Dependency Impact

- **Gated by FDC-11** (direct LAN conn must exist + be device-proven) — **still open** — and **FDC-S2** —
  **RESOLVED 2026-06-27** (Option A, QUIC, identify budget **750ms**). FDC-11's device-proof is the remaining
  hard precondition.
- **Enables FDC-S6** — FDC-15 is the named "media-over-libp2p-LAN" prerequisite whose existence +
  device-proof + 14-day soak lets FDC-S6 issue a "retire the WS media server" verdict
  (`FDC-S6:145,212-217`). FDC-15 does **not** itself retire anything.
- **Shares Go-host files** `node.go` / `config.go` / `feature_flags.go` / `feature_flags_runtime.go` /
  **`bridge_lan.go`** (FDC-11 created it) with **FDC-11** (mDNS) and **FDC-12** (DCUtR), and shares
  **`go_bridge_client.dart`** (`_handleEvent`/`_cmdMap`) + `p2p_service_impl.dart` with the same siblings
  → **collision; run after FDC-11** (consumes its direct conn + its `bridge_lan.go`/native-dispatch
  groundwork). New `media_lan.go` + `media_lan_test.go` are this plan's own files.
- **Inherits FDC-11's unbuilt native bridge leg** — `GoBridge.swift`/`.kt` have no `lan`/`media-lan` case
  yet; FDC-15 must add the `mediaLanSend` dispatch **and** the `media:lan_received` EventChannel emit and
  rebuild the gomobile framework (device-deferred, closed at D1).
- **No migration**, **no relay deploy**, **no relay-CDN (`media.go`) change**, **no group change**,
  **no chat `sendChatMessage` change** (path decision stays in Dart; Go adds a media byte lane).
