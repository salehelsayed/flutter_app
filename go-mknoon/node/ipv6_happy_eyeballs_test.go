package node

import (
	"context"
	"errors"
	"fmt"
	"net"
	"reflect"
	"sync"
	"testing"
	"time"

	libp2p "github.com/libp2p/go-libp2p"
	"github.com/libp2p/go-libp2p/core/network"
	"github.com/libp2p/go-libp2p/core/peer"
	"github.com/libp2p/go-libp2p/core/peerstore"
	"github.com/libp2p/go-libp2p/p2p/net/swarm"
	ma "github.com/multiformats/go-multiaddr"
)

func TestLimitRelayAddresses_PreservesFamiliesAndTransportsForFirstPeer(t *testing.T) {
	first, second := generatePeerIDStr(t), generatePeerIDStr(t)
	v6 := fmt.Sprintf("/ip6/2001:db8::1/udp/4002/quic-v1/p2p/%s", first)
	v4 := fmt.Sprintf("/ip4/192.0.2.1/udp/4002/quic-v1/p2p/%s", first)
	wss := fmt.Sprintf("/dns/relay.example/tcp/4001/wss/p2p/%s", first)
	other := fmt.Sprintf("/ip4/192.0.2.2/tcp/4001/p2p/%s", second)
	input := []string{"invalid", v6, other, v4, wss}
	for _, enabled := range []bool{false, true} {
		flags := DefaultFeatureFlags()
		flags.EnableMultiRelayRouting = enabled
		got := limitRelayAddresses(input, flags)
		want := []string{v6, v4, wss}
		if enabled {
			want = input
		}
		if !reflect.DeepEqual(got, want) {
			t.Fatalf("multi-relay=%v: got %v, want %v", enabled, got, want)
		}
		got[0] = "changed"
		if input[0] != "invalid" {
			t.Fatal("selection aliases caller's address slice")
		}
	}
}

func TestLimitRelayAddresses_InvalidExplicitConfigDoesNotBecomeDefault(t *testing.T) {
	flags := DefaultFeatureFlags()
	flags.EnableMultiRelayRouting = false
	input := []string{"invalid", "/ip6/2001:db8::1/tcp/4001"}
	got := limitRelayAddresses(input, flags)
	if !reflect.DeepEqual(got, input) {
		t.Fatalf("invalid explicit configuration must remain nonempty: %v", got)
	}
	if rs := NewRelaySelector(got); rs.Len() != 0 {
		t.Fatalf("invalid explicit configuration selected %d relay peers", rs.Len())
	}
}

func TestWarmRelayConnectionWithTimeout_UsesOneBudgetForAllAddresses(t *testing.T) {
	n := NewNode()
	n.ctx, n.cancel = context.WithCancel(context.Background())
	defer n.cancel()
	pid, err := peer.Decode(generatePeerIDStr(t))
	if err != nil {
		t.Fatal(err)
	}
	info := peer.AddrInfo{ID: pid, Addrs: []ma.Multiaddr{
		ma.StringCast("/ip6/2001:db8::1/tcp/4001"),
		ma.StringCast("/ip4/192.0.2.1/tcp/4001"),
	}}
	const budget = 25 * time.Millisecond
	start := time.Now()
	calls := 0
	n.connectRelayHook = func(ctx context.Context, got peer.AddrInfo) error {
		calls++
		deadline, ok := ctx.Deadline()
		if !ok || deadline.Sub(start) > budget+10*time.Millisecond {
			t.Fatalf("missing or renewed overall dial deadline: %v", deadline)
		}
		<-ctx.Done()
		return ctx.Err()
	}
	err = n.warmRelayConnectionWithTimeout(info, budget)
	if !errors.Is(err, context.DeadlineExceeded) || calls != 1 {
		t.Fatalf("want one expired overall budget: calls=%d error=%v", calls, err)
	}
}

