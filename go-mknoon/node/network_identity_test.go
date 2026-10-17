package node

import (
	"context"
	"fmt"
	"net"
	"testing"
	"time"

	"github.com/libp2p/go-libp2p/core/event"
	"github.com/libp2p/go-libp2p/core/network"
	"github.com/libp2p/go-libp2p/core/peer"
	"github.com/libp2p/go-libp2p/p2p/net/swarm"
	"github.com/libp2p/go-netroute"
	ma "github.com/multiformats/go-multiaddr"
	manet "github.com/multiformats/go-multiaddr/net"
)

// Residual risk 1 of the D27 fix: libp2p resolves the wildcard listen
// addresses against an interface snapshot it refreshes at most once a minute
// (addrs_manager.go interfaceAddrsCacheTTL), so after Wi-Fi -> LTE the host
// keeps announcing the dead Wi-Fi address for up to a minute. The path event
// must make the announced set follow the interfaces promptly: the old
// interface's address gone, the new one present, in host.Addrs() and in the
// EvtLocalAddressesUpdated event identify pushes to peers.
func TestNetworkPathChange_AnnouncedAddrsFollowInterfaceChangePromptly(t *testing.T) {
	restore := manet.SetInterfaceAddrsProviderForTests(func() ([]net.Addr, error) {
		return avIPNetAddrs(avMarkerPrivateIP), nil
	})
	t.Cleanup(restore)
	restoreNR := netroute.SetNewFailureHookForTests(avDenyNetroute)
	t.Cleanup(restoreNR)

	n := avStartLocalNode(t)
	h := n.Host()
	avWaitHostAddr(t, h, avMarkerPrivateIP, 3*time.Second)
	sub, err := h.EventBus().Subscribe(new(event.EvtLocalAddressesUpdated))
	if err != nil {
		t.Fatalf("subscribe: %v", err)
	}
	defer sub.Close()

	// Wi-Fi -> LTE: the interface set changes under the running host.
	manet.SetInterfaceAddrsProviderForTests(func() ([]net.Addr, error) {
		return avIPNetAddrs(avMarkerPrivateIP2), nil
	})
	start := time.Now()
	if adm := n.NetworkPathChanged(NetworkPathRequest{OwnerGeneration: 1, Epoch: 1, Usable: true}); !adm.Accepted {
		t.Fatalf("admission = %+v, want accepted", adm)
	}

	// libp2p on its own needs the 60 s cache TTL plus a 5 s tick (the 75 s
	// case in addr_visibility_denial_test.go). The path event must do it in
	// a small fraction of that.
	const bound = 10 * time.Second
	deadline := start.Add(bound)
	converged := func(addrs []ma.Multiaddr) bool {
		return avAddrsContain(addrs, avMarkerPrivateIP2) && !avAddrsContain(addrs, avMarkerPrivateIP)
	}
	var addrs []ma.Multiaddr
	for time.Now().Before(deadline) {
		addrs = h.Addrs()
		if converged(addrs) {
			break
		}
		time.Sleep(50 * time.Millisecond)
	}
	if !converged(addrs) {
		t.Fatalf("host.Addrs() %v after the path change: want %s present and %s gone, got %v",
			time.Since(start).Round(time.Millisecond), avMarkerPrivateIP2, avMarkerPrivateIP, addrs)
	}
	t.Logf("host.Addrs() converged %v after the path change", time.Since(start).Round(time.Millisecond))

	for {
		remaining := time.Until(deadline)
		if remaining <= 0 {
			t.Fatalf("no EvtLocalAddressesUpdated announcing %s without %s within %v of the path change", avMarkerPrivateIP2, avMarkerPrivateIP, bound)
		}
		select {
		case raw, ok := <-sub.Out():
			if !ok {
				t.Fatal("subscription closed")
			}
			e := raw.(event.EvtLocalAddressesUpdated)
			current := make([]ma.Multiaddr, 0, len(e.Current))
			for _, u := range e.Current {
				current = append(current, u.Address)
			}
			if converged(current) {
				t.Logf("EvtLocalAddressesUpdated converged %v after the path change", time.Since(start).Round(time.Millisecond))
				return
			}
		case <-time.After(remaining):
		}
	}
}

