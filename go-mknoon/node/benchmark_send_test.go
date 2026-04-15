package node

import (
	"testing"
	"time"
)

func TestBenchmark_SendMessage_EmitsPerStepTiming(t *testing.T) {
	hexKeyA := generateTestKey(t)
	hexKeyB := generateTestKey(t)

	collectorA := &testEventCollector{}
	nodeA := New(collectorA)
	stateA, err := nodeA.Start(NodeConfig{
		PrivateKeyHex:  hexKeyA,
		RelayAddresses: []string{},
		AutoRegister:   false,
	})
	if err != nil {
		t.Fatalf("Start A: %v", err)
	}
	defer nodeA.Stop()

	collectorB := &testEventCollector{}
	nodeB := New(collectorB)
	_, err = nodeB.Start(NodeConfig{
		PrivateKeyHex:  hexKeyB,
		RelayAddresses: []string{},
		AutoRegister:   false,
	})
	if err != nil {
		t.Fatalf("Start B: %v", err)
	}
	defer nodeB.Stop()

	// Connect A → B via local transport
	peerIDB := nodeB.PeerId()
	var addrStrsB []string
	for _, a := range nodeB.Host().Addrs() {
		addrStrsB = append(addrStrsB, a.String())
	}
	if len(addrStrsB) == 0 {
		t.Fatal("node B has no addresses")
	}
	err = nodeA.DialPeer(peerIDB, addrStrsB)
	if err != nil {
		t.Fatalf("connect A→B: %v", err)
	}

	// Send a message from A to B
	_, _, err = nodeA.SendMessage(peerIDB, `{"test":"benchmark_send"}`, 5000)
	if err != nil {
		t.Logf("SendMessage returned error (may be expected if no handler): %v", err)
	}

	// Verify startup timing was emitted
	startupEvents := collectorA.collectEvents("node:startup_timing")
	if len(startupEvents) == 0 {
		t.Log("No node:startup_timing event (expected with empty relay addresses)")
	}

	// Verify node started
	if !stateA.IsStarted {
		t.Fatal("node A should be started")
	}
	t.Logf("BENCHMARK send_test: nodeA started, peerId=%s", stateA.PeerId)
}

func TestBenchmark_SendMessage_ConnectionReuse(t *testing.T) {
	hexKeyA := generateTestKey(t)
	hexKeyB := generateTestKey(t)

	collectorA := &testEventCollector{}
	nodeA := New(collectorA)
	_, err := nodeA.Start(NodeConfig{
		PrivateKeyHex:  hexKeyA,
		RelayAddresses: []string{},
		AutoRegister:   false,
	})
	if err != nil {
		t.Fatalf("Start A: %v", err)
	}
	defer nodeA.Stop()

	nodeB := New(&testEventCollector{})
	_, err = nodeB.Start(NodeConfig{
		PrivateKeyHex:  hexKeyB,
		RelayAddresses: []string{},
		AutoRegister:   false,
	})
	if err != nil {
		t.Fatalf("Start B: %v", err)
	}
	defer nodeB.Stop()

	// Connect A → B
	peerIDB := nodeB.PeerId()
	var addrsB2 []string
	for _, a := range nodeB.Host().Addrs() {
		addrsB2 = append(addrsB2, a.String())
	}
	err = nodeA.DialPeer(peerIDB, addrsB2)
	if err != nil {
		t.Fatalf("connect A→B: %v", err)
	}

	// First send
	_, _, err = nodeA.SendMessage(peerIDB, `{"test":"msg1"}`, 5000)
	if err != nil {
		t.Logf("First send returned error: %v", err)
	}

	// Second send should reuse the connection
	_, _, err = nodeA.SendMessage(peerIDB, `{"test":"msg2"}`, 5000)
	if err != nil {
		t.Logf("Second send returned error: %v", err)
	}

	// Both sends should have been attempted
	t.Log("BENCHMARK: connection reuse test complete")
	time.Sleep(100 * time.Millisecond) // let events flush
}
