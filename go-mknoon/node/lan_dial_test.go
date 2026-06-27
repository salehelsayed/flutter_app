package node

// FDC-11 — libp2p LAN-direct dial fed by bonsoir discovery (Go-unit RED catalog T1–T10).
//
// bonsoir discovers a same-WiFi peer's libp2p QUIC multiaddr (uniform on iOS +
// Android); the resolved AddrInfo is bridged to Go and handed to
// Node.HandleLANPeerFound, which seeds the peerstore (AddressTTL) and
// host.Connects so DefaultDialRanker prefers the LAN leg over the relay. These
// tests reuse the FDC-S2 M1 loopback harness (s2BuildHost / s2PickListenAddr /
// s2WaitIdentify in quic_identify_revalidation_test.go) and the holepunch
// firstDirectConn helper.
//
// Run under GOTOOLCHAIN=go1.25.0 (the QUIC two-host tests panic on Go 1.26.x —
// quic-go v0.49.0 vs Go 1.26.x crypto/tls). Concurrency lock T10 needs -race:
//   GOTOOLCHAIN=go1.25.0 go test -race ./node/... -run TestHandleLANPeerFound

import (
	"context"
	"crypto/rand"
	"sync"
	"sync/atomic"
	"testing"
	"time"

	libp2pcrypto "github.com/libp2p/go-libp2p/core/crypto"
	"github.com/libp2p/go-libp2p/core/event"
	"github.com/libp2p/go-libp2p/core/network"
	"github.com/libp2p/go-libp2p/core/peer"
	ma "github.com/multiformats/go-multiaddr"
)

// startLANDialTestNode spins a real local-only Node (no relay warmup) with the
// EnableLibp2pLANDial flag set as requested, mirroring TestNodeStartStop.
func startLANDialTestNode(t *testing.T, collector *testEventCollector, lanFlag bool) *Node {
	t.Helper()
	n := New(collector)
	flags := DefaultFeatureFlags()
	flags.EnableLibp2pLANDial = lanFlag
	if _, err := n.Start(NodeConfig{
		PrivateKeyHex:  generateTestKey(t),
		RelayAddresses: []string{}, // explicit empty => no relay warmup, local only
		AutoRegister:   false,
		FeatureFlags:   &flags,
	}); err != nil {
		t.Fatalf("Start: %v", err)
	}
	t.Cleanup(func() { _ = n.Stop() })
	return n
}

// waitForLANEvent polls until the collector has at least `want` events named
// `name` — node:lan_* events are delivered asynchronously via the
// EventDispatcher, so an immediate read races delivery.
func waitForLANEvent(t *testing.T, c *testEventCollector, name string, want int) {
	t.Helper()
	deadline := time.Now().Add(2 * time.Second)
	for time.Now().Before(deadline) {
		if len(c.collectEvents(name)) >= want {
			return
		}
		time.Sleep(5 * time.Millisecond)
	}
	t.Fatalf("timed out waiting for %d %q event(s); got %d", want, name, len(c.collectEvents(name)))
}

// drainLANEvents emits a sentinel and waits for its delivery. Because the
// dispatcher's non-coalesced queue is FIFO, once the sentinel is delivered every
// prior node:lan_* event has been delivered too — so a follow-up absence check
// is race-free.
func drainLANEvents(t *testing.T, n *Node, c *testEventCollector) {
	t.Helper()
	n.emitEvent("node:lan_test_drain", nil)
	deadline := time.Now().Add(2 * time.Second)
	for time.Now().Before(deadline) {
		if len(c.collectEvents("node:lan_test_drain")) >= 1 {
			return
		}
		time.Sleep(5 * time.Millisecond)
	}
	t.Fatal("timed out draining the event dispatcher")
}

// newFakeLANPeer builds a random peer with a single loopback QUIC LAN multiaddr
// pointed at a closed port (so a real dial fails fast). Used where the dial is
// suppressed via dialHook or the connection is irrelevant.
func newFakeLANPeer(t *testing.T) peer.AddrInfo {
	t.Helper()
	priv, _, err := libp2pcrypto.GenerateEd25519Key(rand.Reader)
	if err != nil {
		t.Fatalf("gen key: %v", err)
	}
	pid, err := peer.IDFromPrivateKey(priv)
	if err != nil {
		t.Fatalf("peer id: %v", err)
	}
	return peer.AddrInfo{
		ID:    pid,
		Addrs: []ma.Multiaddr{ma.StringCast("/ip4/127.0.0.1/udp/59999/quic-v1")},
	}
}

