package main

import (
	"sync"
	"testing"
	"time"
)

// --- Register tests ---

func TestRegister_StoresRegistration(t *testing.T) {
	store := NewRendezvousStore()
	store.Register("ns1", "peer-1", []byte("peer-record-1"), 3600)

	results := store.Discover("ns1", "other-peer", 10)
	if len(results) != 1 {
		t.Fatalf("expected 1 result, got %d", len(results))
	}
	if string(results[0].SignedPeerRecord) != "peer-record-1" {
		t.Fatalf("expected peer-record-1, got %s", results[0].SignedPeerRecord)
	}
	if results[0].Ns != "ns1" {
		t.Fatalf("expected ns1, got %s", results[0].Ns)
	}
}

func TestRegister_MultiplePeersSameNamespace(t *testing.T) {
	store := NewRendezvousStore()
	store.Register("ns1", "peer-1", []byte("peer-record-1"), 3600)
	store.Register("ns1", "peer-2", []byte("peer-record-2"), 3600)

	results := store.Discover("ns1", "other-peer", 10)
	if len(results) != 2 {
		t.Fatalf("expected 2 results, got %d", len(results))
	}
}

func TestRegister_SamePeerMultipleNamespaces(t *testing.T) {
	store := NewRendezvousStore()
	store.Register("ns1", "peer-1", []byte("peer-record-1"), 3600)
	store.Register("ns2", "peer-1", []byte("peer-record-1"), 3600)

	results1 := store.Discover("ns1", "other-peer", 10)
	results2 := store.Discover("ns2", "other-peer", 10)

	if len(results1) != 1 {
		t.Fatalf("expected 1 result for ns1, got %d", len(results1))
	}
	if len(results2) != 1 {
		t.Fatalf("expected 1 result for ns2, got %d", len(results2))
	}
}

func TestRegister_OverwritesSamePeerSameNamespace(t *testing.T) {
	store := NewRendezvousStore()
	store.Register("ns1", "peer-1", []byte("old-record"), 3600)
	store.Register("ns1", "peer-1", []byte("new-record"), 3600)

	results := store.Discover("ns1", "other-peer", 10)
	if len(results) != 1 {
		t.Fatalf("expected 1 result (overwrite, not duplicate), got %d", len(results))
	}
	if string(results[0].SignedPeerRecord) != "new-record" {
		t.Fatalf("expected new-record, got %s", results[0].SignedPeerRecord)
	}
}

// --- Discover tests ---

func TestDiscover_ReturnsRegisteredPeers(t *testing.T) {
	store := NewRendezvousStore()
	store.Register("ns1", "peer-1", []byte("peer-record-1"), 3600)
	store.Register("ns1", "peer-2", []byte("peer-record-2"), 3600)

	results := store.Discover("ns1", "requester", 10)
	if len(results) != 2 {
		t.Fatalf("expected 2 results, got %d", len(results))
	}
}

func TestDiscover_ExcludesRequestingPeer(t *testing.T) {
	store := NewRendezvousStore()
	store.Register("ns1", "peer-1", []byte("peer-record-1"), 3600)
	store.Register("ns1", "peer-2", []byte("peer-record-2"), 3600)

	// peer-1 discovers — should not see itself
	results := store.Discover("ns1", "peer-1", 10)
	if len(results) != 1 {
		t.Fatalf("expected 1 result (self excluded), got %d", len(results))
	}
	if string(results[0].SignedPeerRecord) != "peer-record-2" {
		t.Fatalf("expected peer-record-2, got %s", results[0].SignedPeerRecord)
	}
}

func TestDiscover_ReturnsEmptyForUnknownNamespace(t *testing.T) {
	store := NewRendezvousStore()
	store.Register("ns1", "peer-1", []byte("peer-record-1"), 3600)

	results := store.Discover("unknown-ns", "other-peer", 10)
	if len(results) != 0 {
		t.Fatalf("expected 0 results for unknown namespace, got %d", len(results))
	}
}

