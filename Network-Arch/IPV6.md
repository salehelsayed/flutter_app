# IPv6 Dual-Stack Support — TDD Implementation Plan

## Why IPv6?

IPv6 addresses are **globally routable** — every device gets a public address without NAT. If both peers have IPv6 connectivity, they can connect **directly** without needing a circuit relay hop. Benefits:

- **Lower latency**: No relay middleman — direct peer-to-peer
- **Less relay load**: Fewer connections through the relay server
- **Better resilience**: No relay single point of failure for direct connections
- **Mobile-native**: Many mobile carriers already assign IPv6 (T-Mobile, most carriers in India, parts of Europe/Asia)
- **Future-proof**: IPv4 exhaustion is real; IPv6 adoption accelerates every year

## Current State

The node **only listens on IPv4**:

```go
// node.go:182-186
listenAddrs := []string{
    "/ip4/0.0.0.0/udp/0/quic-v1",
    "/ip4/0.0.0.0/tcp/0/ws",
    "/ip4/0.0.0.0/tcp/0",
}
```

The relay server also **only listens and announces IPv4**:

```go
// go-relay-server/main.go:57-70
announceAddrs := []ma.Multiaddr{
    ma.StringCast(fmt.Sprintf("/dns4/%s/tcp/%d/wss", serverDNS, wssPort)),
    ma.StringCast(fmt.Sprintf("/ip4/%s/tcp/%d", serverIP4, tcpPort)),
    ma.StringCast(fmt.Sprintf("/dns4/%s/udp/%d/quic-v1", serverDNS, quicPort)),
}
libp2p.ListenAddrStrings(
    fmt.Sprintf("/ip4/0.0.0.0/tcp/%d/ws", wsPort),
    fmt.Sprintf("/ip4/0.0.0.0/tcp/%d", tcpPort),
    fmt.Sprintf("/ip4/0.0.0.0/udp/%d/quic-v1", quicPort),
)
```

The default relay address constants use `dns4` (IPv4-only DNS resolution) in **three places**:

```go
// Go — go-mknoon/node/config.go:10,13 (fallback, rarely used — Flutter overrides)
DefaultRelayAddress = "/dns4/mknoun.xyz/tcp/4001/wss/p2p/12D3KooW..."
DefaultQUICRelay    = "/dns4/mknoun.xyz/udp/4002/quic-v1/p2p/12D3KooW..."
```

```dart
// Dart — lib/core/bridge/p2p_bridge_client.dart:6-11 (ACTUAL production path)
const String defaultRendezvousAddress =
    '/dns4/mknoun.xyz/tcp/4001/wss/p2p/12D3KooW...';
const String defaultQUICRelayAddress =
    '/dns4/mknoun.xyz/udp/4002/quic-v1/p2p/12D3KooW...';
```

```dart
// Dart — lib/core/constants/network_constants.dart:12 (embedded in QR codes + contact requests)
const String RENDEZVOUS_ADDRESS =
    '/dns4/mknoun.xyz/tcp/4001/wss/p2p/12D3KooW...';
```

**Critical**: Flutter's `callP2PNodeStart()` sends `relayAddresses ?? defaultRelayAddresses()` to Go on `node:start` (line 82), so the Go fallback constants in `config.go` are **never used in the real app**. The Dart constants are the ones that matter. Additionally, `RENDEZVOUS_ADDRESS` is embedded into QR payloads and contact request payloads — peers scanning these would only resolve IPv4 DNS.

---

## Architecture Decision

### Dual-stack at the client node

Add IPv6 wildcard listen addresses alongside IPv4. libp2p handles dual-stack natively — it will bind to both `0.0.0.0` (IPv4) and `::` (IPv6), and `host.Addrs()` will return addresses for all interfaces on both families.

**Key insight**: We do NOT need the relay server to support IPv6 for this to be useful. Even with an IPv4-only relay, if two peers both have global IPv6 addresses, libp2p's hole-punching and direct connection mechanisms can establish a direct IPv6 link after initial signaling through the relay.

### `dns4` → `dns` for relay constants (all three locations)

Change `/dns4/` to `/dns/` (protocol-agnostic DNS) in **all three places** that define relay addresses:
1. `go-mknoon/node/config.go` — Go fallback constants
2. `lib/core/bridge/p2p_bridge_client.dart` — Dart production constants (the real path)
3. `lib/core/constants/network_constants.dart` — `RENDEZVOUS_ADDRESS` embedded in QR/contact payloads

`/dns/` resolves both A (IPv4) and AAAA (IPv6) records. This means:
- If the relay server gets an IPv6 address (AAAA record), clients automatically use it
- If no AAAA record exists, falls back to A record (IPv4) — no breakage
- Zero relay server changes required for this to work

### Relay server IPv6 (separate, optional)

Adding IPv6 listen/announce to the relay server is a separate deployment concern (needs server IPv6 connectivity, DNS AAAA records). This plan prepares the client for it but does NOT require it.

**Limitation**: IPv6-only clients (no IPv4 at all) will NOT work after this change — they still cannot reach the IPv4-only relay for bootstrap/rendezvous. Full IPv6-only support requires the relay server IPv6 rollout (see `IPV6-Infra-Ops.md`). This plan targets the common case: dual-stack clients that benefit from direct IPv6 peer-to-peer connections after relay-mediated discovery.

---

## Prerequisite (Satisfied)

~~`loopback-filtering.md` must be implemented first.~~ **Already implemented.** The `filterAddresses()` function (`node.go:120-135`) and `isNonRoutableAddr()` (`node.go:110-118`) are registered as `AddrsFactory` (`node.go:263`), plus defensive re-filtering in `splitHostAddresses()` (`node.go:1117-1134`). IPv6-aware filtering tests exist at `node_test.go:987-1173` covering `::1`, `fe80::`, `::`, and `ip6zone` cases. No blocker remains.

---

