# NET-REL-01 — LAN / Same-WiFi Delivery Reliability — IMPLEMENTATION PLAN

Prepared: 2026-05-29
Status: **DECIDED** — this document converts the OPTIONS in `01-lan-wifi-reliability.md`
into concrete, ordered, file-disjoint-where-possible implementation units.
Lead designer sign-off. All anchors verified against current source (file:line).

Companion doc (problem + acceptance criteria + test plan): `01-lan-wifi-reliability.md`.

---

## Decisions (summary)

| Problem | Decision | Rationale (short) |
|---|---|---|
| **P1** | **Option A — discover-on-send probe**, bounded by the existing `interactiveLocalBudget = 1500ms`. | A is the only option that fixes the cold-open window without continuous battery/mDNS cost (B/C). It is purely additive at the transport layer and the 1500ms cap preserves the negative control. |
| **P2** | **TTL = 30s** on `LocalPeer.discoveredAt`, filtered at read in `getLocalPeer`/`isLocalPeer`; **fast WS connect timeout = 800ms**; **periodic re-resolution every 20s** for entries older than 15s. | 30s comfortably spans a typical mDNS announce cadence on home/office WiFi while expiring a peer that walked away within ~1 conversation turn. 800ms connect cap means a stale `host:port` fails inside the 1500ms budget instead of burning all of it. |
| **P3** | **Two-part fix.** (a) Wire `configureMediaServer` in `main.dart` gated by `!kDisableLocalDiscovery`. (b) Subscribe to `mediaReadyStream` in `P2PServiceImpl`, persist via `persistMedia`, and surface on a **new typed `incomingLocalMediaStream`** (NOT `messageStream` — `ChatMessage` has no media fields). | Send side already works; both receive halves are required. A typed stream with an interface default no-op limits fake/mock churn. |
| **P4** | **Feasible scope only.** LAN telemetry feed already exists and is correct — do NOT rebuild it. Add a **`suspectedPermissionDenied` heuristic** field to `LanAvailabilitySnapshot` (discovery active + zero peers for ≥ 12s), surfaced in the diagnostics card. Document that no accurate iOS Local-Network permission API exists without heavy native code. | bonsoir 5.1.0 does not surface permission status; no permission plugin is in the tree. The zero-peers heuristic is the only pure-Dart signal; it is labelled "suspected", never "denied". |
| **P5** | **ACCEPT + DOCUMENT.** Plaintext `ws://` exposes `from`/`to` peer IDs and nonce on the LAN; message bodies stay ML-KEM E2E-encrypted. No code change. | Metadata-only leak on shared WiFi; cost/complexity of Noise-over-WS is not justified for the current threat model. Documented decision, revisit if threat model changes. |
| **P6** | **ACCEPT + DOCUMENT.** LAN routing trusts the advertised TXT `peerId`; delivery authenticity rests on the inner E2E envelope. No code change. | E2E envelope already binds content to identity; a forged TXT peerId can mis-route but cannot read/forge content. Documented. |

### Open-question answers (doc lines 330-341)
1. **TTL:** 30s (see P2). 2. **Discover-on-send scope:** always-on but bounded (1500ms) — coverage > marginal battery, and the probe only runs on an actual send. 3. **Local media model:** reuse the existing local media server (token-auth + streaming SHA-256), relay-CDN fallback unchanged; fallback trigger = `sendLocalMedia` returns false. 4. **ws:// metadata:** accept (P5). 5. **Groups on LAN:** stay 1:1-only (out of scope; NET-REL-03).

---

## Build order (sequential — units share core files)

```
U-P2-ttl  →  U-P1-discover-on-send  →  U-P3-media  →  U-P4-telemetry
```

Shared core files that MUST be edited in this order to avoid conflicting hunks:
- `lib/core/local_discovery/local_discovery_service.dart` (P2 adds `LocalPeer.isStale`/`resolvePeer` abstract; P1 reuses; P3 nothing).
- `lib/core/local_discovery/bonsoir_discovery_service.dart` (P2 TTL+re-resolution; P1 `resolvePeer` impl).
- `lib/core/local_discovery/local_p2p_service.dart` (P1 `resolvePeer` passthrough; P3 nothing new).
- `lib/core/services/p2p_service.dart` + `p2p_service_impl.dart` (P1 `discoverLocalPeer`; P3 `incomingLocalMediaStream`).
- `lib/core/debug/transport_metrics.dart` (P4 only).

