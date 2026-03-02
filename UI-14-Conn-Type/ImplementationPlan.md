# Implementation Plan: Unified Connection Manager (TDD)

See [ConnectionManager.md](./ConnectionManager.md) for the problem statement and proposed solution.

---

## ~~Phase 1: Unified Connection Check~~ — REMOVED

`hasActiveConnection()` was dropped from the plan. The send flow already checks `isLocalPeer()` (step 2) and `isConnectedToPeer()` (step 3) separately because they use different send mechanisms (WebSocket vs libp2p stream). A unified bool adds no value — the caller would still need to know *which* connection type to use. Removing this avoids unnecessary interface churn across 13 test files / 19 implementations for a method that nothing calls.

---

## Phase 2: Relay Probe — Go Side

Add a `relay:probe` bridge command that dials a peer through the relay circuit address only. Returns fast (~100ms for NO_RESERVATION, ~500ms for connection).

### Tests first

**Go unit tests — File:** `go-mknoon/node/node_test.go`

| # | Test | Scenario | Expected |
|---|------|----------|----------|
| 2.1 | `DialPeerViaRelay returns error when node not started` | Host is nil | `"node not started"` error |
| 2.2 | `DialPeerViaRelay returns error for invalid peer ID` | Bad peer ID string (e.g. "not-a-peer-id") | Error containing `"invalid peer ID"` |
| 2.3 | `RelayProbe returns INVALID_INPUT for missing peerId` | Empty JSON `{}` or `{"peerId": ""}` | `{"ok": false, "errorCode": "INVALID_INPUT"}` |
| 2.4 | `RelayProbe returns NOT_INITIALIZED when node is nil` | Singleton node not set | `{"ok": false, "errorCode": "NOT_INITIALIZED"}` |

**Go integration tests — File:** `go-mknoon/integration/relay_test.go`

| # | Test | Scenario | Expected |
|---|------|----------|----------|
| 2.5 | `DialPeerViaRelay succeeds for online peer` | Both peers started, reservations active | `nil` error, connection established |
| 2.6 | `DialPeerViaRelay returns error for offline peer` | Target not started / no reservation | Error containing `NO_RESERVATION` or circuit error |
| 2.7 | `DialPeerViaRelay connection is usable` | After successful probe, send a message on the connection | Message delivered via relay stream |

### Implementation

