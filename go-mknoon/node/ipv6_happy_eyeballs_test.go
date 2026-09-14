package node

import (
	"context"
	"crypto/tls"
	"crypto/x509"
	"errors"
	"fmt"
	"net"
	"net/http/httptest"
	"reflect"
	"strings"
	"sync"
	"sync/atomic"
	"testing"
	"time"

	libp2p "github.com/libp2p/go-libp2p"
	"github.com/libp2p/go-libp2p/core/host"
	"github.com/libp2p/go-libp2p/core/network"
	"github.com/libp2p/go-libp2p/core/peer"
	"github.com/libp2p/go-libp2p/core/peerstore"
	"github.com/libp2p/go-libp2p/p2p/net/swarm"
	quic "github.com/libp2p/go-libp2p/p2p/transport/quic"
	"github.com/libp2p/go-libp2p/p2p/transport/tcp"
	"github.com/libp2p/go-libp2p/p2p/transport/websocket"
	ma "github.com/multiformats/go-multiaddr"
)

// A socket-scoped fault, never a host firewall rule: establish libp2p through
// IPv6 first, then discard bytes without FIN/RST in either direction. New IPv6
// handshakes also stall; the original IPv4 candidate remains usable.
type establishedPathProxy struct {
	address ma.Multiaddr
	drop    atomic.Bool
}

func newEstablishedPathProxy(t *testing.T, target ma.Multiaddr) *establishedPathProxy {
	t.Helper()
	listener, err := net.Listen("tcp6", "[::1]:0")
	if err != nil {
		t.Skipf("IPv6 loopback unavailable: %v", err)
	}
	port, err := target.ValueForProtocol(ma.P_TCP)
	if err != nil {
		t.Fatal(err)
	}
	proxy := &establishedPathProxy{address: ma.StringCast(fmt.Sprintf("/ip6/::1/tcp/%d", listener.Addr().(*net.TCPAddr).Port))}
	var mu sync.Mutex
	var sockets []net.Conn
	var workers sync.WaitGroup
	acceptDone := make(chan struct{})
	go func() {
		defer close(acceptDone)
		for {
			incoming, err := listener.Accept()
			if err != nil {
				return
			}
			outgoing, err := net.DialTimeout("tcp4", "127.0.0.1:"+port, time.Second)
			if err != nil {
				incoming.Close()
				continue
			}
			mu.Lock()
			sockets = append(sockets, incoming, outgoing)
			mu.Unlock()
			copyUntilClosed := func(dst, src net.Conn) {
				defer workers.Done()
				defer src.Close()
				defer dst.Close()
				buffer := make([]byte, 32*1024)
				for {
					n, err := src.Read(buffer)
					if err != nil {
						return
					}
					if !proxy.drop.Load() {
						if _, err := dst.Write(buffer[:n]); err != nil {
							return
						}
					}
				}
			}
			workers.Add(2)
			go copyUntilClosed(incoming, outgoing)
			go copyUntilClosed(outgoing, incoming)
		}
	}()
	t.Cleanup(func() {
		listener.Close()
		<-acceptDone
		for _, socket := range sockets {
			socket.Close()
		}
		workers.Wait()
	})
	return proxy
}