## Files Affected

| File | Change | Description |
|------|--------|-------------|
| `go-mknoon/node/node.go` | EDIT | Add IPv6 listen addresses in `Start()` |
| `go-mknoon/node/node.go` | EDIT | `DialPeerViaRelay`: try all relay transport addrs, not just first |
| `go-mknoon/node/config.go` | EDIT | `dns4` → `dns` in Go fallback relay constants |
| `lib/core/bridge/p2p_bridge_client.dart` | EDIT | `dns4` → `dns` in Dart production relay constants (the real path) |
| `lib/core/constants/network_constants.dart` | EDIT | `dns4` → `dns` in `RENDEZVOUS_ADDRESS` (embedded in QR + contact payloads) |
| `go-mknoon/node/node_test.go` | ADD | New tests for dual-stack behavior |
| `test/core/bridge/p2p_bridge_client_test.dart` | ADD | Test Dart relay constants use `/dns/` |

### No rollout feature flag

IPv6 listening is harmless — if the machine has no IPv6, libp2p gracefully fails the bind and IPv4 continues working. Adding a feature flag for this adds complexity with no safety benefit. The existing `FeatureFlags` mechanism (`feature_flags.go`) is for features with operational risk (relay recovery, group recovery). Dual-stack listening has no operational risk.

### Files NOT Changed

| File | Why |
|------|-----|
| `go-mknoon/node/rendezvous.go` | Uses `peer.AddrInfoFromP2pAddr` — already multiaddr-agnostic |
| `go-mknoon/node/relay_selector.go` | Parses multiaddrs generically — no IPv4 assumptions |
| `go-mknoon/node/relay_session.go` | Tracks relay state by peer ID, not by address format |
| `go-mknoon/node/pubsub.go` | GossipSub operates on peer connections, not raw addresses |
| `go-mknoon/node/group_inbox.go` | Opens streams by peer ID — address-agnostic |
| `go-mknoon/bridge/bridge.go` | Passes addresses as opaque strings — no parsing |
| `go-mknoon/node/feature_flags.go` | No rollout flag needed — dual-stack listening is harmless |
| `lib/core/bridge/go_bridge_client.dart` | Treats addresses as opaque strings |
| `lib/core/services/p2p_service_impl.dart` | Treats addresses as opaque strings |
| `lib/features/p2p/domain/models/node_state.dart` | `listenAddresses` / `circuitAddresses` are `List<String>` — format-agnostic |
| `ios/Runner/GoBridge.swift` | Forwards strings to Go — no IP parsing |
| `android/.../GoBridge.kt` | Forwards strings to Go — no IP parsing |
| `go-relay-server/main.go` | Relay server IPv6 is a separate deployment task |

---

## TDD Steps

### Step 1: RED — Test that `dns4` → `dns` in relay constants

**File**: `go-mknoon/node/node_test.go`

```go
func TestDefaultRelayAddressUsesDNS(t *testing.T) {
    // Default relay addresses should use /dns/ (not /dns4/) to allow
    // both IPv4 and IPv6 DNS resolution.
    if strings.Contains(DefaultRelayAddress, "/dns4/") {
        t.Errorf("DefaultRelayAddress uses /dns4/ — should use /dns/ for dual-stack: %s",
            DefaultRelayAddress)
    }
    if strings.Contains(DefaultQUICRelay, "/dns4/") {
        t.Errorf("DefaultQUICRelay uses /dns4/ — should use /dns/ for dual-stack: %s",
            DefaultQUICRelay)
    }
}
```

**Expected**: Fails — constants currently use `/dns4/`.

---

### Step 2: GREEN — Change relay constants to `/dns/`

**File**: `go-mknoon/node/config.go`

```go
const (
    // DefaultRelayAddress is the relay server multiaddr (WSS).
    DefaultRelayAddress = "/dns/mknoun.xyz/tcp/4001/wss/p2p/12D3KooWGMYMmN1RGUYjWaSV6P3XtnBjwnosnJGNMnttfVCRnd6g"

    // DefaultQUICRelay is the relay server multiaddr (QUIC).
    DefaultQUICRelay = "/dns/mknoun.xyz/udp/4002/quic-v1/p2p/12D3KooWGMYMmN1RGUYjWaSV6P3XtnBjwnosnJGNMnttfVCRnd6g"
)
```

**Run**: `go test ./node/ -run TestDefaultRelayAddressUsesDNS -v` → passes.

**Note**: `/dns/` resolves both A and AAAA records. If the relay server has no AAAA record, libp2p simply falls back to A (IPv4). No behavior change for existing deployments.

---

### Step 2b: RED — Test Dart relay constants use `/dns/`

The Go constants are a fallback — Flutter sends explicit relay addresses to Go on `node:start`. These are the constants that matter in production.

**File**: `test/core/bridge/p2p_bridge_client_test.dart`

**Note**: Existing tests at lines 56 and 62 assert `startsWith('/dns4/')` — these must be updated to `startsWith('/dns/')` as part of this step, not just supplemented with new tests.

```dart
// UPDATE existing tests (lines 56, 62):
test('defaultRendezvousAddress is valid multiaddr', () {
  expect(defaultRendezvousAddress, startsWith('/dns/'));  // was /dns4/
  expect(defaultRendezvousAddress, contains('/wss/'));
  expect(defaultRendezvousAddress, contains('/p2p/'));
});

test('defaultQUICRelayAddress is valid multiaddr', () {
  expect(defaultQUICRelayAddress, startsWith('/dns/'));  // was /dns4/
  expect(defaultQUICRelayAddress, contains('/quic-v1/'));
  expect(defaultQUICRelayAddress, contains('/p2p/'));
});

// ADD new tests:
test('default relay addresses use /dns/ not /dns4/', () {
  expect(defaultRendezvousAddress, isNot(contains('/dns4/')));
  expect(defaultQUICRelayAddress, isNot(contains('/dns4/')));
});

test('defaultRelayAddresses() returns /dns/ addresses', () {
  final addrs = defaultRelayAddresses();
  for (final addr in addrs) {
    expect(addr, isNot(contains('/dns4/')),
        reason: 'relay address should use /dns/ for dual-stack: $addr');
  }
});
```

