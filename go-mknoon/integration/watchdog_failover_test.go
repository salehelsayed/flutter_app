//go:build integration

package integration_test

import (
	"testing"
	"time"

	"github.com/mknoon/go-mknoon/node"
)

func TestSecondRelayAvailablePreventsWatchdogRestart(t *testing.T) {
	relayA, relayB := startLocalRelayPair(t)
	relayAddrs := []string{relayA.addr(), relayB.addr()}

	nodeA, peerIDA := startNodeWithRelays(t, relayAddrs, nil, nil)
	nodeB, peerIDB := startNodeWithRelays(t, relayAddrs, nil, nil)

	waitForNodeStatus(t, nodeA, 10*time.Second, func(status map[string]interface{}) bool {
		return statusConnectionCount(status) >= 1
	})
	waitForNodeStatus(t, nodeB, 10*time.Second, func(status map[string]interface{}) bool {
		return statusConnectionCount(status) >= 1
	})

	relayA.stop()

	waitForNodeStatus(t, nodeA, 15*time.Second, func(status map[string]interface{}) bool {
		return statusInt(status, "watchdogRestartCount") == 0 &&
			statusString(status, "relayState") != "watchdog_restart"
	})

	namespace := randomNamespace()
	if err := nodeA.RendezvousRegister(namespace, nil); err != nil {
		t.Fatalf("RendezvousRegister after relayA loss: %v", err)
	}

	waitForDiscoverablePeer(t, nodeB, namespace, peerIDA, 15*time.Second)

	message := "hello through relayB after relayA loss"
	if err := nodeA.InboxStore(peerIDB, message); err != nil {
		t.Fatalf("InboxStore after relayA loss: %v", err)
	}

	waitForInboxMessage(t, nodeB, peerIDA, message, 15*time.Second)

	status := nodeA.Status()
	if got := statusInt(status, "watchdogRestartCount"); got != 0 {
		t.Fatalf("expected watchdogRestartCount=0, got %d", got)
	}
	if got := statusString(status, "relayState"); got == "watchdog_restart" {
		t.Fatalf("second relay should prevent watchdog restart, status=%+v", status)
	}
}

func TestAllRelaysUnavailableEnterDegradedStateAndRecover(t *testing.T) {
	relayA, relayB := startLocalRelayPair(t)
	relayAddrs := []string{relayA.addr(), relayB.addr()}

	n, peerID := startNodeWithRelays(t, relayAddrs, nil, nil)

	waitForNodeStatus(t, n, 10*time.Second, func(status map[string]interface{}) bool {
		return statusConnectionCount(status) >= 1
	})

	relayA.stop()
	relayB.stop()

	waitForNodeStatus(t, n, 20*time.Second, func(status map[string]interface{}) bool {
		return statusConnectionCount(status) == 0
	})

	result, err := n.ReconnectRelays()
	if err != nil {
		t.Fatalf("ReconnectRelays() with all relays down: %v", err)
	}
	if result.RecoveryMode != "watchdog_restart" {
		t.Fatalf("expected watchdog_restart fallback, got %+v", result)
	}
	if result.Success {
		t.Fatalf("expected watchdog fallback to remain unhealthy while all relays are down, got %+v", result)
	}

	statusAfterFallback := waitForNodeStatus(t, n, 5*time.Second, func(status map[string]interface{}) bool {
		return statusInt(status, "watchdogRestartCount") >= 1
	})
	if !statusBool(statusAfterFallback, "needsGroupRecovery") {
		t.Fatalf("watchdog restart should mark needsGroupRecovery, got %+v", statusAfterFallback)
	}

	relayB.start()
	nodePeer, peerIDPeer := startNodeWithRelays(t, []string{relayB.addr()}, nil, nil)

	namespace := randomNamespace()
	waitForRendezvousRegister(t, n, namespace, 15*time.Second)
	waitForDiscoverablePeer(t, nodePeer, namespace, peerID, 15*time.Second)

	message := "recovered after relayB returned"
	waitForInboxStore(t, n, peerIDPeer, message, 15*time.Second)
	waitForInboxMessage(t, nodePeer, peerID, message, 15*time.Second)

	status := n.Status()
	if got := statusInt(status, "watchdogRestartCount"); got < 1 {
		t.Fatalf("watchdog restart count should persist after recovery, got %+v", status)
	}
	if n.PeerId() != peerID {
		t.Fatalf("peerId changed across degraded/recovered cycle: got %s want %s", n.PeerId(), peerID)
	}
}

