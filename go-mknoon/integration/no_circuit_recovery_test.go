//go:build integration

package integration_test

// Plan 189 — Defect B: the reserve-ok / no-circuit-publish wedge must not spin
// the node in a permanent watchdog-restart loop. These tests reproduce the
// field wedge deterministically: under ForceReachabilityPublic (test seam),
// go-libp2p v0.39.1's autorelay never publishes a /p2p-circuit address, while
// relay warm + explicit relayclient.Reserve still succeed against the
// harness's REAL circuit-v2 hop service — exactly the loop signature from the
// 2026-07-02 live debug (reserve success ~150ms, then "Timed out waiting for
// circuit address", then full restart, forever).

import (
	"context"
	"fmt"
	"testing"
	"time"

	"github.com/libp2p/go-libp2p/core/network"
	"github.com/libp2p/go-libp2p/core/peer"
	"github.com/mknoon/go-mknoon/node"
)

// startWedgedReserveOkNode starts a node whose autorelay circuit publisher is
// deterministically stopped (Public reachability) while warm + manual Reserve
// succeed — the spec-189 wedge. The seam must be set BEFORE Start.
func startWedgedReserveOkNode(t *testing.T, relayAddrs []string) (*node.Node, string) {
	t.Helper()

	privHex, expectedPeerID := generatePrivateKeyHex(t)
	n := node.NewNode()
	n.SetForcePublicReachabilityForTests(true)

	state, err := n.Start(node.NodeConfig{
		PrivateKeyHex:  privHex,
		RelayAddresses: append([]string(nil), relayAddrs...),
		ListenPort:     0,
	})
	if err != nil {
		t.Fatalf("node.Start(): %v", err)
	}
	if state.PeerId != expectedPeerID {
		t.Fatalf("peerId mismatch: got %s, want %s", state.PeerId, expectedPeerID)
	}
	t.Cleanup(func() {
		if err := n.Stop(); err != nil {
			t.Errorf("node.Stop(): %v", err)
		}
	})

	if err := n.WaitForRelayConnection(20 * time.Second); err != nil {
		t.Fatalf("WaitForRelayConnection(): %v", err)
	}
	return n, state.PeerId
}

func startSingleLocalRelay(t *testing.T) *localRelayServer {
	t.Helper()

	relay := newLocalRelayServer(t, newLocalRelaySharedState())
	relay.start()
	t.Cleanup(func() {
		relay.stop()
	})
	return relay
}

// TC-189-10: a successful explicit Reserve is circuit truth. The recovery
// verdict must accept it in place of an advertised /p2p-circuit address, stay
// in_place (no Stop+Start churn), and drive the relayState aggregate online so
// the Dart health check exits its recovery branch.
func TestReserveSuccessCountsAsCircuitTruth_NoRestartLoop(t *testing.T) {
	relay := startSingleLocalRelay(t)
	n, _ := startWedgedReserveOkNode(t, []string{relay.addr()})

	if got := statusInt(n.Status(), "watchdogRestartCount"); got != 0 {
		t.Fatalf("precondition: watchdogRestartCount=%d, want 0", got)
	}

	result, err := n.ReconnectRelays()
	if err != nil {
		t.Fatalf("ReconnectRelays(): %v", err)
	}
	if !result.Success {
		t.Fatalf("reserve succeeded — the verdict must accept reservation truth, got %+v", result)
	}
	if result.RecoveryMode != "in_place" {
		t.Fatalf("reserve-ok recovery must stay in_place (no host restart), got %+v", result)
	}
	if result.ErrorCode != "" {
		t.Fatalf("expected no error code on reservation-truth success, got %+v", result)
	}
	if got := statusInt(n.Status(), "watchdogRestartCount"); got != 0 {
		t.Fatalf("reserve-ok recovery must not count a watchdog restart, got %d", got)
	}

	waitForNodeStatus(t, n, 5*time.Second, func(status map[string]interface{}) bool {
		return statusString(status, "relayState") == "online"
	})
}

