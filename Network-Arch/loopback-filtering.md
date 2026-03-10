# Loopback Address Filtering — TDD Implementation Plan

## Problem Statement

When the node starts, it listens on `0.0.0.0` (all IPv4 interfaces) and — once the IPv6 plan is implemented — on `::` (all IPv6 interfaces). libp2p's `host.Addrs()` resolves these wildcards to concrete addresses for every network interface, including:

- **IPv4 loopback**: `127.0.0.1` — unreachable from any other machine
- **IPv6 loopback**: `::1` — unreachable from any other machine
- **IPv6 link-local**: `fe80::...` — unreachable beyond the local network segment
- **Unspecified**: `0.0.0.0` / `::` — not a real address, should never be announced

These unroutable addresses leak into three downstream paths:

1. **Rendezvous registration** — The signed peer record (`cab.GetPeerRecord`) contains all host addresses. Peers that discover us receive loopback/link-local addresses they can never reach.
2. **`addresses:updated` push events** — `splitHostAddresses()` forwards all non-circuit addresses to Flutter, polluting `listenAddresses`.
3. **`State()` / `Status()`** — `stateLocked()` and `Status()` expose raw `host.Addrs()` including loopback to callers.

### Scope of Filtering

Filter out:
- **IPv4 loopback**: `/ip4/127.0.0.1/...`
- **IPv6 loopback**: `/ip6/::1/...`
- **Link-local**: `/ip4/169.254.x.x/...` (APIPA, appears when DHCP fails) and `/ip6/fe80::.../...`
- **Unspecified**: `/ip4/0.0.0.0/...`, `/ip6/::/...`

Keep:
- **Private LAN** (`192.168.x.x`, `10.x.x.x`, `172.16-31.x.x`) — useful for local peer discovery
- **Global IPv6** (e.g. `2001:db8::...`) — enables direct peer connectivity
- **Circuit relay** (`/p2p-circuit`) — always keep, even if the relay's transport IP is loopback (see caveat below)
- **Public IPv4 addresses** — always keep

### Circuit Relay Caveat

`manet.IsIPLoopback()` uses `ma.SplitFirst()` to extract the first IP component. This means a circuit relay address like `/ip4/127.0.0.1/tcp/4001/p2p/RELAY/p2p-circuit/p2p/PEER` is classified as loopback — even though it's a valid routable path through the relay. The `filterAddresses()` function must check for `/p2p-circuit` **before** applying loopback checks, to avoid breaking:
- The local integration test harness (`local_relay_harness_test.go` uses `/ip4/127.0.0.1/tcp/PORT`)
- Any future local relay development/debugging scenarios

### Dependency

This plan is designed to work both before and after the IPv6 listen plan (`IPV6.md`). The `filterAddresses()` function handles both address families from day one.

---

## Architecture Decision

**Approach: `libp2p.AddrsFactory` at host creation**

The filter is applied at the libp2p host level using `AddrsFactory`. This is the canonical libp2p mechanism — it intercepts `host.Addrs()` before any consumer sees the addresses. This means:
- Rendezvous signed peer records automatically exclude loopback (the peerstore observes filtered `Addrs()`)
- `splitHostAddresses()` gets clean data with zero code changes
- `stateLocked()` and `Status()` get clean data with zero code changes
- All future callers of `host.Addrs()` are protected

**Library**: `github.com/multiformats/go-multiaddr/net` (`manet`) — already a transitive dependency via `go-libp2p`. Provides `manet.IsIPLoopback()`, `manet.IsIPUnspecified()`. For link-local filtering, we use a custom `isLinkLocalAddr()` based on `net.IP.IsLinkLocalUnicast()` which covers both IPv4 `169.254.x.x` and IPv6 `fe80::` — `manet.IsIP6LinkLocal()` only covers IPv6.

**No new dependency required** — `manet` is pulled in by `go-libp2p` itself.

---

## Files Affected

