package relay

import (
	"context"
	"crypto/rand"
	"sync"
	"sync/atomic"
	"testing"
	"time"

	"github.com/libp2p/go-libp2p"
	"github.com/libp2p/go-libp2p/core/crypto"
	"github.com/libp2p/go-libp2p/core/host"
	"github.com/libp2p/go-libp2p/core/network"
	"github.com/libp2p/go-libp2p/core/peer"
	"github.com/libp2p/go-libp2p/p2p/protocol/circuitv2/client"
	"github.com/libp2p/go-libp2p/p2p/protocol/circuitv2/proto"
	ma "github.com/multiformats/go-multiaddr"
)

// Conn is evaluated after writeResponse and before finishReservation. Holding
// that call exposes the acknowledged-but-unpublished reservation deterministically
// without adding a production test hook or delaying delivery of STATUS_OK.
type acknowledgedReservationStream struct {
	network.Stream
	wroteResponse bool
	paused        chan struct{}
	release       chan struct{}
	once          sync.Once
}

func (s *acknowledgedReservationStream) Write(p []byte) (int, error) {
	n, err := s.Stream.Write(p)
	if err == nil {
		s.wroteResponse = true
	}
	return n, err
}

func (s *acknowledgedReservationStream) Conn() network.Conn {
	if s.wroteResponse {
		s.once.Do(func() { close(s.paused) })
		<-s.release
	}
	return s.Stream.Conn()
}

func TestReservationAcknowledgedBeforePublicationHOPWaits(t *testing.T) {
	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	t.Cleanup(cancel)
	relayHost := reservationVisibilityHost(t)
	r, err := New(relayHost)
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { _ = r.Close() })
	destination := reservationVisibilityHost(t)
	prober := reservationVisibilityHost(t)
	paused, release, hopEntered := make(chan struct{}), make(chan struct{}), make(chan struct{})
	var releaseOnce, hopOnce sync.Once
	unblock := func() { releaseOnce.Do(func() { close(release) }) }
	t.Cleanup(unblock)
	relayHost.SetStreamHandler(proto.ProtoIDv2Hop, func(s network.Stream) {
		if s.Conn().RemotePeer() == destination.ID() {
			r.handleStream(&acknowledgedReservationStream{Stream: s, paused: paused, release: release})
			return
		}
		hopOnce.Do(func() { close(hopEntered) })
		r.handleStream(s)
	})
	info := peer.AddrInfo{ID: relayHost.ID(), Addrs: relayHost.Addrs()}
	reserved := make(chan error, 1)
	go func() { _, err := client.Reserve(ctx, destination, info); reserved <- err }()
	select {
	case <-paused:
	case <-ctx.Done():
		t.Fatal("RESERVE did not pause after delivering OK")
	}
	select {
	case err := <-reserved:
		if err != nil {
			t.Fatalf("unmodified client did not receive OK: %v", err)
		}
	case <-ctx.Done():
		t.Fatal("client waited for server publication after receiving OK")
	}
	circuit := relayHost.Addrs()[0].Encapsulate(ma.StringCast("/p2p/" + relayHost.ID().String() + "/p2p-circuit"))
	dialed := make(chan error, 1)
	go func() {
		dialed <- prober.Connect(ctx, peer.AddrInfo{ID: destination.ID(), Addrs: []ma.Multiaddr{circuit}})
	}()
	select {
	case <-hopEntered:
	case <-ctx.Done():
		t.Fatal("immediate HOP did not reach the relay")
	}
	select {
	case err := <-dialed:
		t.Fatalf("HOP completed before acknowledged reservation publication: %v", err)
	case <-time.After(100 * time.Millisecond):
	}
	unblock()
	select {
	case err := <-dialed:
		if err != nil {
			t.Fatalf("HOP failed after reservation publication: %v", err)
		}
	case <-ctx.Done():
		t.Fatal("HOP did not resume after publication")
	}
}

func TestReservationOlderPendingDoesNotBlockNewerPublishedHOP(t *testing.T) {
	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	t.Cleanup(cancel)
	h := reservationVisibilityHost(t)
	r, err := New(h)
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { _ = r.Close() })
	key, _, err := crypto.GenerateEd25519Key(rand.Reader)
	if err != nil {
		t.Fatal(err)
	}
	older := reservationVisibilityHost(t, libp2p.Identity(key))
	newer := reservationVisibilityHost(t, libp2p.Identity(key))
	prober := reservationVisibilityHost(t)
	paused, release := make(chan struct{}), make(chan struct{})
	var attempts atomic.Int32
	var releaseOnce sync.Once
	unblock := func() { releaseOnce.Do(func() { close(release) }) }
	t.Cleanup(unblock)
	h.SetStreamHandler(proto.ProtoIDv2Hop, func(s network.Stream) {
		if s.Conn().RemotePeer() == older.ID() && attempts.Add(1) == 1 {
			r.handleStream(&acknowledgedReservationStream{Stream: s, paused: paused, release: release})
			return
		}
		r.handleStream(s)
	})
	info := peer.AddrInfo{ID: h.ID(), Addrs: h.Addrs()}
	if _, err := client.Reserve(ctx, older, info); err != nil {
		t.Fatal(err)
	}
	select {
	case <-paused:
	case <-ctx.Done():
		t.Fatal("older response did not pause after OK")
	}
	if _, err := client.Reserve(ctx, newer, info); err != nil {
		t.Fatal(err)
	}
	for {
		r.mx.Lock()
		published := r.rsvp[newer.ID()] != nil && r.rsvp[newer.ID()].conn != nil
		r.mx.Unlock()
		if published {
			break
		}
		select {
		case <-ctx.Done():
			t.Fatal("newer reservation was not published")
		case <-time.After(time.Millisecond):
		}
	}
	circuit := h.Addrs()[0].Encapsulate(ma.StringCast("/p2p/" + h.ID().String() + "/p2p-circuit"))
	dialCtx, cancelDial := context.WithTimeout(ctx, time.Second)
	defer cancelDial()
	if err := prober.Connect(dialCtx, peer.AddrInfo{ID: newer.ID(), Addrs: []ma.Multiaddr{circuit}}); err != nil {
		t.Fatalf("older unfinished response blocked the newer published reservation: %v", err)
	}
	unblock()
}

func reservationVisibilityHost(t *testing.T, options ...libp2p.Option) host.Host {
	t.Helper()
	defaults := []libp2p.Option{libp2p.ListenAddrStrings("/ip4/127.0.0.1/tcp/0"), libp2p.EnableRelay(), libp2p.ForceReachabilityPublic()}
	h, err := libp2p.New(append(defaults, options...)...)
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { _ = h.Close() })
	return h
}
