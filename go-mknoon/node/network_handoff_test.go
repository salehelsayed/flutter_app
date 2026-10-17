package node

import (
	"context"
	"crypto/rand"
	"encoding/json"
	"fmt"
	"net"
	"strconv"
	"sync"
	"sync/atomic"
	"testing"
	"time"

	"github.com/libp2p/go-libp2p"
	libp2pcrypto "github.com/libp2p/go-libp2p/core/crypto"
	"github.com/libp2p/go-libp2p/core/event"
	"github.com/libp2p/go-libp2p/core/host"
	"github.com/libp2p/go-libp2p/core/network"
	"github.com/libp2p/go-libp2p/core/peer"
	relayclient "github.com/libp2p/go-libp2p/p2p/protocol/circuitv2/client"
	"github.com/libp2p/go-libp2p/p2p/protocol/ping"
	"github.com/libp2p/go-libp2p/p2p/transport/quicreuse"
	ma "github.com/multiformats/go-multiaddr"
)

// --- fixture -----------------------------------------------------------------

// startHandoffRelayFixture runs a real circuit-v2 relay on loopback QUIC behind
// a socket-scoped blackhole proxy and returns the relay address the node must
// use (through the proxy).
func startHandoffRelayFixture(t *testing.T) (host.Host, *udpBlackholeProxy, string) {
	t.Helper()
	return startHandoffRelayFixtureOn(t, net.IPv4(127, 0, 0, 1))
}

// startHandoffRelayFixtureOn binds the relay and the proxy to ip. A
// non-loopback ip lets libp2p's observed-address machinery see the proxy's
// back socket as the node's external address (it ignores loopback
// observations).
func startHandoffRelayFixtureOn(t *testing.T, ip net.IP) (host.Host, *udpBlackholeProxy, string) {
	t.Helper()
	priv, _, err := libp2pcrypto.GenerateEd25519Key(rand.Reader)
	if err != nil {
		t.Fatalf("relay key: %v", err)
	}
	// The relay advertises only its proxied address, so identify can never
	// teach the node a direct path around the proxy.
	var advertised atomic.Pointer[ma.Multiaddr]
	relayHost, err := libp2p.New(
		libp2p.Identity(priv),
		libp2p.ListenAddrStrings(fmt.Sprintf("/ip4/%s/udp/0/quic-v1", ip)),
		libp2p.EnableRelayService(),
		libp2p.ForceReachabilityPublic(),
		libp2p.AddrsFactory(func(addrs []ma.Multiaddr) []ma.Multiaddr {
			if a := advertised.Load(); a != nil {
				return []ma.Multiaddr{*a}
			}
			return addrs
		}),
	)
	if err != nil {
		t.Fatalf("relay host: %v", err)
	}
	t.Cleanup(func() { _ = relayHost.Close() })
	proxy := newUDPBlackholeProxyOn(t, ip, quicListenUDPAddrOn(t, relayHost, ip))
	proxied := ma.StringCast(fmt.Sprintf("/ip4/%s/udp/%d/quic-v1", ip, proxy.Addr().Port))
	advertised.Store(&proxied)
	addr := fmt.Sprintf("/ip4/%s/udp/%d/quic-v1/p2p/%s", ip, proxy.Addr().Port, relayHost.ID())
	return relayHost, proxy, addr
}

func quicListenUDPAddr(t *testing.T, h host.Host) *net.UDPAddr {
	t.Helper()
	return quicListenUDPAddrOn(t, h, net.IPv4(127, 0, 0, 1))
}

func quicListenUDPAddrOn(t *testing.T, h host.Host, ip net.IP) *net.UDPAddr {
	t.Helper()
	for _, addr := range h.Network().ListenAddresses() {
		if _, err := addr.ValueForProtocol(ma.P_QUIC_V1); err != nil {
			continue
		}
		if got, err := addr.ValueForProtocol(ma.P_IP4); err != nil || got != ip.String() {
			continue
		}
		udpAddr, _, err := quicreuse.FromQuicMultiaddr(addr)
		if err != nil {
			t.Fatalf("quic listen addr %s: %v", addr, err)
		}
		return udpAddr
	}
	t.Fatalf("host has no QUIC listen address on %s", ip)
	return nil
}

func udpPortOf(addr ma.Multiaddr) int {
	v, err := addr.ValueForProtocol(ma.P_UDP)
	if err != nil {
		return -1
	}
	port, _ := strconv.Atoi(v)
	return port
}