| File | Change |
|------|--------|
| `go-mknoon/node/node.go` | Add `AddrsFactory` to host options; extract `filterAddresses()` helper |
| `go-mknoon/node/node_test.go` | New tests for address filtering |
| `go-mknoon/node/node.go` | `splitHostAddresses()` — add secondary safety filter (belt-and-suspenders) |

**No Dart changes required** — filtering happens in Go before addresses cross the bridge.

---

## TDD Steps

### Step 1: RED — Unit test `filterAddresses()` pure function

**File**: `go-mknoon/node/node_test.go`

Write a table-driven test for a new `filterAddresses([]ma.Multiaddr) []ma.Multiaddr` function that does not yet exist.

```go
func TestFilterAddresses(t *testing.T) {
    tests := []struct {
        name  string
        input []string
        want  []string
    }{
        // --- IPv4 ---
        {
            name:  "removes IPv4 loopback TCP",
            input: []string{"/ip4/127.0.0.1/tcp/1234"},
            want:  []string{},
        },
        {
            name:  "removes IPv4 loopback QUIC",
            input: []string{"/ip4/127.0.0.1/udp/1234/quic-v1"},
            want:  []string{},
        },
        {
            name:  "removes IPv4 loopback WebSocket",
            input: []string{"/ip4/127.0.0.1/tcp/1234/ws"},
            want:  []string{},
        },
        {
            name:  "removes IPv4 unspecified",
            input: []string{"/ip4/0.0.0.0/tcp/1234"},
            want:  []string{},
        },
        {
            name:  "keeps private LAN 192.168.x",
            input: []string{"/ip4/192.168.1.100/tcp/1234"},
            want:  []string{"/ip4/192.168.1.100/tcp/1234"},
        },
        {
            name:  "keeps private LAN 10.x",
            input: []string{"/ip4/10.0.0.1/udp/4001/quic-v1"},
            want:  []string{"/ip4/10.0.0.1/udp/4001/quic-v1"},
        },
        {
            name:  "keeps private LAN 172.16.x WebSocket",
            input: []string{"/ip4/172.16.0.1/tcp/4001/ws"},
            want:  []string{"/ip4/172.16.0.1/tcp/4001/ws"},
        },
        {
            name:  "keeps public IPv4 address",
            input: []string{"/ip4/203.0.113.5/tcp/1234"},
            want:  []string{"/ip4/203.0.113.5/tcp/1234"},
        },
        // --- IPv6 ---
        {
            name:  "removes IPv6 loopback TCP",
            input: []string{"/ip6/::1/tcp/1234"},
            want:  []string{},
        },
        {
            name:  "removes IPv6 loopback QUIC",
            input: []string{"/ip6/::1/udp/1234/quic-v1"},
            want:  []string{},
        },
        {
            name:  "removes IPv6 link-local",
            input: []string{"/ip6/fe80::1/tcp/1234"},
            want:  []string{},
        },
        {
            name:  "removes IPv4 link-local (169.254.x.x)",
            input: []string{"/ip4/169.254.1.100/tcp/1234"},
            want:  []string{},
        },
        {
            name:  "removes IPv6 link-local with zone (ip6zone)",
            input: []string{"/ip6zone/en0/ip6/fe80::1/tcp/1234"},
            want:  []string{},
        },
        {
            name:  "removes IPv6 unspecified",
            input: []string{"/ip6/::/tcp/1234"},
            want:  []string{},
        },
        {
            name:  "keeps global IPv6 address",
            input: []string{"/ip6/2001:db8::1/tcp/1234"},
            want:  []string{"/ip6/2001:db8::1/tcp/1234"},
        },
        {
            name:  "keeps global IPv6 QUIC",
            input: []string{"/ip6/2607:f8b0:4004:800::200e/udp/4001/quic-v1"},
            want:  []string{"/ip6/2607:f8b0:4004:800::200e/udp/4001/quic-v1"},
        },
        // --- Circuit relay (must survive loopback filter) ---
        {
            name:  "keeps circuit relay even when transport IP is loopback",
            input: []string{"/ip4/127.0.0.1/tcp/4001/p2p/12D3KooWRelay/p2p-circuit/p2p/12D3KooWPeer"},
            want:  []string{"/ip4/127.0.0.1/tcp/4001/p2p/12D3KooWRelay/p2p-circuit/p2p/12D3KooWPeer"},
        },
        {
            name:  "keeps circuit relay with public IP",
            input: []string{"/ip4/203.0.113.5/tcp/4001/p2p/12D3KooWRelay/p2p-circuit/p2p/12D3KooWPeer"},
            want:  []string{"/ip4/203.0.113.5/tcp/4001/p2p/12D3KooWRelay/p2p-circuit/p2p/12D3KooWPeer"},
        },
        {
            name: "loopback circuit kept, plain loopback removed",
            input: []string{
                "/ip4/127.0.0.1/tcp/5678",
                "/ip4/127.0.0.1/tcp/4001/p2p/12D3KooWRelay/p2p-circuit/p2p/12D3KooWPeer",
            },
            want: []string{
                "/ip4/127.0.0.1/tcp/4001/p2p/12D3KooWRelay/p2p-circuit/p2p/12D3KooWPeer",
            },
        },
        // --- Mixed ---
        {
            name: "mixed IPv4+IPv6: filters all loopback, keeps routable and circuit",
            input: []string{
                "/ip4/127.0.0.1/tcp/5678",
                "/ip4/127.0.0.1/udp/5678/quic-v1",
                "/ip4/127.0.0.1/tcp/5678/ws",
                "/ip6/::1/tcp/5678",
                "/ip6/::1/udp/5678/quic-v1",
                "/ip6/fe80::1/tcp/5678",
                "/ip4/192.168.1.100/tcp/5678",
                "/ip4/192.168.1.100/udp/5678/quic-v1",
                "/ip6/2001:db8::1/tcp/5678",
                "/ip6/2001:db8::1/udp/5678/quic-v1",
                "/ip4/127.0.0.1/tcp/4001/p2p/12D3KooWRelay/p2p-circuit/p2p/12D3KooWPeer",
            },
            want: []string{
                "/ip4/192.168.1.100/tcp/5678",
                "/ip4/192.168.1.100/udp/5678/quic-v1",
                "/ip6/2001:db8::1/tcp/5678",
                "/ip6/2001:db8::1/udp/5678/quic-v1",
                "/ip4/127.0.0.1/tcp/4001/p2p/12D3KooWRelay/p2p-circuit/p2p/12D3KooWPeer",
            },
        },
        {
            name:  "empty input returns empty",
            input: []string{},
            want:  []string{},
        },
        {
            name:  "nil input returns empty",
            input: nil,
            want:  []string{},
        },
    }
    // ... parse input strings to ma.Multiaddr, call filterAddresses(), compare
}
```