// Residual risk 2 of the D27 fix: the fresh-socket policy covers only the
// handoff dial. Every later QUIC dial went back through ordinary socket reuse,
// which picks the wildcard listener socket created on the old network. If
// Android keeps that socket on the dead network, a later relay reconnect and
// every direct peer dial fail until the next path event or a restart.
//
// After a successful handoff only the old listener socket goes dark. The
// handoff connection then drops, as it would later in a call. A later ordinary
// relay redial and a direct QUIC peer dial must both succeed and must not
// leave from the old listener socket.
func TestNetworkPathChange_LaterRedialsDoNotUseOldListenerSocket(t *testing.T) {
	if testing.Short() {
		t.Skip("real relay + proxy fixture; skipped in -short")
	}
	_, proxy, relayAddr := startHandoffRelayFixture(t)
	relay := relayPeerOf(t, relayAddr)
	n, collector := startHandoffNode(t, relayAddr)
	waitForEpoch1Reservation(t, n, relay)
	h := n.Host()
	oldListenerPort := quicListenPort(t, h)

	if adm := n.NetworkPathChanged(NetworkPathRequest{OwnerGeneration: 1, Epoch: 2, Usable: true}); !adm.Accepted {
		t.Fatalf("admission = %+v, want accepted", adm)
	}
	if name, data := waitHandoffTerminal(t, collector, 2, NetworkHandoffBudget+2*time.Second); name != "network:relay_ready" {
		t.Fatalf("epoch 2 terminal = %s %v, want relay_ready", name, data)
	}

	// The listener socket born on the old network is the only thing that stalls.
	if !proxy.BlackholeClientPort(oldListenerPort) {
		t.Fatalf("relay never saw the old listener socket %d", oldListenerPort)
	}
	for _, c := range h.Network().ConnsToPeer(relay) {
		_ = c.Close()
	}
	waitNotConnected(t, h, relay)

	start := time.Now()
	done := make(chan *RecoveryResult, 1)
	go func() { done <- n.RefreshRelaySession() }()
	var result *RecoveryResult
	select {
	case result = <-done:
	case <-time.After(25 * time.Second):
		t.Fatal("later relay redial did not return within 25 s")
	}
	if result == nil || !result.Success {
		t.Fatalf("later relay redial %v after the path change failed: %+v", time.Since(start).Round(time.Millisecond), result)
	}
	conns := h.Network().ConnsToPeer(relay)
	if len(conns) == 0 {
		t.Fatal("relay redial reported success without a connection")
	}
	for _, c := range conns {
		if p := udpPortOf(c.LocalMultiaddr()); p == oldListenerPort {
			t.Fatalf("later relay redial left from the old listener socket %d", p)
		}
	}
	t.Logf("later relay redial succeeded in %v from port %d (old listener %d)",
		time.Since(start).Round(time.Millisecond), udpPortOf(conns[0].LocalMultiaddr()), oldListenerPort)

	// A direct QUIC peer dial also leaves from the current listener socket.
	buddy := newPolicyHost(t, newFreshQUICDialPolicy(), "/ip4/127.0.0.1/udp/0/quic-v1")
	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()
	if err := h.Connect(ctx, peer.AddrInfo{ID: buddy.ID(), Addrs: loopbackQUICAddrs(buddy)}); err != nil {
		t.Fatalf("direct QUIC dial after the path change: %v", err)
	}
	direct := onlyConnTo(t, h, buddy.ID())
	current := quicListenPort(t, h)
	if p := udpPortOf(direct.LocalMultiaddr()); p == oldListenerPort || p != current {
		t.Fatalf("direct dial local port = %d, want the current listener socket %d (old %d)", p, current, oldListenerPort)
	}
}

