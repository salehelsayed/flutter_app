package node

import (
	"context"
	"strings"
	"testing"

	"github.com/libp2p/go-libp2p/core/peer"
)

// connectRelayNoPanic runs dial and turns a panic into a test failure, so a
// nil-host crash fails this test instead of aborting the whole package.
func connectRelayNoPanic(t *testing.T, dial func() error) error {
	t.Helper()
	var err error
	func() {
		defer func() {
			if r := recover(); r != nil {
				t.Fatalf("relay dial panicked on a missing host: %v", r)
			}
		}()
		err = dial()
	}()
	return err
}

// A Start warm-up goroutine can reach connectRelay after Stop has cleared the
// host (node.go Start warm-up vs Stop). It must fail the dial, not crash.
func TestConnectRelayAfterStopReturnsErrorNotPanic(t *testing.T) {
	n := New(&testEventCollector{})
	if _, err := n.Start(NodeConfig{
		PrivateKeyHex:  generateTestKey(t),
		RelayAddresses: []string{},
		AutoRegister:   false,
	}); err != nil {
		t.Fatalf("Start: %v", err)
	}
	if err := n.Stop(); err != nil {
		t.Fatalf("Stop: %v", err)
	}

	relay := peer.AddrInfo{ID: fakePeerID("relay-after-stop")}
	err := connectRelayNoPanic(t, func() error {
		return n.warmRelayConnectionForStart(relay)
	})
	if err == nil || !strings.Contains(err.Error(), "node host not available") {
		t.Fatalf("warm dial after Stop error = %v, want node host not available", err)
	}
}

func TestConnectRelayZeroNodeNoHost(t *testing.T) {
	n := &Node{}
	relay := peer.AddrInfo{ID: fakePeerID("relay-zero-node")}
	err := connectRelayNoPanic(t, func() error {
		return n.connectRelay(context.Background(), relay)
	})
	if err == nil || err.Error() != "node host not available" {
		t.Fatalf("connectRelay without host error = %v, want node host not available", err)
	}
}