func TestSendMessage_EstablishedIPv6BlackholeRecoversWithoutRestart(t *testing.T) {
	for _, scenario := range []string{"normal", "quiet", "ack_lost", "uncached_quiet_protocol"} {
		t.Run(scenario, func(t *testing.T) {
			sender := startLocalNodeForMultiRelayTest(t)
			callback := &quietRecoveryCallback{received: make(chan map[string]interface{}, 8)}
			receiver := New(callback)
			callback.node = receiver
			receiver.hermeticLocalNetworkForTests = true
			if _, err := receiver.Start(NodeConfig{PrivateKeyHex: generateTestKey(t), RelayAddresses: []string{}, AutoRegister: false}); err != nil {
				t.Fatal(err)
			}
			t.Cleanup(func() { receiver.Stop() })
			var v4 ma.Multiaddr
			for _, addr := range receiver.Host().Addrs() {
				if ip := extractIP(addr); ip != nil && ip.IsLoopback() && ip.To4() != nil && !strings.Contains(addr.String(), "/ws") {
					if _, err := addr.ValueForProtocol(ma.P_TCP); err == nil {
						v4 = addr
						break
					}
				}
			}
			if v4 == nil {
				t.Fatal("missing IPv4 TCP listener")
			}
			proxy := newEstablishedPathProxy(t, v4)
			pid := receiver.Host().ID()
			if err := sender.DialPeerWithTimeout(pid.String(), []string{proxy.address.String()}, 3000); err != nil {
				t.Fatal(err)
			}
			conns := sender.Host().Network().ConnsToPeer(pid)
			if len(conns) != 1 || !conns[0].RemoteMultiaddr().Equal(proxy.address) {
				t.Fatalf("not established over IPv6: %v", conns)
			}
			original := conns[0]
			sender.Host().Peerstore().ClearAddrs(pid)
			sender.Host().Peerstore().AddAddrs(pid, []ma.Multiaddr{proxy.address, v4}, peerstore.PermanentAddrTTL)
			quiet := scenario != "normal"
			const wire = `{"type":"chat_message","version":"2","id":"established-original","senderPeerId":"synthetic","encrypted":{"kem":"k","ciphertext":"immutable","nonce":"n"}}`
			warm, err := sender.SendMessageWithNotificationPolicy(pid.String(), wire, 4000, quiet)
			if err != nil || !warm.Acked {
				t.Fatalf("IPv6 warm delivery: %+v %v", warm, err)
			}
			<-callback.received
			t.Logf("warm selected=%s", original.RemoteMultiaddr())
			if scenario == "ack_lost" {
				callback.beforeConfirm = func() { proxy.drop.Store(true) }
			} else {
				proxy.drop.Store(true)
			}
			if scenario == "uncached_quiet_protocol" {
				if err := sender.Host().Peerstore().RemoveProtocols(pid, QuietRecoveryChatProtocol); err != nil {
					t.Fatal(err)
				}
			}
			start := time.Now()
			failed, err := sender.SendMessageWithNotificationPolicy(pid.String(), wire, 4000, quiet)
			if failed.Acked {
				t.Fatalf("blackhole invented ACK: %+v", failed)
			}
			if time.Since(start) > 4500*time.Millisecond {
				t.Fatal("command renewed its deadline")
			}
			if scenario == "ack_lost" {
				event := <-callback.received
				if event["content"] != wire || event["from"] != sender.PeerId() || event["to"] != pid.String() || event["quietRecovery"] != true {
					t.Fatalf("pre-ACK durable delivery changed: %v", event)
				}
			}
			// The existing retry owner calls the same operation with the same
			// envelope; neither node is restarted and IPv6 stays blackholed.
			recovered, err := sender.SendMessageWithNotificationPolicy(pid.String(), wire, 4000, quiet)
			if err != nil || !recovered.Acked {
				t.Fatalf("established path did not recover: %+v %v", recovered, err)
			}
			event := <-callback.received
			if event["content"] != wire || event["from"] != sender.PeerId() || event["to"] != pid.String() || (event["quietRecovery"] == true) != quiet {
				t.Fatalf("fallback changed delivery: %v", event)
			}
			conns = sender.Host().Network().ConnsToPeer(pid)
			if !original.IsClosed() || len(conns) == 0 || extractIP(conns[0].RemoteMultiaddr()).To4() == nil {
				t.Fatalf("missing selected IPv4 recovery: %v", conns)
			}
			t.Logf("recovery selected=%s", conns[0].RemoteMultiaddr())
		})
	}
}