**Expected**: Fails — Dart constants still use `/dns4/`.

---

### Step 2c: GREEN — Change Dart relay constants to `/dns/`

**File**: `lib/core/bridge/p2p_bridge_client.dart`

```dart
/// Default rendezvous server address (WSS).
const String defaultRendezvousAddress =
    '/dns/mknoun.xyz/tcp/4001/wss/p2p/12D3KooWGMYMmN1RGUYjWaSV6P3XtnBjwnosnJGNMnttfVCRnd6g';

/// Default QUIC relay address (faster than WSS on most networks).
const String defaultQUICRelayAddress =
    '/dns/mknoun.xyz/udp/4002/quic-v1/p2p/12D3KooWGMYMmN1RGUYjWaSV6P3XtnBjwnosnJGNMnttfVCRnd6g';
```

---

### Step 2d: RED — Test `RENDEZVOUS_ADDRESS` uses `/dns/`

This constant is embedded in QR payloads and contact request payloads. Peers scanning these need dual-stack DNS resolution.

**File**: `test/core/constants/network_constants_test.dart` (new file)

```dart
import 'package:flutter_app/core/constants/network_constants.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('RENDEZVOUS_ADDRESS uses /dns/ not /dns4/', () {
    expect(RENDEZVOUS_ADDRESS, isNot(contains('/dns4/')));
    expect(RENDEZVOUS_ADDRESS, contains('/dns/'));
  });
}
```

**Expected**: Fails — `RENDEZVOUS_ADDRESS` still uses `/dns4/`.

---

### Step 2e: GREEN — Change `RENDEZVOUS_ADDRESS` to `/dns/`

**File**: `lib/core/constants/network_constants.dart`

```dart
/// Format: /dns/{domain}/tcp/{port}/wss/p2p/{peerId}
const String RENDEZVOUS_ADDRESS =
    '/dns/mknoun.xyz/tcp/4001/wss/p2p/12D3KooWGMYMmN1RGUYjWaSV6P3XtnBjwnosnJGNMnttfVCRnd6g';
```

---

### Step 3: RED — Test that node has both IPv4 and IPv6 listeners

Check `ListenAddresses()` (the raw listener bindings) rather than `Addrs()` (resolved addresses that depend on which interfaces exist). This tests the _configuration_, not whether the machine has a global IPv6 address.

**File**: `go-mknoon/node/node_test.go`

```go
func TestNodeListensDualStack(t *testing.T) {
    hexKey := generateTestKey(t)
    n := NewNode()
    _, err := n.Start(NodeConfig{
        PrivateKeyHex:  hexKey,
        RelayAddresses: []string{},
        AutoRegister:   false,
    })
    if err != nil {
        t.Fatalf("Start: %v", err)
    }
    defer n.Stop()

    // Use ListenAddresses (raw bindings) — not Addrs() which depends on
    // the machine having a routable address for each family.
    listeners := n.Host().Network().ListenAddresses()
    hasIPv4 := false
    hasIPv6 := false
    for _, a := range listeners {
        s := a.String()
        if strings.HasPrefix(s, "/ip4/") {
            hasIPv4 = true
        }
        if strings.HasPrefix(s, "/ip6/") {
            hasIPv6 = true
        }
    }

    if !hasIPv4 {
        t.Error("node should have at least one IPv4 listener")
    }
    if !hasIPv6 {
        t.Error("node should have at least one IPv6 listener")
    }
}
```

**Expected**: Fails — no IPv6 listen addresses configured. Passes on any machine after Step 4 (including CI without global IPv6).

---

### Step 4: GREEN — Add IPv6 listen addresses

**File**: `go-mknoon/node/node.go`, in `Start()` (~line 182)

```go
// Build listen addresses (dual-stack: IPv4 + IPv6)
listenAddrs := []string{
    "/ip4/0.0.0.0/udp/0/quic-v1",
    "/ip4/0.0.0.0/tcp/0/ws",
    "/ip4/0.0.0.0/tcp/0",
    "/ip6/::/udp/0/quic-v1",
    "/ip6/::/tcp/0/ws",
    "/ip6/::/tcp/0",
}
if cfg.ListenPort > 0 {
    listenAddrs = []string{
        fmt.Sprintf("/ip4/0.0.0.0/udp/%d/quic-v1", cfg.ListenPort),
        fmt.Sprintf("/ip4/0.0.0.0/tcp/%d/ws", cfg.ListenPort),
        fmt.Sprintf("/ip4/0.0.0.0/tcp/%d", cfg.ListenPort),
        fmt.Sprintf("/ip6/::/udp/%d/quic-v1", cfg.ListenPort),
        fmt.Sprintf("/ip6/::/tcp/%d/ws", cfg.ListenPort),
        fmt.Sprintf("/ip6/::/tcp/%d", cfg.ListenPort),
    }
}
```

**Run**: `go test ./node/ -run TestNodeListensDualStack -v` → passes.

---

### Step 5: GREEN — Verify IPv6 loopback/link-local are NOT in announced addresses

Loopback filtering is already implemented (`filterAddresses()` at `node.go:120-135`, `AddrsFactory` at `node.go:263`). This test confirms the existing filter handles IPv6 addresses produced by the new dual-stack listen config. Expected to pass immediately after Step 4.

**File**: `go-mknoon/node/node_test.go`