**Invariant preserved across ALL units:** every existing caller signature stays intact, and the parallel-race negative control holds — the DIRECT future is always added unconditionally; the LOCAL future never blocks or delays it; any new local work is `.timeout`-wrapped to ≤ `interactiveLocalBudget` (1500ms). `DisabledLocalDiscoveryService` short-circuits every new method so test builds never report `local`.

---

## U-P2-ttl — TTL / freshness on the discovered-peers map

**Goal (P2):** stale `host:port` entries are skipped/expired so a departed peer fails fast (≤ 800ms WS connect) instead of burning the full 1500ms; periodic re-resolution refreshes live entries.

### Files & changes

1. **`lib/core/local_discovery/local_discovery_service.dart`**
   - Add a TTL constant + freshness helper to `LocalPeer` (after the ctor, line 13):
     ```dart
     static const Duration ttl = Duration(seconds: 30);
     bool isStale(DateTime nowUtc) => nowUtc.difference(discoveredAt) > ttl;
     ```
   - Do NOT change the `const` ctor shape (recon: positional/required preserved).

2. **`lib/core/local_discovery/bonsoir_discovery_service.dart`**
   - **Freshness filter at read** (the load-bearing fix). Replace `getLocalPeer` (`:139`) and `isLocalPeer` (`:136`):
     ```dart
     @override
     LocalPeer? getLocalPeer(String peerId) {
       final p = _peers[peerId];
       if (p == null) return null;
       if (p.isStale(DateTime.now().toUtc())) { _peers.remove(peerId); return null; }
       return p;
     }
     @override
     bool isLocalPeer(String peerId) => getLocalPeer(peerId) != null;
     ```
     This immediately fixes the send path: `LocalP2PService.sendMessage` guard (`:90-91`) calls `getLocalPeer`, and the race gate (`send_chat_message_use_case.dart:385`) calls `isLocalPeer`.
   - **Retain BonsoirService handle for re-resolution.** Add `final _resolvable = <String, BonsoirService>{};` near `:19`. In `discoveryServiceFound` (`:64-70`), before `service.resolve(...)`, store the handle. In `discoveryServiceLost` (`:98`), `_resolvable.remove(peerId)`. In `stopAdvertising` (`:122`), `_resolvable.clear()`.
   - **Periodic re-resolution.** Add `Timer? _refreshTimer;` near `:17`. Start in `startAdvertising` after `:53`:
     ```dart
     _refreshTimer = Timer.periodic(const Duration(seconds: 20), (_) {
       final now = DateTime.now().toUtc();
       for (final e in _peers.entries.toList()) {
         if (now.difference(e.value.discoveredAt) > const Duration(seconds: 15)) {
           final svc = _resolvable[e.key];
           final disc = _discovery;
           if (svc != null && disc != null) unawaited(svc.resolve(disc.serviceResolver));
         }
       }
     });
     ```
     Cancel + null in `stopAdvertising` (`:113-126`). The re-resolve completes through the existing `discoveryServiceResolved` path (`:79-85`), which overwrites `discoveredAt` → freshness refreshed for free.
   - **Fast connect timeout (pair with TTL).** In `local_ws_server.dart`, bound the outbound `WebSocket.connect('ws://$host:$port')` (around the pooled-connect block, `:258-338`) with `.timeout(const Duration(milliseconds: 800))` so a stale `host:port` fails inside the 1500ms budget. Confirm an existing connect-timeout is not already shorter; if one exists, leave it.
   - **`printLogs:false` invariant:** the re-resolution path reuses the existing `_discovery.serviceResolver` and `BonsoirService` objects — no new `BonsoirDiscovery`/`BonsoirBroadcast` is constructed, so the documented native-logging crash mitigation is unaffected. Do NOT introduce any new bonsoir object without `printLogs:false`.

3. **`lib/core/local_discovery/disabled_local_discovery_service.dart`** — no change (already returns null/false; stale check is a no-op).

### Caller-contract preservation
- `getLocalPeer`/`isLocalPeer` signatures unchanged. `discoveredPeers`/`discoveredPeerCount` (census at `p2p_service_impl.dart:196,445`) now naturally drop stale entries on the next read — acceptable and desirable (count reflects fresh-only). Document this in the diagnostics card comment.
- `discoveredAt` comparisons use `DateTime.now().toUtc()` to match the UTC write at `bonsoir_discovery_service.dart:83` (recon risk).