// avMarkerPublicIPv6 is a documentation-range global IPv6 (RFC 3849) the
// interface seam reports so a test host behaves dual-stack.
const avMarkerPublicIPv6 = "2001:db8:190::10"

// freePortForTCPAndUDP returns a port that is free for both protocols right
// now, for a fixed-ListenPort node.
func freePortForTCPAndUDP(t *testing.T) int {
	t.Helper()
	for i := 0; i < 20; i++ {
		tl, err := net.Listen("tcp4", "127.0.0.1:0")
		if err != nil {
			continue
		}
		port := tl.Addr().(*net.TCPAddr).Port
		_ = tl.Close()
		ul, err := net.ListenUDP("udp4", &net.UDPAddr{IP: net.IPv4zero, Port: port})
		if err != nil {
			continue
		}
		_ = ul.Close()
		return port
	}
	t.Fatal("no port free for both TCP and UDP")
	return 0
}

func startNodeWithSocketSeam(t *testing.T, factory *observedSocketFactory, listenPort int) *Node {
	t.Helper()
	n := New(&testEventCollector{})
	n.freshRelayDial.listenUDP = factory.listen
	if _, err := n.Start(NodeConfig{
		PrivateKeyHex:  generateTestKey(t),
		RelayAddresses: []string{},
		AutoRegister:   false,
		ListenPort:     listenPort,
	}); err != nil {
		t.Fatalf("Start: %v", err)
	}
	t.Cleanup(func() { _ = n.Stop() })
	return n
}

func ip4QUICListenPorts(h interface {
	Network() network.Network
}) map[int]bool {
	return quicListenPortsByFamily(h)["ip4"]
}

// quicListenPortsByFamily groups the QUIC listen ports by address family
// ("ip4", "ip6"). The IPv4 and IPv6 wildcard listeners are separate sockets
// with ports of their own, so comparisons must stay within one family.
func quicListenPortsByFamily(h interface {
	Network() network.Network
}) map[string]map[int]bool {
	out := map[string]map[int]bool{}
	for _, a := range h.Network().ListenAddresses() {
		if _, err := a.ValueForProtocol(ma.P_QUIC_V1); err != nil {
			continue
		}
		f := addrFamily(a)
		if out[f] == nil {
			out[f] = map[int]bool{}
		}
		out[f][udpPortOf(a)] = true
	}
	return out
}

func addrFamily(a ma.Multiaddr) string {
	if _, err := a.ValueForProtocol(ma.P_IP6); err == nil {
		return "ip6"
	}
	return "ip4"
}

func onlyPort(t *testing.T, what string, ports map[int]bool) int {
	t.Helper()
	if len(ports) != 1 {
		t.Fatalf("%s = %v, want exactly one port", what, ports)
	}
	for p := range ports {
		return p
	}
	return 0
}