```go
func TestNodeIPv6LoopbackFiltered(t *testing.T) {
    hexKey := generateTestKey(t)
    n := NewNode()
    _, err := n.Start(NodeConfig{
        PrivateKeyHex:  hexKey,
        RelayAddresses: []string{},
        AutoRegister:   false,
    })
    if err != nil {
        t.Fatalf("Start: %v", err)
    }
    defer n.Stop()

    for _, addr := range n.Host().Addrs() {
        s := addr.String()
        if strings.Contains(s, "/ip6/::1/") {
            t.Errorf("host.Addrs() contains IPv6 loopback: %s", s)
        }
        if strings.HasPrefix(s, "/ip6/fe80") {
            t.Errorf("host.Addrs() contains IPv6 link-local: %s", s)
        }
        if strings.HasPrefix(s, "/ip6/::/") {
            t.Errorf("host.Addrs() contains IPv6 unspecified: %s", s)
        }
    }
}
```

**Expected**: Passes immediately — loopback filtering already handles IPv6 (`node_test.go:987-1173` covers unit cases; this is an integration-level confirmation with the new listen config).

---

### Step 6: RED — Test that `splitHostAddresses` returns IPv6 addresses in `listenAddrs`

Verify that global IPv6 addresses (not loopback/link-local) appear in the `listenAddrs` return, not dropped or miscategorized.

**File**: `go-mknoon/node/node_test.go`

```go
func TestSplitHostAddressesIncludesIPv6(t *testing.T) {
    hexKey := generateTestKey(t)
    n := NewNode()
    _, err := n.Start(NodeConfig{
        PrivateKeyHex:  hexKey,
        RelayAddresses: []string{},
        AutoRegister:   false,
    })
    if err != nil {
        t.Fatalf("Start: %v", err)
    }
    defer n.Stop()

    listenAddrs, _ := splitHostAddresses(n.Host())

    // On machines with IPv6 connectivity, we should see at least one /ip6/ address.
    // On CI/machines without IPv6, this test is informational — skip gracefully.
    hasIPv6 := false
    for _, a := range listenAddrs {
        if strings.HasPrefix(a, "/ip6/") {
            hasIPv6 = true
            // Verify it's not loopback or link-local
            if strings.Contains(a, "/ip6/::1/") || strings.HasPrefix(a, "/ip6/fe80") {
                t.Errorf("splitHostAddresses returned non-routable IPv6: %s", a)
            }
        }
    }

    if !hasIPv6 {
        t.Log("INFO: no global IPv6 addresses found — machine may not have IPv6 connectivity")
    }
}
```

**Expected**: Passes — `splitHostAddresses` uses string matching for `/p2p-circuit`, which is IP-version-agnostic.

---

### Step 7: RED — Test `Status()` includes IPv6 listen addresses

**File**: `go-mknoon/node/node_test.go`

```go
func TestStatusIncludesIPv6Addresses(t *testing.T) {
    hexKey := generateTestKey(t)
    n := NewNode()
    _, err := n.Start(NodeConfig{
        PrivateKeyHex:  hexKey,
        RelayAddresses: []string{},
        AutoRegister:   false,
    })
    if err != nil {
        t.Fatalf("Start: %v", err)
    }
    defer n.Stop()

    status := n.Status()
    listenAddrs, ok := status["listenAddresses"].([]string)
    if !ok {
        t.Fatal("status missing listenAddresses")
    }

    hasIPv4 := false
    hasIPv6 := false
    for _, a := range listenAddrs {
        if strings.HasPrefix(a, "/ip4/") {
            hasIPv4 = true
        }
        if strings.HasPrefix(a, "/ip6/") {
            hasIPv6 = true
        }
    }

    if !hasIPv4 {
        t.Error("Status() listenAddresses should contain IPv4 addresses")
    }
    if !hasIPv6 {
        t.Log("INFO: Status() has no IPv6 listen addresses — machine may lack IPv6")
    }
}
```

---

### Step 8: RED — Test `addresses:updated` event includes IPv6

Verify the push event emitted by `watchConnectionEvents` on `EvtLocalAddressesUpdated` includes IPv6 addresses.

**File**: `go-mknoon/node/node_test.go`

```go
func TestAddressesUpdatedEventIncludesIPv6(t *testing.T) {
    hexKey := generateTestKey(t)

    var lastEvent map[string]interface{}
    var mu sync.Mutex

    cb := &testEventCallback{
        handler: func(jsonStr string) {
            var ev map[string]interface{}
            if err := json.Unmarshal([]byte(jsonStr), &ev); err != nil {
                return
            }
            if ev["event"] == "addresses:updated" {
                mu.Lock()
                lastEvent = ev["data"].(map[string]interface{})
                mu.Unlock()
            }
        },
    }

    n := New(cb)
    _, err := n.Start(NodeConfig{
        PrivateKeyHex:  hexKey,
        RelayAddresses: []string{},
        AutoRegister:   false,
    })
    if err != nil {
        t.Fatalf("Start: %v", err)
    }
    defer n.Stop()

    // Give the event bus time to fire the initial addresses:updated event.
    time.Sleep(500 * time.Millisecond)

    mu.Lock()
    ev := lastEvent
    mu.Unlock()

    if ev == nil {
        t.Skip("no addresses:updated event received — may need relay connection")
        return
    }

    listenAddrs, _ := ev["listenAddresses"].([]interface{})
    hasIPv6 := false
    for _, a := range listenAddrs {
        if s, ok := a.(string); ok && strings.HasPrefix(s, "/ip6/") {
            hasIPv6 = true
        }
    }

    if !hasIPv6 {
        t.Log("INFO: addresses:updated event has no IPv6 — machine may lack IPv6")
    }
}
```

---

### Step 9: RED — Test fixed listen port includes IPv6

When `ListenPort > 0`, both IPv4 and IPv6 should use that port.

**File**: `go-mknoon/node/node_test.go`

