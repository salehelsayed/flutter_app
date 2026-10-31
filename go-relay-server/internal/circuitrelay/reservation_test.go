package relay

import (
	"crypto/rand"
	"errors"
	"sync"
	"sync/atomic"
	"testing"
	"time"

	"github.com/libp2p/go-libp2p/core/connmgr"
	"github.com/libp2p/go-libp2p/core/crypto"
	"github.com/libp2p/go-libp2p/core/host"
	"github.com/libp2p/go-libp2p/core/network"
	"github.com/libp2p/go-libp2p/core/peer"
	"github.com/libp2p/go-libp2p/core/peerstore"
	pbv2 "github.com/libp2p/go-libp2p/p2p/protocol/circuitv2/pb"
	ma "github.com/multiformats/go-multiaddr"
)

type reservationTestConn struct {
	network.Conn
	remote peer.ID
	closed atomic.Bool
}

func (c *reservationTestConn) RemotePeer() peer.ID { return c.remote }
func (c *reservationTestConn) RemoteMultiaddr() ma.Multiaddr {
	return ma.StringCast("/ip4/127.0.0.1/tcp/1234")
}
func (c *reservationTestConn) IsClosed() bool { return c.closed.Load() }

type reservationTestStream struct {
	network.Stream
	conn        *reservationTestConn
	entered     chan struct{}
	release     chan struct{}
	releaseOnce sync.Once
	writeOnce   sync.Once
	writeErr    error
}

func (s *reservationTestStream) Conn() network.Conn               { return s.conn }
func (s *reservationTestStream) Close() error                     { return nil }
func (s *reservationTestStream) Reset() error                     { return nil }
func (s *reservationTestStream) SetWriteDeadline(time.Time) error { return nil }
func (s *reservationTestStream) Write(p []byte) (int, error) {
	if s.entered != nil {
		s.writeOnce.Do(func() { close(s.entered) })
		<-s.release
	}
	if s.writeErr != nil {
		return 0, s.writeErr
	}
	return len(p), nil
}
func (s *reservationTestStream) unblock() { s.releaseOnce.Do(func() { close(s.release) }) }

type reservationTestConnManager struct{ connmgr.ConnManager }

func (*reservationTestConnManager) TagPeer(peer.ID, string, int) {}
func (*reservationTestConnManager) UntagPeer(peer.ID, string)    {}

type reservationTestPeerstore struct {
	peerstore.Peerstore
	key crypto.PrivKey
}

func (s reservationTestPeerstore) PrivKey(peer.ID) crypto.PrivKey { return s.key }

type reservationTestHost struct {
	host.Host
	key crypto.PrivKey
	id  peer.ID
}

func (h reservationTestHost) ID() peer.ID           { return h.id }
func (h reservationTestHost) Addrs() []ma.Multiaddr { return nil }
func (h reservationTestHost) ConnManager() connmgr.ConnManager {
	return &reservationTestConnManager{}
}
func (h reservationTestHost) Peerstore() peerstore.Peerstore {
	return reservationTestPeerstore{key: h.key}
}

func newReservationTestRelay(t *testing.T) *Relay {
	t.Helper()
	key, _, err := crypto.GenerateEd25519Key(rand.Reader)
	if err != nil {
		t.Fatal(err)
	}
	id, err := peer.IDFromPrivateKey(key)
	if err != nil {
		t.Fatal(err)
	}
	r := &Relay{
		host:                  reservationTestHost{key: key, id: id},
		rc:                    DefaultResources(),
		rsvp:                  make(map[peer.ID]*reservation),
		conns:                 make(map[peer.ID]int),
		reservationAddrFilter: func(ma.Multiaddr) bool { return true },
	}
	r.constraints = newConstraints(&r.rc)
	return r
}

func beginGatedReservation(t *testing.T, r *Relay, conn *reservationTestConn, writeErr error) (*reservationTestStream, <-chan pbv2.Status) {
	t.Helper()
	s := &reservationTestStream{conn: conn, entered: make(chan struct{}), release: make(chan struct{}), writeErr: writeErr}
	t.Cleanup(s.unblock)
	result := make(chan pbv2.Status, 1)
	go func() { result <- r.handleReserve(s) }()
	select {
	case <-s.entered:
	case <-time.After(5 * time.Second):
		t.Fatal("reservation did not reach response write")
	}
	return s, result
}

func finishGatedReservation(t *testing.T, s *reservationTestStream, result <-chan pbv2.Status, want pbv2.Status) {
	t.Helper()
	s.unblock()
	select {
	case got := <-result:
		if got != want {
			t.Fatalf("reservation status = %v, want %v", got, want)
		}
	case <-time.After(5 * time.Second):
		t.Fatal("reservation did not finish")
	}
}

func assertReservationBinding(t *testing.T, r *Relay, conn network.Conn, pending int) {
	t.Helper()
	r.mx.Lock()
	defer r.mx.Unlock()
	current := r.rsvp[peer.ID("destination")]
	if current == nil || current.conn != conn || current.pending != pending {
		t.Fatalf("reservation = %+v, want conn %p and %d pending", current, conn, pending)
	}
	if len(r.constraints.total) != 1 {
		t.Fatalf("reservation accounting = %d, want 1", len(r.constraints.total))
	}
}

