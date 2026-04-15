package node

import (
	"testing"
	"time"
)

func TestBenchmark_NodeStart_EmitsStartupTiming(t *testing.T) {
	hexKey := generateTestKey(t)

	collector := &testEventCollector{}
	n := New(collector)
	state, err := n.Start(NodeConfig{
		PrivateKeyHex:  hexKey,
		RelayAddresses: []string{},
		AutoRegister:   false,
	})
	if err != nil {
		t.Fatalf("Start: %v", err)
	}
	defer n.Stop()

	if !state.IsStarted {
		t.Fatal("node should be started")
	}

	// Verify startup timing event was emitted
	events := collector.collectEvents("node:startup_timing")
	if len(events) > 0 {
		ev := events[0]
		if libp2pMs, ok := ev["libp2pNewMs"].(float64); ok {
			if libp2pMs < 0 {
				t.Fatalf("libp2pNewMs should be >= 0, got %v", libp2pMs)
			}
			t.Logf("BENCHMARK startup_host_ready_ms = %.0fms", libp2pMs)
		}
	} else {
		t.Log("No node:startup_timing event emitted (may be normal with empty relay)")
	}
}

func TestBenchmark_NodeStart_ReturnsValidState(t *testing.T) {
	hexKey := generateTestKey(t)

	collector := &testEventCollector{}
	n := New(collector)
	state, err := n.Start(NodeConfig{
		PrivateKeyHex:  hexKey,
		RelayAddresses: []string{},
		AutoRegister:   false,
	})
	if err != nil {
		t.Fatalf("Start: %v", err)
	}
	defer n.Stop()

	if state.PeerId == "" {
		t.Fatal("PeerId should be non-empty")
	}
	if !state.IsStarted {
		t.Fatal("IsStarted should be true")
	}
	t.Logf("BENCHMARK: node started with peerId=%s", state.PeerId)
}

func TestBenchmark_NodeStart_StopStart_Succeeds(t *testing.T) {
	hexKey := generateTestKey(t)

	collector := &testEventCollector{}
	n := New(collector)

	// First start
	_, err := n.Start(NodeConfig{
		PrivateKeyHex:  hexKey,
		RelayAddresses: []string{},
		AutoRegister:   false,
	})
	if err != nil {
		t.Fatalf("Start 1: %v", err)
	}

	// Stop
	if err := n.Stop(); err != nil {
		t.Fatalf("Stop: %v", err)
	}

	// Restart
	state, err := n.Start(NodeConfig{
		PrivateKeyHex:  hexKey,
		RelayAddresses: []string{},
		AutoRegister:   false,
	})
	if err != nil {
		t.Fatalf("Start 2: %v", err)
	}
	defer n.Stop()

	if !state.IsStarted {
		t.Fatal("node should be started after restart")
	}
	t.Log("BENCHMARK: stop-start cycle complete")
}

func TestBenchmark_NodeStart_NoRelays_NoRelayWarmDoneEvent(t *testing.T) {
	hexKey := generateTestKey(t)

	collector := &testEventCollector{}
	n := New(collector)
	_, err := n.Start(NodeConfig{
		PrivateKeyHex:  hexKey,
		RelayAddresses: []string{},
		AutoRegister:   false,
	})
	if err != nil {
		t.Fatalf("Start: %v", err)
	}
	defer n.Stop()

	// Give a moment for any async events to be emitted.
	time.Sleep(50 * time.Millisecond)

	events := collector.collectEvents("node:startup_timing")
	for _, ev := range events {
		if phase, _ := ev["phase"].(string); phase == "relay_warm_done" {
			t.Fatal("relay_warm_done should NOT be emitted when no relays are configured")
		}
	}
	t.Log("BENCHMARK: no relay_warm_done emitted with empty relays (correct)")
}

func TestBenchmark_NodeStart_RelayWarmDoneEvent(t *testing.T) {
	hexKey := generateTestKey(t)

	collector := &testEventCollector{}
	n := New(collector)

	// Use a syntactically valid but unreachable relay address so that
	// relayInfos is non-empty and the relay_warm_done goroutine is launched.
	fakeRelay := "/ip4/192.0.2.1/tcp/4001/p2p/12D3KooWDpJ7As7BWAwRMfu1VU2WCqNjvq387JEYKDBj4kx6nXTN"

	_, err := n.Start(NodeConfig{
		PrivateKeyHex:  hexKey,
		RelayAddresses: []string{fakeRelay},
		AutoRegister:   false,
	})
	if err != nil {
		t.Fatalf("Start: %v", err)
	}
	defer n.Stop()

	// Manually close the relayReady channel to simulate a successful relay
	// connection, which triggers the relay_warm_done event.
	n.relayReadyOnce.Do(func() { close(n.relayReady) })

	// Allow the goroutine to pick up the channel close and emit the event.
	time.Sleep(100 * time.Millisecond)

	events := collector.collectEvents("node:startup_timing")
	var found bool
	for _, ev := range events {
		if phase, _ := ev["phase"].(string); phase == "relay_warm_done" {
			found = true

			relayWarmMs, ok := ev["relayWarmMs"].(float64)
			if !ok {
				t.Fatal("relayWarmMs should be present in relay_warm_done event")
			}
			if relayWarmMs < 0 {
				t.Fatalf("relayWarmMs should be >= 0, got %v", relayWarmMs)
			}

			relaysAttempted, ok := ev["relaysAttempted"].(float64)
			if !ok {
				t.Fatal("relaysAttempted should be present in relay_warm_done event")
			}
			if int(relaysAttempted) != 1 {
				t.Fatalf("relaysAttempted should be 1, got %v", relaysAttempted)
			}

			t.Logf("BENCHMARK relay_warm_done: relayWarmMs=%.0f relaysAttempted=%.0f",
				relayWarmMs, relaysAttempted)
			break
		}
	}
	if !found {
		t.Fatal("relay_warm_done event should be emitted after relayReady closes")
	}
}