```go
func TestFixedListenPortDualStack(t *testing.T) {
    hexKey := generateTestKey(t)
    n := NewNode()
    _, err := n.Start(NodeConfig{
        PrivateKeyHex:  hexKey,
        RelayAddresses: []string{},
        AutoRegister:   false,
        ListenPort:     9876,
    })
    if err != nil {
        t.Fatalf("Start: %v", err)
    }
    defer n.Stop()

    // Use ListenAddresses (raw bindings) — Addrs() depends on routable interfaces.
    listeners := n.Host().Network().ListenAddresses()
    hasIPv4Port := false
    hasIPv6Port := false
    for _, a := range listeners {
        s := a.String()
        if strings.HasPrefix(s, "/ip4/") && strings.Contains(s, "/9876") {
            hasIPv4Port = true
        }
        if strings.HasPrefix(s, "/ip6/") && strings.Contains(s, "/9876") {
            hasIPv6Port = true
        }
    }
    if !hasIPv4Port {
        t.Errorf("expected IPv4 listener on port 9876, got: %v", listeners)
    }
    if !hasIPv6Port {
        t.Errorf("expected IPv6 listener on port 9876, got: %v", listeners)
    }
}
```

**Expected**: Passes after Step 4 (both branches set IPv6 addrs). Would **fail** if `ListenPort > 0` branch stayed IPv4-only — unlike the previous version which only checked for any address with `/9876`.

---

### Step 10: RED — Smoke test: two local nodes connect over IPv6

Two nodes started on the same machine should be able to connect via IPv6 local addresses (if the machine has IPv6). This verifies the full dual-stack path works end-to-end without a relay.

**File**: `go-mknoon/node/node_test.go`

```go
func TestTwoNodesDualStackConnect(t *testing.T) {
    keyA := generateTestKey(t)
    keyB := generateTestKey(t)

    nodeA := NewNode()
    stateA, err := nodeA.Start(NodeConfig{
        PrivateKeyHex:  keyA,
        RelayAddresses: []string{},
        AutoRegister:   false,
    })
    if err != nil {
        t.Fatalf("Start A: %v", err)
    }
    defer nodeA.Stop()

    nodeB := NewNode()
    _, err = nodeB.Start(NodeConfig{
        PrivateKeyHex:  keyB,
        RelayAddresses: []string{},
        AutoRegister:   false,
    })
    if err != nil {
        t.Fatalf("Start B: %v", err)
    }
    defer nodeB.Stop()

    // Collect all of A's addresses
    var addrStrs []string
    for _, a := range nodeA.Host().Addrs() {
        addrStrs = append(addrStrs, a.String())
    }

    // B dials A using all available addresses (IPv4 + IPv6)
    err = nodeB.DialPeer(stateA.PeerId, addrStrs)
    if err != nil {
        t.Fatalf("DialPeer: %v", err)
    }

    // Verify connection established
    conns := nodeB.Host().Network().ConnsToPeer(nodeA.Host().ID())
    if len(conns) == 0 {
        t.Fatal("expected at least one connection from B to A")
    }

    // Log which transport was used
    for _, c := range conns {
        t.Logf("Connection: %s → %s", c.LocalMultiaddr(), c.RemoteMultiaddr())
    }
}
```

---

### Step 11: RED — Fix `DialPeerViaRelay` to try all relay transport addresses

`DialPeerViaRelay()` (`node.go:815-823`) currently uses only `relay.Addrs[0]` when building a circuit probe address. If a relay announces both IPv4 and IPv6 transport addresses and the first one is unreachable, the probe fails without trying alternatives. This is a latent bug today (relays only announce IPv4), but becomes active once relays add IPv6 announcements.

**Unit test** — verifies relay selector groups multi-addr correctly and the code path exercises all addresses:

**File**: `go-mknoon/node/node_test.go`

```go
func TestDialPeerViaRelayTriesAllAddresses(t *testing.T) {
    // Set up a relay peer with TWO transport addresses (same peer ID).
    // Existing tests in multi_relay_test.go cover multiple relay *peers*
    // falling over (TestDialPeerViaRelay_TriesSecondRelayWhenFirstFails).
    // This test covers multiple *addresses* on a single relay peer.

    n := startLocalNodeForMultiRelayTest(t)

    // Generate ONE relay peer ID with TWO transports (TCP + QUIC).
    key, _, err := crypto.GenerateKeyPair(crypto.Ed25519, 0)
    if err != nil {
        t.Fatal(err)
    }
    relayID, _ := peer.IDFromPrivateKey(key)

    addr1 := fmt.Sprintf("/ip4/127.0.0.1/tcp/19991/p2p/%s", relayID)
    addr2 := fmt.Sprintf("/ip4/127.0.0.1/udp/19992/quic-v1/p2p/%s", relayID)

    n.mu.Lock()
    n.relayAddresses = []string{addr1, addr2}
    n.mu.Unlock()

    // Verify the selector groups them as 1 relay with 2 addrs.
    rs := n.buildRelaySelector(nil)
    if rs.Len() != 1 {
        t.Fatalf("expected 1 relay (grouped by peer ID), got %d", rs.Len())
    }
    relays := rs.Relays()
    if len(relays[0].Addrs) != 2 {
        t.Fatalf("expected 2 addrs for relay, got %d", len(relays[0].Addrs))
    }

    // Dial target — both addresses unreachable, but the code path
    // must build circuit addrs from ALL relay.Addrs, not just [0].
    targetKey := generateTestKey(t)
    targetNode := NewNode()
    st, err := targetNode.Start(NodeConfig{
        PrivateKeyHex:  targetKey,
        RelayAddresses: []string{},
        AutoRegister:   false,
    })
    if err != nil {
        t.Fatal(err)
    }
    defer targetNode.Stop()

    err = n.DialPeerViaRelay(st.PeerId)
    if err == nil {
        t.Fatal("expected error (fake relay unreachable)")
    }

    // Confirm the error comes from the relay selector (all relays tried),
    // not from an early bail on address count.
    if !strings.Contains(err.Error(), "relay") {
        t.Errorf("error should reference relay attempt, got: %v", err)
    }
}
```