func quicListenPort(t *testing.T, h host.Host) int {
	t.Helper()
	for _, addr := range h.Network().ListenAddresses() {
		if _, err := addr.ValueForProtocol(ma.P_QUIC_V1); err == nil {
			if _, err := addr.ValueForProtocol(ma.P_IP4); err == nil {
				return udpPortOf(addr)
			}
		}
	}
	t.Fatal("host has no IPv4 QUIC listen address")
	return -1
}

func startHandoffNode(t *testing.T, relayAddr string) (*Node, *testEventCollector) {
	t.Helper()
	collector := &testEventCollector{}
	n := New(collector)
	n.hermeticLocalNetworkForTests = true
	// A loopback relay never yields an advertised /p2p-circuit address
	// (autorelay drops non-public relay addrs), so the explicit-reserve path
	// is the reservation truth here. Skip the circuit-address poll budget.
	n.waitForCircuitAddressHook = func(time.Duration) bool { return false }
	if _, err := n.Start(NodeConfig{
		PrivateKeyHex:  generateTestKey(t),
		RelayAddresses: []string{relayAddr},
		AutoRegister:   false,
	}); err != nil {
		t.Fatalf("Start: %v", err)
	}
	t.Cleanup(func() { _ = n.Stop() })
	if err := n.WaitForRelayConnection(10 * time.Second); err != nil {
		t.Fatalf("relay warm: %v", err)
	}
	return n, collector
}

func relayPeerOf(t *testing.T, relayAddr string) peer.ID {
	t.Helper()
	info, err := peer.AddrInfoFromString(relayAddr)
	if err != nil {
		t.Fatalf("relay addr: %v", err)
	}
	return info.ID
}

// waitForEpoch1Reservation puts the node in the state D27 started from: a
// live explicit reservation on the relay, obtained through the production
// in-place refresh path.
func waitForEpoch1Reservation(t *testing.T, n *Node, relay peer.ID) {
	t.Helper()
	result := n.RefreshRelaySession()
	if result == nil || !result.Success {
		t.Fatalf("epoch-1 refresh failed: %+v", result)
	}
	if !n.relaySessionMgr.HasActiveManualReservation(relay) {
		t.Fatal("epoch-1 refresh succeeded without an explicit reservation")
	}
}

func handoffEvents(c *testEventCollector, name string) []map[string]interface{} {
	var out []map[string]interface{}
	for _, raw := range c.snapshot() {
		var ev struct {
			Event string                 `json:"event"`
			Data  map[string]interface{} `json:"data"`
		}
		if json.Unmarshal([]byte(raw), &ev) != nil || ev.Event != name {
			continue
		}
		out = append(out, ev.Data)
	}
	return out
}

func eventsForEpoch(c *testEventCollector, name string, epoch uint64) []map[string]interface{} {
	var out []map[string]interface{}
	for _, data := range handoffEvents(c, name) {
		if e, _ := data["epoch"].(float64); uint64(e) == epoch {
			out = append(out, data)
		}
	}
	return out
}

// waitHandoffTerminal waits for the one terminal event of an epoch and returns
// its name and payload.
func waitHandoffTerminal(t *testing.T, c *testEventCollector, epoch uint64, timeout time.Duration) (string, map[string]interface{}) {
	t.Helper()
	deadline := time.Now().Add(timeout)
	for time.Now().Before(deadline) {
		if ev := eventsForEpoch(c, "network:relay_ready", epoch); len(ev) > 0 {
			return "network:relay_ready", ev[0]
		}
		if ev := eventsForEpoch(c, "network:relay_failed", epoch); len(ev) > 0 {
			return "network:relay_failed", ev[0]
		}
		time.Sleep(20 * time.Millisecond)
	}
	t.Fatalf("no terminal handoff event for epoch %d within %v; events=%v", epoch, timeout, c.snapshot())
	return "", nil
}

func newLoopbackTCPHost(t *testing.T) host.Host {
	t.Helper()
	h, err := libp2p.New(libp2p.ListenAddrStrings("/ip4/127.0.0.1/tcp/0"))
	if err != nil {
		t.Fatalf("tcp host: %v", err)
	}
	t.Cleanup(func() { _ = h.Close() })
	return h
}

func connectHosts(t *testing.T, from host.Host, to host.Host) {
	t.Helper()
	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()
	if err := from.Connect(ctx, peer.AddrInfo{ID: to.ID(), Addrs: to.Addrs()}); err != nil {
		t.Fatalf("connect %s -> %s: %v", from.ID(), to.ID(), err)
	}
}

func pingOK(h host.Host, p peer.ID, timeout time.Duration) error {
	ctx, cancel := context.WithTimeout(context.Background(), timeout)
	defer cancel()
	select {
	case res := <-ping.Ping(ctx, h, p):
		return res.Error
	case <-ctx.Done():
		return ctx.Err()
	}
}

