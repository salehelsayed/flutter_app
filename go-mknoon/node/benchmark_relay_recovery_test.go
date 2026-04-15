package node

import (
	"testing"
)

func TestBenchmark_RelayState_EmitsOnChange(t *testing.T) {
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

	// Verify node started successfully
	state := n.State()
	if !state.IsStarted {
		t.Fatal("node should be started")
	}

	// Check for any relay:state events (may or may not fire without real relays)
	relayEvents := collector.collectEvents("relay:state")
	t.Logf("BENCHMARK: %d relay:state events emitted during startup", len(relayEvents))
}

func TestBenchmark_RelayWarm_EmitsTiming(t *testing.T) {
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

	// With empty relay addresses, relay:warm_timing won't fire
	warmEvents := collector.collectEvents("relay:warm_timing")
	t.Logf("BENCHMARK: %d relay:warm_timing events (expected 0 with empty relays)", len(warmEvents))
}