**Integration test** — verifies actual failover (bogus first address, real second address):

**File**: `go-mknoon/integration/local_relay_harness_test.go` (build tag `integration`)

```go
func TestDialPeerViaRelayMultiAddrFailover(t *testing.T) {
    // Start a real local relay (IPv4 only).
    shared := newLocalRelaySharedState()
    relay := newLocalRelayServer(t, shared)
    relay.start()
    defer relay.stop()

    // Build a relay entry with TWO addresses for the same relay peer:
    //   [0] = bogus unreachable address (simulates failed IPv6 transport)
    //   [1] = real relay address (IPv4, should succeed)
    realAddr := relay.addr()  // e.g. "/ip4/127.0.0.1/tcp/PORT/p2p/RELAY_ID"

    // Extract relay peer ID from real address.
    maddr, _ := ma.NewMultiaddr(realAddr)
    relayInfo, _ := peer.AddrInfoFromP2pAddr(maddr)

    bogusAddr := fmt.Sprintf("/ip4/192.0.2.1/tcp/1/p2p/%s", relayInfo.ID)

    // Node A: configure with bogus-first relay addresses.
    nodeA, peerIdA := startNodeWithRelays(t, []string{bogusAddr, realAddr}, nil, nil)
    waitForRendezvousRegister(t, nodeA, nodeA.Namespace(), 10*time.Second)

    // Node B: configure with only the real relay.
    nodeB, _ := startNodeWithRelays(t, []string{realAddr}, nil, nil)

    // B dials A via relay — must succeed even though Addrs[0] is bogus.
    err := nodeB.DialPeerViaRelay(peerIdA)
    if err != nil {
        t.Fatalf("DialPeerViaRelay should succeed via second address: %v", err)
    }
}
```

**File**: `go-mknoon/node/node.go` — change `DialPeerViaRelay` to iterate all addresses per relay:

```go
// Before (single address — bug):
//   relayTransportAddr := relay.Addrs[0]
//   circuitAddr := relayTransportAddr.Encapsulate(circuitSuffix)
//   ai := peer.AddrInfo{ID: pid, Addrs: []ma.Multiaddr{circuitAddr}}

// After (try all transport addresses for each relay):
var circuitAddrs []ma.Multiaddr
for _, transportAddr := range relay.Addrs {
    circuitAddr := transportAddr.Encapsulate(circuitSuffix)
    circuitAddrs = append(circuitAddrs, circuitAddr)
}
ai := peer.AddrInfo{ID: pid, Addrs: circuitAddrs}
```

libp2p's `h.Connect()` already handles multi-address failover — it tries all provided addresses. This is consistent with how `DialPeer()` (`node.go:763-792`) works.

---

### Step 12: RED — Integration test: dual-stack node connects to IPv4-only local relay

Verify that a dual-stack node can connect to an IPv4-only relay, register, and be discovered. This uses the local relay harness (which listens on `127.0.0.1`) — the node must connect via IPv4 even though it also listens on IPv6.

**File**: `go-mknoon/integration/local_relay_harness_test.go` (build tag `integration`)

```go
//go:build integration

func TestDualStackNodeWithIPv4Relay(t *testing.T) {
    // Local relay listens on IPv4 only (/ip4/127.0.0.1/tcp/PORT).
    shared := newLocalRelaySharedState()
    relay := newLocalRelayServer(t, shared)
    relay.start()
    defer relay.stop()

    // Start a dual-stack node with the IPv4-only relay.
    nodeA, peerIdA := startNodeWithRelays(t, []string{relay.addr()}, nil, nil)

    // Verify node has both IPv4 and IPv6 listeners.
    listeners := nodeA.Host().Network().ListenAddresses()
    hasIPv4 := false
    hasIPv6 := false
    for _, a := range listeners {
        s := a.String()
        if strings.HasPrefix(s, "/ip4/") { hasIPv4 = true }
        if strings.HasPrefix(s, "/ip6/") { hasIPv6 = true }
    }
    if !hasIPv4 {
        t.Error("dual-stack node should have IPv4 listeners")
    }
    if !hasIPv6 {
        t.Error("dual-stack node should have IPv6 listeners")
    }

    // Register on rendezvous via the IPv4 relay — must succeed.
    nsA := nodeA.Namespace()
    waitForRendezvousRegister(t, nodeA, nsA, 10*time.Second)

    // Start a second node and discover A — proves the IPv4 relay works
    // with a dual-stack node end-to-end.
    nodeB, _ := startNodeWithRelays(t, []string{relay.addr()}, nil, nil)
    waitForDiscoverablePeer(t, nodeB, nsA, peerIdA, 10*time.Second)
}
```

---

### Step 13: RED — Test `NodeState` (Dart) parses IPv6 addresses correctly

Verify the Dart `NodeState.fromJson` handles IPv6 multiaddr strings without issue.

**File**: `test/features/p2p/domain/models/node_state_test.dart`

```dart
test('fromJson handles IPv6 listen addresses', () {
  final json = {
    'peerId': 'QmTest123',
    'isStarted': true,
    'listenAddresses': [
      '/ip4/192.168.1.100/tcp/5678',
      '/ip6/2001:db8::1/tcp/5678',
      '/ip6/2607:f8b0:4004:800::200e/udp/5678/quic-v1',
    ],
    'circuitAddresses': [
      '/ip6/2001:db8::99/tcp/4001/p2p/12D3KooWRelay/p2p-circuit/p2p/QmPeer',
    ],
  };

  final state = NodeState.fromJson(json);

  expect(state.listenAddresses, hasLength(3));
  expect(state.listenAddresses[1], contains('2001:db8::1'));
  expect(state.circuitAddresses, hasLength(1));
  expect(state.circuitAddresses[0], contains('p2p-circuit'));
});
```