// --- main causal test ----------------------------------------------------------

// TestDefaultNetworkChange_ReplacesStalledRelayBeforeIdleTimeout is the D27
// causal test. Epoch 1: a real reservation on a real relay. Then every socket
// that existed on epoch 1 is blackholed while the libp2p connection stays
// "connected" (no close, no idle-timer trick). Epoch 2 arrives through the
// production handoff entry. The node must retire the stalled relay connection,
// come back on a brand-new socket, hold a new reservation and answer a bounded
// round trip, all inside the handoff budget and long before QUIC's 30 s idle
// timeout, without restarting the host.
func TestDefaultNetworkChange_ReplacesStalledRelayBeforeIdleTimeout(t *testing.T) {
	if testing.Short() {
		t.Skip("real relay + proxy fixture; skipped in -short")
	}
	_, proxy, relayAddr := startHandoffRelayFixture(t)
	relay := relayPeerOf(t, relayAddr)
	n, collector := startHandoffNode(t, relayAddr)
	waitForEpoch1Reservation(t, n, relay)

	h0 := n.Host()
	id0 := h0.ID()
	listenerPort := quicListenPort(t, h0)
	oldConns := h0.Network().ConnsToPeer(relay)
	if len(oldConns) == 0 {
		t.Fatal("no epoch-1 relay connection")
	}
	oldPorts := map[int]bool{}
	for _, c := range oldConns {
		oldPorts[udpPortOf(c.LocalMultiaddr())] = true
	}
	if !oldPorts[listenerPort] {
		t.Fatalf("epoch-1 relay connection did not reuse the listener socket: ports=%v listener=%d", oldPorts, listenerPort)
	}

	// Preservation controls: an unrelated TCP peer connection and an unrelated
	// event-bus subscription must both survive the handoff untouched.
	buddy := newLoopbackTCPHost(t)
	connectHosts(t, h0, buddy)
	sub, err := h0.EventBus().Subscribe(new(event.EvtPeerConnectednessChanged))
	if err != nil {
		t.Fatalf("subscribe: %v", err)
	}
	defer sub.Close()
	hostReadyBefore := len(handoffEventsWithPhase(collector, "host_ready"))

	// The causal condition: epoch-1 sockets go dark, the connection stays labelled connected.
	blackholed := proxy.BlackholeCurrentClients()
	if len(blackholed) == 0 {
		t.Fatal("proxy saw no epoch-1 client socket")
	}
	if got := h0.Network().Connectedness(relay); got != network.Connected {
		t.Fatalf("relay connectedness after blackhole = %v, want Connected (stalled, not closed)", got)
	}
	if err := pingOK(h0, relay, 700*time.Millisecond); err == nil {
		t.Fatal("ping over the blackholed relay connection succeeded; the fixture does not stall")
	}
	socketsBefore := len(proxy.ClientSockets())

	// Epoch 2 delivered three times at once: one owned attempt, two coalesced.
	start := time.Now()
	var admissions [3]NetworkPathAdmission
	var wg sync.WaitGroup
	for i := range admissions {
		wg.Add(1)
		go func(i int) {
			defer wg.Done()
			admissions[i] = n.NetworkPathChanged(NetworkPathRequest{OwnerGeneration: 7, Epoch: 2, Usable: true})
		}(i)
	}
	wg.Wait()
	accepted, coalesced := 0, 0
	for _, adm := range admissions {
		if adm.Accepted {
			accepted++
		}
		if adm.Coalesced {
			coalesced++
		}
	}
	if accepted != 1 || coalesced != 2 {
		t.Fatalf("admissions = %+v, want exactly 1 accepted and 2 coalesced", admissions)
	}

	name, data := waitHandoffTerminal(t, collector, 2, NetworkHandoffBudget+2*time.Second)
	elapsed := time.Since(start)
	if name != "network:relay_ready" {
		t.Fatalf("epoch 2 terminal event = %s %v after %v, want network:relay_ready", name, data, elapsed)
	}
	if elapsed > NetworkHandoffBudget {
		t.Fatalf("handoff took %v, over the %v budget", elapsed, NetworkHandoffBudget)
	}
	if gen, _ := data["ownerGeneration"].(float64); int64(gen) != 7 {
		t.Fatalf("relay_ready ownerGeneration = %v, want 7", data["ownerGeneration"])
	}
	if stage, _ := data["stage"].(string); stage != handoffStageProbeOK {
		t.Fatalf("relay_ready stage = %v, want %s", data["stage"], handoffStageProbeOK)
	}
	if fresh, _ := data["socketFresh"].(bool); !fresh {
		t.Fatalf("relay_ready socketFresh = %v, want true", data["socketFresh"])
	}

	// Old relay connections retired; the new one rides a new socket.
	for _, c := range oldConns {
		if !c.IsClosed() {
			t.Fatalf("epoch-1 relay connection %s still open after handoff", c.LocalMultiaddr())
		}
	}
	newConns := h0.Network().ConnsToPeer(relay)
	if len(newConns) == 0 {
		t.Fatal("no relay connection after handoff")
	}
	var fresh network.Conn
	for _, c := range newConns {
		port := udpPortOf(c.LocalMultiaddr())
		if port > 0 && port != listenerPort && !oldPorts[port] {
			fresh = c
		}
	}
	if fresh == nil {
		ports := []int{}
		for _, c := range newConns {
			ports = append(ports, udpPortOf(c.LocalMultiaddr()))
		}
		t.Fatalf("relay connection after handoff reuses an epoch-1 socket: ports=%v listener=%d old=%v", ports, listenerPort, oldPorts)
	}
	if epoch, ok := n.freshRelayDial.freshEpoch(fresh); !ok || epoch != 2 {
		t.Fatalf("new relay connection not recorded as epoch-2 fresh: epoch=%d ok=%v", epoch, ok)
	}
	newSockets := proxy.ClientSockets()[socketsBefore:]
	if len(newSockets) != 1 {
		t.Fatalf("relay saw %d new client sockets after the switch, want exactly 1 (one owned attempt): %v", len(newSockets), newSockets)
	}

	// New reservation, proven from outside: a third host reaches the node
	// through the relay circuit, which only works while the relay holds a
	// live reservation for the node.
	if !n.relaySessionMgr.HasActiveManualReservation(relay) {
		t.Fatal("no explicit reservation recorded after handoff")
	}
	prober, err := libp2p.New(libp2p.ListenAddrStrings("/ip4/127.0.0.1/udp/0/quic-v1"), libp2p.EnableRelay())
	if err != nil {
		t.Fatalf("prober: %v", err)
	}
	defer prober.Close()
	circuit, err := ma.NewMultiaddr(relayAddr + "/p2p-circuit")
	if err != nil {
		t.Fatalf("circuit addr: %v", err)
	}
	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()
	if err := prober.Connect(ctx, peer.AddrInfo{ID: id0, Addrs: []ma.Multiaddr{circuit}}); err != nil {
		t.Fatalf("circuit dial through the new reservation failed: %v", err)
	}

	// Host, identity, unrelated connection and subscription preserved; no Stop/Start.
	if n.Host() != h0 || n.Host().ID() != id0 {
		t.Fatal("host instance or identity changed across the handoff")
	}
	if got := h0.Network().Connectedness(buddy.ID()); got != network.Connected {
		t.Fatalf("unrelated TCP peer connectedness = %v after handoff, want Connected", got)
	}
	if err := pingOK(h0, buddy.ID(), 2*time.Second); err != nil {
		t.Fatalf("unrelated TCP peer ping after handoff: %v", err)
	}
	if n.relaySessionMgr.WatchdogRestartCount() != 0 {
		t.Fatal("watchdog restart count moved during handoff")
	}
	if got := len(handoffEventsWithPhase(collector, "host_ready")); got != hostReadyBefore {
		t.Fatalf("host_ready startup events = %d, want %d (no Start inside the handoff)", got, hostReadyBefore)
	}
	late := newLoopbackTCPHost(t)
	connectHosts(t, h0, late)
	if !subscriptionSawPeer(sub, late.ID(), 3*time.Second) {
		t.Fatal("event-bus subscription created before the handoff stopped delivering")
	}

	// Duplicates and stale epochs after readiness do nothing.
	if adm := n.NetworkPathChanged(NetworkPathRequest{OwnerGeneration: 7, Epoch: 2, Usable: true}); adm.Accepted || !adm.Coalesced {
		t.Fatalf("duplicate epoch 2 admission = %+v, want coalesced", adm)
	}
	if adm := n.NetworkPathChanged(NetworkPathRequest{OwnerGeneration: 7, Epoch: 1, Usable: true}); adm.Accepted || adm.Reason != handoffReasonStaleEpoch {
		t.Fatalf("stale epoch 1 admission = %+v, want stale_epoch", adm)
	}
	time.Sleep(200 * time.Millisecond)
	if got := len(handoffEvents(collector, "network:relay_ready")); got != 1 {
		t.Fatalf("relay_ready events = %d, want 1", got)
	}
	if status := n.NetworkPathStatus(); status["readyEpoch"].(uint64) != 2 {
		t.Fatalf("status readyEpoch = %v, want 2", status["readyEpoch"])
	}
	t.Logf("handoff ready in %v (dialMs=%v reserveMs=%v probeMs=%v)", elapsed, data["dialMs"], data["reserveMs"], data["probeMs"])
}

