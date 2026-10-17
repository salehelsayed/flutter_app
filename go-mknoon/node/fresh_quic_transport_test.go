package node

import (
	"context"
	"crypto/rand"
	"net"
	"sync"
	"sync/atomic"
	"testing"
	"time"

	"github.com/libp2p/go-libp2p"
	libp2pcrypto "github.com/libp2p/go-libp2p/core/crypto"
	"github.com/libp2p/go-libp2p/core/host"
	"github.com/libp2p/go-libp2p/core/network"
	"github.com/libp2p/go-libp2p/core/peer"
	"github.com/libp2p/go-libp2p/core/peerstore"
	ma "github.com/multiformats/go-multiaddr"
)

// observedSocketFactory stands in for net.ListenUDP so a test can count the
// sockets the fresh-dial seam creates and see each one close.
type observedSocketFactory struct {
	mu      sync.Mutex
	sockets []*observedPacketConn
}

type observedPacketConn struct {
	net.PacketConn
	closed atomic.Int32
}

func (c *observedPacketConn) Close() error {
	c.closed.Add(1)
	return c.PacketConn.Close()
}

func (f *observedSocketFactory) listen(network string, laddr *net.UDPAddr) (net.PacketConn, error) {
	pc, err := net.ListenUDP(network, laddr)
	if err != nil {
		return nil, err
	}
	wrapped := &observedPacketConn{PacketConn: pc}
	f.mu.Lock()
	f.sockets = append(f.sockets, wrapped)
	f.mu.Unlock()
	return wrapped, nil
}

func (f *observedSocketFactory) count() int {
	f.mu.Lock()
	defer f.mu.Unlock()
	return len(f.sockets)
}

func (f *observedSocketFactory) allClosedWithin(timeout time.Duration) bool {
	deadline := time.Now().Add(timeout)
	for time.Now().Before(deadline) {
		f.mu.Lock()
		open := 0
		for _, s := range f.sockets {
			if s.closed.Load() == 0 {
				open++
			}
		}
		f.mu.Unlock()
		if open == 0 {
			return true
		}
		time.Sleep(20 * time.Millisecond)
	}
	return false
}

func newPolicyHost(t *testing.T, p *freshQUICDialPolicy, listen ...string) host.Host {
	t.Helper()
	priv, _, err := libp2pcrypto.GenerateEd25519Key(rand.Reader)
	if err != nil {
		t.Fatalf("key: %v", err)
	}
	opts := []libp2p.Option{
		libp2p.Identity(priv),
		libp2p.ListenAddrStrings(listen...),
		libp2p.ForceReachabilityPublic(),
	}
	opts = append(opts, nodeTransportOptions(p)...)
	h, err := libp2p.New(opts...)
	if err != nil {
		t.Fatalf("host: %v", err)
	}
	t.Cleanup(func() { _ = h.Close() })
	return h
}

func loopbackQUICAddrs(h host.Host) []ma.Multiaddr {
	var out []ma.Multiaddr
	for _, a := range h.Addrs() {
		if _, err := a.ValueForProtocol(ma.P_QUIC_V1); err == nil {
			if ip, err := a.ValueForProtocol(ma.P_IP4); err == nil && ip == "127.0.0.1" {
				out = append(out, a)
			}
		}
	}
	return out
}

func onlyConnTo(t *testing.T, h host.Host, p peer.ID) network.Conn {
	t.Helper()
	conns := h.Network().ConnsToPeer(p)
	if len(conns) != 1 {
		t.Fatalf("conns to %s = %d, want 1", p, len(conns))
	}
	return conns[0]
}

func waitNotConnected(t *testing.T, h host.Host, p peer.ID) {
	t.Helper()
	deadline := time.Now().Add(3 * time.Second)
	for time.Now().Before(deadline) {
		if h.Network().Connectedness(p) == network.NotConnected {
			return
		}
		time.Sleep(10 * time.Millisecond)
	}
	t.Fatalf("still connected to %s", p)
}

