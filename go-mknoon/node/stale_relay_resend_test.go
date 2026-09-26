package node

import (
	"context"
	"sync"
	"testing"
	"time"

	"github.com/libp2p/go-libp2p/core/host"
	"github.com/libp2p/go-libp2p/core/network"
	"github.com/libp2p/go-libp2p/core/peer"
	"github.com/libp2p/go-libp2p/core/protocol"
	ma "github.com/multiformats/go-multiaddr"
)

type staleRelayTimeoutError struct{}

func (staleRelayTimeoutError) Error() string   { return "i/o timeout" }
func (staleRelayTimeoutError) Timeout() bool   { return true }
func (staleRelayTimeoutError) Temporary() bool { return true }

// silentProbeStream accepts the ping negotiation write and never answers, the
// way a relay circuit to a killed peer process behaves.
type silentProbeStream struct {
	network.Stream
	mu       sync.Mutex
	deadline time.Time
}

func (s *silentProbeStream) SetProtocol(protocol.ID) error { return nil }
func (s *silentProbeStream) SetDeadline(d time.Time) error {
	s.mu.Lock()
	s.deadline = d
	s.mu.Unlock()
	return nil
}
func (s *silentProbeStream) Write(p []byte) (int, error) { return len(p), nil }
func (s *silentProbeStream) Read([]byte) (int, error) {
	s.mu.Lock()
	d := s.deadline
	s.mu.Unlock()
	time.Sleep(time.Until(d))
	return 0, staleRelayTimeoutError{}
}
func (s *silentProbeStream) Reset() error { return nil }
func (s *silentProbeStream) Close() error { return nil }

type staleRelayConn struct {
	network.Conn
	limited bool
	mu      sync.Mutex
	closed  bool
	probes  int
}

func (c *staleRelayConn) LocalMultiaddr() ma.Multiaddr {
	return ma.StringCast("/ip4/127.0.0.1/tcp/40001")
}
func (c *staleRelayConn) RemoteMultiaddr() ma.Multiaddr {
	if c.limited {
		return ma.StringCast("/ip4/127.0.0.1/tcp/4001/p2p-circuit")
	}
	return ma.StringCast("/ip4/127.0.0.1/tcp/4002")
}

func (c *staleRelayConn) Stat() network.ConnStats {
	return network.ConnStats{Stats: network.Stats{Limited: c.limited, Opened: time.Now().Add(-25 * time.Second)}}
}
func (c *staleRelayConn) IsClosed() bool {
	c.mu.Lock()
	defer c.mu.Unlock()
	return c.closed
}
func (c *staleRelayConn) Close() error {
	c.mu.Lock()
	c.closed = true
	c.mu.Unlock()
	return nil
}
func (c *staleRelayConn) NewStream(context.Context) (network.Stream, error) {
	c.mu.Lock()
	c.probes++
	c.mu.Unlock()
	return &silentProbeStream{}, nil
}

type connScriptedStream struct {
	*r3ScriptedStream
	conn network.Conn
}

func (s connScriptedStream) Conn() network.Conn { return s.conn }

func TestStaleRelayResend_ClosesUnresponsiveRelayCircuitAndResendsOnce(t *testing.T) {
	n, target := startR3DeadlineNode(t)
	conn := &staleRelayConn{limited: true}
	first := newR3ScriptedStream(t, `{"ack":true}`)
	first.readErr = staleRelayTimeoutError{}
	second := newR3ScriptedStream(t, `{"ack":true}`)
	opens := 0
	n.openChatStreamHook = func(context.Context, host.Host, peer.ID) (network.Stream, error) {
		opens++
		if opens == 1 {
			return connScriptedStream{r3ScriptedStream: first, conn: conn}, nil
		}
		return second, nil
	}

	result, err := n.SendMessageWithTransport(target.String(), r3ChatEnvelope, 10000)
	if err != nil {
		t.Fatalf("SendMessageWithTransport: %v", err)
	}
	if !result.Acked {
		t.Fatal("resend over a fresh circuit was not acked")
	}
	if opens != 2 {
		t.Fatalf("stream opens = %d, want exactly one resend", opens)
	}
	if !conn.IsClosed() || conn.probes != 1 {
		t.Fatalf("stale relay circuit closed=%v probes=%d, want closed after one probe", conn.IsClosed(), conn.probes)
	}
}

func TestStaleRelayResend_DirectConnectionKeepsSingleAttempt(t *testing.T) {
	n, target := startR3DeadlineNode(t)
	conn := &staleRelayConn{limited: false}
	first := newR3ScriptedStream(t, `{"ack":true}`)
	first.readErr = staleRelayTimeoutError{}
	opens := 0
	n.openChatStreamHook = func(context.Context, host.Host, peer.ID) (network.Stream, error) {
		opens++
		return connScriptedStream{r3ScriptedStream: first, conn: conn}, nil
	}

	result, err := n.SendMessageWithTransport(target.String(), r3ChatEnvelope, 10000)
	if err != nil {
		t.Fatalf("SendMessageWithTransport: %v", err)
	}
	if result.Acked || opens != 1 {
		t.Fatalf("direct timeout acked=%v opens=%d, want one unacked attempt", result.Acked, opens)
	}
	if conn.IsClosed() || conn.probes != 0 {
		t.Fatalf("direct connection closed=%v probes=%d, want untouched (359f6fca7)", conn.IsClosed(), conn.probes)
	}
}