func handoffEventsWithPhase(c *testEventCollector, phase string) []map[string]interface{} {
	var out []map[string]interface{}
	for _, data := range handoffEvents(c, "node:startup_timing") {
		if p, _ := data["phase"].(string); p == phase {
			out = append(out, data)
		}
	}
	return out
}

func subscriptionSawPeer(sub event.Subscription, p peer.ID, timeout time.Duration) bool {
	deadline := time.After(timeout)
	for {
		select {
		case ev, ok := <-sub.Out():
			if !ok {
				return false
			}
			if e, ok := ev.(event.EvtPeerConnectednessChanged); ok && e.Peer == p && e.Connectedness == network.Connected {
				return true
			}
		case <-deadline:
			return false
		}
	}
}

// TestDefaultNetworkChange_PlainCloseAndRedialReusesStalledSocket is the
// negative control for the fresh-socket seam. With the seam switched off the
// handoff still closes the stalled connection and redials through the stock
// swarm and QUIC path. libp2p then reuses the listener socket, which is the
// blackholed one, so the relay never sees a new socket and the dial times out.
// This is the behavior the public close-and-redial APIs give on their own.
func TestDefaultNetworkChange_PlainCloseAndRedialReusesStalledSocket(t *testing.T) {
	if testing.Short() {
		t.Skip("real relay + proxy fixture; skipped in -short")
	}
	_, proxy, relayAddr := startHandoffRelayFixture(t)
	relay := relayPeerOf(t, relayAddr)
	n, collector := startHandoffNode(t, relayAddr)
	waitForEpoch1Reservation(t, n, relay)
	oldConns := n.Host().Network().ConnsToPeer(relay)

	proxy.BlackholeCurrentClients()
	socketsBefore := len(proxy.ClientSockets())
	n.freshRelayDial.disabledForTests = true

	if adm := n.NetworkPathChanged(NetworkPathRequest{OwnerGeneration: 1, Epoch: 2, Usable: true}); !adm.Accepted {
		t.Fatalf("admission = %+v, want accepted", adm)
	}
	name, data := waitHandoffTerminal(t, collector, 2, NetworkHandoffBudget+2*time.Second)
	if name != "network:relay_failed" {
		t.Fatalf("plain close+redial produced %s %v; expected the reused socket to stall", name, data)
	}
	if stage, _ := data["stage"].(string); stage != handoffStageDial {
		t.Fatalf("failure stage = %v, want %s", data["stage"], handoffStageDial)
	}
	for _, c := range oldConns {
		if !c.IsClosed() {
			t.Fatal("stalled relay connection was not retired")
		}
	}
	if got := len(proxy.ClientSockets()) - socketsBefore; got != 0 {
		t.Fatalf("relay saw %d new client sockets from a plain redial, want 0 (reuse)", got)
	}
	if n.freshRelayDial.createdSockets() != 0 {
		t.Fatal("control created a fresh socket; the seam was not disabled")
	}
}