### Tests enabled → maps to doc **U2** + acceptance criterion **#2**
- **TTL predicate unit test** (`test/core/local_discovery/`): construct `LocalPeer(discoveredAt: now-31s)`, assert `isStale(now) == true`; `now-29s` → false. Plain host test.
- **U2 (use-case):** in `send_chat_message_use_case_test.dart` race group, drive the in-file `FakeP2PService` so `isLocalPeer` returns false for a stale peer (mirror P2 behaviour) → assert `localSendCallCount == 0` and the call completes well under 1500ms (direct carries it). Per recon, the boolean fake cannot prove timing alone; for the "does not burn 1500ms" timing assertion use the integration fake's `localAckDelay` or a bespoke inline `P2PService` (pattern: `_SlowLocalFastDirectP2PService` at `:2786`).
- **I2 stale host:port** (`integration_test/wifi_transport_test.dart`, extend F2/F9): `addPeer` with a dead port → `sendMessage` returns false within ~800ms (fast connect timeout). Real-stack also via `test/core/local_discovery/local_p2p_service_test.dart` (`FakeLocalDiscoveryService.addPeer`).

---

## U-P1-discover-on-send — bounded probe at send time

**Goal (P1):** sending to a peer not yet in `_peers` kicks a bounded mDNS resolve that joins the race if it resolves within the local budget. Cold-open peers use LAN.

### Files & changes

1. **`lib/core/local_discovery/local_discovery_service.dart`** — add to the abstract interface (after `getLocalPeer`, `:148`):
   ```dart
   /// On-demand bounded resolve. Returns the peer once it resolves within
   /// [timeout], or null. Implementations must complete within [timeout].
   Future<LocalPeer?> resolvePeer(String peerId, {required Duration timeout});
   ```

2. **`lib/core/local_discovery/bonsoir_discovery_service.dart`** — implement `resolvePeer`:
   - Fast path: `final fresh = getLocalPeer(peerId); if (fresh != null) return fresh;` (already-fresh-in-map short-circuit).
   - Otherwise register a `Completer<LocalPeer?>` in a new `_pendingResolves = <String, Completer<LocalPeer?>>{}` map keyed by peerId; in `discoveryServiceResolved` (`:79-85`), after the `_peers[peerId] = ...` write, complete any matching pending completer with the new `LocalPeer`. Await the completer with `.timeout(timeout, onTimeout: () => null)`; in a `finally`, remove the completer from the map (recon risk: clean up to avoid leaking completers). If the peer was never `found` by mDNS, the completer simply times out to null.
   - Self/`_ownPeerId` and null-host guards already short-circuit in `discoveryServiceResolved`.

3. **`lib/core/local_discovery/disabled_local_discovery_service.dart`** — `Future<LocalPeer?> resolvePeer(...) async => null;` (preserves negative control in test builds).

4. **`lib/core/local_discovery/local_p2p_service.dart`** — add passthrough + a `discoverPeer` helper used by the transport API:
   ```dart
   Future<bool> discoverLocalPeer(String peerId, {required Duration timeout}) async =>
       (await _discovery.resolvePeer(peerId, timeout: timeout)) != null;
   ```

5. **`lib/core/services/p2p_service.dart`** — add to the abstract interface (after `isLocalPeer`, `:169`):
   ```dart
   /// Bounded on-demand local discovery. Returns true if the peer became
   /// visible on the LAN within [timeout]. Default no-op for non-local impls.
   Future<bool> discoverLocalPeer(String peerId, {required Duration timeout}) async => false;
   ```
   (Default body avoids breaking every fake/mock; recon-recommended pattern.)

6. **`lib/core/services/p2p_service_impl.dart`** — implement near `isLocalPeer` (`:2989`):
   ```dart
   @override
   Future<bool> discoverLocalPeer(String peerId, {required Duration timeout}) async =>
       _localP2P == null ? false : _localP2P.discoverLocalPeer(peerId, timeout: timeout);
   ```