func TestInboxStore_EstablishedIPv6BlackholeRecoversWithoutRestart(t *testing.T) {
	for _, protected := range []bool{false, true} {
		t.Run(fmt.Sprint(protected), func(t *testing.T) {
			relay := startAckCustodyTestRelay(t, func(req inboxRequest) string {
				return `{"status":"OK","storeStatus":"stored","custodyContract":"ack_or_expiry_v1"}`
			})
			sender := startLocalNodeForMultiRelayTest(t)
			v4 := relay.host.Addrs()[0]
			proxy := newEstablishedPathProxy(t, v4)
			pid := relay.host.ID()
			sender.relayAddresses = []string{proxy.address.String() + "/p2p/" + pid.String(), v4.String() + "/p2p/" + pid.String()}
			if err := sender.DialPeerWithTimeout(pid.String(), []string{proxy.address.String()}, 3000); err != nil {
				t.Fatal(err)
			}
			original := sender.Host().Network().ConnsToPeer(pid)[0]
			const wire = `{"type":"chat_message","version":"2","id":"inbox-original","encrypted":{"ciphertext":"immutable"}}`
			store := func() (InboxStoreOutcome, error) {
				if protected {
					return sender.InboxStoreAckCustodyDetailedWithNotificationPolicy("recipient", wire, 500, "", CustodyKindDirectTextV108, 0, false, true)
				}
				return sender.InboxStoreDetailedWithNotificationPolicy("recipient", wire, 500, "", false, true)
			}
			if _, err := store(); err != nil {
				t.Fatal(err)
			}
			if !original.RemoteMultiaddr().Equal(proxy.address) {
				t.Fatalf("not IPv6: %s", original.RemoteMultiaddr())
			}
			proxy.drop.Store(true)
			if _, err := store(); err == nil {
				t.Fatal("blackhole falsely accepted custody")
			}
			if _, err := store(); err != nil {
				t.Fatalf("durable retry trapped on stale IPv6: %v", err)
			}
			conns := sender.Host().Network().ConnsToPeer(pid)
			if !original.IsClosed() || len(conns) == 0 || extractIP(conns[0].RemoteMultiaddr()).To4() == nil {
				t.Fatalf("missing IPv4 inbox recovery: %v", conns)
			}
			for _, request := range relay.snapshotActions() {
				if request.Message != wire || request.To != "recipient" || !request.QuietRecovery || !request.SuppressNotification {
					t.Fatalf("inbox retry changed bytes/recipient/policy: %+v", request)
				}
			}
			t.Logf("inbox warm=%s recovery=%s", original.RemoteMultiaddr(), conns[0].RemoteMultiaddr())
		})
	}
}

func TestSendMessageRecovery_PreservesHealthyConnection(t *testing.T) {
	sender := startLocalNodeForMultiRelayTest(t)
	receiver := startLocalNodeForMultiRelayTest(t)
	pid := receiver.Host().ID()
	if err := sender.Host().Connect(context.Background(), peer.AddrInfo{ID: pid, Addrs: receiver.Host().Addrs()}); err != nil {
		t.Fatal(err)
	}
	connections := sender.Host().Network().ConnsToPeer(pid)
	sender.openChatStreamHook = func(context.Context, host.Host, peer.ID) (network.Stream, error) {
		return nil, errors.New("failed to open stream: synthetic resource limit")
	}
	if _, err := sender.SendMessageWithTransport(pid.String(), "control", 1000); err == nil {
		t.Fatal("expected resource failure")
	}
	for _, connection := range connections {
		if connection.IsClosed() {
			t.Fatal("recovery closed a healthy connection without a transport timeout")
		}
	}
	sender.openChatStreamHook = nil
	if result, err := sender.SendMessageWithTransport(pid.String(), "control", 1000); err != nil || !result.Acked {
		t.Fatalf("healthy connection no longer usable: %+v %v", result, err)
	}
}