**Expected**: Compilation fails — `filterAddresses` doesn't exist yet.

---

### Step 2: GREEN — Implement `filterAddresses()`

**File**: `go-mknoon/node/node.go`

Add the pure filtering function and the new import:

```go
import (
    "net"
    manet "github.com/multiformats/go-multiaddr/net"
)

// isCircuitAddr returns true if the multiaddr contains a /p2p-circuit component.
func isCircuitAddr(a ma.Multiaddr) bool {
    return strings.Contains(a.String(), "/p2p-circuit")
}

// isLinkLocalAddr returns true if the multiaddr starts with a link-local IP.
// Covers both IPv4 (169.254.x.x) and IPv6 (fe80::) — manet.IsIP6LinkLocal
// only handles IPv6, so we use net.IP.IsLinkLocalUnicast() directly.
// Handles scoped IPv6 addresses like /ip6zone/en0/ip6/fe80::1/... by
// stripping the zone prefix first (same approach as manet's zoneless()).
func isLinkLocalAddr(a ma.Multiaddr) bool {
    c, rest := ma.SplitFirst(a)
    if c == nil {
        return false
    }
    // Strip ip6zone prefix: /ip6zone/<zone>/ip6/<addr>/...
    if c.Protocol().Code == ma.P_IP6ZONE {
        if rest == nil {
            return false
        }
        c, _ = ma.SplitFirst(rest)
        if c == nil {
            return false
        }
    }
    switch c.Protocol().Code {
    case ma.P_IP4, ma.P_IP6:
        return net.IP(c.RawValue()).IsLinkLocalUnicast()
    }
    return false
}

// filterAddresses removes loopback, link-local, and unspecified addresses
// from the given multiaddr slice. Circuit relay addresses are always kept —
// manet.IsIPLoopback checks the first IP component, so a relay address like
// /ip4/127.0.0.1/.../p2p-circuit/... would be incorrectly classified as
// loopback without this check.
func filterAddresses(addrs []ma.Multiaddr) []ma.Multiaddr {
    filtered := make([]ma.Multiaddr, 0, len(addrs))
    for _, a := range addrs {
        if isCircuitAddr(a) {
            filtered = append(filtered, a)
            continue
        }
        if manet.IsIPLoopback(a) || isLinkLocalAddr(a) || manet.IsIPUnspecified(a) {
            continue
        }
        filtered = append(filtered, a)
    }
    return filtered
}
```

