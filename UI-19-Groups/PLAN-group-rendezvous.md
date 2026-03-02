# TDD Plan: GossipSub Peer Discovery via Per-Group Rendezvous

## Problem
GossipSub requires peers to be connected to form a mesh. Currently `JoinGroupTopic()` joins topics and publishes, but there's no peer discovery mechanism for group members to find each other. In 1:1 chat, peers connect via relay circuits using rendezvous namespace `mknoon:chat:<peerId>`. Groups need an analogous mechanism.

## Solution
Use the existing rendezvous infrastructure (relay server already supports arbitrary namespaces) with per-group namespaces. When a node joins a group topic, it:
1. Registers on rendezvous namespace `/mknoon/group/<groupId>`
2. Discovers other online members on that namespace
3. Connects to discovered peers via relay circuits
4. Starts a periodic discovery loop to find newly-online members
5. On leave, unregisters from the namespace

**No relay server changes needed** — it already handles arbitrary namespaces.

## Architecture

```
JoinGroupTopic(groupId)
  ├── [existing] Register topic validator, join topic, subscribe
  └── [NEW] Start group peer discovery goroutine
         ├── Register on rendezvous ns="/mknoon/group/<groupId>"
         ├── Discover peers on that namespace
         ├── Dial discovered peers via relay circuit
         └── Re-discover every 30s (find newly-online members)

LeaveGroupTopic(groupId)
  ├── [existing] Cancel sub, close topic, cleanup
  └── [NEW] Unregister from rendezvous namespace
```

---

## Implementation Tasks (TDD Order)

### Task 1: Add `GroupRendezvousPrefix` constant and `groupRendezvousNamespace()` helper
**File:** `go-mknoon/node/config.go`, `go-mknoon/node/pubsub.go`

**Test first** (`pubsub_test.go`):
```go
func TestGroupRendezvousNamespace(t *testing.T) {
    ns := groupRendezvousNamespace("abc-123")
    if ns != "/mknoon/group/abc-123" {
        t.Errorf("got %s", ns)
    }
}
```

**Implementation:**
- Add `GroupRendezvousPrefix = "/mknoon/group/"` to config.go (reuse same prefix as topic, which is already `"/mknoon/group/"`)
- Add helper `func groupRendezvousNamespace(groupId string) string` that returns `GroupTopicPrefix + groupId`
- Note: topic name and rendezvous namespace can be the same string since they're used in different systems (pubsub vs rendezvous protocol)

---

### Task 2: Add `discoverAndConnectGroupPeers()` method
**File:** `go-mknoon/node/pubsub.go`

**Test first** (`pubsub_test.go`):
```go
func TestDiscoverAndConnectGroupPeers_SkipsSelf(t *testing.T)
func TestDiscoverAndConnectGroupPeers_SkipsAlreadyConnected(t *testing.T)
func TestDiscoverAndConnectGroupPeers_LogsDiscoveryCount(t *testing.T)
```

Since these require network, test via pure function extraction:
```go
func TestFilterDiscoveredPeers_ExcludesSelf(t *testing.T)
func TestFilterDiscoveredPeers_ExcludesConnected(t *testing.T)
func TestFilterDiscoveredPeers_ReturnsNewPeers(t *testing.T)
```

**Implementation:**
```go
// filterDiscoveredPeers returns peers that are not self and not already connected.
func filterDiscoveredPeers(discovered []peer.AddrInfo, selfId peer.ID, connectedPeers map[peer.ID]struct{}) []peer.AddrInfo

// discoverAndConnectGroupPeers discovers peers on the group rendezvous namespace
// and dials any that are not already connected.
func (n *Node) discoverAndConnectGroupPeers(groupId string)
```

The method:
1. Calls `n.RendezvousDiscover(groupRendezvousNamespace(groupId), nil)`
2. Filters out self and already-connected peers via `filterDiscoveredPeers()`
3. For each new peer, calls `n.DialPeerViaRelay(peer.ID)` (non-blocking, logs errors)

---

### Task 3: Add `groupPeerDiscoveryLoop()` goroutine
**File:** `go-mknoon/node/pubsub.go`

**Test first** (`pubsub_test.go`):
```go
func TestGroupPeerDiscoveryLoop_StopsOnContextCancel(t *testing.T)
func TestGroupPeerDiscoveryLoop_InitialDiscoveryBeforeTicker(t *testing.T)
```