// --- preservation and race matrix (Go rows) ------------------------------------

// Flap Wi-Fi -> LTE -> Wi-Fi: the latest epoch wins. A completed epoch-2
// attempt whose readiness arrives after epoch 3 was requested is discarded;
// attempts never overlap; epoch 3 is proven on its own.
func TestNetworkHandoff_LatestEpochWins_OldCompletionCannotMarkReady(t *testing.T) {
	if testing.Short() {
		t.Skip("real relay + proxy fixture; skipped in -short")
	}
	_, proxy, relayAddr := startHandoffRelayFixture(t)
	relay := relayPeerOf(t, relayAddr)
	n, collector := startHandoffNode(t, relayAddr)
	waitForEpoch1Reservation(t, n, relay)
	proxy.BlackholeCurrentClients()

	var concurrent, maxConcurrent atomic.Int32
	var publishes atomic.Int32
	n.beforePublishNetworkHandoffHook = func(epoch uint64) {
		cur := concurrent.Add(1)
		for {
			prev := maxConcurrent.Load()
			if cur <= prev || maxConcurrent.CompareAndSwap(prev, cur) {
				break
			}
		}
		if publishes.Add(1) == 1 {
			// Epoch 2 finished its work. Before its outcome is published the
			// path changes again.
			adm := n.NetworkPathChanged(NetworkPathRequest{OwnerGeneration: 9, Epoch: 3, Usable: true})
			if !adm.Accepted || adm.Reason != handoffReasonSupersededRunning {
				t.Errorf("epoch 3 admission while epoch 2 completes = %+v", adm)
			}
		}
		concurrent.Add(-1)
	}

	if adm := n.NetworkPathChanged(NetworkPathRequest{OwnerGeneration: 9, Epoch: 2, Usable: true}); !adm.Accepted {
		t.Fatalf("epoch 2 admission = %+v", adm)
	}
	name2, data2 := waitHandoffTerminal(t, collector, 2, NetworkHandoffBudget+2*time.Second)
	if name2 != "network:relay_failed" || data2["errorCode"] != handoffReasonSuperseded {
		t.Fatalf("epoch 2 terminal = %s %v, want relay_failed/superseded", name2, data2)
	}
	name3, _ := waitHandoffTerminal(t, collector, 3, NetworkHandoffBudget+2*time.Second)
	if name3 != "network:relay_ready" {
		t.Fatalf("epoch 3 terminal = %s, want relay_ready", name3)
	}
	if got := n.NetworkPathStatus()["readyEpoch"].(uint64); got != 3 {
		t.Fatalf("readyEpoch = %d, want 3", got)
	}
	if got := len(eventsForEpoch(collector, "network:relay_ready", 2)); got != 0 {
		t.Fatalf("epoch 2 emitted %d relay_ready events, want 0", got)
	}
	if maxConcurrent.Load() != 1 {
		t.Fatalf("max concurrent attempts = %d, want 1", maxConcurrent.Load())
	}
	// Epoch 3 retired epoch 2's relay connection. The live one rides epoch
	// 3's listener socket; no dedicated dial socket stays open.
	h := n.Host()
	deadline := time.Now().Add(2 * time.Second)
	for n.freshRelayDial.openSockets() != 0 && time.Now().Before(deadline) {
		time.Sleep(20 * time.Millisecond)
	}
	if got := n.freshRelayDial.openSockets(); got != 0 {
		t.Fatalf("open dedicated dial sockets = %d, want 0 (handoff dials ride the listener generation)", got)
	}
	current := quicListenPort(t, h)
	live := 0
	for _, c := range h.Network().ConnsToPeer(relay) {
		if c.IsClosed() {
			continue
		}
		live++
		if p := udpPortOf(c.LocalMultiaddr()); p != current {
			t.Fatalf("live relay connection local port = %d, want epoch 3's listener %d", p, current)
		}
	}
	if live == 0 {
		t.Fatal("no live relay connection after epoch 3")
	}
}