**Run**: `go test ./node/ -run TestFilterAddresses -v` → all pass.

---

### Step 3: RED — Test that `AddrsFactory` is wired into host creation

**File**: `go-mknoon/node/node_test.go`

Test that a started node's `host.Addrs()` does NOT contain any loopback addresses.
The node listens on wildcard addresses which get resolved to every interface.
On any machine, `127.0.0.1` (and `::1` once IPv6 is enabled) would normally appear.
After wiring AddrsFactory, they must not.

```go
func TestNodeAddressesExcludeLoopback(t *testing.T) {
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
        if strings.Contains(s, "/ip4/127.0.0.1/") || strings.Contains(s, "/ip6/::1/") {
            t.Errorf("host.Addrs() contains loopback address: %s", s)
        }
        if strings.Contains(s, "/ip6/fe80") || strings.Contains(s, "169.254.") {
            t.Errorf("host.Addrs() contains link-local address: %s", s)
        }
        if strings.Contains(s, "/ip4/0.0.0.0/") || strings.Contains(s, "/ip6/::/") {
            t.Errorf("host.Addrs() contains unspecified address: %s", s)
        }
    }

    // Also verify State() doesn't contain any non-routable address
    state := n.State()
    for _, a := range state.Addresses {
        if strings.Contains(a, "127.0.0.1") || strings.Contains(a, "::1/") ||
           strings.Contains(a, "/ip6/fe80") || strings.Contains(a, "169.254.") {
            t.Errorf("State().Addresses contains non-routable: %s", a)
        }
    }
}
```

**Expected**: Fails — loopback addresses are still present because `AddrsFactory` isn't wired yet.

---

### Step 4: GREEN — Wire `AddrsFactory` into host creation

**File**: `go-mknoon/node/node.go`, in `Start()` method (~line 198)

Add the `AddrsFactory` option to the `hostOpts` slice:

```go
hostOpts := []libp2p.Option{
    libp2p.Identity(privKey),
    libp2p.ListenAddrStrings(listenAddrs...),
    libp2p.ConnectionManager(cm),
    libp2p.EnableRelay(),
    libp2p.EnableHolePunching(),
    libp2p.NATPortMap(),
    libp2p.ForceReachabilityPrivate(),
    libp2p.AddrsFactory(filterAddresses),  // ← NEW
}
```

**Run**: `go test ./node/ -run TestNodeAddressesExcludeLoopback -v` → passes.

---

### Step 5: RED — Test `splitHostAddresses()` safety filter with synthetic input

The secondary filter in `splitHostAddresses()` must be tested independently of `AddrsFactory`. If we use a real node (which already has `AddrsFactory` wired), the test is vacuous — `host.Addrs()` returns pre-filtered data, so the secondary filter is never exercised.

Instead, use a `fakeHost` stub that returns raw unfiltered addresses, proving the secondary filter works on its own.

**File**: `go-mknoon/node/node_test.go`