**Implementation:**
```go
// groupPeerDiscoveryLoop runs periodic peer discovery for a group.
// It registers on the group rendezvous namespace, performs an initial discovery,
// then re-discovers every GroupDiscoveryInterval.
func (n *Node) groupPeerDiscoveryLoop(ctx context.Context, groupId string)
```

Flow:
1. Register on rendezvous: `n.RendezvousRegister(groupRendezvousNamespace(groupId), nil)`
2. Initial discover+connect: `n.discoverAndConnectGroupPeers(groupId)`
3. Ticker every `GroupDiscoveryInterval` (30s):
   - `n.discoverAndConnectGroupPeers(groupId)`
4. On context cancel: `n.RendezvousUnregister(groupRendezvousNamespace(groupId), nil)` (best-effort)

Add constant: `GroupDiscoveryInterval = 30 * time.Second`

---

### Task 4: Integrate discovery into `JoinGroupTopic()` and `LeaveGroupTopic()`
**File:** `go-mknoon/node/pubsub.go`, `go-mknoon/node/node.go`

**Test first** (`pubsub_test.go`):
```go
func TestJoinGroupTopic_StartsDiscoveryLoop(t *testing.T)
func TestLeaveGroupTopic_CancelsDiscoveryLoop(t *testing.T)
```

**Implementation changes:**

In `Node` struct, add:
```go
groupDiscoveryCtx map[string]context.CancelFunc  // discovery loop cancellation per group
```

In `initPubSub()`, initialize:
```go
n.groupDiscoveryCtx = make(map[string]context.CancelFunc)
```

In `JoinGroupTopic()`, after starting subscription handler, add:
```go
// Start group peer discovery in background (register + periodic discover).
discoveryCtx, discoveryCancel := context.WithCancel(n.ctx)
n.groupDiscoveryCtx[groupId] = discoveryCancel
go n.groupPeerDiscoveryLoop(discoveryCtx, groupId)
```

In `LeaveGroupTopic()`, before existing cleanup, add:
```go
// Cancel discovery loop (triggers unregister from rendezvous).
if cancel, ok := n.groupDiscoveryCtx[groupId]; ok {
    cancel()
    delete(n.groupDiscoveryCtx, groupId)
}
```

In `Stop()`, cancel all discovery loops:
```go
for gid, cancel := range n.groupDiscoveryCtx {
    cancel()
    delete(n.groupDiscoveryCtx, gid)
}
```

---

### Task 5: Add `GroupDiscoveryInterval` constant and cleanup in Stop()
**File:** `go-mknoon/node/config.go`, `go-mknoon/node/node.go`

**Test first** (`pubsub_test.go`):
```go
func TestGroupDiscoveryInterval_Is30Seconds(t *testing.T) {
    if GroupDiscoveryInterval != 30*time.Second {
        t.Errorf("expected 30s, got %v", GroupDiscoveryInterval)
    }
}
```

**Implementation:**
- Add `GroupDiscoveryInterval = 30 * time.Second` to config.go
- Verify `Stop()` cancels discovery contexts (Task 4)

---

## Files Modified

| File | Change |
|------|--------|
| `go-mknoon/node/config.go` | Add `GroupDiscoveryInterval` constant |
| `go-mknoon/node/node.go` | Add `groupDiscoveryCtx` field to Node struct, cleanup in Stop() |
| `go-mknoon/node/pubsub.go` | Add `groupRendezvousNamespace()`, `filterDiscoveredPeers()`, `discoverAndConnectGroupPeers()`, `groupPeerDiscoveryLoop()`; modify `JoinGroupTopic()`, `LeaveGroupTopic()`, `initPubSub()` |
| `go-mknoon/node/pubsub_test.go` | Add tests for all new functions |

## Files NOT Modified
- **go-relay-server/**: No changes needed (already supports arbitrary namespaces)
- **Flutter/Dart layer**: No changes needed (discovery is automatic on join)
- **go-mknoon/bridge/**: No new bridge commands needed (discovery is transparent)

## Key Design Decisions
1. **Reuse existing rendezvous infra**: No new protocols or dependencies
2. **Same namespace for topic and rendezvous**: `/mknoon/group/<groupId>` is used for both GossipSub topic name and rendezvous namespace. They operate in different protocol spaces so no collision.
3. **Non-blocking dials**: `DialPeerViaRelay` failures are logged, not propagated — discovery is best-effort
4. **30s discovery interval**: Balance between freshness and resource usage
5. **Graceful cleanup**: Context cancellation triggers unregister on leave/stop
6. **Pure function extraction**: `filterDiscoveredPeers()` is testable without network