// T1 — bonsoir-found peer is wired to a libp2p LAN dial when the flag is on.
func TestLANPeerFound_DialsWhenFlagEnabled(t *testing.T) {
	collector := &testEventCollector{}
	n := startLANDialTestNode(t, collector, true)

	if n.lanDialHandler == nil {
		t.Fatal("lanDialHandler should be non-nil after Start with the flag on")
	}

	var dialCount int32
	var dialedTo peer.ID
	n.lanDialHandler.dialHook = func(_ context.Context, pi peer.AddrInfo) error {
		atomic.AddInt32(&dialCount, 1)
		dialedTo = pi.ID
		return nil
	}

	found := newFakeLANPeer(t)
	n.HandleLANPeerFound(found)

	if got := atomic.LoadInt32(&dialCount); got != 1 {
		t.Fatalf("expected exactly 1 LAN dial, got %d", got)
	}
	if dialedTo != found.ID {
		t.Fatalf("dialed wrong peer: got %s want %s", dialedTo, found.ID)
	}
	waitForLANEvent(t, collector, "node:lan_dial_ready", 1)
	if ev := collector.collectEvents("node:lan_dial_ready"); len(ev) != 1 {
		t.Fatalf("expected exactly 1 node:lan_dial_ready event, got %d", len(ev))
	}
}

// T2 — flag OFF ⇒ no libp2p LAN dial (gate preservation / rollout safety).
func TestLANPeerFound_NoDial_WhenFlagDisabled(t *testing.T) {
	collector := &testEventCollector{}
	n := startLANDialTestNode(t, collector, false)

	var dialCount int32
	if n.lanDialHandler != nil { // handler may still be wired; the flag gates the dial
		n.lanDialHandler.dialHook = func(_ context.Context, _ peer.AddrInfo) error {
			atomic.AddInt32(&dialCount, 1)
			return nil
		}
	}

	n.HandleLANPeerFound(newFakeLANPeer(t))

	if got := atomic.LoadInt32(&dialCount); got != 0 {
		t.Fatalf("flag off: expected 0 LAN dials, got %d", got)
	}
	drainLANEvents(t, n, collector)
	if ev := collector.collectEvents("node:lan_dial_ready"); len(ev) != 0 {
		t.Fatalf("flag off: expected no node:lan_dial_ready, got %d", len(ev))
	}
	if !n.State().IsStarted {
		t.Fatal("node should remain started under flag-off (baseline intact)")
	}
}

// T3 — HandleLANPeerFound on a same-LAN AddrInfo dials direct and identify
// completes within the budget (headline; reuses the FDC-S2 M1 harness).
func TestHandleLANPeerFound_ConnectsDirect_IdentifyCompletes(t *testing.T) {
	nodeA := startLANDialTestNode(t, &testEventCollector{}, true)

	hostB := s2BuildHost(t, []string{
		"/ip4/127.0.0.1/udp/0/quic-v1",
		"/ip4/127.0.0.1/tcp/0",
	}, false)
	defer hostB.Close()

	// Subscribe BEFORE dialing (production node.go does NOT subscribe this event;
	// the identify assertion lives in the test).
	sub, err := nodeA.Host().EventBus().Subscribe([]interface{}{
		new(event.EvtPeerIdentificationCompleted),
		new(event.EvtPeerIdentificationFailed),
	})
	if err != nil {
		t.Fatalf("subscribe: %v", err)
	}
	defer sub.Close()

	quic := s2PickListenAddr(t, hostB, "quic")
	start := time.Now()
	nodeA.HandleLANPeerFound(peer.AddrInfo{ID: hostB.ID(), Addrs: []ma.Multiaddr{quic}})

	deadline := make(chan struct{})
	timer := time.AfterFunc(5*time.Second, func() { close(deadline) })
	defer timer.Stop()
	ok, reason := s2WaitIdentify(sub, hostB.ID(), deadline)
	elapsed := time.Since(start)
	if !ok {
		t.Fatalf("LAN-direct identify did not complete: %s", reason)
	}
	if elapsed > LANDirectIdentifyBudget {
		t.Fatalf("identify took %v, exceeds LANDirectIdentifyBudget %v", elapsed, LANDirectIdentifyBudget)
	}

	conn := firstDirectConn(nodeA, hostB.ID())
	if conn == nil {
		t.Fatal("expected a non-circuit direct conn to B after HandleLANPeerFound")
	}
	if isCircuitAddr(conn.RemoteMultiaddr()) {
		t.Fatalf("conn is circuit, want direct: %s", conn.RemoteMultiaddr())
	}
}