```go
// fakeHostWithAddrs is a minimal host.Host stub for testing splitHostAddresses
// with synthetic addresses that bypass AddrsFactory.
type fakeHostWithAddrs struct {
    host.Host // embed to satisfy interface; only Addrs() is called
    addrs []ma.Multiaddr
}

func (f *fakeHostWithAddrs) Addrs() []ma.Multiaddr { return f.addrs }

func TestSplitHostAddressesFiltersLoopbackDirectly(t *testing.T) {
    // Feed raw unfiltered addresses directly — no AddrsFactory involved.
    // Covers every category the plan says to filter: IPv4 loopback, IPv6 loopback,
    // IPv6 link-local, IPv4 unspecified, IPv6 unspecified.
    // Also includes a loopback-transport circuit relay to verify it survives.
    rawAddrs := []ma.Multiaddr{
        // Should be filtered (non-routable)
        ma.StringCast("/ip4/127.0.0.1/tcp/5678"),
        ma.StringCast("/ip4/127.0.0.1/udp/5678/quic-v1"),
        ma.StringCast("/ip6/::1/tcp/5678"),
        ma.StringCast("/ip6/fe80::1/tcp/5678"),
        ma.StringCast("/ip4/169.254.1.100/tcp/5678"),
        ma.StringCast("/ip4/0.0.0.0/tcp/5678"),
        ma.StringCast("/ip6/::/tcp/5678"),
        // Should be kept (routable listen addresses)
        ma.StringCast("/ip4/192.168.1.100/tcp/5678"),
        ma.StringCast("/ip6/2001:db8::1/tcp/5678"),
        // Should be kept (circuit relay — even with loopback transport)
        ma.StringCast("/ip4/127.0.0.1/tcp/4001/p2p/12D3KooWRelay/p2p-circuit/p2p/12D3KooWPeer"),
    }

    fh := &fakeHostWithAddrs{addrs: rawAddrs}
    listenAddrs, circuitAddrs := splitHostAddresses(fh)

    for _, a := range listenAddrs {
        if strings.Contains(a, "127.0.0.1") || strings.Contains(a, "::1/") ||
           strings.Contains(a, "/ip6/fe80") || strings.Contains(a, "169.254.") ||
           strings.HasPrefix(a, "/ip4/0.0.0.0") || strings.HasPrefix(a, "/ip6/::/" ) {
            t.Errorf("splitHostAddresses returned non-routable listen address: %s", a)
        }
    }

    // Should keep exactly the two routable listen addresses
    if len(listenAddrs) != 2 {
        t.Errorf("expected 2 routable listen addrs, got %d: %v", len(listenAddrs), listenAddrs)
    }

    // Circuit relay through loopback must appear in circuitAddrs
    if len(circuitAddrs) != 1 {
        t.Errorf("expected 1 circuit addr, got %d: %v", len(circuitAddrs), circuitAddrs)
    }
}
```

---

### Step 6: GREEN — Add secondary filter in `splitHostAddresses()`

**File**: `go-mknoon/node/node.go`, `splitHostAddresses()` (~line 1052)

```go
func splitHostAddresses(h host.Host) (listenAddrs []string, circuitAddrs []string) {
    if h == nil {
        return nil, nil
    }
    for _, addr := range h.Addrs() {
        s := addr.String()
        // Circuit relay addresses are always kept (even if transport IP is loopback).
        if strings.Contains(s, "/p2p-circuit") {
            circuitAddrs = append(circuitAddrs, s)
            continue
        }
        // Belt-and-suspenders: skip loopback/link-local even if AddrsFactory missed them.
        if manet.IsIPLoopback(addr) || isLinkLocalAddr(addr) || manet.IsIPUnspecified(addr) {
            continue
        }
        listenAddrs = append(listenAddrs, s)
    }
    return listenAddrs, circuitAddrs
}
```

---

### Step 7: RED — Test `Status()` map output excludes loopback

**File**: `go-mknoon/node/node_test.go`