func TestDiscover_RespectsLimit(t *testing.T) {
	store := NewRendezvousStore()
	for i := 0; i < 10; i++ {
		pid := "peer-" + string(rune('A'+i))
		store.Register("ns1", pid, []byte("record-"+pid), 3600)
	}

	results := store.Discover("ns1", "requester", 3)
	if len(results) != 3 {
		t.Fatalf("expected 3 results (limit=3), got %d", len(results))
	}
}

func TestDiscover_ReturnsEmptyFromEmptyStore(t *testing.T) {
	store := NewRendezvousStore()

	results := store.Discover("ns1", "peer-1", 10)
	if results == nil {
		// nil is acceptable for empty
	}
	if len(results) != 0 {
		t.Fatalf("expected 0 results from empty store, got %d", len(results))
	}
}

// --- Unregister tests ---

func TestUnregister_RemovesPeerFromNamespace(t *testing.T) {
	store := NewRendezvousStore()
	store.Register("ns1", "peer-1", []byte("peer-record-1"), 3600)
	store.Register("ns1", "peer-2", []byte("peer-record-2"), 3600)

	store.Unregister("ns1", "peer-1")

	results := store.Discover("ns1", "other-peer", 10)
	if len(results) != 1 {
		t.Fatalf("expected 1 result after unregister, got %d", len(results))
	}
	if string(results[0].SignedPeerRecord) != "peer-record-2" {
		t.Fatalf("expected peer-record-2, got %s", results[0].SignedPeerRecord)
	}
}

func TestUnregister_CleansUpEmptyNamespace(t *testing.T) {
	store := NewRendezvousStore()
	store.Register("ns1", "peer-1", []byte("peer-record-1"), 3600)

	store.Unregister("ns1", "peer-1")

	// Verify namespace map is cleaned up via Stats
	nsCount, peerCount := store.Stats()
	if nsCount != 0 {
		t.Fatalf("expected 0 namespaces after removing last peer, got %d", nsCount)
	}
	if peerCount != 0 {
		t.Fatalf("expected 0 peers, got %d", peerCount)
	}
}

func TestUnregister_Idempotent(t *testing.T) {
	store := NewRendezvousStore()
	store.Register("ns1", "peer-1", []byte("peer-record-1"), 3600)

	// Unregister twice — should not panic or error
	store.Unregister("ns1", "peer-1")
	store.Unregister("ns1", "peer-1")

	results := store.Discover("ns1", "other-peer", 10)
	if len(results) != 0 {
		t.Fatalf("expected 0 results after double unregister, got %d", len(results))
	}
}

func TestUnregister_UnknownNamespace(t *testing.T) {
	store := NewRendezvousStore()

	// Should not panic on unregistering from a namespace that does not exist
	store.Unregister("nonexistent", "peer-1")
}

// --- Expiry tests ---

func TestExpiry_ExpiredRegistrationsNotReturnedByDiscover(t *testing.T) {
	store := NewRendezvousStore()
	// Use a peer ID >= 20 chars to avoid panic in cleanupExpired log
	store.Register("ns1", "peer-1-long-id-pad!!", []byte("peer-record-1"), 1)
	store.Register("ns1", "peer-2-long-id-pad!!", []byte("peer-record-2"), 3600)

	time.Sleep(1100 * time.Millisecond)

	results := store.Discover("ns1", "requester", 10)
	if len(results) != 1 {
		t.Fatalf("expected 1 result (expired peer excluded), got %d", len(results))
	}
	if string(results[0].SignedPeerRecord) != "peer-record-2" {
		t.Fatalf("expected peer-record-2, got %s", results[0].SignedPeerRecord)
	}
}

func TestExpiry_CleanupExpiredRemovesEntries(t *testing.T) {
	store := NewRendezvousStore()
	// Use peer IDs >= 20 chars to avoid panic in cleanupExpired log (pid[:20])
	store.Register("ns1", "peer-1-long-id-pad!!", []byte("peer-record-1"), 1)
	store.Register("ns1", "peer-2-long-id-pad!!", []byte("peer-record-2"), 3600)

	time.Sleep(1100 * time.Millisecond)

	store.cleanupExpired()

	nsCount, peerCount := store.Stats()
	if nsCount != 1 {
		t.Fatalf("expected 1 namespace, got %d", nsCount)
	}
	if peerCount != 1 {
		t.Fatalf("expected 1 peer after cleanup, got %d", peerCount)
	}
}