// TC-189-14 (PROD-CRITICAL wire leg): the accepted reservation must be REAL —
// a second default-flag node dialing <relay>/p2p-circuit/p2p/<A> reaches A
// (no NO_RESERVATION 204) and can open a stream. This is the invariant that
// broke direct dial and the 183 keepalive pings in the field.
func TestPeerCanDialReservationAfterRecovery(t *testing.T) {
	relay := startSingleLocalRelay(t)
	nodeA, peerIDA := startWedgedReserveOkNode(t, []string{relay.addr()})
	nodeB, _ := startNodeWithRelays(t, []string{relay.addr()}, nil, nil)

	if _, err := nodeA.ReconnectRelays(); err != nil {
		t.Fatalf("nodeA.ReconnectRelays(): %v", err)
	}

	circuitAddr := relay.addr() + "/p2p-circuit"
	if err := nodeB.DialPeerWithTimeout(peerIDA, []string{circuitAddr}, 8000); err != nil {
		t.Fatalf("peer dial via relay circuit failed — reservation not honored after recovery: %v", err)
	}

	pidA, err := peer.Decode(peerIDA)
	if err != nil {
		t.Fatalf("peer.Decode(%s): %v", peerIDA, err)
	}
	ctx, cancel := context.WithTimeout(context.Background(), 8*time.Second)
	defer cancel()
	ctx = network.WithAllowLimitedConn(ctx, "189-circuit-stream")
	s, err := nodeB.Host().NewStream(ctx, pidA, node.ChatProtocol)
	if err != nil {
		t.Fatalf("stream open over the relayed conn failed: %v", err)
	}
	_ = s.Close()
}

// TC-189-15 (collateral bound): repeated recovery cycles on the wedged node
// must not tear down pubsub / latch needsGroupRecovery / bump the watchdog
// counter — reserve-ok cycles stay in_place.
func TestNoCircuitCyclesDoNotChurnGroupsOrRestartUnbounded(t *testing.T) {
	relay := startSingleLocalRelay(t)
	n, _ := startWedgedReserveOkNode(t, []string{relay.addr()})

	for i := 0; i < 3; i++ {
		result, err := n.ReconnectRelays()
		if err != nil {
			t.Fatalf("cycle %d: ReconnectRelays(): %v", i, err)
		}
		if result.RecoveryMode == "watchdog_restart" {
			t.Fatalf("cycle %d fell through to a full restart: %+v", i, result)
		}
	}

	status := n.Status()
	if got := statusInt(status, "watchdogRestartCount"); got != 0 {
		t.Fatalf("reserve-ok cycles must not count watchdog restarts, got %d", got)
	}
	if statusBool(status, "needsGroupRecovery") {
		t.Fatalf("reserve-ok cycles must not latch needsGroupRecovery, status=%+v", status)
	}
}

// relayDNS4Addr returns the local relay's multiaddr in /dns4 form. autorelay
// v0.39.1's cleanupAddressSet (addrsplosion.go:12-36) keeps ONLY public or DNS
// relay addresses when building the published /p2p-circuit set — a loopback
// 127.0.0.1 relay addr is silently dropped, so the publish guard below must
// reach the relay the way production does (DNS, like /dns/mknoun.xyz/…).
func relayDNS4Addr(relay *localRelayServer) string {
	return fmt.Sprintf("/dns4/localhost/tcp/%d/p2p/%s", relay.tcpPort, relay.peerID)
}

// TC-189-41 (integration half; unit half lives in
// node/reachability_default_guard_test.go): under DEFAULT flags the node runs
// ForceReachabilityPrivate, so autorelay stays alive and eventually publishes
// a real /p2p-circuit address against the local hop service. Guards the 188
// coupling (EnableDcutrUpgrade → ForceReachabilityPublic) from silently
// re-creating the NO_CIRCUIT wedge for everyone.
func TestDefaultFlagsKeepPrivateReachability_CircuitPublished(t *testing.T) {
	relay := startSingleLocalRelay(t)
	n, _ := startNodeWithRelays(t, []string{relayDNS4Addr(relay)}, nil, nil)

	waitForNodeStatus(t, n, 30*time.Second, func(status map[string]interface{}) bool {
		addrs, _ := status["circuitAddresses"].([]string)
		return len(addrs) > 0
	})
}