// T4 — HandleLANPeerFound seeds the peerstore (AddressTTL) before dialing so a
// later ranked race can use the LAN addr even if this dial fails. The real dial
// is suppressed so the peerstore addr can only come from the explicit AddAddrs
// seed (not h.Connect's transient internal add).
func TestHandleLANPeerFound_SeedsPeerstore_PrivateAddr(t *testing.T) {
	n := startLANDialTestNode(t, &testEventCollector{}, true)
	n.lanDialHandler.dialHook = func(_ context.Context, _ peer.AddrInfo) error { return nil }

	pi := newFakeLANPeer(t)
	n.HandleLANPeerFound(pi)

	addrs := n.Host().Peerstore().Addrs(pi.ID)
	if len(addrs) == 0 {
		t.Fatal("expected the LAN addr seeded into the peerstore (AddressTTL) for a later ranked race")
	}
	found := false
	for _, a := range addrs {
		if a.Equal(pi.Addrs[0]) {
			found = true
		}
	}
	if !found {
		t.Fatalf("seeded addr not present in peerstore: %v", addrs)
	}
}

// T5 — self-peer is ignored (no self-dial loop).
func TestHandleLANPeerFound_IgnoresSelf(t *testing.T) {
	collector := &testEventCollector{}
	n := startLANDialTestNode(t, collector, true)

	var dialCount int32
	n.lanDialHandler.dialHook = func(_ context.Context, _ peer.AddrInfo) error {
		atomic.AddInt32(&dialCount, 1)
		return nil
	}

	self := peer.AddrInfo{
		ID:    n.Host().ID(),
		Addrs: []ma.Multiaddr{ma.StringCast("/ip4/127.0.0.1/udp/1234/quic-v1")},
	}
	n.HandleLANPeerFound(self)

	if got := atomic.LoadInt32(&dialCount); got != 0 {
		t.Fatalf("self must not be dialed, got %d dials", got)
	}
	drainLANEvents(t, n, collector)
	if ev := collector.collectEvents("node:lan_peer_found"); len(ev) != 0 {
		t.Fatalf("self must emit no node:lan_peer_found, got %d", len(ev))
	}
}

// T6 — per-peer warm cooldown debounces repeated finds (swarm-backoff guard).
func TestHandleLANPeerFound_DebouncesRepeatedFinds_WithinCooldown(t *testing.T) {
	n := startLANDialTestNode(t, &testEventCollector{}, true)

	var dialCount int32
	n.lanDialHandler.dialHook = func(_ context.Context, _ peer.AddrInfo) error {
		atomic.AddInt32(&dialCount, 1)
		return nil
	}
	base := time.Now()
	current := base
	n.lanDialHandler.nowFunc = func() time.Time { return current }

	pi := newFakeLANPeer(t)
	n.HandleLANPeerFound(pi) // dial #1, records cooldown at base
	current = base.Add(LANDialWarmCooldown / 2)
	n.HandleLANPeerFound(pi) // within cooldown => suppressed
	if got := atomic.LoadInt32(&dialCount); got != 1 {
		t.Fatalf("within cooldown: expected exactly 1 dial, got %d", got)
	}

	current = base.Add(LANDialWarmCooldown + time.Second)
	n.HandleLANPeerFound(pi) // past cooldown => dials again
	if got := atomic.LoadInt32(&dialCount); got != 2 {
		t.Fatalf("after cooldown elapsed: expected 2 dials, got %d", got)
	}
}

// T7 — a known LAN addr upgrades an existing relay conn to direct via
// WithForceDirectDial (host-seam: the upgrade dial carries the force-direct ctx;
// the real circuit-in-loop half is the device gate D1).
func TestHandleLANPeerFound_UpgradesRelayConnToDirect(t *testing.T) {
	n := startLANDialTestNode(t, &testEventCollector{}, true)
	n.lanDialHandler.circuitConnHook = func(_ peer.ID) bool { return true } // pretend a circuit conn is held

	var dialed int32
	var forceDirect bool
	n.lanDialHandler.dialHook = func(ctx context.Context, _ peer.AddrInfo) error {
		atomic.AddInt32(&dialed, 1)
		fd, _ := network.GetForceDirectDial(ctx)
		forceDirect = fd
		return nil
	}

	n.HandleLANPeerFound(newFakeLANPeer(t)) // non-circuit LAN addr

	if atomic.LoadInt32(&dialed) != 1 {
		t.Fatal("expected the relay->direct upgrade dial to be issued")
	}
	if !forceDirect {
		t.Fatal("relay->direct upgrade must dial with network.WithForceDirectDial")
	}
}