// Pins what the fix changes on purpose. On a path change every QUIC listen
// port (one per address family) moves to a socket the node created itself
// (through its socket seam, so a platform owner can bind it to the current
// network). Connections already on the old socket are not touched. New
// ordinary dials leave from the new socket, so identify's observed addresses
// and hole punching follow it: the relay sees the new socket's mapping on the
// next relay connection. A fixed ListenPort keeps its listener. Stop closes
// every socket the node created.
func TestNetworkPathChange_MovesQUICListenerToNewSocket(t *testing.T) {
	// A dual-stack host: the IPv4 and IPv6 wildcard listeners get ports of
	// their own, so h.Addrs() carries two QUIC ports (Task 15 finding 9).
	restore := manet.SetInterfaceAddrsProviderForTests(func() ([]net.Addr, error) {
		return avIPNetAddrs(avMarkerPrivateIP, avMarkerPublicIPv6), nil
	})
	t.Cleanup(restore)
	factory := &observedSocketFactory{}
	n := startNodeWithSocketSeam(t, factory, 0)
	h := n.Host()
	oldPorts := quicListenPortsByFamily(h)
	p1 := onlyPort(t, "IPv4 QUIC listen ports before the path change", oldPorts["ip4"])
	if _, dualStack := oldPorts["ip6"]; !dualStack {
		t.Fatal("precondition: the node has no IPv6 QUIC listener on this host")
	}
	buddy := newPolicyHost(t, newFreshQUICDialPolicy(), "/ip4/127.0.0.1/udp/0/quic-v1")
	connectHosts(t, h, buddy)
	before := onlyConnTo(t, h, buddy.ID())
	if got := udpPortOf(before.LocalMultiaddr()); got != p1 {
		t.Fatalf("pre-change dial local port = %d, want listener %d", got, p1)
	}
	seamSocketsBefore := factory.count()

	if adm := n.NetworkPathChanged(NetworkPathRequest{OwnerGeneration: 1, Epoch: 1, Usable: true}); !adm.Accepted {
		t.Fatalf("admission = %+v, want accepted", adm)
	}
	// Every family's listener moved to exactly one new port.
	moved := func(now map[string]map[int]bool) bool {
		for f, old := range oldPorts {
			if len(now[f]) != 1 {
				return false
			}
			for p := range now[f] {
				if old[p] {
					return false
				}
			}
		}
		return true
	}
	deadline := time.Now().Add(5 * time.Second)
	var newPorts map[string]map[int]bool
	for time.Now().Before(deadline) {
		newPorts = quicListenPortsByFamily(h)
		if moved(newPorts) {
			break
		}
		time.Sleep(20 * time.Millisecond)
	}
	if !moved(newPorts) {
		t.Fatalf("QUIC listen ports after the path change = %v, want one new port per family (old %v)", newPorts, oldPorts)
	}
	p2 := onlyPort(t, "IPv4 QUIC listen ports after the path change", newPorts["ip4"])
	if factory.count() <= seamSocketsBefore {
		t.Fatal("the new listener socket did not come from the node's socket seam")
	}

	// The connection on the old socket is untouched.
	if before.IsClosed() {
		t.Fatal("path change closed a live connection on the old listener socket")
	}
	if err := pingOK(h, buddy.ID(), 2*time.Second); err != nil {
		t.Fatalf("ping over the pre-change connection: %v", err)
	}

	// New ordinary dials leave from the new socket.
	buddy2 := newPolicyHost(t, newFreshQUICDialPolicy(), "/ip4/127.0.0.1/udp/0/quic-v1")
	connectHosts(t, h, buddy2)
	after := onlyConnTo(t, h, buddy2.ID())
	if got := udpPortOf(after.LocalMultiaddr()); got != p2 {
		t.Fatalf("post-change dial local port = %d, want new listener %d (old %d)", got, p2, p1)
	}

	// Advertised addresses carry each family's new port and never its old one.
	advertised := func() (bad string, ok bool) {
		seen := map[string]bool{}
		for _, a := range h.Addrs() {
			if _, err := a.ValueForProtocol(ma.P_QUIC_V1); err != nil {
				continue
			}
			f, got := addrFamily(a), udpPortOf(a)
			seen[f] = true
			if oldPorts[f][got] {
				return fmt.Sprintf("h.Addrs() still advertises the old %s QUIC port %d: %v", f, got, h.Addrs()), false
			}
			if !newPorts[f][got] {
				return fmt.Sprintf("h.Addrs() advertises %s QUIC port %d, want one of %v: %v", f, got, newPorts[f], h.Addrs()), false
			}
		}
		if !seen["ip4"] || !seen["ip6"] {
			return fmt.Sprintf("h.Addrs() lacks a QUIC address for both families: %v", h.Addrs()), false
		}
		return "", true
	}
	var bad string
	var ok bool
	for deadline = time.Now().Add(5 * time.Second); time.Now().Before(deadline); time.Sleep(20 * time.Millisecond) {
		if bad, ok = advertised(); ok {
			break
		}
	}
	if !ok {
		t.Fatal(bad)
	}

	if err := n.Stop(); err != nil {
		t.Fatalf("Stop: %v", err)
	}
	if !factory.allClosedWithin(3 * time.Second) {
		t.Fatal("a node-created listener socket survived Stop")
	}
}

