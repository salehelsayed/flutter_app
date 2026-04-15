package node

import (
	"testing"
	"time"
)

func TestBenchmark_EventQueue_IdleDelivery(t *testing.T) {
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

	// Emit some events and verify they arrive quickly
	for i := 0; i < 20; i++ {
		n.emitEvent("benchmark:test_event", map[string]interface{}{
			"iteration": i,
			"timestamp": time.Now().UnixMilli(),
		})
	}

	// Brief wait for async event delivery
	time.Sleep(100 * time.Millisecond)

	events := collector.collectEvents("benchmark:test_event")
	if len(events) != 20 {
		t.Fatalf("expected 20 events, got %d", len(events))
	}

	t.Logf("[BENCHMARK] event_queue_idle_delivery_count = %d/20", len(events))
}

func TestBenchmark_EventQueue_BurstDelivery(t *testing.T) {
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

	// Burst 100 events
	start := time.Now()
	for i := 0; i < 100; i++ {
		n.emitEvent("benchmark:burst_event", map[string]interface{}{
			"iteration": i,
		})
	}
	emitDuration := time.Since(start)

	// Wait for all to be delivered
	time.Sleep(200 * time.Millisecond)

	events := collector.collectEvents("benchmark:burst_event")
	t.Logf("[BENCHMARK] event_queue_burst: emitted 100 events in %dms, delivered %d",
		emitDuration.Milliseconds(), len(events))

	if len(events) < 100 {
		t.Logf("Warning: only %d/100 events delivered (some may have been coalesced)", len(events))
	}
}

func TestBenchmark_EventQueue_NoDropUnderLoad(t *testing.T) {
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

	// Emit lossless events that should never be dropped
	for i := 0; i < 50; i++ {
		n.emitEvent("benchmark:lossless_event", map[string]interface{}{
			"index": i,
		})
	}

	time.Sleep(500 * time.Millisecond)

	events := collector.collectEvents("benchmark:lossless_event")
	if len(events) < 50 {
		t.Errorf("expected all 50 lossless events, got %d (dropped %d)", len(events), 50-len(events))
	}
	t.Logf("[BENCHMARK] event_queue_no_drop: %d/50 events delivered", len(events))
}