// Existing recovery owner still running: the handoff cancels it, waits for the
// owner to really finish, and only then mutates. The old owner's success is not
// the new epoch's proof.
func TestNetworkHandoff_WaitsForRunningRecoveryOwner_NoOverlap(t *testing.T) {
	if testing.Short() {
		t.Skip("real relay + proxy fixture; skipped in -short")
	}
	_, proxy, relayAddr := startHandoffRelayFixture(t)
	relay := relayPeerOf(t, relayAddr)
	n, collector := startHandoffNode(t, relayAddr)
	waitForEpoch1Reservation(t, n, relay)
	oldConns := n.Host().Network().ConnsToPeer(relay)
	proxy.BlackholeCurrentClients()

	mgr := n.relaySessionMgr
	recovery, isNew := mgr.BeginRecovery()
	if !isNew {
		t.Fatal("test could not take recovery ownership")
	}

	if adm := n.NetworkPathChanged(NetworkPathRequest{OwnerGeneration: 3, Epoch: 2, Usable: true}); !adm.Accepted {
		t.Fatalf("admission = %+v", adm)
	}
	deadline := time.Now().Add(2 * time.Second)
	for recovery.Context().Err() == nil && time.Now().Before(deadline) {
		time.Sleep(10 * time.Millisecond)
	}
	if recovery.Context().Err() == nil {
		t.Fatal("handoff did not cancel the running recovery owner")
	}
	time.Sleep(300 * time.Millisecond)
	for _, c := range oldConns {
		if c.IsClosed() {
			t.Fatal("handoff mutated relay connections while another owner still held recovery")
		}
	}
	if got := n.NetworkPathStatus()["readyEpoch"].(uint64); got != 0 {
		t.Fatalf("readyEpoch = %d before the old owner released, want 0", got)
	}
	if len(handoffEvents(collector, "network:path_changing")) != 1 {
		t.Fatal("path_changing should be announced once while waiting for ownership")
	}

	mgr.CompleteRecovery(recovery, &RecoveryResult{RecoveryMode: "in_place", Success: true, ReusedHost: true}, nil)
	name, _ := waitHandoffTerminal(t, collector, 2, NetworkHandoffBudget+2*time.Second)
	if name != "network:relay_ready" {
		t.Fatalf("terminal after owner release = %s, want relay_ready", name)
	}
	for _, c := range oldConns {
		if !c.IsClosed() {
			t.Fatal("old relay connection not retired after ownership passed")
		}
	}
}

