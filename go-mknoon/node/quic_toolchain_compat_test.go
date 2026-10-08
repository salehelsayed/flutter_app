package node

// Plan 406 — Go toolchain upgrade guard. quic-go before v0.57.1 panics with
// "crypto/tls bug: where's my session ticket?" on the ACCEPTING side of a QUIC
// handshake when built with Go 1.26 or newer, which SIGABRTs the receiver of
// any direct QUIC dial (the QR contact-add path). This test makes two
// production-configured nodes connect over QUIC twice (the second dial may
// resume the first session) and checks the accepting node is still serving.
// Under an affected toolchain the test binary aborts instead of failing.

import (
	"context"
	"strings"
	"testing"
	"time"

	"github.com/libp2p/go-libp2p/core/network"
	"github.com/libp2p/go-libp2p/core/peer"
	ma "github.com/multiformats/go-multiaddr"
)

func loopbackQUICAddr(t *testing.T, n *Node) ma.Multiaddr {
	t.Helper()
	for _, a := range n.Host().Network().ListenAddresses() {
		s := a.String()
		if !strings.Contains(s, "/quic-v1") || !strings.HasPrefix(s, "/ip4/") {
			continue
		}
		loopback, err := ma.NewMultiaddr(strings.Replace(s, "/ip4/0.0.0.0/", "/ip4/127.0.0.1/", 1))
		if err != nil {
			t.Fatalf("loopback addr from %s: %v", s, err)
		}
		return loopback
	}
	t.Fatalf("no ip4 quic-v1 listen addr among %v", n.Host().Network().ListenAddresses())
	return nil
}

func TestQUICDirectDial_AcceptingNodeSurvivesRepeatHandshakes(t *testing.T) {
	acceptor := startLocalNodeForMultiRelayTestWithCollector(t, &testEventCollector{})
	dialer := startLocalNodeForMultiRelayTestWithCollector(t, &testEventCollector{})

	target := peer.AddrInfo{
		ID:    acceptor.Host().ID(),
		Addrs: []ma.Multiaddr{loopbackQUICAddr(t, acceptor)},
	}

	for attempt := 1; attempt <= 2; attempt++ {
		ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
		err := dialer.Host().Connect(ctx, target)
		cancel()
		if err != nil {
			t.Fatalf("attempt %d: QUIC connect: %v", attempt, err)
		}
		conns := dialer.Host().Network().ConnsToPeer(target.ID)
		quic := false
		for _, c := range conns {
			if strings.Contains(c.RemoteMultiaddr().String(), "/quic-v1") {
				quic = true
			}
		}
		if !quic {
			t.Fatalf("attempt %d: no QUIC connection to acceptor, conns=%v", attempt, conns)
		}
		if err := dialer.Host().Network().ClosePeer(target.ID); err != nil {
			t.Fatalf("attempt %d: close: %v", attempt, err)
		}
		deadline := time.Now().Add(5 * time.Second)
		for dialer.Host().Network().Connectedness(target.ID) == network.Connected {
			if time.Now().After(deadline) {
				t.Fatalf("attempt %d: connection did not close", attempt)
			}
			time.Sleep(20 * time.Millisecond)
		}
		dialer.Host().Peerstore().AddAddrs(target.ID, target.Addrs, time.Minute)
	}

	acceptor.mu.Lock()
	started := acceptor.isStarted
	acceptor.mu.Unlock()
	if !started {
		t.Fatal("accepting node stopped after QUIC handshakes")
	}
	if len(acceptor.Host().Network().ListenAddresses()) == 0 {
		t.Fatal("accepting node lost its listen addresses after QUIC handshakes")
	}
}
