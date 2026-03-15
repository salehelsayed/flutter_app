//go:build integration

package integration_test

import (
	"testing"
	"time"

	"github.com/mknoon/go-mknoon/node"
)

func startPersonalNodeWithExplicitInitialRegister(
	t *testing.T,
	relayAddrs []string,
	refreshInterval time.Duration,
) (*node.Node, string) {
	return startPersonalNodeWithExplicitInitialRegisterAndFlags(t, relayAddrs, refreshInterval, nil)
}

func startPersonalNodeWithExplicitInitialRegisterAndFlags(
	t *testing.T,
	relayAddrs []string,
	refreshInterval time.Duration,
	flags *node.FeatureFlags,
) (*node.Node, string) {
	t.Helper()

	n, peerID := startNodeWithRelayConfig(t, relayAddrs, nil, flags, func(cfg *node.NodeConfig, expectedPeerID string) {
		cfg.Namespace = node.RendezvousPrefix + expectedPeerID
		cfg.AutoRegister = true
		cfg.PersonalRendezvousRefreshInterval = refreshInterval
	})

	// The local relay harness keeps rendezvous state but does not surface the
	// public circuit addresses that the production auto-register path waits for.
	// Seed the initial personal registration explicitly, then let the normal
	// personal refresh loop keep it alive.
	waitForRendezvousRegister(t, n, n.Namespace(), 10*time.Second)
	return n, peerID
}

func TestPersonalNamespaceRefresh_AutoRegisterMakesNodeDiscoverableAfterCircuitReady(t *testing.T) {
	if testing.Short() {
		t.Skip("skipping integration test in -short mode")
	}
	requireRelay(t)

	collector := &eventCollector{}
	nodeA, peerIDA := startNodeWithRelayConfig(t, []string{relayAddr()}, collector, nil, func(cfg *node.NodeConfig, expectedPeerID string) {
		cfg.Namespace = node.RendezvousPrefix + expectedPeerID
		cfg.AutoRegister = true
		cfg.PersonalRendezvousRefreshInterval = time.Second
	})

	if _, ok := collector.waitForEvent("p2p-circuit", 30*time.Second); !ok {
		t.Logf("all events: %v", collector.snapshot())
		t.Fatal("nodeA did not publish a circuit address before personal auto-register")
	}

	nodeB, _ := startNode(t)
	waitForDiscoverablePeer(t, nodeB, nodeA.Namespace(), peerIDA, 15*time.Second)
}

func TestPersonalNamespaceRefresh_KeepsDiscoverablePastShortTTL(t *testing.T) {
	relayA, _ := startLocalRelayPairWithRegistrationTTL(t, 3)

	nodeA, peerIDA := startPersonalNodeWithExplicitInitialRegister(t, []string{relayA.addr()}, time.Second)
	nodeB, _ := startNodeWithRelays(t, []string{relayA.addr()}, nil, nil)

	namespace := nodeA.Namespace()
	waitForDiscoverablePeer(t, nodeB, namespace, peerIDA, 10*time.Second)

	time.Sleep(4 * time.Second)

	waitForDiscoverablePeer(t, nodeB, namespace, peerIDA, 3*time.Second)
}

func TestPersonalNamespaceRecovery_ReRegistersAfterInPlaceRefresh(t *testing.T) {
	relayA, _ := startLocalRelayPairWithRegistrationTTL(t, 3)

	nodeA, peerIDA := startPersonalNodeWithExplicitInitialRegister(t, []string{relayA.addr()}, 30*time.Second)
	nodeB, _ := startNodeWithRelays(t, []string{relayA.addr()}, nil, nil)
	nodeA.SetWaitForCircuitAddressHookForTests(func(timeout time.Duration) bool {
		return true
	})

	namespace := nodeA.Namespace()
	waitForDiscoverablePeer(t, nodeB, namespace, peerIDA, 10*time.Second)

	time.Sleep(4 * time.Second)
	waitForPeerUndiscoverable(t, nodeB, namespace, peerIDA, 3*time.Second)

	result := nodeA.RefreshRelaySession()
	if !result.Success {
		t.Fatalf("RefreshRelaySession() should restore personal discoverability, got %+v", result)
	}
	if result.RecoveryMode != "in_place" {
		t.Fatalf("expected in_place recovery, got %+v", result)
	}

	waitForDiscoverablePeer(t, nodeB, namespace, peerIDA, 3*time.Second)
}

func TestPersonalNamespaceRefresh_RefreshesBeforeExpiryUnderIdleNode(t *testing.T) {
	relayA, _ := startLocalRelayPairWithRegistrationTTL(t, 3)

	nodeA, peerIDA := startPersonalNodeWithExplicitInitialRegister(t, []string{relayA.addr()}, time.Second)
	nodeB, _ := startNodeWithRelays(t, []string{relayA.addr()}, nil, nil)

	namespace := nodeA.Namespace()
	waitForDiscoverablePeer(t, nodeB, namespace, peerIDA, 10*time.Second)

	for i := 0; i < 3; i++ {
		time.Sleep(2 * time.Second)
		waitForDiscoverablePeer(t, nodeB, namespace, peerIDA, 2*time.Second)
	}
}

func TestPersonalNamespaceRefresh_StopPreventsFurtherReRegistration(t *testing.T) {
	relayA, _ := startLocalRelayPairWithRegistrationTTL(t, 3)

	nodeA, peerIDA := startPersonalNodeWithExplicitInitialRegister(t, []string{relayA.addr()}, time.Second)
	nodeB, _ := startNodeWithRelays(t, []string{relayA.addr()}, nil, nil)

	namespace := nodeA.Namespace()
	waitForDiscoverablePeer(t, nodeB, namespace, peerIDA, 10*time.Second)

	if err := nodeA.Stop(); err != nil {
		t.Fatalf("nodeA.Stop(): %v", err)
	}

	waitForPeerUndiscoverable(t, nodeB, namespace, peerIDA, 5*time.Second)
}

func waitForPeerUndiscoverable(
	t *testing.T,
	n *node.Node,
	namespace, peerID string,
	timeout time.Duration,
) {
	t.Helper()

	deadline := time.Now().Add(timeout)
	for time.Now().Before(deadline) {
		peers, err := n.RendezvousDiscover(namespace, nil)
		if err == nil {
			found := false
			for _, discovered := range peers {
				if discovered.ID.String() == peerID {
					found = true
					break
				}
			}
			if !found {
				return
			}
		}
		time.Sleep(200 * time.Millisecond)
	}

	peers, err := n.RendezvousDiscover(namespace, nil)
	t.Fatalf(
		"peer %s remained discoverable on %s within %v (last err=%v peers=%v)",
		peerID,
		namespace,
		timeout,
		err,
		peers,
	)
}