**Expected**: Passes — `NodeState.fromJson` treats addresses as `List<String>`, no parsing.

---

### Step 14: RED — Test Dart `_handleAddressesUpdated` with IPv6

Verify the Dart P2P service correctly processes addresses:updated events containing IPv6.

**File**: `test/core/services/p2p_service_impl_test.dart`

```dart
test('handles addresses:updated with IPv6 addresses', () async {
  // ... setup p2p service with fake bridge ...

  // Simulate Go pushing an addresses:updated event with IPv6
  fakeBridge.simulateAddressesUpdated(
    listenAddresses: [
      '/ip4/192.168.1.100/tcp/5678',
      '/ip6/2001:db8::1/tcp/5678',
    ],
    circuitAddresses: [
      '/ip4/203.0.113.5/tcp/4001/p2p/12D3KooWRelay/p2p-circuit/p2p/QmSelf',
    ],
  );

  // Verify state updated correctly
  final state = p2pService.currentState;
  expect(state.listenAddresses, hasLength(2));
  expect(state.listenAddresses.any((a) => a.contains('ip6')), isTrue);
});
```

**Expected**: Passes — addresses are opaque strings in Dart.

---

## Test Execution Order

```bash
# --- Go tests ---
cd go-mknoon

# Step 1+2: Go DNS constant
go test ./node/ -run TestDefaultRelayAddressUsesDNS -v

# Step 3+4: Dual-stack listen (uses ListenAddresses, passes on any machine)
go test ./node/ -run TestNodeListensDualStack -v

# Step 5: IPv6 loopback filtering (already implemented — should pass immediately)
go test ./node/ -run TestNodeIPv6LoopbackFiltered -v

# Step 6: splitHostAddresses with IPv6
go test ./node/ -run TestSplitHostAddressesIncludesIPv6 -v

# Step 7: Status includes IPv6
go test ./node/ -run TestStatusIncludesIPv6Addresses -v

# Step 8: Event includes IPv6
go test ./node/ -run TestAddressesUpdatedEventIncludesIPv6 -v

# Step 9: Fixed port dual-stack
go test ./node/ -run TestFixedListenPortDualStack -v

# Step 10: Two-node connect (smoke)
go test ./node/ -run TestTwoNodesDualStackConnect -v

# Step 11: DialPeerViaRelay multi-address (unit)
go test ./node/ -run TestDialPeerViaRelayTriesAllAddresses -v

# Step 12: Dual-stack with IPv4-only relay + multi-addr failover (integration)
go test -tags integration ./integration/ -run TestDualStackNodeWithIPv4Relay -v
go test -tags integration ./integration/ -run TestDialPeerViaRelayMultiAddrFailover -v

# Full Go suite
go test ./node/ -v -count=1
go test -tags integration ./integration/ -v -count=1

# --- Dart tests ---
cd ..

# Step 2b+2c: Dart relay constants
flutter test test/core/bridge/p2p_bridge_client_test.dart -v

# Step 2d+2e: RENDEZVOUS_ADDRESS
flutter test test/core/constants/network_constants_test.dart -v

# Step 13: NodeState parsing
flutter test test/features/p2p/domain/models/node_state_test.dart -v

# Step 14: P2P service IPv6 event handling
flutter test test/core/services/p2p_service_impl_test.dart -v

# Full Dart suite
flutter test
```

---

## What Changes

| Component | Change | Risk |
|-----------|--------|------|
| `node.go:182-193` listen addrs | Add 3 IPv6 listen addrs (`/ip6/::/...`) | Low — libp2p handles dual-stack natively |
| `node.go:815-823` `DialPeerViaRelay` | Try all relay transport addrs, not just `[0]` | Low — uses existing `h.Connect()` multi-addr failover |
| `config.go:10,13` Go relay consts | `/dns4/` → `/dns/` | Low — `/dns/` falls back to A record if no AAAA |
| `p2p_bridge_client.dart:6-11` Dart relay consts | `/dns4/` → `/dns/` | Low — production path, same semantics |
| `network_constants.dart:12` `RENDEZVOUS_ADDRESS` | `/dns4/` → `/dns/` | Low — affects QR/contact payloads |
| `config.go:187-191` fixed port | Add IPv6 variants for fixed port path | Low — mirrors IPv4 pattern |

## What Does NOT Change

| Component | Why |
|-----------|-----|
| `rendezvous.go` | Uses `peer.AddrInfoFromP2pAddr` — already multiaddr-agnostic |
| `relay_selector.go` | Parses multiaddrs generically — handles any protocol |
| `relay_session.go` | Tracks state by peer ID, not address format |
| `pubsub.go` | Operates on peer connections, not raw addresses |
| `group_inbox.go` | Opens streams by peer ID |
| `inbox.go` | Opens streams by peer ID |
| `media.go` | Opens streams by peer ID |
| `bridge.go` | Passes addresses as opaque strings |
| `feature_flags.go` | No rollout flag needed — dual-stack listening is harmless |
| `go_bridge_client.dart` | Treats addresses as opaque strings |
| `p2p_service_impl.dart` | Treats addresses as opaque strings |
| Platform bridges (iOS/Android) | Forward strings to Go — no IP parsing |
| `go-relay-server/` | Server IPv6 is a separate deployment task |
| `local_relay_harness_test.go` | Test harness intentionally uses `127.0.0.1` for deterministic local testing |

---

## Risks and Mitigations

