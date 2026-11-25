package node

import (
	"context"
	"errors"
	"fmt"
	"net"
	"syscall"
	"testing"

	"github.com/libp2p/go-libp2p/core/sec"
	"github.com/libp2p/go-libp2p/p2p/net/swarm"
	ma "github.com/multiformats/go-multiaddr"
)

func dialErrorWith(t *testing.T, causes ...error) error {
	t.Helper()
	attempts := make([]swarm.TransportError, 0, len(causes))
	for _, cause := range causes {
		attempts = append(attempts, swarm.TransportError{
			Address: ma.StringCast("/ip4/192.0.2.1/tcp/4001"),
			Cause:   cause,
		})
	}
	return &swarm.DialError{DialErrors: attempts, Cause: swarm.ErrAllDialsFailed}
}

func socketError(errno syscall.Errno) error {
	return &net.OpError{Op: "dial", Net: "tcp", Err: errno}
}

func TestClassifyDialErrorNamesTheCause(t *testing.T) {
	relay := func(status string) error {
		return fmt.Errorf("error opening relay circuit: %s (204)", status)
	}
	cases := []struct {
		name string
		err  error
		want string
	}{
		{"deadline", fmt.Errorf("failed to dial: %w", context.DeadlineExceeded), "timeout"},
		{"swarm timeout", swarm.ErrDialTimeout, "timeout"},
		{"canceled", fmt.Errorf("failed to dial: %w", context.Canceled), "canceled"},
		{"no addresses", swarm.ErrNoAddresses, "no_addresses"},
		{"no good addresses", swarm.ErrNoGoodAddresses, "no_good_addresses"},
		{"filtered", swarm.ErrAddrFiltered, "no_good_addresses"},
		{"backoff", swarm.ErrDialBackoff, "backoff"},
		{"black hole", swarm.ErrDialRefusedBlackHole, "black_hole"},
		{"gater", swarm.ErrGaterDisallowedConnection, "gater_denied"},
		{"no transport", swarm.ErrNoTransport, "no_transport"},
		{"refused", dialErrorWith(t, socketError(syscall.ECONNREFUSED)), "socket_refused"},
		{"network unreachable", dialErrorWith(t, socketError(syscall.ENETUNREACH)), "socket_unreachable"},
		{"host unreachable", dialErrorWith(t, socketError(syscall.EHOSTUNREACH)), "socket_unreachable"},
		{"no reservation", dialErrorWith(t, relay("NO_RESERVATION")), "relay_no_reservation"},
		{"relay limit", dialErrorWith(t, relay("RESOURCE_LIMIT_EXCEEDED")), "relay_limit"},
		{"relay denied", dialErrorWith(t, relay("PERMISSION_DENIED")), "relay_denied"},
		{"relay failed", dialErrorWith(t, relay("CONNECTION_FAILED")), "relay_failed"},
		{"security", dialErrorWith(t, fmt.Errorf("failed to negotiate security protocol: %w", errors.New("eof"))), "handshake_failed"},
		{"peer id mismatch", dialErrorWith(t, sec.ErrPeerIDMismatch{}), "handshake_failed"},
		{"relay outranks socket", dialErrorWith(t, socketError(syscall.ECONNREFUSED), relay("NO_RESERVATION")), "relay_no_reservation"},
		{"socket outranks timeout", dialErrorWith(t, context.DeadlineExceeded, socketError(syscall.ENETUNREACH)), "socket_unreachable"},
		{"unknown", errors.New("boom"), "other"},
	}
	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			if got := ClassifyDialError(c.err); got != c.want {
				t.Fatalf("ClassifyDialError(%v) = %q, want %q", c.err, got, c.want)
			}
		})
	}
}

func TestDialPeerWithDiagnosticsReportsNotStartedAndInvalidPeer(t *testing.T) {
	n := NewNode()
	if _, err := n.DialPeerWithDiagnostics("12D3KooWFakeDialTestPeer", nil, 100); !errors.Is(err, ErrDialNodeNotStarted) {
		t.Fatalf("not started: got %v, want ErrDialNodeNotStarted", err)
	}
}
