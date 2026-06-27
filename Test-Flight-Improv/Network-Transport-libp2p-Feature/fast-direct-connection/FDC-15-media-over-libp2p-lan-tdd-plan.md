# FDC-15 — 1:1 media over a peer-authenticated libp2p LAN stream  (New Feature)

Status: awaiting-review — **FDC-S2 RESOLVED (Option A, QUIC, 750ms; `<from FDC-S2>` values threaded)**; STILL gated by **FDC-11 device-proof**.

> # ⚠ DRAFT — FDC-S2 RESOLVED (Option A); STILL gated by FDC-11 (direct LAN conn device-proven)
> **FDC-S2 closed Option A** (2026-06-27): direct LAN **QUIC** + identify is reliable (budget **750ms**), so
> the `<from FDC-S2>` transport/budget values are now threaded below (QUIC, `/tcp` fallback lane,
> `LANMediaOpenBudget = 750ms`). The Option-C "shelve this plan / KEEP the WS media server" branch did
> **NOT** fire. **This plan still cannot finalize until FDC-11 ships a device-proven direct libp2p LAN
> connection** (D1 GREEN on both platforms) — FDC-15 streams media *over* that conn, so the
> `EnableLibp2pLANMedia` flag stays **default-OFF until FDC-11 lands + is device-proven**. The **Go
> protocol/framing/handler/SHA-256-verify** core and the **Dart leg-selection /
> relay-CDN-still-unconditional** guards are **host-testable now**; the **real two-phone LAN media
> transfer** is the **device-only** closure gate.

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
- **(Bridge)** NEW bridge command `MediaLANSend` (`go-mknoon/bridge/bridge.go`) + Dart
  `callP2PLanMediaSend` (`p2p_bridge_client.dart`), mirroring `MediaUpload` framing/watchdog.
- **(Dart)** behind flag `EnableLibp2pLANMedia` (default per FDC-S2), `sendLocalMedia`
  (`p2p_service_impl.dart:4184`) gains a **libp2p-LAN leg**: when the flag is on **and** the peer holds
  a **direct (non-circuit) libp2p conn** (FDC-11), invoke `callP2PLanMediaSend` with the **ciphertext
  artifact path** (never plaintext) **in addition to / raced with** the WS HTTP-PUT; the relay-CDN
  `uploadMedia` stays **unconditional** at the call sites. Idempotent by blob id / SHA-256.
- **(Go)** `Stop` removes the `MediaLANProtocol` handler (lifecycle).
- New config constants (LAN media open/identify budget = `750ms` (FDC-S2 Option A), idle/stall reuse of
  `MediaIdleTimeout`) and the feature flag.

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
- `go-mknoon/node/config.go` — add `MediaLANProtocol`, `LANMediaOpenBudget = 750ms` (FDC-S2 Option A); existing
  `MediaProtocol:24`, `MediaTimeout:34`, `MediaIdleTimeout:35`, `PeerDialTimeout:29`.
- `go-mknoon/node/node.go` — `SetStreamHandler` block `:391-392` (add media-lan handler, flag-gated),
  `Stop` (`:471+`, remove handler), `openChatStream`/`SendMessageWithTransport` `:1291-1440` (framing +
  `classifyStreamTransport` pattern to mirror), `Node` struct fields `:39-109`.
- **NEW** `go-mknoon/node/media_lan.go` — `handleIncomingLANMedia` (framed header → streamed SHA-256
  verify → staged temp → framed ack → `media:lan_received`), `SendLANMedia` (non-circuit gate + header
  + ciphertext stream + ack), `isCircuitAddr` reuse.
- `go-mknoon/node/feature_flags.go` — add `EnableLibp2pLANMedia` to `FeatureFlags` +
  `DefaultFeatureFlags()` (default = **false** — S2 = Option A is satisfied; flip true once FDC-11 ships + is device-proven).