func TestRendezvousAndInboxStillWorkAfterRelayRestart(t *testing.T) {
	relayA, relayB := startLocalRelayPair(t)
	relayAddrs := []string{relayA.addr(), relayB.addr()}

	nodeA, peerIDA := startNodeWithRelays(t, relayAddrs, nil, nil)
	nodeB, peerIDB := startNodeWithRelays(t, relayAddrs, nil, nil)

	waitForNodeStatus(t, nodeA, 10*time.Second, func(status map[string]interface{}) bool {
		return statusConnectionCount(status) >= 1
	})
	waitForNodeStatus(t, nodeB, 10*time.Second, func(status map[string]interface{}) bool {
		return statusConnectionCount(status) >= 1
	})

	relayA.stop()

	namespaceWhileADown := randomNamespace()
	waitForRendezvousRegister(t, nodeA, namespaceWhileADown, 15*time.Second)
	waitForDiscoverablePeer(t, nodeB, namespaceWhileADown, peerIDA, 15*time.Second)

	msgWhileADown := "message via relayB while relayA is down"
	waitForInboxStore(t, nodeA, peerIDB, msgWhileADown, 15*time.Second)
	waitForInboxMessage(t, nodeB, peerIDA, msgWhileADown, 15*time.Second)

	relayA.start()
	relayB.stop()

	postRestartRelayAddrs := []string{relayA.addr()}
	nodeC, peerIDC := startNodeWithRelays(t, postRestartRelayAddrs, nil, nil)
	nodeD, peerIDD := startNodeWithRelays(t, postRestartRelayAddrs, nil, nil)

	namespaceAfterRestart := randomNamespace()
	waitForRendezvousRegister(t, nodeC, namespaceAfterRestart, 15*time.Second)
	waitForDiscoverablePeer(t, nodeD, namespaceAfterRestart, peerIDC, 15*time.Second)

	msgAfterRestart := "message via restarted relayA"
	waitForInboxStore(t, nodeC, peerIDD, msgAfterRestart, 15*time.Second)
	waitForInboxMessage(t, nodeD, peerIDC, msgAfterRestart, 15*time.Second)
}

func TestNodeStatusIncludesWatchdogMetrics(t *testing.T) {
	relayA, relayB := startLocalRelayPair(t)
	n, _ := startNodeWithRelays(t, []string{relayA.addr(), relayB.addr()}, nil, nil)

	status := waitForNodeStatus(t, n, 10*time.Second, func(status map[string]interface{}) bool {
		return statusConnectionCount(status) >= 1
	})

	if _, ok := status["watchdogRestartCount"]; !ok {
		t.Fatal("status should include watchdogRestartCount")
	}
	if _, ok := status["relayState"]; !ok {
		t.Fatal("status should include relayState")
	}
	if _, ok := status["healthyRelayCount"]; !ok {
		t.Fatal("status should include healthyRelayCount")
	}

	flags, ok := status["featureFlags"].(map[string]bool)
	if !ok {
		t.Fatalf("status should include featureFlags, got %T", status["featureFlags"])
	}
	if !flags["enableMultiRelayRouting"] {
		t.Fatal("enableMultiRelayRouting should be true by default")
	}
}

func waitForDiscoverablePeer(t *testing.T, n *node.Node, namespace, peerID string, timeout time.Duration) {
	t.Helper()

	deadline := time.Now().Add(timeout)
	for time.Now().Before(deadline) {
		peers, err := n.RendezvousDiscover(namespace, nil)
		if err == nil {
			for _, discovered := range peers {
				if discovered.ID.String() == peerID {
					return
				}
			}
		}
		time.Sleep(300 * time.Millisecond)
	}

	peers, err := n.RendezvousDiscover(namespace, nil)
	t.Fatalf("peer %s not discoverable on %s within %v (last err=%v peers=%v)", peerID, namespace, timeout, err, peers)
}

func waitForRendezvousRegister(t *testing.T, n *node.Node, namespace string, timeout time.Duration) {
	t.Helper()

	deadline := time.Now().Add(timeout)
	var lastErr error
	for time.Now().Before(deadline) {
		if err := n.RendezvousRegister(namespace, nil); err == nil {
			return
		} else {
			lastErr = err
		}
		time.Sleep(300 * time.Millisecond)
	}
	t.Fatalf("RendezvousRegister for %s did not succeed within %v: %v", namespace, timeout, lastErr)
}

func waitForInboxStore(t *testing.T, n *node.Node, toPeerID, message string, timeout time.Duration) {
	t.Helper()

	deadline := time.Now().Add(timeout)
	var lastErr error
	for time.Now().Before(deadline) {
		if err := n.InboxStore(toPeerID, message); err == nil {
			return
		} else {
			lastErr = err
		}
		time.Sleep(300 * time.Millisecond)
	}
	t.Fatalf("InboxStore to %s did not succeed within %v: %v", toPeerID, timeout, lastErr)
}

func waitForInboxMessage(t *testing.T, n *node.Node, fromPeerID, message string, timeout time.Duration) {
	t.Helper()

	deadline := time.Now().Add(timeout)
	for time.Now().Before(deadline) {
		messages, err := n.InboxRetrieve()
		if err == nil {
			for _, inboxMessage := range messages {
				if inboxMessage.From == fromPeerID && inboxMessage.Message == message {
					return
				}
			}
		}
		time.Sleep(300 * time.Millisecond)
	}

	messages, err := n.InboxRetrieve()
	t.Fatalf("message %q from %s not retrieved within %v (last err=%v messages=%v)", message, fromPeerID, timeout, err, messages)
}

func statusInt(status map[string]interface{}, key string) int {
	switch value := status[key].(type) {
	case int:
		return value
	case int32:
		return int(value)
	case int64:
		return int(value)
	case float64:
		return int(value)
	default:
		return 0
	}
}

func statusString(status map[string]interface{}, key string) string {
	value, _ := status[key].(string)
	return value
}

func statusBool(status map[string]interface{}, key string) bool {
	value, _ := status[key].(bool)
	return value
}

func statusConnectionCount(status map[string]interface{}) int {
	switch value := status["connections"].(type) {
	case []map[string]interface{}:
		return len(value)
	case []interface{}:
		return len(value)
	default:
		return 0
	}
}
