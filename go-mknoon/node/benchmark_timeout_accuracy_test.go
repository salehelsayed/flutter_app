package node

import (
	"testing"
	"time"
)

func TestBenchmark_Timeout_NodeStartWithBadRelay(t *testing.T) {
	hexKey := generateTestKey(t)

	collector := &testEventCollector{}
	n := New(collector)
	_, err := n.Start(NodeConfig{
		PrivateKeyHex:  hexKey,
		RelayAddresses: []string{}, // empty = no relay timeout
		AutoRegister:   false,
	})
	if err != nil {
		t.Fatalf("Start: %v", err)
	}
	defer n.Stop()

	// With empty relays, no timeout events should fire
	timeoutEvents := collector.collectEvents("timeout:fired")
	t.Logf("BENCHMARK: %d timeout:fired events (expected 0 with empty relays)", len(timeoutEvents))
}

func TestBenchmark_Timeout_SendToUnreachablePeer(t *testing.T) {
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

	// Send to unreachable peer with short timeout
	start := time.Now()
	_, _, err = n.SendMessage("12D3KooWUnreachablePeer", `{"test":"timeout"}`, 1000)
	elapsed := time.Since(start)

	if err != nil {
		t.Logf("SendMessage to unreachable peer returned error (expected): %v", err)
	}

	t.Logf("[BENCHMARK] send_unreachable_actual_ms = %dms (timeout=1000ms)", elapsed.Milliseconds())
}

func TestBenchmark_Timeout_DirectAckTimeout(t *testing.T) {
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

	// Check for any message:direct_ack_timing events
	ackEvents := collector.collectEvents("message:direct_ack_timing")
	t.Logf("BENCHMARK: %d direct_ack_timing events", len(ackEvents))
}