// This is an executable contract with the pinned library, including WSS's
// resolved /tls/sni/ws form. It catches dependency changes that silently remove
// family fallback; production continues to use libp2p's default ranker.
func TestPinnedLibp2pHappyEyeballs_RanksIPv6ThenIPv4(t *testing.T) {
	for _, transport := range []string{
		"/udp/4002/quic-v1", "/tcp/4001", "/tcp/4001/wss", "/tcp/4001/tls/sni/relay.example/ws",
	} {
		t.Run(transport, func(t *testing.T) {
			v4 := ma.StringCast("/ip4/192.0.2.1" + transport)
			v6 := ma.StringCast("/ip6/2001:db8::1" + transport)
			ranked := swarm.DefaultDialRanker([]ma.Multiaddr{v4, v6})
			if len(ranked) != 2 || !ranked[0].Addr.Equal(v6) || ranked[0].Delay != 0 ||
				!ranked[1].Addr.Equal(v4) || ranked[1].Delay != 250*time.Millisecond {
				t.Fatalf("unexpected dual-family schedule: %v", ranked)
			}
		})
	}
}

func TestRelaySelector_CompleteCandidatesInEveryOperation(t *testing.T) {
	pid := generatePeerIDStr(t)
	rs := NewRelaySelector([]string{
		fmt.Sprintf("/ip6/2001:db8::1/tcp/4001/p2p/%s", pid),
		fmt.Sprintf("/ip4/192.0.2.1/tcp/4001/p2p/%s", pid),
	})
	for _, operation := range []string{"foreach", "fanout", "result"} {
		t.Run(operation, func(t *testing.T) {
			calls := 0
			operationErr := errors.New("peer operation failed")
			check := func(relay RelayInfo) error {
				calls++
				if relay.ID.String() != pid || len(relay.Addrs) != 2 {
					return fmt.Errorf("incomplete same-peer candidate: %v", relay)
				}
				return operationErr
			}
			var err error
			switch operation {
			case "foreach":
				err = rs.ForEach(check)
			case "fanout":
				err = rs.FanOut(check)
			case "result":
				_, err = ForEachWithResult(rs, func(relay RelayInfo) (string, error) { return "", check(relay) })
			}
			if !errors.Is(err, operationErr) || calls != 1 {
				t.Fatalf("operation must fail once per peer: calls=%d err=%v", calls, err)
			}
		})
	}
}

func TestWarmRelayConnection_IPv6HandshakeStallFallsBackToIPv4(t *testing.T) {
	// A reachable IPv6 TCP socket that never completes the libp2p handshake
	// proves delayed fallback, rather than a quick connection-refused shortcut.
	blackhole, err := net.Listen("tcp6", "[::1]:0")
	if err != nil {
		t.Skipf("IPv6 loopback unavailable: %v", err)
	}
	var mu sync.Mutex
	var stalled []net.Conn
	accepted := make(chan struct{}, 1)
	done := make(chan struct{})
	go func() {
		defer close(done)
		for {
			conn, err := blackhole.Accept()
			if err != nil {
				return
			}
			mu.Lock()
			stalled = append(stalled, conn)
			mu.Unlock()
			select {
			case accepted <- struct{}{}:
			default:
			}
		}
	}()
	t.Cleanup(func() {
		blackhole.Close()
		<-done
		mu.Lock()
		defer mu.Unlock()
		for _, conn := range stalled {
			conn.Close()
		}
	})
	target, err := libp2p.New(libp2p.ListenAddrStrings("/ip4/127.0.0.1/tcp/0"), libp2p.DisableRelay())
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { target.Close() })
	n := startLocalNodeForMultiRelayTest(t)
	info := peer.AddrInfo{ID: target.ID(), Addrs: []ma.Multiaddr{
		ma.StringCast(fmt.Sprintf("/ip6/::1/tcp/%d", blackhole.Addr().(*net.TCPAddr).Port)),
		target.Addrs()[0],
	}}
	start := time.Now()
	if err := n.warmRelayConnectionWithTimeout(info, 3*time.Second); err != nil {
		t.Fatalf("IPv4 fallback failed: %v", err)
	}
	if elapsed := time.Since(start); elapsed >= 2*time.Second {
		t.Fatalf("fallback waited for the stalled address budget: %v", elapsed)
	}
	select {
	case <-accepted:
	default:
		t.Fatal("IPv6 candidate was not attempted")
	}
	conns := n.Host().Network().ConnsToPeer(target.ID())
	if len(conns) == 0 || extractIP(conns[0].RemoteMultiaddr()).To4() == nil {
		t.Fatalf("expected established IPv4 fallback connection: %v", conns)
	}
}

