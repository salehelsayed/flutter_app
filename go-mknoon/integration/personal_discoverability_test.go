//go:build integration

package integration_test

import (
	"testing"
	"time"

	"github.com/mknoon/go-mknoon/node"
)

func TestPersonalNamespaceRefresh_KeepsDiscoverablePastShortTTL(t *testing.T) {
	relayA, _ := startLocalRelayPairWithRegistrationTTL(t, 3)

	nodeA, peerIDA := startNodeWithRelays(t, []string{relayA.addr()}, nil, nil)
	nodeB, _ := startNodeWithRelays(t, []string{relayA.addr()}, nil, nil)

	namespace := nodeA.Namespace()
	waitForRendezvousRegister(t, nodeA, namespace, 10*time.Second)
	waitForDiscoverablePeer(t, nodeB, namespace, peerIDA, 10*time.Second)

	time.Sleep(4 * time.Second)

	// RED in Phase 0: this currently fails because the personal namespace is
	// only auto-registered once at startup and is not refreshed before TTL.
	waitForDiscoverablePeer(t, nodeB, namespace, peerIDA, 3*time.Second)
}

func TestPersonalNamespaceRefresh_StopPreventsFurtherReRegistration(t *testing.T) {
	relayA, _ := startLocalRelayPairWithRegistrationTTL(t, 3)

	nodeA, peerIDA := startNodeWithRelays(t, []string{relayA.addr()}, nil, nil)
	nodeB, _ := startNodeWithRelays(t, []string{relayA.addr()}, nil, nil)

	namespace := nodeA.Namespace()
	waitForRendezvousRegister(t, nodeA, namespace, 10*time.Second)
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