// TestFreshRelayDial_NewSocketPerHandoffDial_ReuseOtherwise drives the seam the
// way production does: BasicHost.Connect -> swarm dial sync/worker -> the
// host's QUIC transport. An ordinary dial reuses the wildcard listener socket.
// A dial to an armed peer gets a brand-new socket that is released exactly once
// on connection close, dial cancellation, failed handshake and host close.
func TestFreshRelayDial_NewSocketPerHandoffDial_ReuseOtherwise(t *testing.T) {
	factory := &observedSocketFactory{}
	policy := newFreshQUICDialPolicy()
	policy.listenUDP = factory.listen

	dialer := newPolicyHost(t, policy, "/ip4/0.0.0.0/udp/0/quic-v1")
	target := newPolicyHost(t, newFreshQUICDialPolicy(), "/ip4/127.0.0.1/udp/0/quic-v1")
	listenerPort := quicListenPort(t, dialer)
	targetInfo := peer.AddrInfo{ID: target.ID(), Addrs: loopbackQUICAddrs(target)}
	if len(targetInfo.Addrs) == 0 {
		t.Fatal("target has no loopback QUIC address")
	}
	connect := func(ctx context.Context, info peer.AddrInfo) error {
		return dialer.Connect(ctx, info)
	}
	ctx5 := func() (context.Context, context.CancelFunc) {
		return context.WithTimeout(context.Background(), 5*time.Second)
	}

	// 1. Ordinary dial: reuse of the listener socket, no seam socket.
	ctx, cancel := ctx5()
	if err := connect(ctx, targetInfo); err != nil {
		t.Fatalf("ordinary connect: %v", err)
	}
	cancel()
	ordinary := onlyConnTo(t, dialer, target.ID())
	if got := udpPortOf(ordinary.LocalMultiaddr()); got != listenerPort {
		t.Fatalf("ordinary dial local port = %d, want listener port %d (reuse)", got, listenerPort)
	}
	if _, fresh := policy.freshEpoch(ordinary); fresh || factory.count() != 0 {
		t.Fatalf("ordinary dial touched the fresh seam: fresh=%v sockets=%d", fresh, factory.count())
	}

	// 2. Armed dial: new socket, recorded for its epoch.
	_ = dialer.Network().ClosePeer(target.ID())
	waitNotConnected(t, dialer, target.ID())
	policy.arm(2, []peer.ID{target.ID()})
	ctx, cancel = ctx5()
	if err := connect(ctx, targetInfo); err != nil {
		t.Fatalf("armed connect: %v", err)
	}
	cancel()
	freshConn := onlyConnTo(t, dialer, target.ID())
	if got := udpPortOf(freshConn.LocalMultiaddr()); got == listenerPort || got <= 0 {
		t.Fatalf("handoff-marked dial local port = %d, want a new socket (listener is %d)", got, listenerPort)
	}
	if epoch, ok := policy.freshEpoch(freshConn); !ok || epoch != 2 {
		t.Fatalf("fresh record = (%d,%v), want (2,true)", epoch, ok)
	}
	if factory.count() != 1 || policy.openSockets() != 1 {
		t.Fatalf("after armed dial: sockets created=%d open=%d, want 1/1", factory.count(), policy.openSockets())
	}

	// 3. Connection close releases the dedicated socket once.
	if err := freshConn.Close(); err != nil {
		t.Fatalf("close fresh conn: %v", err)
	}
	if !factory.allClosedWithin(3 * time.Second) {
		t.Fatal("fresh socket not closed after its connection closed")
	}
	if policy.openSockets() != 0 {
		t.Fatalf("open sockets after close = %d, want 0", policy.openSockets())
	}
	if factory.sockets[0].closed.Load() != 1 {
		t.Fatalf("fresh socket Close() called %d times, want exactly 1", factory.sockets[0].closed.Load())
	}
	policy.disarm(2)

	// 4. Cancelled dial (silent peer) releases the socket.
	silent, err := net.ListenUDP("udp4", &net.UDPAddr{IP: net.IPv4(127, 0, 0, 1), Port: 0})
	if err != nil {
		t.Fatalf("silent socket: %v", err)
	}
	defer silent.Close()
	silentPriv, _, _ := libp2pcrypto.GenerateEd25519Key(rand.Reader)
	silentID, _ := peer.IDFromPrivateKey(silentPriv)
	silentAddr, _ := ma.NewMultiaddr("/ip4/127.0.0.1/udp/" + itoa(silent.LocalAddr().(*net.UDPAddr).Port) + "/quic-v1")
	dialer.Peerstore().AddAddrs(silentID, []ma.Multiaddr{silentAddr}, peerstore.TempAddrTTL)
	policy.arm(3, []peer.ID{silentID})
	ctx, cancel = context.WithTimeout(context.Background(), 400*time.Millisecond)
	if err := connect(ctx, peer.AddrInfo{ID: silentID}); err == nil {
		t.Fatal("dial to a silent peer succeeded")
	}
	cancel()
	if factory.count() != 2 {
		t.Fatalf("cancelled dial created %d sockets in total, want 2", factory.count())
	}
	if !factory.allClosedWithin(3 * time.Second) {
		t.Fatal("socket of the cancelled dial not released")
	}
	policy.disarm(3)

	// 5. Failed handshake (wrong peer id at a real listener) releases the socket.
	wrongPriv, _, _ := libp2pcrypto.GenerateEd25519Key(rand.Reader)
	wrongID, _ := peer.IDFromPrivateKey(wrongPriv)
	dialer.Peerstore().AddAddrs(wrongID, targetInfo.Addrs, peerstore.TempAddrTTL)
	policy.arm(4, []peer.ID{wrongID})
	ctx, cancel = ctx5()
	if err := connect(ctx, peer.AddrInfo{ID: wrongID}); err == nil {
		t.Fatal("dial with a mismatched peer id succeeded")
	}
	cancel()
	if factory.count() != 3 {
		t.Fatalf("failed handshake created %d sockets in total, want 3", factory.count())
	}
	if !factory.allClosedWithin(3 * time.Second) {
		t.Fatal("socket of the failed handshake not released")
	}
	policy.disarm(4)

	// 6. Reuse is back to normal once disarmed.
	ctx, cancel = ctx5()
	if err := connect(ctx, targetInfo); err != nil {
		t.Fatalf("post-disarm connect: %v", err)
	}
	cancel()
	again := onlyConnTo(t, dialer, target.ID())
	if got := udpPortOf(again.LocalMultiaddr()); got != listenerPort {
		t.Fatalf("post-disarm dial local port = %d, want listener port %d", got, listenerPort)
	}
	if factory.count() != 3 {
		t.Fatalf("post-disarm dial created a seam socket (total %d)", factory.count())
	}

	// 7. Host close releases a live fresh socket.
	_ = dialer.Network().ClosePeer(target.ID())
	waitNotConnected(t, dialer, target.ID())
	policy.arm(5, []peer.ID{target.ID()})
	ctx, cancel = ctx5()
	if err := connect(ctx, targetInfo); err != nil {
		t.Fatalf("armed connect before host close: %v", err)
	}
	cancel()
	if factory.count() != 4 || policy.openSockets() != 1 {
		t.Fatalf("before host close: created=%d open=%d, want 4/1", factory.count(), policy.openSockets())
	}
	if err := dialer.Close(); err != nil {
		t.Fatalf("host close: %v", err)
	}
	if !factory.allClosedWithin(3 * time.Second) {
		t.Fatal("fresh socket survived host close")
	}
	if policy.openSockets() != 0 {
		t.Fatalf("open sockets after host close = %d, want 0", policy.openSockets())
	}
}

func itoa(i int) string {
	return string(appendInt(nil, i))
}

func appendInt(b []byte, i int) []byte {
	if i == 0 {
		return append(b, '0')
	}
	var tmp [20]byte
	n := len(tmp)
	for i > 0 {
		n--
		tmp[n] = byte('0' + i%10)
		i /= 10
	}
	return append(b, tmp[n:]...)
}