// Reserve failure is a failure even though the node was reserved on epoch 1,
// Connect returned nil and a circuit address was advertised moments ago.
func TestNetworkHandoff_ReserveFailureIsNotReady(t *testing.T) {
	if testing.Short() {
		t.Skip("real relay + proxy fixture; skipped in -short")
	}
	_, proxy, relayAddr := startHandoffRelayFixture(t)
	relay := relayPeerOf(t, relayAddr)
	n, collector := startHandoffNode(t, relayAddr)
	waitForEpoch1Reservation(t, n, relay)
	proxy.BlackholeCurrentClients()
	n.reserveRelaySlotHook = func(ctx context.Context, h host.Host, info peer.AddrInfo) (*relayclient.Reservation, error) {
		return nil, fmt.Errorf("relay refused the reservation")
	}

	if adm := n.NetworkPathChanged(NetworkPathRequest{OwnerGeneration: 2, Epoch: 2, Usable: true}); !adm.Accepted {
		t.Fatalf("admission = %+v", adm)
	}
	name, data := waitHandoffTerminal(t, collector, 2, NetworkHandoffBudget+2*time.Second)
	if name != "network:relay_failed" || data["stage"] != handoffStageReserve || data["errorCode"] != handoffReasonReserveFailed {
		t.Fatalf("terminal = %s %v, want relay_failed at reserve", name, data)
	}
	if got := n.NetworkPathStatus()["readyEpoch"].(uint64); got != 0 {
		t.Fatalf("readyEpoch = %d after a failed reservation, want 0", got)
	}
	if n.relaySessionMgr.HasActiveManualReservation(relay) {
		t.Fatal("a failed epoch-2 reservation left an active manual hold")
	}
}

// Startup / stopped node / loss-only: observations are recorded, nothing starts.
func TestNetworkPathChanged_StoppedNodeAndUnusablePathStartNoWork(t *testing.T) {
	collector := &testEventCollector{}
	n := New(collector)
	if adm := n.NetworkPathChanged(NetworkPathRequest{OwnerGeneration: 1, Epoch: 1, Usable: true}); adm.Accepted || adm.Reason != handoffReasonNotStarted {
		t.Fatalf("stopped node admission = %+v, want not_started", adm)
	}
	if adm := n.NetworkPathChanged(NetworkPathRequest{OwnerGeneration: 1, Epoch: 2, Usable: false}); adm.Accepted || adm.Reason != handoffReasonNotUsable {
		t.Fatalf("loss-only admission = %+v, want not_usable", adm)
	}
	if adm := n.NetworkPathChanged(NetworkPathRequest{OwnerGeneration: 1, Epoch: 0, Usable: true}); adm.Accepted || adm.Reason != "invalid_epoch" {
		t.Fatalf("epoch 0 admission = %+v, want invalid_epoch", adm)
	}
	time.Sleep(100 * time.Millisecond)
	if got := len(collector.snapshot()); got != 0 {
		t.Fatalf("stopped node emitted %d events, want 0", got)
	}
	if n.Host() != nil {
		t.Fatal("a network observation started a stopped node")
	}

	n.hermeticLocalNetworkForTests = true
	if _, err := n.Start(NodeConfig{PrivateKeyHex: generateTestKey(t), RelayAddresses: []string{}}); err != nil {
		t.Fatalf("Start: %v", err)
	}
	t.Cleanup(func() { _ = n.Stop() })
	if adm := n.NetworkPathChanged(NetworkPathRequest{OwnerGeneration: 2, Epoch: 3, Usable: true}); !adm.Accepted {
		t.Fatalf("admission on a started node without relays = %+v, want accepted", adm)
	}
	name, data := waitHandoffTerminal(t, collector, 3, 3*time.Second)
	if name != "network:relay_failed" || data["errorCode"] != handoffReasonNoRelays {
		t.Fatalf("terminal = %s %v, want relay_failed/no_relays", name, data)
	}
	if adm := n.NetworkPathChanged(NetworkPathRequest{OwnerGeneration: 2, Epoch: 3, Usable: true}); adm.Accepted || adm.Reason != handoffReasonDuplicateEpoch {
		t.Fatalf("duplicate admission = %+v, want duplicate_epoch", adm)
	}
}