func TestReservationFailedResponsePreservesWorkingConnection(t *testing.T) {
	r := newReservationTestRelay(t)
	old := &reservationTestConn{remote: peer.ID("destination")}
	if got := r.handleReserve(&reservationTestStream{conn: old}); got != pbv2.Status_OK {
		t.Fatal(got)
	}
	oldExpiry := r.rsvp[old.remote].expire
	fresh := &reservationTestConn{remote: old.remote}
	if got := r.handleReserve(&reservationTestStream{conn: fresh, writeErr: errors.New("response failed")}); got != pbv2.Status_CONNECTION_FAILED {
		t.Fatal(got)
	}
	assertReservationBinding(t, r, old, 0)
	if !r.rsvp[old.remote].expire.Equal(oldExpiry) {
		t.Fatal("failed response replaced working expiry")
	}
	if got := r.handleReserve(&reservationTestStream{conn: fresh}); got != pbv2.Status_OK {
		t.Fatal(got)
	}
	assertReservationBinding(t, r, fresh, 0)
}

func TestReservationLateOlderResponseCannotReplaceNewerConnection(t *testing.T) {
	r := newReservationTestRelay(t)
	older := &reservationTestConn{remote: peer.ID("destination")}
	olderStream, olderResult := beginGatedReservation(t, r, older, nil)
	newer := &reservationTestConn{remote: older.remote}
	if got := r.handleReserve(&reservationTestStream{conn: newer}); got != pbv2.Status_OK {
		t.Fatal(got)
	}
	assertReservationBinding(t, r, newer, 1)
	finishGatedReservation(t, olderStream, olderResult, pbv2.Status_OK)
	assertReservationBinding(t, r, newer, 0)
	r.disconnected(nil, older)
	assertReservationBinding(t, r, newer, 0)
}

func TestReservationOldDisconnectDuringSuccessorResponsePreservesAccounting(t *testing.T) {
	r := newReservationTestRelay(t)
	old := &reservationTestConn{remote: peer.ID("destination")}
	if got := r.handleReserve(&reservationTestStream{conn: old}); got != pbv2.Status_OK {
		t.Fatal(got)
	}
	fresh := &reservationTestConn{remote: old.remote}
	s, result := beginGatedReservation(t, r, fresh, nil)
	old.closed.Store(true)
	r.disconnected(nil, old)
	assertReservationBinding(t, r, nil, 1)
	finishGatedReservation(t, s, result, pbv2.Status_OK)
	assertReservationBinding(t, r, fresh, 0)
	r.disconnected(nil, old)
	assertReservationBinding(t, r, fresh, 0)
	fresh.closed.Store(true)
	r.disconnected(nil, fresh)
	if len(r.rsvp) != 0 || len(r.constraints.total) != 0 {
		t.Fatal("bound disconnect left reservation accounting")
	}
}

func TestReservationFailedSuccessorAfterOldDisconnectReleasesAccounting(t *testing.T) {
	r := newReservationTestRelay(t)
	old := &reservationTestConn{remote: peer.ID("destination")}
	if got := r.handleReserve(&reservationTestStream{conn: old}); got != pbv2.Status_OK {
		t.Fatal(got)
	}
	fresh := &reservationTestConn{remote: old.remote}
	s, result := beginGatedReservation(t, r, fresh, errors.New("response failed"))
	old.closed.Store(true)
	r.disconnected(nil, old)
	finishGatedReservation(t, s, result, pbv2.Status_CONNECTION_FAILED)
	if len(r.rsvp) != 0 || len(r.constraints.total) != 0 {
		t.Fatal("failed successor left reservation accounting")
	}
}

func TestReservationPendingRenewalSurvivesGCAndClosedRelayCannotResurrect(t *testing.T) {
	for _, closeRelay := range []bool{false, true} {
		t.Run(map[bool]string{false: "expiry", true: "closed"}[closeRelay], func(t *testing.T) {
			r := newReservationTestRelay(t)
			conn := &reservationTestConn{remote: peer.ID("destination")}
			s, result := beginGatedReservation(t, r, conn, nil)
			r.mx.Lock()
			r.rsvp[conn.remote].expire = time.Now().Add(-time.Minute)
			r.closed = closeRelay
			r.mx.Unlock()
			r.gc()
			finishGatedReservation(t, s, result, pbv2.Status_OK)
			if closeRelay {
				if len(r.rsvp) != 0 {
					t.Fatal("successful response resurrected closed relay")
				}
			} else {
				assertReservationBinding(t, r, conn, 0)
				if !r.rsvp[conn.remote].expire.After(time.Now()) {
					t.Fatal("successful response did not renew expiry")
				}
			}
		})
	}
}

func TestReservationConcurrentResponsesKeepLatestSuccessfulRevision(t *testing.T) {
	r := newReservationTestRelay(t)
	const attempts = 8
	streams := make([]*reservationTestStream, attempts)
	results := make([]<-chan pbv2.Status, attempts)
	for i := range attempts {
		streams[i], results[i] = beginGatedReservation(t, r, &reservationTestConn{remote: peer.ID("destination")}, nil)
	}
	// Complete the newest response first, then all older pending streams.
	for i := attempts - 1; i >= 0; i-- {
		finishGatedReservation(t, streams[i], results[i], pbv2.Status_OK)
	}
	assertReservationBinding(t, r, streams[attempts-1].conn, 0)
}