7. **`lib/features/conversation/application/send_chat_message_use_case.dart`** — the race hook. Replace the `if (isLocalPeer)` gate (`:391-402`) so the local leg is **added unconditionally but bounded**, doing discover-then-send inside the budget:
   ```dart
   raceFutures.add(
     _tryLocalSendWithDiscovery(
       p2pService, targetPeerId, jsonString, senderPeerId,
       alreadyLocal: isLocalPeer,
       budget: interactiveLocalBudget,
       transportMetrics: transportMetrics,
     ).timeout(
       interactiveLocalBudget,
       onTimeout: () => _RaceResult.failed('local_discover_timeout'),
     ),
   );
   ```
   New helper near `_tryLocalSend` (`:796`):
   ```dart
   Future<_RaceResult> _tryLocalSendWithDiscovery(
     P2PService p2pService, String targetPeerId, String jsonString, String senderPeerId, {
     required bool alreadyLocal, required Duration budget, TransportMetrics? transportMetrics,
   }) async {
     final sw = Stopwatch()..start();
     if (!alreadyLocal) {
       final found = await p2pService.discoverLocalPeer(targetPeerId, timeout: budget);
       if (!found) {
         transportMetrics?.recordAttempt(leg: 'local', succeeded: false);
         return _RaceResult.failed('local_not_discovered',
             stepTimings: {'localDiscoverMs': sw.elapsedMilliseconds});
       }
     }
     final remaining = budget.inMilliseconds - sw.elapsedMilliseconds;
     return _tryLocalSend(p2pService, targetPeerId, jsonString, senderPeerId,
         timeoutMs: remaining > 0 ? remaining : 1, transportMetrics: transportMetrics);
   }
   ```
   - **DIRECT future (`:411-421`) stays added unconditionally, exactly as-is.** Never delay it. The first-wins `Completer` semantics (`:425-483`) are untouched — the local leg is just one more `raceFutures` entry, now self-bounded.
   - **Scope note (doc lines 107-115):** introductions, contact requests, delete/tombstones, share-batch all gate on `isLocalPeer` + `sendLocalMessage`. This unit fixes ONLY `sendChatMessage`. Those flows benefit only if they later call `discoverLocalPeer` the same way — out of scope here; flagged for a follow-up. (Intended scope confirmed: chat text only for NET-REL-01.)

### Negative control (must hold)
A non-LAN peer: `discoverLocalPeer` times out to false within ≤ 1500ms → `_tryLocalSendWithDiscovery` returns `_RaceResult.failed` → the direct leg (running concurrently) wins → transport becomes `direct`/`relay`/`inbox`, never `local`. `DisabledLocalDiscoveryService.resolvePeer` returns null immediately → test builds never stall and never report `local`.

### Tests enabled → maps to doc **U1, U3, U-N1** + acceptance criteria **#1, #5**
- **U1 (happy):** EDIT `send_chat_message_use_case_test.dart:1306` — add `expect(message!.transport, 'local')` to the existing `localSendCallCount==1 / probeRelayCallCount==0 / lastReadinessSendPath=='local'` asserts (recon: existing test does NOT assert transport).
- **U3 (discover-on-send):** extend in-file `FakeP2PService` with a controllable `discoverLocalPeer` that flips `isLocalPeer`→true within budget; assert `localSendCallCount==1` and total time < 1500ms. (Write AFTER this unit lands.)
- **U-N1 (negative control):** EDIT `:1375` — `localPeers` empty, `discoverLocalPeer`→false; add `expect(message!.transport, isNot('local'))` and keep `localSendCallCount==0` / direct path wins. Proves U1 isn't hard-coded.
- **I3 (device, MUST BUILD — unchanged from doc):** two physical iOS devices, same WiFi, discovery ON, assert receiver `transport == 'local'` + census `wifi` moved. Real `BonsoirDiscoveryService.resolvePeer` is device-only (never instantiated in host/integration tests).

---

## U-P3-media — local media in production (two-part fix)

**Goal (P3):** wire the receive-side media server AND consume its `mediaReadyStream`, so same-LAN media uses the local server with relay-CDN fallback intact. Send side already works.

### Files & changes