// T8 — a LAN-direct stream still classifies as "direct" (label contract).
func TestLANDirectStream_ClassifiesDirect(t *testing.T) {
	nodeA := startLANDialTestNode(t, &testEventCollector{}, true)

	hostB := s2BuildHost(t, []string{"/ip4/127.0.0.1/udp/0/quic-v1"}, false)
	defer hostB.Close()
	recv := make(chan struct{}, 1)
	hostB.SetStreamHandler(ChatProtocol, func(s network.Stream) {
		buf := make([]byte, 4)
		_, _ = s.Read(buf)
		select {
		case recv <- struct{}{}:
		default:
		}
		_ = s.Close()
	})

	quic := s2PickListenAddr(t, hostB, "quic")
	nodeA.HandleLANPeerFound(peer.AddrInfo{ID: hostB.ID(), Addrs: []ma.Multiaddr{quic}})

	sctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()
	st, err := nodeA.Host().NewStream(sctx, hostB.ID(), ChatProtocol)
	if err != nil {
		t.Fatalf("NewStream over the LAN-direct conn: %v", err)
	}
	defer st.Close()

	if got := classifyStreamTransport(st); got != "direct" {
		t.Fatalf("LAN-direct stream classified %q, want \"direct\"", got)
	}
}

// T9 — Stop tears down the LAN-dial handler and a fresh Start re-wires cleanly.
func TestStop_TearsDownLANDialHandler(t *testing.T) {
	n := New(&testEventCollector{})
	flags := DefaultFeatureFlags()
	flags.EnableLibp2pLANDial = true
	cfg := NodeConfig{
		PrivateKeyHex:  generateTestKey(t),
		RelayAddresses: []string{},
		FeatureFlags:   &flags,
	}
	if _, err := n.Start(cfg); err != nil {
		t.Fatalf("Start: %v", err)
	}
	if n.lanDialHandler == nil {
		t.Fatal("lanDialHandler should be non-nil after Start")
	}
	n.lanDialHandler.dialHook = func(_ context.Context, _ peer.AddrInfo) error { return nil }
	n.HandleLANPeerFound(newFakeLANPeer(t)) // seed cooldown map

	if err := n.Stop(); err != nil {
		t.Fatalf("Stop: %v", err)
	}
	if n.lanDialHandler != nil {
		t.Fatal("lanDialHandler should be nil after Stop")
	}

	// A subsequent Start re-wires cleanly (no double-wire panic) with an empty cooldown.
	cfg.PrivateKeyHex = generateTestKey(t)
	if _, err := n.Start(cfg); err != nil {
		t.Fatalf("re-Start: %v", err)
	}
	if n.lanDialHandler == nil {
		t.Fatal("lanDialHandler should re-wire on the second Start")
	}
	if got := len(n.lanDialHandler.cooldown); got != 0 {
		t.Fatalf("cooldown map should be empty after re-wire, got %d entries", got)
	}
	_ = n.Stop()
}

// T10 — concurrent HandleLANPeerFound for distinct peers issues no racy map
// write (run under -race).
func TestHandleLANPeerFound_ConcurrentDistinctPeers_NoRace(t *testing.T) {
	n := startLANDialTestNode(t, &testEventCollector{}, true)
	n.lanDialHandler.dialHook = func(_ context.Context, _ peer.AddrInfo) error { return nil }

	const peers = 16
	infos := make([]peer.AddrInfo, peers)
	for i := range infos {
		infos[i] = newFakeLANPeer(t)
	}

	var wg sync.WaitGroup
	for i := 0; i < peers; i++ {
		wg.Add(1)
		go func(pi peer.AddrInfo) {
			defer wg.Done()
			n.HandleLANPeerFound(pi)
		}(infos[i])
	}
	wg.Wait()

	n.lanDialHandler.mu.Lock()
	got := len(n.lanDialHandler.cooldown)
	n.lanDialHandler.mu.Unlock()
	if got != peers {
		t.Fatalf("expected %d distinct peers recorded in the cooldown map, got %d", peers, got)
	}
}