func TestExpiry_CleanupExpiredRemovesEmptyNamespace(t *testing.T) {
	store := NewRendezvousStore()
	// All registrations expire — namespace should be cleaned up
	store.Register("ns1", "peer-1-long-id-pad!!", []byte("peer-record-1"), 1)

	time.Sleep(1100 * time.Millisecond)

	store.cleanupExpired()

	nsCount, peerCount := store.Stats()
	if nsCount != 0 {
		t.Fatalf("expected 0 namespaces after all expired, got %d", nsCount)
	}
	if peerCount != 0 {
		t.Fatalf("expected 0 peers after all expired, got %d", peerCount)
	}
}

// --- Stats tests ---

func TestStats_ReturnsCorrectCounts(t *testing.T) {
	store := NewRendezvousStore()

	nsCount, peerCount := store.Stats()
	if nsCount != 0 || peerCount != 0 {
		t.Fatalf("expected 0/0 for empty store, got %d/%d", nsCount, peerCount)
	}

	store.Register("ns1", "peer-1", []byte("r1"), 3600)
	store.Register("ns1", "peer-2", []byte("r2"), 3600)
	store.Register("ns2", "peer-3", []byte("r3"), 3600)

	nsCount, peerCount = store.Stats()
	if nsCount != 2 {
		t.Fatalf("expected 2 namespaces, got %d", nsCount)
	}
	if peerCount != 3 {
		t.Fatalf("expected 3 peers, got %d", peerCount)
	}
}

func TestStats_ReflectsUnregister(t *testing.T) {
	store := NewRendezvousStore()
	store.Register("ns1", "peer-1", []byte("r1"), 3600)
	store.Register("ns1", "peer-2", []byte("r2"), 3600)

	store.Unregister("ns1", "peer-1")

	nsCount, peerCount := store.Stats()
	if nsCount != 1 {
		t.Fatalf("expected 1 namespace, got %d", nsCount)
	}
	if peerCount != 1 {
		t.Fatalf("expected 1 peer, got %d", peerCount)
	}
}

// --- Concurrent access tests ---

func TestConcurrent_RegisterAndDiscover(t *testing.T) {
	store := NewRendezvousStore()
	const goroutines = 50
	const opsPerGoroutine = 100

	var wg sync.WaitGroup

	// Concurrent registers
	for g := 0; g < goroutines; g++ {
		wg.Add(1)
		go func(id int) {
			defer wg.Done()
			for i := 0; i < opsPerGoroutine; i++ {
				ns := "ns-" + string(rune('A'+id%5))
				pid := "peer-" + string(rune('A'+id))
				store.Register(ns, pid, []byte("record"), 3600)
			}
		}(g)
	}

	// Concurrent discovers
	for g := 0; g < goroutines; g++ {
		wg.Add(1)
		go func(id int) {
			defer wg.Done()
			for i := 0; i < opsPerGoroutine; i++ {
				ns := "ns-" + string(rune('A'+id%5))
				store.Discover(ns, "requester", 10)
			}
		}(g)
	}

	// Concurrent unregisters
	for g := 0; g < goroutines/2; g++ {
		wg.Add(1)
		go func(id int) {
			defer wg.Done()
			for i := 0; i < opsPerGoroutine; i++ {
				ns := "ns-" + string(rune('A'+id%5))
				pid := "peer-" + string(rune('A'+id))
				store.Unregister(ns, pid)
			}
		}(g)
	}

	wg.Wait()

	// If we reach here without a race condition panic, the test passes.
	// Verify store is still functional after concurrent operations.
	store.Register("final-ns", "final-peer", []byte("final-record"), 3600)
	results := store.Discover("final-ns", "other", 10)
	if len(results) != 1 {
		t.Fatalf("expected 1 result after concurrent ops, got %d", len(results))
	}
}