- `go-mknoon/node/media.go` — `mediaUploadProgressReader:118`, `copyMediaDownloadToFile:290`,
  `sendMediaRequest:267`, `setStreamDeadline`, framed read/write helpers to reuse.
- `go-mknoon/bridge/bridge.go` — `MediaUpload:1426-1458` pattern to mirror for `MediaLANSend`.

**Dart (production)**
- `lib/core/services/p2p_service_impl.dart` — `sendLocalMedia:4184-4216` (add the libp2p-LAN leg
  inside the existing account-gate), `isLocalPeer`/`isConnectedToPeer`/a non-circuit-direct predicate
  (`:4092-4097`).
- `lib/core/bridge/p2p_bridge_client.dart` — `_sendMediaTransferWithWatchdog:676`,
  `callP2PMediaUpload:791/837` (mirror for `callP2PLanMediaSend`).
- `lib/features/conversation/application/upload_media_use_case.dart` — `EncryptedMediaArtifact:142`,
  `prepareEncryptedMediaArtifact:176`, `uploadMedia:224` (the **unconditional** relay-CDN upload —
  must stay).
- `lib/features/share/application/share_batch_delivery_coordinator.dart:290-330` — the encrypt-once
  LAN-then-unconditional-relay pattern to mirror.

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
  `local_ws_server_*_test.dart` (1to1 family) — **exist**; the WS path locks to keep green
  (preservation).
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
- **Tier:** Go unit (two in-process hosts, `/ip4/127.0.0.1/udp/0/quic-v1` — QUIC per FDC-S2 Option A; mirror
  `holepunch_feasibility_test.go`). **Shape:** hostA `host.Connect`s hostB (non-circuit); write a
  temp ciphertext blob + its sha256; `A.SendLANMedia(Bid, path, id, opaqueMime, size, sha256)`.
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

### TL5 — SendLANMedia REFUSES a circuit (relay) conn — media never on the live relay (critical invariant)
- **file::name** `…::TestSendLANMedia_RefusesCircuitConn`
- **Tier:** Go unit (a circuit/limited conn to B, or a conn whose only addr `isCircuitAddr`; if a full
  circuit harness is infeasible host-side, assert the **non-circuit precondition** is enforced before
  `NewStream`). **Shape:** A holds only a circuit conn to B; call `SendLANMedia`.
- **RED-on-HEAD:** no non-circuit gate exists.
- **GREEN:** returns a typed `errMediaLANRequiresDirect`; **no** `MediaLANProtocol` stream is opened
  over the circuit; no bytes written (proposal §6.2 128 KB cap honored).
- **Mutation:** remove the `isCircuitAddr` refusal (open over any conn) → stream opens over circuit →
  RED.
- **Discriminator:** the typed refusal error + zero stream-open over a circuit addr.

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

### TL8 — Stop removes the media-lan handler (lifecycle durability)
- **file::name** `…::TestStop_RemovesMediaLANHandler`
- **Tier:** Go unit. **Shape:** Start (flag on) → `Stop()` → assert handler removed; a subsequent Start
  re-registers cleanly (no double-register panic), mirror `node_test.go` reconnect hygiene.
- **RED-on-HEAD:** no handler to remove.
- **GREEN:** `RemoveStreamHandler(MediaLANProtocol)` called; clean restart.
- **Mutation:** drop the `RemoveStreamHandler` in `Stop` → leak / double-register on restart → RED.

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
  enters `io.CopyN` (guards disk-fill / OOM from a malicious header; mirror the receiver size check
  `local_media_server.dart:202` / `handleUpload`).
- **Mutation:** remove the max-size check (trust the header `size`) → `io.CopyN` runs on the oversize
  header → RED.