// A live call-media lease keeps every recovery lane off the Stop/Start
// fallback; a stale release cannot clear a successor's lease.
func TestCallMediaProtection_BlocksFullRestartFallback(t *testing.T) {
	n := NewNode()
	n.hermeticLocalNetworkForTests = true
	n.warmRelayConnectionHook = func(peer.AddrInfo) error { return nil }
	n.waitForCircuitAddressHook = func(time.Duration) bool { return true }
	n.refreshRelaySessionHook = func() *RecoveryResult {
		return &RecoveryResult{RecoveryMode: "in_place", Success: false, ErrorCode: "REFRESH_FAILED", Reason: "forced"}
	}
	if _, err := n.Start(NodeConfig{
		PrivateKeyHex:  generateTestKey(t),
		RelayAddresses: []string{generateFakeRelayAddr(t, 19047)},
	}); err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { _ = n.Stop() })
	h0 := n.Host()

	grant := n.AcquireCallMediaProtection(5)
	if !grant.Held || grant.Generation != 5 || grant.Incarnation == 0 || grant.Reason != "" {
		t.Fatalf("acquire = %+v, want held generation 5 with an incarnation", grant)
	}
	result, err := n.ReconnectRelays()
	if err != nil {
		t.Fatalf("ReconnectRelays: %v", err)
	}
	if result.Success || result.ErrorCode != "CALL_MEDIA_PROTECTED" || result.RecoveryMode != "in_place" {
		t.Fatalf("protected reconnect result = %+v, want in_place failure CALL_MEDIA_PROTECTED", result)
	}
	if n.Host() != h0 {
		t.Fatal("full restart happened behind a live call-media lease")
	}
	if older := n.AcquireCallMediaProtection(3); older.Held || older.Reason != CallMediaProtectionSuperseded {
		t.Fatalf("older acquire = %+v, want refused superseded", older)
	}
	if stale := n.ReleaseCallMediaProtection(4, grant.Incarnation); stale.Released || !n.relaySessionMgr.CallMediaProtected() {
		t.Fatalf("stale-generation release = %+v, want no-op with the lease kept", stale)
	}
	if wrong := n.ReleaseCallMediaProtection(5, grant.Incarnation+1); wrong.Released || !n.relaySessionMgr.CallMediaProtected() {
		t.Fatalf("wrong-incarnation release = %+v, want no-op with the lease kept", wrong)
	}
	if ok := n.ReleaseCallMediaProtection(5, grant.Incarnation); !ok.Released || n.relaySessionMgr.CallMediaProtected() {
		t.Fatalf("matching release = %+v, want the lease cleared", ok)
	}
	result, err = n.ReconnectRelays()
	if err != nil {
		t.Fatalf("ReconnectRelays after release: %v", err)
	}
	if result.RecoveryMode != "watchdog_restart" || n.Host() == h0 {
		t.Fatalf("after release the fallback should restart: mode=%s sameHost=%v", result.RecoveryMode, n.Host() == h0)
	}
}

// A recovery cancelled by a newer network path must not take the Stop/Start
// fallback for a path that no longer exists.
func TestSupersededRecoveryCannotStopStart(t *testing.T) {
	n := NewNode()
	n.hermeticLocalNetworkForTests = true
	n.warmRelayConnectionHook = func(peer.AddrInfo) error { return nil }
	n.waitForCircuitAddressHook = func(time.Duration) bool { return true }
	n.refreshRelaySessionHook = func() *RecoveryResult {
		n.relaySessionMgr.CancelRecovery(errHandoffSuperseded)
		return &RecoveryResult{RecoveryMode: "in_place", Success: false, ErrorCode: "REFRESH_FAILED", Reason: "forced"}
	}
	if _, err := n.Start(NodeConfig{
		PrivateKeyHex:  generateTestKey(t),
		RelayAddresses: []string{generateFakeRelayAddr(t, 19048)},
	}); err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { _ = n.Stop() })
	h0 := n.Host()
	result, err := n.ReconnectRelays()
	if err != nil {
		t.Fatalf("ReconnectRelays: %v", err)
	}
	if result.Success || result.ErrorCode != "RECOVERY_SUPERSEDED" {
		t.Fatalf("superseded reconnect result = %+v, want RECOVERY_SUPERSEDED", result)
	}
	if n.Host() != h0 {
		t.Fatal("superseded recovery restarted the host")
	}
}