func TestWarmRelayConnection_ConnectsToIPv6Loopback(t *testing.T) {
	target, err := libp2p.New(libp2p.ListenAddrStrings("/ip6/::1/tcp/0"), libp2p.DisableRelay())
	if err != nil {
		t.Skipf("IPv6 loopback unavailable: %v", err)
	}
	t.Cleanup(func() { target.Close() })
	n := startLocalNodeForMultiRelayTest(t)
	if err := n.warmRelayConnectionWithTimeout(peer.AddrInfo{ID: target.ID(), Addrs: target.Addrs()}, time.Second); err != nil {
		t.Fatalf("IPv6 connection failed: %v", err)
	}
	conns := n.Host().Network().ConnsToPeer(target.ID())
	if len(conns) == 0 || extractIP(conns[0].RemoteMultiaddr()).To4() != nil {
		t.Fatalf("expected established IPv6 connection: %v", conns)
	}
}

func TestMediaProtocolRetry_DoesNotDialDisconnectedPeer(t *testing.T) {
	target, err := libp2p.New(libp2p.ListenAddrStrings("/ip4/127.0.0.1/tcp/0"), libp2p.DisableRelay())
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { target.Close() })
	target.SetStreamHandler(MediaProtocol, func(stream network.Stream) { stream.Close() })
	n := startLocalNodeForMultiRelayTest(t)
	// Make the target dialable from the peerstore: without WithNoDial, NewStream
	// would establish a new connection and silently renew the dial budget.
	n.Host().Peerstore().AddAddrs(target.ID(), target.Addrs(), peerstore.PermanentAddrTTL)
	stream, err := n.openMediaStreamForRelayWithDial("ack_custody", RelayInfo{ID: target.ID(), Addrs: target.Addrs()}, false)
	if err == nil {
		stream.cancel()
		stream.stream.Close()
		t.Fatal("protocol retry dialed a disconnected peer")
	}
	if len(n.Host().Network().ConnsToPeer(target.ID())) != 0 {
		t.Fatal("protocol retry opened a connection")
	}
}

func TestMediaDownloadProtocolRetry_KeepsCompletePeerWithoutNewDialBudget(t *testing.T) {
	pid := generatePeerIDStr(t)
	rs := NewRelaySelector([]string{
		fmt.Sprintf("/ip6/2001:db8::1/tcp/4001/p2p/%s", pid),
		fmt.Sprintf("/ip4/192.0.2.1/tcp/4001/p2p/%s", pid),
		generateFakeRelayAddr(t, 19031),
	})
	calls := 0
	n := NewNode()
	_, err := n.mediaDownloadAcrossRelays(rs, func(relay RelayInfo, allowDial bool) (MediaDownloadResult, bool, error) {
		calls++
		if relay.ID.String() != pid || len(relay.Addrs) != 2 || allowDial != (calls == 1) {
			t.Fatalf("incorrect retry scope: call=%d peer=%v allowDial=%v", calls, relay, allowDial)
		}
		if calls == 1 {
			return MediaDownloadResult{}, true, errors.New("pre-body request failed")
		}
		return MediaDownloadResult{}, false, nil
	})
	if err != nil || calls != 2 {
		t.Fatalf("same-peer protocol retry failed: calls=%d error=%v", calls, err)
	}
}