- **Discriminator:** zero bytes streamed + no temp file created when `size > max`.

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
| Stop removes handler | clean restart | Go unit | `…::TestStop_RemovesMediaLANHandler` | no handler | drop RemoveStreamHandler | `cd go-mknoon && go test ./...` | Go `./...` |
| Concurrent dup-id dedup (-race) | one lan_received, race-clean | Go unit (`-race`) | `…::TestHandleIncomingLANMedia_ConcurrentDuplicateId_RaceClean` | unguarded `lanMediaSeenIds` map | drop the mutex | `cd go-mknoon && go test -race ./node/...` | Go `./node/...` `-race` |
| Oversize header rejected pre-CopyN | no temp, no `io.CopyN` | Go unit | `…::TestHandleIncomingLANMedia_OversizeHeader_RejectedBeforeCopy` | no size-bound guard | trust header `size` | `cd go-mknoon && go test ./...` | Go `./...` |
| Leg invoked when direct | ciphertext path call | Dart unit | `p2p_service_impl_lan_media_test.dart::libp2pLanLeg_invoked_whenFlagOnAndDirect` | no leg | remove leg | `./scripts/run_test_gates.sh 1to1` | **append `p2p_service_impl_lan_media_test.dart` to `ONE_TO_ONE_TESTS`** (+ `TRANSPORT_TESTS`) — curated arrays, NOT auto-globbed into `1to1`/`transport` |
| Relay-CDN unconditional | upload count==1 on LAN win | Dart unit | `…::relayCdnUpload_unconditional_evenWhenLanLegSucceeds` | preservation (112-P2.4) | gate upload on !lanSuccess | `./scripts/run_test_gates.sh 1to1` | 1to1 |
| Flag off ⇒ no leg | WS unchanged | Dart unit | `…::flagOff_noLibp2pLanLeg_wsPathUnchanged` | flag absent | ignore flag | `./scripts/run_test_gates.sh 1to1` | 1to1 |
| No direct conn ⇒ no leg | leg skipped on circuit | Dart unit | `…::noDirectConn_noLibp2pLanLeg` | no gate | drop precondition | `./scripts/run_test_gates.sh 1to1` | 1to1 |
| Ciphertext-only | path==ciphertext, opaque mime | Dart unit | `…::libp2pLanLeg_streamsCiphertext_neverPlaintext` | no leg | pass plaintext path | `./scripts/run_test_gates.sh 1to1` | 1to1 |
| Group never uses leg | relay-CDN only | Dart unit | `…::groupMedia_neverInvokesLibp2pLanLeg` | scope preservation | wire group→leg | `./scripts/run_test_gates.sh groups` | groups |
| **Two-phone LAN media** | media-lan + direct + dedup + relay copy | **device-proof** | device smoke (MISSING; author at gates GREEN) | host can't see real NIC/multicast | n/a (device) | manual 2-phone, `DISABLE_LOCAL_DISCOVERY` | TRANSPORT array + `classify_path()` if a sim variant added |

## Blind-Spot Sweep

- **Lifecycle / derived-state durability:** the media-lan handler must be **removed on Stop** and
  re-registered cleanly on Start → TL8; the receiver's duplicate-id dedup map must be bounded / not
  leak across Stop → TL7 + TL8.
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
8. The handler is **removed on Stop** and re-registers cleanly (TL8).

## Step-By-Step Implementation Plan (RED first; name the seam)

> RED-first. Do not write a production line before its RED test fails for the real reason.
> **Stop-if:** FDC-11 has not device-proven the direct LAN conn **or** FDC-S2 = Option C → **halt and
> shelve** (no direct LAN conn to stream over; FDC-S6 answer = "KEEP WS media server").

1. **Author the Go RED catalog** `media_lan_test.go` (TL1-TL8). Confirm each fails for the stated
   reason (missing constant/symbol/handler). Seam names: `MediaLANProtocol`,
   `Node.handleIncomingLANMedia`, `Node.SendLANMedia`, `errMediaLANRequiresDirect`,
   `lanMediaSeenIds` dedup map.
2. **Add the constant + flag** — `config.go`: `MediaLANProtocol`, `LANMediaOpenBudget = 750ms` (FDC-S2 Option A);
   `feature_flags.go`: `EnableLibp2pLANMedia` default **false** (flip true after FDC-11 ships + device-proof). Greens TL1 + TL2 compile.
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
6. **Remove on Stop** — `node.go` `Stop`: `h.RemoveStreamHandler(MediaLANProtocol)`; reset
   `lanMediaSeenIds`. Greens TL8.