**File:** `go-mknoon/node/config.go`
- Add: `RelayProbeTimeout = 5 * time.Second`
- Add: `PeerDialTimeout = 5 * time.Second` (see [Phase 5](#phase-5-config-tuning-go))

**File:** `go-mknoon/node/node.go`
- Add method:
```go
func (n *Node) DialPeerViaRelay(peerIdStr string) error {
    // 1. Get host (read lock)
    // 2. Parse peer ID
    // 3. Get relay address from node config (stored during Start)
    // 4. Construct circuit multiaddr: relayAddr + "/p2p-circuit/p2p/" + peerIdStr
    // 5. Build AddrInfo with ONLY the circuit address
    // 6. context.WithTimeout(n.ctx, RelayProbeTimeout)
    // 7. h.Connect(ctx, addrInfo)
    // 8. Return nil on success, error on failure
}
```

**File:** `go-mknoon/bridge/bridge.go`
- Add exported function:
```go
func RelayProbe(paramsJSON string) (result string) {
    // Parse { "peerId": "..." }
    // Call n.DialPeerViaRelay(peerId)
    // On success: return okJSON({"ok": true})
    // On error containing "NO_RESERVATION": return errJSON("NO_RESERVATION", ...)
    // On other error: return errJSON("RELAY_PROBE_ERROR", ...)
}
```

**File:** `ios/Runner/GoBridge.swift`
- Add case to `handleMethodCall` switch:
```swift
case "relayProbe":
    runOnBackground({ BridgeRelayProbe(args ?? "") }, result: result)
```

**File:** `android/app/src/main/kotlin/com/example/flutter_app/GoBridge.kt`
- Add case to `onMethodCall` when:
```kotlin
"relayProbe" -> runOnBackground({ GoMknoon.relayProbe(args ?: "") }, result)
```

---

## Phase 3: Relay Probe — Dart Side

Wire the new Go command into the Dart bridge layer and P2PService.

**Key design decision:** `probeRelay()` returns a 3-state enum, not a bool. This preserves the distinction between `connected` (peer is online, relay circuit established), `noReservation` (peer is definitely offline), and `error` (network/platform issue — should fall through to dial, not skip to inbox).

### Probe result type

**File:** `lib/core/services/p2p_service.dart` (or nearby)

```dart
enum RelayProbeResult {
  connected,      // Relay circuit established — peer is online
  noReservation,  // Peer has no reservation — definitely offline
  error,          // Network/bridge error — unknown state, fall through to dial
}
```

### Tests first

**Bridge helper tests — File:** `test/core/bridge/p2p_bridge_client_test.dart` (new or extend)

| # | Test | Setup | Expected |
|---|------|-------|----------|
| 3.1 | `callP2PRelayProbe returns parsed response on success` | FakeBridge returns `{"ok": true}` | Returns map with `ok: true` |
| 3.2 | `callP2PRelayProbe returns parsed response on NO_RESERVATION` | FakeBridge returns `{"ok": false, "errorCode": "NO_RESERVATION"}` | Returns map with `ok: false, errorCode: NO_RESERVATION` |
| 3.3 | `callP2PRelayProbe returns parsed response on other error` | FakeBridge returns `{"ok": false, "errorCode": "RELAY_PROBE_ERROR"}` | Returns map with `ok: false, errorCode: RELAY_PROBE_ERROR` |

**P2PService impl tests — File:** `test/core/services/p2p_service_impl_test.dart` (or extend existing)

| # | Test | Setup | Expected |
|---|------|-------|----------|
| 3.4 | `probeRelay returns connected when bridge ok` | Bridge returns `{"ok": true}` | `RelayProbeResult.connected` |
| 3.5 | `probeRelay returns noReservation when errorCode is NO_RESERVATION` | Bridge returns `{"ok": false, "errorCode": "NO_RESERVATION"}` | `RelayProbeResult.noReservation` |
| 3.6 | `probeRelay returns error when bridge returns other error` | Bridge returns `{"ok": false, "errorCode": "RELAY_PROBE_ERROR"}` | `RelayProbeResult.error` |
| 3.7 | `probeRelay returns error when bridge throws` | Bridge throws exception | `RelayProbeResult.error` |

**Error classification tests — ensure only NO_RESERVATION maps to noReservation:**

| # | Test | Setup | Expected |
|---|------|-------|----------|
| 3.8 | `probeRelay returns error for PLATFORM_ERROR` | Bridge returns `{"ok": false, "errorCode": "PLATFORM_ERROR"}` | `RelayProbeResult.error` (NOT noReservation) |
| 3.9 | `probeRelay returns error for BRIDGE_TIMEOUT` | Bridge returns `{"ok": false, "errorCode": "BRIDGE_TIMEOUT"}` | `RelayProbeResult.error` |
| 3.10 | `probeRelay returns error for null response` | Bridge returns `null` or missing `ok` field | `RelayProbeResult.error` |
| 3.11 | `probeRelay returns error for INTERNAL_ERROR` | Bridge returns `{"ok": false, "errorCode": "INTERNAL_ERROR"}` | `RelayProbeResult.error` |

**Fake service — File:** `test/core/services/fake_p2p_service.dart`

- Add `probeRelayResult` configurable `RelayProbeResult` (default: `RelayProbeResult.noReservation`)
- Add `probeRelayCallCount` tracker
- Add `shouldThrowOnProbeRelay` bool (default: false)
- Implement `probeRelay()` method

### Implementation

**File:** `lib/core/bridge/go_bridge_client.dart`
- Add to `_cmdMap`: `'relay:probe': _CmdSpec('relayProbe', true)`

**File:** `lib/core/bridge/p2p_bridge_client.dart`
- Add helper:
```dart
Future<Map<String, dynamic>> callP2PRelayProbe(Bridge bridge, {required String peerId}) async {
    // emitFlowEvent REQUEST
    // send { cmd: 'relay:probe', payload: { peerId } }
    // emitFlowEvent RESPONSE
    // return parsed response (includes ok, errorCode, errorMessage)
}
```

**File:** `lib/core/services/p2p_service.dart`
- Add enum `RelayProbeResult { connected, noReservation, error }`
- Add abstract method: `Future<RelayProbeResult> probeRelay(String peerId);`

**File:** `lib/core/services/p2p_service_impl.dart`
- Implement:
```dart
Future<RelayProbeResult> probeRelay(String peerId) async {
    try {
        final result = await callP2PRelayProbe(_bridge, peerId: peerId);
        if (result['ok'] == true) return RelayProbeResult.connected;
        if (result['errorCode'] == 'NO_RESERVATION') return RelayProbeResult.noReservation;
        return RelayProbeResult.error;
    } catch (e) {
        return RelayProbeResult.error;
    }
}
```

---

## Phase 4: Optimized Send Flow (Dart)

Restructure `send_chat_message_use_case.dart` to use the relay probe as a fast offline signal.

### New send flow

```
1. Validate & encrypt                          (unchanged)
2. WiFi (Bonsoir) — sendLocalMessage            (unchanged, step 4.5)
3. Fast path — isConnectedToPeer? Send.         (unchanged, step 4.7)
4. NEW: Relay probe — probeRelay(targetPeerId)
   - connected     → we have a connection → sendMessageWithReply → done
   - noReservation → peer definitely offline → skip to inbox (step 6)
   - error         → unknown state → fall through to single dial attempt (step 5)
5. Single dial attempt — discover + dial + send (maxAttempts: 1)
6. Inbox fallback — storeInInbox               (unchanged)
7. Failed — save with wireEnvelope             (unchanged)
```

### Status semantics alignment

Migration 015 establishes the product rule: **inbox store success = `delivered`** (not `queued`). The current code in `send_chat_message_use_case.dart` saves inbox-stored messages as `'queued'`, which conflicts with the migration that upgrades `'queued'` → `'delivered'`.

This plan aligns with the product rule: inbox store success saves as `'delivered'` with transport `'inbox'`. All new tests use `'delivered'` for inbox-stored messages.

### Tests first

**File:** `test/features/conversation/application/send_chat_message_use_case_test.dart`

**Relay probe — new path tests:**

| # | Test | Setup | Expected |
|---|------|-------|----------|
| 4.1 | `relay probe connected → delivers via relay` | probe = `connected`, `sendMessageWithReply` = sent+ack | Result: success, status: delivered, `discoverCallCount` = 0 |
| 4.2 | `relay probe connected, send not ACK'd → inbox safety net` | probe = `connected`, `sendMessageWithReply` = sent (no ack) | Result: success, status: delivered via inbox, or sent with wireEnvelope |
| 4.3 | `relay probe connected but send fails → falls through to dial` | probe = `connected`, `sendMessageWithReply` throws | Falls to discover/dial, `discoverCallCount` = 1 |
| 4.4 | `relay probe noReservation → skips dial, goes to inbox` | probe = `noReservation`, `storeInInbox` = true | Result: success, status: delivered, transport: inbox, `discoverCallCount` = 0, `dialCallCount` = 0 |
| 4.5 | `relay probe noReservation, inbox fails → saves as failed` | probe = `noReservation`, `storeInInbox` = false | Result: sendFailed, status: failed |
| 4.6 | `relay probe error → falls through to dial` | probe = `error` | Falls to discover/dial with `maxAttempts` = 1 |

**Relay probe — dial fallback uses single attempt:**

| # | Test | Setup | Expected |
|---|------|-------|----------|
| 4.7 | `dial fallback after probe error uses 1 attempt, not 3` | probe = `error`, discover+dial+send all fail | `discoverCallCount` = 1 (not 3), then inbox |

**Dual-path interaction tests (WiFi + relay probe):**

| # | Test | Setup | Expected |
|---|------|-------|----------|
| 4.8 | `WiFi sent + relay probe connected → delivered, transport: wifi` | `isLocalPeer` = true, local send succeeds, probe = `connected`, send+ack | status: delivered, transport: wifi |
| 4.9 | `WiFi sent + relay probe noReservation → inbox fallback` | `isLocalPeer` = true, local send succeeds, probe = `noReservation`, inbox succeeds | status: delivered via inbox |

**Existing flow unchanged (regression):**

| # | Test | Setup | Expected |
|---|------|-------|----------|
| 4.10 | `fast path still works, probeRelay not called` | `isConnectedToPeer` = true, send+ack | `probeRelayCallCount` = 0, result: success |
| 4.11 | `WiFi path still runs before probe` | `isLocalPeer` = true | `localSendCallCount` = 1, WiFi runs before probe |

**Timing / flow event tests:**

| # | Test | Setup | Expected |
|---|------|-------|----------|
| 4.12 | `relay probe events include durationMs` | probe = `connected` or `noReservation` | `CHAT_MSG_SEND_RELAY_PROBE_*` event emitted with `durationMs` |
| 4.13 | `totalMs present on terminal event after relay probe path` | probe = `noReservation`, inbox succeeds | Final `CHAT_MSG_SEND_SUCCESS` includes `totalMs` |

### Implementation

**File:** `lib/features/conversation/application/send_chat_message_use_case.dart`

Replace step 5 (discover/dial loop with 3 attempts) with:

```dart
// Step 4.8: Relay probe — fast offline detection
final probeStart = DateTime.now();
RelayProbeResult probeResult = RelayProbeResult.error;
try {
    probeResult = await p2pService.probeRelay(targetPeerId);
} catch (e) {
    emitFlowEvent(layer: 'FL', event: 'CHAT_MSG_SEND_RELAY_PROBE_ERROR', details: {
        'error': e.toString(),
        'durationMs': DateTime.now().difference(probeStart).inMilliseconds,
    });
}

if (probeResult == RelayProbeResult.connected) {
    emitFlowEvent(layer: 'FL', event: 'CHAT_MSG_SEND_RELAY_PROBE_CONNECTED', details: {
        'durationMs': DateTime.now().difference(probeStart).inMilliseconds,
    });
    // Peer is online — send on the newly established relay connection
    try {
        final result = await p2pService.sendMessageWithReply(targetPeerId, jsonString);
        if (result.sent) {
            // Save as delivered/sent based on ACK, return success
        }
    } catch (e) {
        // Send failed after relay connect — fall through to dial
    }
} else if (probeResult == RelayProbeResult.noReservation) {
    emitFlowEvent(layer: 'FL', event: 'CHAT_MSG_SEND_RELAY_PROBE_OFFLINE', details: {
        'durationMs': DateTime.now().difference(probeStart).inMilliseconds,
    });
    // Peer is definitely offline — skip dial entirely, go straight to inbox
    // → jump to inbox fallback (step 6)
}
// probeResult == error → fall through to single dial attempt

// Step 5: Single dial attempt (only reached on probe error or probe connected + send failed)
if (probeResult != RelayProbeResult.noReservation) {
    const maxAttempts = 1; // Reduced from 3 — probe already checked relay
    // ... existing discover/dial/send loop with maxAttempts = 1 ...
}

// Step 6: Inbox fallback (unchanged)
```

Add flow events:
- `CHAT_MSG_SEND_RELAY_PROBE_ATTEMPT`
- `CHAT_MSG_SEND_RELAY_PROBE_CONNECTED`
- `CHAT_MSG_SEND_RELAY_PROBE_OFFLINE`
- `CHAT_MSG_SEND_RELAY_PROBE_ERROR`

Add timing:
- `durationMs` on probe result
- `totalMs` on all terminal events (already in place from prior work)

---

## Phase 5: Config Tuning (Go)

### Problem

`DialTimeout` (15s) is used for **both** peer dials (`DialPeer`) and relay server connections (`connectToRelay`). Lowering it globally to 5s would affect relay startup reliability on slow networks, since the relay server dial also uses this constant.

### Solution

Introduce a separate `PeerDialTimeout` for peer-to-peer dials, keep `DialTimeout` at 15s for relay infrastructure.

### Tests first

| # | Test | Scenario | Expected |
|---|------|----------|----------|
| 5.1 | Existing Go integration tests pass with new timeout | Run full test suite | All pass (online peers connect within 5s) |

### Implementation

**File:** `go-mknoon/node/config.go`
```go
const (
    DialTimeout      = 15 * time.Second  // Relay server connection (UNCHANGED)
    PeerDialTimeout  = 5 * time.Second   // Peer-to-peer dial (NEW — was using DialTimeout)
    RelayProbeTimeout = 5 * time.Second  // Relay probe (added in Phase 2)
)
```

**File:** `go-mknoon/node/node.go`
- `DialPeer()`: change `context.WithTimeout(n.ctx, DialTimeout)` → `context.WithTimeout(n.ctx, PeerDialTimeout)`
- `connectToRelay()`: keep using `DialTimeout` (unchanged)

---

## Interface Blast Radius

Adding `probeRelay()` to the `P2PService` interface requires updating **all 19 implementations across 13 test files**:

| File | Class(es) |
|------|-----------|
| `test/core/services/fake_p2p_service.dart` | `FakeP2PService` |
| `test/shared/fakes/fake_p2p_service_integration.dart` | `FakeP2PService` |
| `test/features/conversation/presentation/screens/conversation_wired_test.dart` | `FakeP2PService` |
| `test/core/services/incoming_message_router_test.dart` | `FakeP2PService` |
| `test/core/services/incoming_message_router_profile_test.dart` | `FakeP2PService` |
| `test/core/resilience/c3_half_open_test.dart` | `_HalfOpenP2PService` |
| `test/core/resilience/c2_ack_drop_test.dart` | `_AckDropP2PService` |
| `test/features/conversation/application/send_chat_message_use_case_test.dart` | `FakeP2PService`, `_WiFiThenFastFailThenRelayP2PService`, `_FastPathFailThenSucceedP2PService`, `_FastPathThrowThenSucceedP2PService`, `_AllFailButInboxP2PService`, `_ThrowOnSendP2PService`, `_FlakyDiscoverP2PService` |
| `test/features/contact_request/application/send_contact_request_use_case_test.dart` | `_FakeP2PService` |
| `test/features/settings/application/upload_profile_picture_use_case_test.dart` | `_FakeP2PService` |
| `test/features/contact_request/application/accept_and_reciprocate_use_case_test.dart` | `_FakeP2PService` |
| `test/features/settings/presentation/screens/settings_wired_test.dart` | `_FakeP2PService` |
| `test/features/push/application/register_push_token_use_case_test.dart` | `_FakeP2PService` |

**Default implementation for test doubles:**
- `probeRelay(peerId)` → `return RelayProbeResult.noReservation;`

This is a safe default: most test doubles don't test the send path, and `noReservation` will cause the send flow to go to inbox (the safest fallback).

---

## Phase 6: Regression & Smoke Tests

Run after all phases are implemented to verify nothing broke.

### Automated regression

| # | Test | How | Expected |
|---|------|-----|----------|
| 6.1 | All existing Dart tests pass | `flutter test` | All 79+ existing tests pass (no regressions) |
| 6.2 | All existing Go tests pass | `cd go-mknoon && go test ./...` | All pass |
| 6.3 | Go integration tests pass with new config | `cd go-mknoon && go test -run Integration ./...` | All pass with PeerDialTimeout = 5s |

### Manual smoke tests (on device)

| # | Test | Steps | Expected |
|---|------|-------|----------|
| 6.4 | Offline peer — fast inbox | 1. Start app, send message to offline peer<br/>2. Check `[FLOW]` logs | `RELAY_PROBE_OFFLINE` within ~100ms, `CHAT_MSG_SEND_SUCCESS` with `via: inbox` and `totalMs < 2000` |
| 6.5 | Online peer — relay probe delivery | 1. Both apps running<br/>2. Kill libp2p connection (no fast path)<br/>3. Send message | `RELAY_PROBE_CONNECTED`, then `CHAT_MSG_SEND_SUCCESS` with status `delivered` and `totalMs < 1000` |
| 6.6 | Online peer — fast path unchanged | 1. Both apps running, active connection<br/>2. Send message | Fast path used, `probeRelay` not called, `totalMs < 500` |
| 6.7 | Same WiFi — local path unchanged | 1. Both on same WiFi<br/>2. Send message | `CHAT_MSG_SEND_LOCAL_SUCCESS` fires, message delivered |
| 6.8 | Relay probe connects, then send fails | 1. Peer online but kills app between probe and send | Falls through to dial (1 attempt) or inbox, message not lost |

---

## Test Count Summary

| Phase | Unit | Integration | Smoke | Total |
|-------|------|-------------|-------|-------|
| ~~1 — Unified check~~ | ~~4~~ | — | — | ~~removed~~ |
| 2 — Go relay probe | 4 | 3 | — | 7 |
| 3 — Dart bridge wiring | 11 | — | — | 11 |
| 4 — Send flow | 13 | — | — | 13 |
| 5 — Config tuning | — | 1 | — | 1 |
| 6 — Regression & smoke | 3 | — | 5 | 8 |
| **Total** | **31** | **4** | **5** | **40** |

---

## Phase Summary

| Phase | Layer | Files Modified | Depends On |
|-------|-------|----------------|------------|
| 2 | Go + Native | node.go, bridge.go, config.go, GoBridge.swift, GoBridge.kt | — |
| 3 | Dart | go_bridge_client.dart, p2p_bridge_client.dart, p2p_service.dart, p2p_service_impl.dart, + 13 test files (19 test doubles) | Phase 2 |
| 4 | Dart | send_chat_message_use_case.dart, send_chat_message_use_case_test.dart | Phase 3 |
| 5 | Go | config.go, node.go (DialPeer timeout reference) | — |
| 6 | All | — (test runs only) | Phase 2–5 |

**Phases 2 and 5 can run in parallel** (no dependencies).
Phase 3 depends on Phase 2 (Go command must exist).
Phase 4 depends on Phase 3 (relay probe must be wired into Dart).
Phase 6 runs last after all implementation is complete.

---

## Accepted Limitations

**30-second reservation gap:** The relay probe is a **fast negative signal**, not a perfect positive one. A peer could be online but temporarily without a reservation (relay dropped between 30-second health checks, network switch, relay server restart). In that case, the probe returns `noReservation`, we skip dial and go straight to inbox. The message still gets delivered — just not in real-time. This is an acceptable tradeoff: the inbox is the safety net, and the 30-second gap is rare in practice compared to the common case of a genuinely offline peer burning 24 seconds on failed dials.

**Stale WiFi entries:** The WiFi path (step 2) runs before the relay probe and has a 5-second ack timeout in LocalWsServer. If Bonsoir has a stale mDNS entry (peer left WiFi but wasn't removed), this could add up to 5 seconds before falling through. This is a pre-existing issue not introduced by this plan. A future improvement could add a shorter WiFi timeout or validate mDNS entries more aggressively.

## Out of Scope (Future Work)

- **Contact request send path** (`send_contact_request_use_case.dart`): Uses the same discover/dial loop pattern and would benefit from relay probe optimization. Should be aligned in a follow-up.
- **Relay inbox durability**: The relay server's inbox is in-memory (not persisted to disk) with no deduplication/idempotency guard. A server restart loses all queued messages. Separate reliability improvement.
- **Background push handling**: Push notifications received in background defer inbox drain until app resume. Messages aren't surfaced until the user opens the app.

---

## Expected Results

| Metric | Before | After |
|--------|--------|-------|
| Offline peer send time | ~24s | ~1.5s |
| Online peer (connected) | ~100-500ms | ~100-500ms (unchanged) |
| Online peer (not connected) | ~10s (first dial) | ~500ms relay probe + connect |
| Dial attempts for offline peer | 3 (wasted) | 0 |
| Go rebuild required | — | Yes (`make all` + `pod install`) |

## Verification

1. `flutter test` — all existing + new tests pass (40 new tests)
2. `cd go-mknoon && go test ./...` — all Go tests pass
3. Hot restart → send to offline peer → check `[FLOW]` logs:
   - `RELAY_PROBE_OFFLINE` appears within ~100ms
   - `CHAT_MSG_SEND_SUCCESS` with `via: inbox` and `totalMs < 2000`
4. Hot restart → send to online peer → check fast delivery via relay probe connection
