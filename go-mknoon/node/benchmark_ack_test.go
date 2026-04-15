package node

import (
	"testing"
	"time"
)

func TestBenchmark_DirectAck_FastConfirm(t *testing.T) {
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

	// Connect A → B using DialPeer (the tested pattern)
	peerIDB := nodeB.PeerId()
	var addrsB []string
	for _, a := range nodeB.Host().Addrs() {
		addrsB = append(addrsB, a.String())
	}
	err = nodeA.DialPeer(peerIDB, addrsB)
	if err != nil {
		t.Fatalf("connect A→B: %v", err)
	}

	// Send with timeout — measure ack response time
	start := time.Now()
	_, acked, err := nodeA.SendMessage(peerIDB, `{"test":"ack_benchmark"}`, 2000)
	elapsed := time.Since(start)

	if err != nil {
		t.Logf("SendMessage returned error: %v", err)
	}
	t.Logf("[BENCHMARK] direct_send_elapsed_ms = %d, acked = %v", elapsed.Milliseconds(), acked)

	// Check for ack timing events
	ackEvents := collectorA.collectEvents("message:direct_ack_timing")
	t.Logf("BENCHMARK: %d direct_ack_timing events", len(ackEvents))
	for _, ev := range ackEvents {
		if ackMs, ok := ev["ackMs"].(float64); ok {
			t.Logf("  ackMs = %.0fms", ackMs)
		}
	}
}

func TestBenchmark_DirectAck_MultipleMessages(t *testing.T) {
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

	peerIDB := nodeB.PeerId()
	var addrsB2 []string
	for _, a := range nodeB.Host().Addrs() {
		addrsB2 = append(addrsB2, a.String())
	}
	err = nodeA.DialPeer(peerIDB, addrsB2)
	if err != nil {
		t.Fatalf("connect A→B: %v", err)
	}

	var timings []int

	for i := 0; i < 10; i++ {
		start := time.Now()
		_, _, err := nodeA.SendMessage(peerIDB, `{"test":"ack_multi","i":`+string(rune('0'+i))+`}`, 2000)
		elapsed := int(time.Since(start).Milliseconds())
		if err != nil {
			t.Logf("Send %d error: %v", i, err)
		}
		timings = append(timings, elapsed)
	}

	if len(timings) > 0 {
		sorted := make([]int, len(timings))
		copy(sorted, timings)
		p50 := benchmarkPercentile(sorted, 50)
		p95 := benchmarkPercentile(sorted, 95)
		t.Logf("[BENCHMARK] direct_send_ms p50=%dms p95=%dms (n=%d)", p50, p95, len(sorted))
	}
}
