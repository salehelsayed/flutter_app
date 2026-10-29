package node

import (
	"fmt"
	"net"
	"strings"
	"testing"
	"time"

	"github.com/libp2p/go-libp2p/core/event"
	"github.com/libp2p/go-libp2p/core/network"
	"github.com/libp2p/go-libp2p/p2p/host/observedaddrs"
	ma "github.com/multiformats/go-multiaddr"
)

// Task 15 finding 8. After a handoff the relay is the node's only connection
// on the new network, so it is the only peer that can teach libp2p the new
// NAT mapping through identify's observed address. libp2p records that
// observation only when the connection's local thin waist (ip/udp) is one of
// the host's listen addresses (go-libp2p v0.50.0
// p2p/host/observedaddrs/manager.go:391-404). A relay connection on a
// dedicated dial-only socket therefore teaches it nothing, and hole punching
// keeps the old mapping. This test runs the real relay behind the proxy on a
// non-loopback interface, because libp2p drops loopback observations, and
// pins, for the post-handoff relay connection, that the relay really observed
// the proxy's socket for the new client socket, that libp2p recorded that
// observation (it surfaces in the host's direct address set once the observer
// threshold is met; the threshold is lowered to this one relay, production
// reaches it through its relays and peers over time), and that the
// connection's local address is a listen address, the rule that decides the
// recording. It does not prove a hole punch: the observed address here is a
// private IP, which libp2p's hole-punch candidate set excludes, and no second
// NATed peer exists.
func TestNetworkHandoff_RelayConnectionLocalAddrIsAListenAddr_ObservedMappingAcceptable(t *testing.T) {
	if testing.Short() {
		t.Skip("real relay + proxy fixture; skipped in -short")
	}
	ip := nonLoopbackIPv4(t)
	priorThresh := observedaddrs.ActivationThresh
	observedaddrs.ActivationThresh = 1
	t.Cleanup(func() { observedaddrs.ActivationThresh = priorThresh })
	_, proxy, relayAddr := startHandoffRelayFixtureOn(t, ip)
	relay := relayPeerOf(t, relayAddr)
	n, collector := startHandoffNode(t, relayAddr)
	h := n.Host()
	sub, err := h.EventBus().Subscribe(new(event.EvtPeerIdentificationCompleted))
	if err != nil {
		t.Fatalf("subscribe: %v", err)
	}
	defer sub.Close()
	waitForEpoch1Reservation(t, n, relay)

	listenTW := func() map[string]bool {
		out := map[string]bool{}
		for _, a := range h.Network().ListenAddresses() {
			out[udpThinWaist(a)] = true
		}
		return out
	}
	// Control: the epoch-1 relay connection left from the listener socket.
	for _, c := range h.Network().ConnsToPeer(relay) {
		if tw := udpThinWaist(c.LocalMultiaddr()); !listenTW()[tw] {
			t.Fatalf("precondition: epoch-1 relay connection local %s is not a listen address %v", tw, h.Network().ListenAddresses())
		}
	}

	proxy.BlackholeCurrentClients()
	if adm := n.NetworkPathChanged(NetworkPathRequest{OwnerGeneration: 1, Epoch: 2, Usable: true}); !adm.Accepted {
		t.Fatalf("admission = %+v, want accepted", adm)
	}
	if name, data := waitHandoffTerminal(t, collector, 2, NetworkHandoffBudget+2*time.Second); name != "network:relay_ready" {
		t.Fatalf("epoch 2 terminal = %s %v, want relay_ready", name, data)
	}
	var fresh network.Conn
	for _, c := range h.Network().ConnsToPeer(relay) {
		if !c.IsClosed() {
			fresh = c
		}
	}
	if fresh == nil {
		t.Fatal("no open relay connection after the handoff")
	}

	// identify completed on the post-handoff relay connection and carried the
	// relay's observation of it.
	var observed ma.Multiaddr
	deadline := time.After(5 * time.Second)
	for observed == nil {
		select {
		case raw := <-sub.Out():
			e := raw.(event.EvtPeerIdentificationCompleted)
			if e.Peer == relay && e.Conn != nil && e.Conn.ID() == fresh.ID() {
				observed = e.ObservedAddr
				if observed == nil {
					t.Fatal("identify on the post-handoff relay connection carried no observed address")
				}
			}
		case <-deadline:
			t.Fatal("identify did not complete on the post-handoff relay connection within 5 s")
		}
	}
	clientPort := udpPortOf(fresh.LocalMultiaddr())
	back := proxy.BackAddrForClientPort(clientPort)
	if back == nil {
		t.Fatalf("relay never saw the post-handoff client socket %d; proxy clients=%v", clientPort, proxy.ClientSockets())
	}
	want := ma.StringCast(fmt.Sprintf("/ip4/%s/udp/%d/quic-v1", ip, back.Port))
	if !observed.Equal(want) {
		t.Fatalf("relay observed %s for the new socket, want the proxy's back socket %s (the simulated NAT mapping)", observed, want)
	}

	// libp2p recorded the observation: the mapping shows up in the host's
	// direct address set (basichost AllAddrs, before the node's address
	// factory), which is where hole punching reads candidates from.
	localTW := udpThinWaist(fresh.LocalMultiaddr())
	direct, ok := h.(interface{ AllAddrs() []ma.Multiaddr })
	if !ok {
		t.Fatalf("host %T does not expose AllAddrs", h)
	}
	recorded := false
	for end := time.Now().Add(8 * time.Second); time.Now().Before(end) && !recorded; time.Sleep(100 * time.Millisecond) {
		for _, a := range direct.AllAddrs() {
			if a.Equal(want) {
				recorded = true
			}
		}
	}
	if !recorded {
		t.Fatalf("libp2p never recorded the relay's observation %s of the post-handoff connection (local %s, listen addresses %v): direct addresses %v. The observed-address manager records only connections whose local ip/udp is a listen address, so the new NAT mapping never reaches the hole-punch candidates",
			observed, localTW, h.Network().ListenAddresses(), direct.AllAddrs())
	}
	// The rule that decided it.
	if !listenTW()[localTW] {
		t.Fatalf("post-handoff relay connection local %s is not a listen address %v", localTW, h.Network().ListenAddresses())
	}
	t.Logf("post-handoff relay connection local %s is a listen address; relay observed %s; libp2p surfaces it in AllAddrs", fresh.LocalMultiaddr(), observed)
}