```go
func TestStatusExcludesLoopback(t *testing.T) {
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
    listenAddrs, _ := status["listenAddresses"].([]string)
    for _, a := range listenAddrs {
        if strings.Contains(a, "127.0.0.1") || strings.Contains(a, "::1/") ||
           strings.Contains(a, "/ip6/fe80") || strings.Contains(a, "169.254.") {
            t.Errorf("Status() listenAddresses contains non-routable: %s", a)
        }
    }
}
```

**Expected**: Already passes (because `Status()` calls `splitHostAddresses()` which now filters).

---

### Step 8: RED — Test `stateLocked()` output excludes loopback

`stateLocked()` (line 411-424) iterates `host.Addrs()` directly into `NodeState.Addresses` without going through `splitHostAddresses()`. `AddrsFactory` filters at the host level, so `host.Addrs()` already returns clean data. This test guards against regression.

**File**: `go-mknoon/node/node_test.go`

```go
func TestStateLockedExcludesLoopback(t *testing.T) {
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

    state := n.State()
    for _, a := range state.Addresses {
        if strings.Contains(a, "127.0.0.1") || strings.Contains(a, "::1/") ||
           strings.Contains(a, "/ip6/fe80") || strings.Contains(a, "169.254.") ||
           strings.Contains(a, "0.0.0.0") || strings.Contains(a, "/ip6/::/") {
            t.Errorf("State().Addresses contains non-routable address: %s", a)
        }
    }
}
```

**Expected**: Already passes (covered by `AddrsFactory`). Regression guard only.

---

### Step 8b: RED — Test `addresses:updated` event payload excludes non-routable

The problem statement identifies `addresses:updated` push events as leak path #2. Steps 5-6 test `splitHostAddresses()` in isolation, but this test verifies the actual event payload emitted by `watchConnectionEvents()` through the event callback.

**File**: `go-mknoon/node/node_test.go`

```go
func TestAddressesUpdatedEventExcludesNonRoutable(t *testing.T) {
    hexKey := generateTestKey(t)

    var captured []map[string]interface{}
    var mu sync.Mutex
    gotEvent := make(chan struct{}, 1)

    // Use the repo's existing event collector pattern (see recordingEventCallback
    // in node_test.go) or a minimal equivalent:
    cb := &recordingEventCallback{
        handler: func(jsonStr string) {
            var ev map[string]interface{}
            if err := json.Unmarshal([]byte(jsonStr), &ev); err != nil {
                return
            }
            if ev["event"] == "addresses:updated" {
                mu.Lock()
                captured = append(captured, ev["data"].(map[string]interface{}))
                mu.Unlock()
                select {
                case gotEvent <- struct{}{}:
                default:
                }
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

    // Poll with bounded timeout — fail if no event arrives (not t.Skip).
    select {
    case <-gotEvent:
        // got at least one event
    case <-time.After(5 * time.Second):
        t.Fatal("addresses:updated event not received within 5s — leak path #2 untested")
    }

    mu.Lock()
    events := captured
    mu.Unlock()

    for _, ev := range events {
        addrs, _ := ev["listenAddresses"].([]interface{})
        for _, a := range addrs {
            s, _ := a.(string)
            if strings.Contains(s, "127.0.0.1") || strings.Contains(s, "::1/") ||
               strings.Contains(s, "/ip6/fe80") || strings.Contains(s, "169.254.") ||
               strings.HasPrefix(s, "/ip4/0.0.0.0") || strings.HasPrefix(s, "/ip6/::/") {
                t.Errorf("addresses:updated event contains non-routable: %s", s)
            }
        }
    }
}
```

---

### Step 9: RED — Integration test: discovered peer record excludes loopback

The problem statement identifies rendezvous registration as leak path #1, so we need a test that verifies the _discovered_ peer record (what another peer actually receives) contains no loopback addresses. This exercises the full path: `host.Addrs()` → `AddrsFactory` → certified address book → signed peer record → rendezvous registration → discovery response.

**File**: `go-mknoon/integration/local_relay_harness_test.go` (package `integration_test`, build tag `integration`)