7. **Bridge command** — `bridge.go` `MediaLANSend` (mirror `MediaUpload:1429-1458`) →
   `n.SendLANMedia(...)`; Dart `callP2PLanMediaSend` (mirror `callP2PMediaUpload`/
   `_sendMediaTransferWithWatchdog`).
8. **Author the Dart RED leg tests** (TD1-TD6). Then add the libp2p-LAN leg to `sendLocalMedia`
   (`p2p_service_impl.dart:4184`): inside the existing account gate, `if EnableLibp2pLANMedia &&
   hasNonCircuitDirectConn(peerId)` → `callP2PLanMediaSend(ciphertextPath, opaqueMime, id, sha256)`
   **in addition to** the WS leg; **leave the relay-CDN `uploadMedia` call sites unconditional**
   (TD2). Greens TD1/TD3/TD4/TD5; TD2/TD6 stay green as preservation locks.
9. **Mutation pass** — apply each catalogued mutation, confirm RED, revert.
10. **Gates** — `cd go-mknoon && go test ./...`; `go-relay-server` unchanged + green; `1to1`, `groups`,
    `transport` families; `flutter analyze`; `git diff --check`. **Device D1** scheduled as the
    closure gate.

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

- **Host-only closure:** TL1-TL8 + TD1-TD6 close host-side (`cd go-mknoon && go test ./...`;
  `./scripts/run_test_gates.sh 1to1 groups`). TL3/TL5 use loopback two-host dials (FDC-S2 M1 shape) —
  they prove the **protocol/framing/verify/refusal seam**, not real-NIC behavior.
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
# Go host (core gate) — expected: PASS, +8 new Go-unit tests, 0 regress
cd /Users/I560101/Project-Sat/mknoon-2/flutter_app/go-mknoon && go test ./...

# Go lint + race detector (the shared lanMediaSeenIds dedup map) — expected: PASS, 0 lint, 0 race
cd go-mknoon && make lint
cd go-mknoon && go test -race ./node/...   # lanMediaSeenIds shared map

# Relay must be UNTOUCHED (preserved; relay-CDN media.go unchanged) — expected: PASS, 0 changed
cd /Users/I560101/Project-Sat/mknoon-2/flutter_app/go-relay-server && go test ./...

# 1:1 family (the libp2p-LAN media leg + relay-CDN-unconditional guards) — expected: PASS, +6
./scripts/run_test_gates.sh 1to1

# GROUPS preservation gate (group media must stay relay-CDN-only, never touch the LAN leg) — PASS, 0 regress
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
- [ ] (If A/B) TL1-TL8 + TD1-TD6 authored RED-first, GREEN, each mutation re-reds.
- [ ] `cd go-mknoon && go test ./...` PASS; `go-relay-server` + `media.go` unchanged + PASS.
- [ ] `./scripts/run_test_gates.sh 1to1` PASS (+6); `groups` PASS (0 regress — scope); `transport`
      host-side PASS.
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
- **The bridge send entrypoint goes in a NEW `go-mknoon/bridge/bridge_lan.go`** — do NOT grow the
  2878-line `bridge.go`; keep the new command + its watchdog in the new file (supersedes the
  `bridge.go` location named in Real Scope / Files To Inspect / Step 7).

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
- **Shares Go-host files** `node.go` / `config.go` / `feature_flags.go` with **FDC-11** (mDNS) and
  **FDC-12** (DCUtR) → **collision; run after FDC-11** (consumes its direct conn). New `media_lan.go`
  + `media_lan_test.go` are this plan's own files.
- **No migration**, **no relay deploy**, **no relay-CDN (`media.go`) change**, **no group change**,
  **no chat `sendChatMessage` change** (path decision stays in Dart; Go adds a media byte lane).