// udpThinWaist renders the ip/udp part of a QUIC multiaddr, the form
// libp2p's observed-address manager compares against the listen addresses.
func udpThinWaist(a ma.Multiaddr) string {
	var b strings.Builder
	for _, c := range a {
		switch c.Protocol().Code {
		case ma.P_IP4, ma.P_IP6, ma.P_UDP:
			b.WriteString(c.String())
		}
	}
	return b.String()
}

// nonLoopbackIPv4 returns an IPv4 address of an interface that is up and not
// loopback, or skips the test when the host has none.
func nonLoopbackIPv4(t *testing.T) net.IP {
	t.Helper()
	ifaces, err := net.Interfaces()
	if err != nil {
		t.Skipf("interfaces: %v", err)
	}
	for _, ifc := range ifaces {
		if ifc.Flags&net.FlagUp == 0 || ifc.Flags&net.FlagLoopback != 0 {
			continue
		}
		addrs, err := ifc.Addrs()
		if err != nil {
			continue
		}
		for _, a := range addrs {
			if ipn, ok := a.(*net.IPNet); ok && ipn.IP.To4() != nil && !ipn.IP.IsLinkLocalUnicast() {
				return ipn.IP.To4()
			}
		}
	}
	t.Skip("no non-loopback, non-link-local IPv4 interface; libp2p ignores loopback observations")
	return nil
}
