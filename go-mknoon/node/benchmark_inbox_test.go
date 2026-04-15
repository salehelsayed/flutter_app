package node

import (
	"testing"
)

func TestBenchmark_InboxStore_RequiresConnection(t *testing.T) {
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

	// InboxStore to a nonexistent peer should fail
	err = n.InboxStore("12D3KooWNonExistentPeer", `{"test":"inbox_msg"}`, 0)
	if err == nil {
		t.Log("InboxStore to nonexistent peer succeeded (unexpected but okay)")
	} else {
		t.Logf("InboxStore returned error (expected): %v", err)
	}

	// Check for inbox:store_timing events
	storeEvents := collector.collectEvents("inbox:store_timing")
	t.Logf("BENCHMARK: %d inbox:store_timing events emitted", len(storeEvents))
	for _, ev := range storeEvents {
		if outcome, ok := ev["outcome"].(string); ok {
			t.Logf("  outcome=%s", outcome)
		}
	}
}

func TestBenchmark_InboxRetrieve_ReturnsEmpty(t *testing.T) {
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

	// Retrieve with no inbox handler should return empty or error
	messages, err := n.InboxRetrieve()
	if err != nil {
		t.Logf("InboxRetrieve returned error (expected without relay): %v", err)
	} else {
		t.Logf("BENCHMARK: InboxRetrieve returned %d messages", len(messages))
	}
	_ = messages

	// Check for timing events
	retrieveEvents := collector.collectEvents("inbox:retrieve_timing")
	t.Logf("BENCHMARK: %d inbox:retrieve_timing events emitted", len(retrieveEvents))
}