**(a) Wire `configureMediaServer` — `lib/main.dart`**
- Add import: `import 'package:flutter_app/core/local_discovery/local_media_server.dart';` (and `local_discovery_service.dart` for `LocalMediaReady` if needed).
- Immediately after `final localWsServer = LocalWsServer();` (`:1377`) and before `LocalP2PService(...)` (`:1378`):
  ```dart
  if (!kDisableLocalDiscovery) {
    final mediaServer = LocalMediaServer(
      tempDir: '${appDocDir.path}/local_media_tmp',
      mediaDir: '${appDocDir.path}/local_media',
    );
    localWsServer.configureMediaServer(mediaServer);
  }
  ```
  `appDocDir` is already in scope (`main.dart:294`). Gating on `!kDisableLocalDiscovery` keeps test builds media-server-free (matches existing gating intent). Dedicated subdirs avoid collision with relay-CDN media storage.

**(b) Consume `mediaReadyStream` — `lib/core/services/p2p_service_impl.dart`**
- Add field after `_localPeersSub` (`:48`): `StreamSubscription<LocalMediaReady>? _localMediaSub;`
- Add a broadcast controller near the other controllers: `final _incomingLocalMediaController = StreamController<LocalMediaReady>.broadcast();`
- In the constructor, immediately after the `_localMessageSub` block (ends `:187`) and before `_localPeersSub` (`:188`), mirror the localMessageStream merge:
  ```dart
  _localMediaSub = _localP2P?.mediaReadyStream?.listen((media) {
    _transportMetrics?.recordTransport('wifi');
    _incomingLocalMediaController.add(media);
  });
  ```
  Use `?.listen` — `mediaReadyStream` is nullable (null when the media server is unconfigured, e.g. test builds).
- **New typed surface (NOT messageStream).** `ChatMessage` has no media fields and `messageStream` is text-only, so add to the `P2PService` interface (`p2p_service.dart`, near `messageStream:51`) a default-empty getter to limit fake churn:
  ```dart
  /// Stream of media files received over the local WiFi path. Default empty.
  Stream<LocalMediaReady> get incomingLocalMediaStream => const Stream.empty();
  ```
  Override in `P2PServiceImpl`: `Stream<LocalMediaReady> get incomingLocalMediaStream => _incomingLocalMediaController.stream;`
- **Dispose** (`:3036-3037`): add `_localMediaSub?.cancel();`; near `_messageController.close()` (`:3048`) add `if (!_incomingLocalMediaController.isClosed) _incomingLocalMediaController.close();`.