func TestDualStackUDPBlackholeFallsBackToTCPAndWSSMessaging(t *testing.T) {
	for _, transport := range []string{"tcp", "wss"} {
		t.Run(transport, func(t *testing.T) {
			udp, err := net.ListenPacket("udp4", "127.0.0.1:0")
			if err != nil {
				t.Fatal(err)
			}
			attempted := make(chan struct{}, 1)
			done := make(chan struct{})
			go func() {
				defer close(done)
				buffer := make([]byte, 2048)
				for {
					if _, _, err := udp.ReadFrom(buffer); err != nil {
						return
					}
					select {
					case attempted <- struct{}{}:
					default:
					}
				}
			}()
			t.Cleanup(func() { udp.Close(); <-done })
			address := "/ip4/127.0.0.1/tcp/0"
			var serverOptions, clientOptions []libp2p.Option
			if transport == "wss" {
				// Trust only this fixture's certificate. No system trust changes or
				// insecure TLS bypass; both peers still use the pinned native transport.
				certificateServer := httptest.NewTLSServer(nil)
				certificateServer.Close()
				roots := x509.NewCertPool()
				roots.AddCert(certificateServer.Certificate())
				serverOptions = []libp2p.Option{libp2p.Transport(websocket.New, websocket.WithTLSConfig(certificateServer.TLS))}
				clientOptions = []libp2p.Option{
					libp2p.Transport(tcp.NewTCPTransport),
					libp2p.Transport(quic.NewTransport),
					libp2p.Transport(websocket.New, websocket.WithTLSClientConfig(&tls.Config{RootCAs: roots, MinVersion: tls.VersionTLS12})),
				}
				address += "/wss"
			}
			target, err := libp2p.New(append(serverOptions, libp2p.ListenAddrStrings(address), libp2p.DisableRelay())...)
			if err != nil {
				t.Fatal(err)
			}
			t.Cleanup(func() { target.Close() })
			frames := make(chan string, 1)
			target.SetStreamHandler(ChatProtocol, func(s network.Stream) {
				defer s.Close()
				wire, err := readFrame(s)
				if err != nil {
					return
				}
				frames <- string(wire)
				_ = writeFrame(s, []byte(`{"ack":true}`))
			})
			sender := NewNode()
			sender.hermeticLocalNetworkForTests = true
			sender.newHost = func(_ NodeConfig, opts []libp2p.Option) (host.Host, error) {
				return libp2p.New(append(opts, clientOptions...)...)
			}
			if _, err := sender.Start(NodeConfig{PrivateKeyHex: generateTestKey(t), RelayAddresses: []string{}, AutoRegister: false}); err != nil {
				t.Fatal(err)
			}
			t.Cleanup(func() { sender.Stop() })
			addresses := []string{
				fmt.Sprintf("/ip4/127.0.0.1/udp/%d/quic-v1", udp.LocalAddr().(*net.UDPAddr).Port),
				target.Addrs()[0].String(),
			}
			if err := sender.DialPeerWithTimeout(target.ID().String(), addresses, 3000); err != nil {
				t.Fatal(err)
			}
			result, err := sender.SendMessageWithTransport(target.ID().String(), "immutable TCP fallback", 1000)
			if err != nil || !result.Acked || <-frames != "immutable TCP fallback" {
				t.Fatalf("TCP delivery failed: %+v %v", result, err)
			}
			select {
			case <-attempted:
			case <-time.After(time.Second):
				t.Fatal("UDP was never attempted")
			}
			connections := sender.Host().Network().ConnsToPeer(target.ID())
			if len(connections) == 0 || !strings.Contains(connections[0].RemoteMultiaddr().String(), "/tcp/") {
				t.Fatalf("not a selected TCP path: %v", connections)
			}
			selected := connections[0].RemoteMultiaddr().String()
			if transport == "wss" && !strings.Contains(selected, "/wss") && !strings.Contains(selected, "/tls/ws") {
				t.Fatalf("not a selected TLS WebSocket path: %s", selected)
			}
			t.Logf("UDP blackholed; selected=%s", connections[0].RemoteMultiaddr())
		})
	}
}

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