| Risk | Likelihood | Impact | Mitigation |
|------|-----------|--------|------------|
| Machine has no IPv6 → listen fails | Low | Medium | libp2p gracefully handles listen failures on individual addresses — if IPv6 bind fails, IPv4 still works. Tests use `t.Log` for informational output on IPv6-less machines |
| IPv6 bind on iOS/Android restricted | Very Low | Medium | Both iOS and Android fully support IPv6 sockets. No special permissions needed beyond standard network access |
| `/dns/` breaks existing relay connections | Very Low | High | `/dns/` is a strict superset of `/dns4/` — it tries AAAA first, falls back to A. If server has no AAAA record, behavior is identical to `/dns4/` |
| Doubled listen addresses increase port usage | Low | Low | Ports are ephemeral (`:0`), OS reclaims on close. 6 listeners instead of 3 is negligible |
| CI runners don't have IPv6 | Medium | Low | IPv6-specific assertions use `t.Log` (informational) or `t.Skip`, not `t.Fatal`. Core tests verify the _configuration_ (listen addrs include `/ip6/`), not that a global IPv6 address exists on the machine |
| Existing tests with hardcoded `/ip4/` test addresses break | None | None | Test addresses in test files are for _test relay servers_ (intentionally `127.0.0.1`). They don't need IPv6 variants — they test relay protocol logic, not address format |

---

## CI Considerations

Most CI runners (GitHub Actions, etc.) have IPv6 support via loopback (`::1`) but may not have a global IPv6 address. The test strategy accounts for this:

- **Configuration tests** (Steps 1-4, 9): Assert that the _code_ configures IPv6 listen addrs via `ListenAddresses()`. Pass on any machine.
- **Dart constant tests** (Steps 2b-2e): Assert `/dns/` not `/dns4/`. Pass on any machine.
- **Filtering tests** (Step 5): Assert `::1` is filtered. Pass on any machine (loopback always exists).
- **Integration tests** (Step 12): Uses local relay harness — tests IPv4 relay compatibility with dual-stack node. Pass on any machine.
- **Connectivity tests** (Step 10): Two local nodes connect — works via IPv4 LAN on any machine. IPv6 is a bonus.
- **Address presence tests** (Steps 6-8): Use `t.Log` not `t.Error` for "no IPv6 found" — informational, not failure.

---

## Known IPv4-Biased Test Artifacts (Follow-Up)

These files still hardcode `/dns4/` or IPv4 literals. They do NOT block this plan's client-side changes, but should be updated as part of the relay server IPv6 rollout to complete the verification story:

| File | Line(s) | Issue |
|------|---------|-------|
| `go-relay-server/quic_smoke_test.go` | 21-23 | `/dns4/mknoun.xyz/...` and `/ip4/13.60.15.36/...` hardcoded |
| `integration_test/scripts/run_transport_e2e.dart` | 513 | `/dns4/mknoun.xyz/...` in relay circuit fallback |
| `integration_test/scripts/run_wifi_relay_fallback_smoke.dart` | 476, 634 | `/dns4/mknoun.xyz/...` in relay circuit fallback (S1 + S4) |

These are intentionally deferred: the relay smoke test belongs to `go-relay-server/` (excluded from this plan's scope), and the Dart E2E scripts test against the production relay which is IPv4-only today. Updating them to `/dns/` before the relay has an AAAA record would be cosmetic — correct but untestable.

---

## Future Work (Out of Scope)

1. **Relay server IPv6**: Add IPv6 listen/announce to `go-relay-server/main.go` and DNS AAAA records for `mknoun.xyz`
2. **Prefer IPv6 for direct connections**: Configure libp2p swarm to prefer IPv6 when both are available
3. **IPv6-only mode**: For networks with no IPv4 at all (carrier-grade NAT464/DNS64)
4. **Address display in UI**: Show transport type icons (direct IPv6 vs relayed) in connection info

---

## Summary of Changes

```
go-mknoon/node/config.go
  ├── DefaultRelayAddress: /dns4/ → /dns/                     (EDIT)
  └── DefaultQUICRelay: /dns4/ → /dns/                        (EDIT)

go-mknoon/node/node.go
  ├── Start(): add 3 IPv6 listen addresses (/ip6/::/...)      (EDIT)
  └── DialPeerViaRelay(): try all relay addrs, not just [0]   (EDIT)

lib/core/bridge/p2p_bridge_client.dart
  ├── defaultRendezvousAddress: /dns4/ → /dns/                (EDIT)
  └── defaultQUICRelayAddress: /dns4/ → /dns/                 (EDIT)

lib/core/constants/network_constants.dart
  └── RENDEZVOUS_ADDRESS: /dns4/ → /dns/                      (EDIT)

go-mknoon/node/node_test.go
  ├── TestDefaultRelayAddressUsesDNS                           (NEW)
  ├── TestNodeListensDualStack                                 (NEW)
  ├── TestNodeIPv6LoopbackFiltered                             (NEW)
  ├── TestSplitHostAddressesIncludesIPv6                       (NEW)
  ├── TestStatusIncludesIPv6Addresses                          (NEW)
  ├── TestAddressesUpdatedEventIncludesIPv6                    (NEW)
  ├── TestFixedListenPortDualStack                             (NEW)
  ├── TestTwoNodesDualStackConnect                             (NEW — smoke)
  └── TestDialPeerViaRelayTriesAllAddresses                    (NEW)

go-mknoon/integration/ (build tag: integration)
  ├── TestDualStackNodeWithIPv4Relay                           (NEW — integration)
  └── TestDialPeerViaRelayMultiAddrFailover                    (NEW — integration)

test/core/bridge/p2p_bridge_client_test.dart
  ├── 'default relay addresses use /dns/ not /dns4/'           (NEW)
  └── 'defaultRelayAddresses() returns /dns/ addresses'        (NEW)

test/core/constants/network_constants_test.dart
  └── 'RENDEZVOUS_ADDRESS uses /dns/ not /dns4/'               (NEW)

test/features/p2p/domain/models/node_state_test.dart
  └── 'fromJson handles IPv6 listen addresses'                 (NEW)

test/core/services/p2p_service_impl_test.dart
  └── 'handles addresses:updated with IPv6 addresses'          (NEW)
```

**Total**: ~25 lines of production code, ~350 lines of test code (Go + Dart).