Uses existing helpers: `generatePrivateKeyHex`, `startNodeWithRelays`, `waitForRendezvousRegister`, `waitForDiscoverablePeer`.

```go
//go:build integration

func TestDiscoveredPeerRecordExcludesLoopback(t *testing.T) {
    // Start the local relay harness (listens on 127.0.0.1).
    shared := newLocalRelaySharedState()
    relay := newLocalRelayServer(t, shared)
    relay.start()
    defer relay.stop()

    relayAddr := relay.addr()

    // Start node A — will register on rendezvous.
    nodeA, peerIdA := startNodeWithRelays(t, []string{relayAddr}, nil, nil)
    nsA := nodeA.Namespace()

    // Register A and poll until discoverable (no time.Sleep).
    waitForRendezvousRegister(t, nodeA, nsA, 10*time.Second)

    // Start node B — discovers A via rendezvous.
    nodeB, _ := startNodeWithRelays(t, []string{relayAddr}, nil, nil)

    // Poll until B can discover A (no time.Sleep).
    waitForDiscoverablePeer(t, nodeB, nsA, peerIdA, 10*time.Second)

    // Now do the actual assertion: discover A's peer record and check addresses.
    peers, err := nodeB.RendezvousDiscover(nsA, nil)
    if err != nil {
        t.Fatalf("Discover: %v", err)
    }

    // Positive assertion: the filter must not be so aggressive that it strips
    // all addresses. The discovered record should contain at least one address
    // (typically a /p2p-circuit path through the local relay).
    totalAddrs := 0
    for _, p := range peers {
        totalAddrs += len(p.Addrs)
        for _, addr := range p.Addrs {
            s := addr.String()
            // Circuit relay addresses through 127.0.0.1 are OK (that's the local test relay).
            if strings.Contains(s, "/p2p-circuit") {
                continue
            }
            if strings.Contains(s, "/ip4/127.0.0.1/") || strings.Contains(s, "/ip6/::1/") ||
               strings.Contains(s, "/ip6/fe80") || strings.Contains(s, "169.254.") ||
               strings.HasPrefix(s, "/ip4/0.0.0.0") || s == "/ip6/::" || strings.HasPrefix(s, "/ip6/::/") {
                t.Errorf("discovered peer record contains non-routable address: %s", s)
            }
        }
    }
    if totalAddrs == 0 {
        t.Fatal("discovered peer record has zero addresses — filter may be too aggressive")
    }
}
```

**Expected**: Passes — the signed peer record is built from `host.Addrs()` which is filtered by `AddrsFactory`.

**Why this test matters**: This is the only test that verifies the _external symptom_ (what peers actually discover). The other tests verify internal invariants (`host.Addrs()`, `Status()`, `State()`), but this test closes the loop on leak path #1 from the problem statement.

---

### Step 10: REFACTOR — Log announced addresses at startup

Add a one-time log at startup showing the addresses that will be announced.

**File**: `go-mknoon/node/node.go`, after host creation (~line 220)

```go
// Log announced addresses (post-filter).
rawAddrs := h.Addrs()
log.Printf("[NODE] Announcing %d addresses (loopback/link-local filtered out)", len(rawAddrs))
for _, a := range rawAddrs {
    log.Printf("[NODE]   %s", a.String())
}
```

No test needed — this is pure logging.

---

## Test Execution Order

```bash
# Step 1+2: Pure function tests (includes circuit relay bypass cases)
cd go-mknoon && go test ./node/ -run TestFilterAddresses -v

# Step 3+4: Integration test (host-level filtering)
go test ./node/ -run TestNodeAddressesExcludeLoopback -v

# Step 5+6: splitHostAddresses safety (synthetic input, no AddrsFactory)
go test ./node/ -run TestSplitHostAddressesFiltersLoopbackDirectly -v

# Step 7: Status map output
go test ./node/ -run TestStatusExcludesLoopback -v

# Step 8: State struct output
go test ./node/ -run TestStateLockedExcludesLoopback -v

# Step 8b: addresses:updated event payload (leak path #2)
go test ./node/ -run TestAddressesUpdatedEventExcludesNonRoutable -v

# Step 9: Rendezvous discover-side regression (integration, needs relay harness)
go test -tags integration ./integration/ -run TestDiscoveredPeerRecordExcludesLoopback -v

# Full suite — verify no regressions
go test ./node/ -v -count=1
go test -tags integration ./integration/ -v -count=1
```