**(c) Bridge into the attachment pipeline — `lib/main.dart` consumer**
- In the listener-wiring region (around `:1382-1414`, where `chatMessageListener`/`introductionListener` are declared late), after `localP2PService`/`mediaServer` exist, subscribe to `p2pService.incomingLocalMediaStream` and for each `LocalMediaReady`:
  1. **dedupe** by `media.id`/`media.sha256` against any attachment already inserted via the relay-CDN path (recon risk: same-LAN media can also arrive via relay fallback);
  2. call `mediaServer.persistMedia(media.id, media.from)` to move temp→persistent (otherwise the 5-min `pendingTtl` cleanup GC's the file — recon risk); the temp `localPath` alone does NOT persist;
  3. insert/update the attachment via the existing media-attachment repository path (`media_attachment_repository_impl.updateLocalPath` / the conversation media pipeline) keyed by `media.id`, so it surfaces in the conversation like a downloaded relay attachment.
- Keep this consumer behind the same `!kDisableLocalDiscovery` guard that constructed `mediaServer`.

### Transport tagging & merge shape (exact)
- Inbound local media is tagged `'wifi'` for the census (`recordTransport('wifi')`), matching the inbound text merge at `p2p_service_impl.dart:176` — NOT `'local'` (which is the *outgoing* race label only). This keeps census semantics consistent (`wifi` = inbound LAN, `local` = outbound LAN win).
- Media does NOT enter `messageStream`. The merge shape is: `LocalMediaServer.handleUpload → mediaReadyStream(LocalMediaReady) → P2PServiceImpl._localMediaSub → _incomingLocalMediaController → incomingLocalMediaStream → main.dart consumer → persistMedia → attachment repo`. Symmetric to the text path but on a typed media channel.

### Caller-contract preservation
- `sendLocalMedia` (`p2p_service_impl.dart:3008`) unchanged — send side already fires from `conversation_wired.dart` (images `:1766-1775`, voice `:2639-2648`), relay-CDN fallback `:1805-1825` intact.
- The new interface getter has a default no-op body → existing `P2PService` fakes/mocks compile unchanged.

### Tests enabled → maps to doc **U4, U-N2, I1** + acceptance criterion **#3** (SEQUENCE AFTER this unit)
- **U4 (media wiring):** port `test/core/local_discovery/local_media_server_test.dart` to a production-wiring test under `test/core/services/` — configure the media server on `LocalWsServer`, drive a `PUT/GET` upload, assert token-auth + declared-size + streaming SHA-256 enforced AND the `LocalMediaReady` reaches `incomingLocalMediaStream` (the consumer surfaces it).
- **U-N2 (negative control):** same upload but NO `incomingLocalMediaStream` consumer subscribed → assert inbound media does NOT surface (reproduces today's P3 bug; catches a future regression that drops the consumer).
- **I1 media variant:** extend `integration_test/wifi_transport_test.dart` F10 (already wires `configureMediaServer` + `mediaReadyStream` over loopback) with the production-wiring path + dedupe assertion.

---

## U-P4-telemetry — LAN availability + suspected-permission-denied diagnostic

**Goal (P4):** the LAN-availability feed already exists end-to-end (do NOT rebuild). Add a pure-Dart **suspected** permission-denial heuristic and surface it. Document the iOS limitation.

### Files & changes

1. **`lib/core/debug/transport_metrics.dart`** — extend `LanAvailabilitySnapshot` (`:44-57`) with a third field, defaulted to keep `const empty` and existing callers working:
   ```dart
   final bool suspectedPermissionDenied; // heuristic only; never authoritative
   const LanAvailabilitySnapshot({
     required this.discoveryActive,
     required this.discoveredPeerCount,
     this.suspectedPermissionDenied = false,
   });
   static const empty = LanAvailabilitySnapshot(
     discoveryActive: false, discoveredPeerCount: 0, suspectedPermissionDenied: false);
   ```
   Add it to `baselineReport()` (`:284-288`) as `"LAN perm: suspected-denied"` only when true. `updateLanAvailability` (`:191-193`) is unchanged (replaces the snapshot).

2. **`lib/core/services/p2p_service_impl.dart`** — heuristic timer:
   - Add `Timer? _lanPermProbeTimer;` near the other fields.
   - In `_setLocalDiscoveryActive` (`:441-447`): start a one-shot `Timer(const Duration(seconds: 12), ...)` that, if `_localDiscoveryActive && (_localP2P?.discoveredPeers.isEmpty ?? true)`, re-records the snapshot with `suspectedPermissionDenied: true`. Cancel + restart on each activation.
   - In the `_localPeersSub` listener (`:188-193`) and `_setLocalDiscoveryInactive` (`:449-452`): cancel the timer and clear the suspected flag whenever a peer appears or discovery stops (so a peer-seen-then-left does NOT leave a false "denied").
   - Cancel in `dispose` (`:3032-3056`).
   - Extend `_recordLanAvailability` (`:454-464`) with an optional `bool suspectedPermissionDenied = false` param, threaded into the `LanAvailabilitySnapshot`. Update the 3 existing call sites (`:188-193`, `:194-197`, `:441-452`) to pass it (default false; the timer passes true).

3. **`lib/features/settings/presentation/widgets/settings_transport_diagnostics_card.dart`** — add a third `_MetricRow` in the LAN section (`:178-187`): `permission: suspected-denied?` reading `metrics.lanAvailability.suspectedPermissionDenied`. Privacy-safe (no identifiers).

### Hard limitation (documented, no native work)
- **No accurate iOS Local-Network permission API exists** without a custom `Network.framework` `NWBrowser`/`NWPathMonitor` MethodChannel (heavy native code, explicitly out of scope). bonsoir 5.1.0 does not surface permission status; `startAdvertising`/`start()` do NOT reliably throw on iOS denial. The zero-peers-for-12s signal is a **heuristic** with a false positive when the user is genuinely alone on the LAN — hence it is labelled `suspectedPermissionDenied`, never `denied`, and `discoveryActive` (which only means `start()` returned) is kept distinct from it.
- Android: `CHANGE_WIFI_MULTICAST_STATE` is present; no runtime prompt → no denial mode to detect.

### IMPLEMENTED (2026-05-29) — U-P4-telemetry
- **Recon outcome: NO feasible iOS permission-denied signal exists** in the current tree (bonsoir 5.1.0 exposes none; no permission plugin; `start()` does not throw on denial). Per the unit instruction, the telemetry feed + zero-peers heuristic was implemented and the iOS permission-detection limitation is documented here (above).
- `LanAvailabilitySnapshot` gained `suspectedPermissionDenied` (defaulted `false`, const-friendly, included in `empty`); `baselineReport()` appends `, perm: suspected-denied` only when true. `updateLanAvailability` unchanged (snapshot replace).
- `P2PServiceImpl` gained `Timer? _lanPermProbeTimer` + `_startLanPermProbe()`: a one-shot 12s timer armed in `_setLocalDiscoveryActive`; on fire, if `_localDiscoveryActive && discoveredPeers.isEmpty` it emits FL `LOCAL_MDNS_SUSPECTED_PERMISSION_DENIED` and re-records the snapshot with the flag true. Cancelled + flag cleared in the `_localPeersSub` listener when any peer appears, in `_setLocalDiscoveryInactive` (discovery stops), and in `dispose`. `_recordLanAvailability` gained an optional `suspectedPermissionDenied = false` param threaded into the snapshot.
- Diagnostics card renders a third LAN `_MetricRow` (`permission: ok | suspected-denied`) from `metrics.lanAvailability.suspectedPermissionDenied`. Privacy-safe (no identifiers).
- The pre-existing LAN telemetry feed (`LanAvailabilitySnapshot{discoveryActive, discoveredPeerCount}` → `updateLanAvailability`) was NOT rebuilt, per the decision-table scope.

### Tests enabled → maps to doc **P-iOS diagnostic** + acceptance criterion **#4**
- `transport_metrics_test.dart` / `transport_metrics_privacy_test.dart` / `settings_transport_diagnostics_card_test.dart`: update snapshot constructions for the new defaulted field; assert privacy invariant (no identifiers) and that `suspectedPermissionDenied` renders. Add a `P2PServiceImpl` test (fake clock or short timer override) asserting the flag flips true after the timeout with zero peers and clears when a peer appears.

---

## Acceptance-criteria traceability (doc lines 239-252)

| Criterion | Unit(s) | How proven |
|---|---|---|
| #1 first msg uses `local`/`wifi` within bounded window | U-P1 (+U-P2) | U1, U3, I3 (device) + census `wifi`/`local` rise |
| #2 stale peer does not burn full budget | U-P2 | TTL predicate unit, U2, I2 stale host:port |
| #3 same-LAN media uses local server, relay fallback intact | U-P3 | U4, U-N2, I1 media variant |
| #4 denied iOS permission detected/recorded; no infinite silent skip | U-P4 | snapshot heuristic test + diagnostics card (documented limitation) |
| #5 no regression; direct path carries when local unavailable | U-P1 (negative control) + all | U-N1; DIRECT future always added unconditionally |

## Gate placement (doc lines 324-328)
- Host units (TTL predicate, U1/U2/U3/U-N1/U4/U-N2, P4 metrics): `./scripts/run_host_test_gates.sh core-host-all` / `feature-host-all`.
- I1/I2: `integration_test/wifi_transport_test.dart` (device/sim; currently NIGHTLY_ONLY — run directly or add to `TRANSPORT_TESTS` in `run_test_gates.sh:70-75` if it should be in the transport gate).
- I3 + control: two physical iOS devices, discovery ON (a `DISABLE_LOCAL_DISCOVERY=false` variant of `reset_simulators.sh`). Sims cannot validate LAN.
- After every unit: `./scripts/check_flutter_analyze_baseline.sh` must pass.

## Risks carried forward (per-unit, from recon)
- **U-P2:** UTC comparison required; re-resolution must clear `_resolvable` on lost/stop to avoid native-handle leaks; do not construct new bonsoir objects without `printLogs:false`.
- **U-P1:** completer-per-peerId map must be cleaned up in `finally` on timeout; `DisabledLocalDiscoveryService.resolvePeer` must return null fast; BonsoirDiscoveryService.resolvePeer is device-only-tested.
- **U-P3:** `mediaReadyStream` nullable → `?.listen`; consumer MUST call `persistMedia` or the temp file is GC'd; dedupe vs relay-CDN; new interface getter default no-op limits fake churn.
- **U-P4:** heuristic false-positive when alone → "suspected" wording; timer cancel on peer-seen/background/dispose to avoid leaks and stale "denied".
