//go:build integration

package integration_test

import (
	"fmt"
	"strings"
	"testing"
	"time"

	"github.com/libp2p/go-libp2p/core/peer"
	ma "github.com/multiformats/go-multiaddr"
)

func TestDualStackNodeWithIPv4Relay(t *testing.T) {
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
		if strings.HasPrefix(s, "/ip4/") {
			hasIPv4 = true
		}
		if strings.HasPrefix(s, "/ip6/") {
			hasIPv6 = true
		}
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

func TestDialPeerViaRelayMultiAddrFailover(t *testing.T) {
	// Start a real local relay (IPv4 only).
	shared := newLocalRelaySharedState()
	relay := newLocalRelayServer(t, shared)
	relay.start()
	defer relay.stop()

	realAddr := relay.addr()

	// Extract relay peer ID from real address.
	maddr, err := ma.NewMultiaddr(realAddr)
	if err != nil {
		t.Fatalf("parse relay addr: %v", err)
	}
	relayInfo, err := peer.AddrInfoFromP2pAddr(maddr)
	if err != nil {
		t.Fatalf("AddrInfoFromP2pAddr: %v", err)
	}

	// Build a bogus unreachable address with the SAME relay peer ID.
	// When the relay selector groups these by peer ID, it creates one relay
	// entry with two transport addrs: [bogus, real]. DialPeerViaRelay must
	// try both (the fix) rather than only relay.Addrs[0] (the old bug).
	bogusAddr := fmt.Sprintf("/ip4/192.0.2.1/tcp/1/p2p/%s", relayInfo.ID)

	// Node A: configure with the real relay so it can register on rendezvous.
	nodeA, peerIdA := startNodeWithRelays(t, []string{realAddr}, nil, nil)
	waitForRendezvousRegister(t, nodeA, nodeA.Namespace(), 10*time.Second)

	// Node B (the dialer): configure with bogus-first, real-second — SAME peer ID.
	// This is the node whose DialPeerViaRelay must exercise multi-addr failover.
	nodeB, _ := startNodeWithRelays(t, []string{bogusAddr, realAddr}, nil, nil)

	// B dials A via relay — must succeed despite Addrs[0] being bogus.
	err = nodeB.DialPeerViaRelay(peerIdA)
	if err != nil {
		t.Fatalf("DialPeerViaRelay should succeed via second address: %v", err)
	}
}