---

## What This Does NOT Change

| Concern | Why no change needed |
|---------|---------------------|
| **Dart `NodeState`** | Addresses already arrive clean from Go |
| **`go_bridge_client.dart`** | Passes through whatever Go sends — no filtering logic needed |
| **`p2p_service_impl.dart`** | `_handleAddressesUpdated` receives pre-filtered lists |
| **Rendezvous registration** | Signed peer record built from `host.Addrs()` which is now filtered by `AddrsFactory` |
| **Rendezvous discovery (receiving side)** | Other peers' addresses come from their signed records — we can't control what they advertise |
| **Circuit relay addresses** | `filterAddresses()` checks for `/p2p-circuit` first — circuit addrs always pass through even when the relay's transport IP is loopback |
| **`waitForCircuitAddress()`** | Only checks for `/p2p-circuit` substring — unaffected |

---

## Risks and Mitigations

| Risk | Mitigation |
|------|------------|
| `manet.IsIPLoopback` classifies `/ip4/127.0.0.1/.../p2p-circuit/...` as loopback | `filterAddresses()` checks for `/p2p-circuit` first — circuit addrs bypass loopback checks entirely. Explicit test case covers this. |
| Filtering breaks local-only testing (no relay, both peers on same machine) | Private LAN addresses (`192.168.x.x`, `10.x.x.x`) are **kept** — same-machine peers connect via LAN IP, not `127.0.0.1` |
| `AddrsFactory` interacts with AutoRelay address injection | AutoRelay adds `/p2p-circuit` addresses — `filterAddresses()` passes them through unconditionally |
| Future libp2p version changes `AddrsFactory` semantics | Belt-and-suspenders filter in `splitHostAddresses()` catches leaks for the Status/event paths. **Note**: The rendezvous signed peer record path is protected solely by `AddrsFactory` — the signed envelope cannot be re-filtered without invalidating its signature. |
| `manet` import adds binary size | Already a transitive dependency of `go-libp2p` — zero additional size |

---

## Summary of Changes

```
go-mknoon/node/node.go
  ├── import manet "github.com/multiformats/go-multiaddr/net"
  ├── func isCircuitAddr(a ma.Multiaddr) bool                       (NEW)
  ├── func isLinkLocalAddr(a ma.Multiaddr) bool                     (NEW — covers IPv4 169.254 + IPv6 fe80)
  ├── func filterAddresses(addrs []ma.Multiaddr) []ma.Multiaddr     (NEW — circuit-aware)
  ├── Start(): add libp2p.AddrsFactory(filterAddresses) to hostOpts (EDIT)
  └── splitHostAddresses(): add circuit-first + manet guard          (EDIT)

go-mknoon/node/node_test.go
  ├── TestFilterAddresses                           (NEW — table-driven, includes circuit relay + 169.254)
  ├── TestNodeAddressesExcludeLoopback              (NEW — integration, host-level, all non-routable classes)
  ├── TestSplitHostAddressesFiltersLoopbackDirectly (NEW — synthetic input via fakeHost, all classes + circuit)
  ├── TestStatusExcludesLoopback                    (NEW — Status() map, all non-routable classes)
  ├── TestStateLockedExcludesLoopback               (NEW — State() struct, all non-routable classes)
  └── TestAddressesUpdatedEventExcludesNonRoutable  (NEW — event payload, leak path #2)

go-mknoon/integration/ (test file)
  └── TestDiscoveredPeerRecordExcludesLoopback      (NEW — rendezvous discover-side + positive assertion)
```

**Total**: ~80 lines of production code, ~260 lines of test code.