func TestNetworkPathChange_FixedListenPortKeepsItsListener(t *testing.T) {
	factory := &observedSocketFactory{}
	port := freePortForTCPAndUDP(t)
	n := startNodeWithSocketSeam(t, factory, port)
	h := n.Host()
	if got := quicListenPort(t, h); got != port {
		t.Fatalf("fixed-port node listens on %d, want %d", got, port)
	}
	if adm := n.NetworkPathChanged(NetworkPathRequest{OwnerGeneration: 1, Epoch: 1, Usable: true}); !adm.Accepted {
		t.Fatalf("admission = %+v, want accepted", adm)
	}
	time.Sleep(300 * time.Millisecond)
	if ports := ip4QUICListenPorts(h); !ports[port] || len(ports) != 1 {
		t.Fatalf("fixed-port listeners after the path change = %v, want only %d", ports, port)
	}
	if factory.count() != 0 {
		t.Fatalf("fixed-port node created %d sockets on the path change, want 0", factory.count())
	}
}

// A path-change generation closes its ConnManager (and the gc goroutine
// inside it) once its sockets are gone, and no later than host close.
// libp2p's reuse gc closes an unused socket 10 to 40 s after the last
// connection on it ends; the test stands in for the gc by closing the socket.
func TestQUICGeneration_ClosesOnceItsSocketsAreGone(t *testing.T) {
	factory := &observedSocketFactory{}
	policy := newFreshQUICDialPolicy()
	policy.listenUDP = factory.listen
	h := newPolicyHost(t, policy, "/ip4/0.0.0.0/udp/0/quic-v1")
	tr := policy.transport.Load()
	if tr == nil {
		t.Fatal("policy does not know the host's QUIC transport")
	}
	sw := h.Network().(*swarm.Swarm)

	if moved, err := tr.rebindListeners(sw, 0, 1); err != nil || moved != 1 {
		t.Fatalf("first rebind = (%d, %v), want (1, nil)", moved, err)
	}
	tr.mu.RLock()
	gen1 := tr.generations[0]
	tr.mu.RUnlock()
	if len(gen1.socketsCreated()) == 0 {
		t.Fatal("first generation created no socket")
	}
	if moved, err := tr.rebindListeners(sw, 0, 2); err != nil || moved != 1 {
		t.Fatalf("second rebind = (%d, %v), want (1, nil)", moved, err)
	}
	if got := tr.openGenerations(); got != 2 {
		t.Fatalf("open generations after two rebinds = %d, want 2 (old sockets may still carry connections)", got)
	}

	// What the reuse gc does once nothing uses the socket any more.
	for _, s := range gen1.socketsCreated() {
		_ = s.Close()
	}
	deadline := time.Now().Add(2 * time.Second)
	for time.Now().Before(deadline) && tr.openGenerations() != 1 {
		time.Sleep(10 * time.Millisecond)
	}
	if got := tr.openGenerations(); got != 1 {
		t.Fatalf("open generations after the first generation's sockets closed = %d, want 1", got)
	}

	if err := h.Close(); err != nil {
		t.Fatalf("host close: %v", err)
	}
	if got := tr.openGenerations(); got != 0 {
		t.Fatalf("open generations after host close = %d, want 0", got)
	}
	if !factory.allClosedWithin(3 * time.Second) {
		t.Fatal("a generation socket survived host close")
	}
	if policy.transport.Load() != nil {
		t.Fatal("policy still points at the closed host's transport")
	}
}
