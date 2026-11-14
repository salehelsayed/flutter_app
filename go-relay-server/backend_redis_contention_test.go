package main

import (
	"errors"
	"fmt"
	"strings"
	"sync"
	"testing"
	"time"

	"github.com/alicebob/miniredis/v2"
	"github.com/redis/go-redis/v9"
)

func TestRedisInboxBackend_ConcurrentStoreAckContention(t *testing.T) {
	const rounds, seeded, stores = 20, 32, 64
	server := miniredis.RunT(t)
	storeClient := newTestRedisClient(t, server)
	ackClient := newTestRedisClient(t, server)
	storeConflicts, ackConflicts := 0, 0
	started := time.Now()

	for round := range rounds {
		prefix := fmt.Sprintf("store-ack-contention:%d:", round)
		writer := newRedisInboxBackend(storeClient, prefix, 100)
		receiver := newRedisInboxBackend(ackClient, prefix, 100)
		const recipient = "same-recipient"
		now := time.Now().UnixMilli()
		for i := range seeded {
			requireRedisInboxStoreResult(t, writer, recipient, inboxMessage{
				ID: fmt.Sprintf("seed-%d", i), From: "earlier-sender",
				Message: strings.Repeat("s", 256), Timestamp: now,
			}, InboxStoreResultStored)
		}

		storeErrors := make([]error, stores)
		storeResults := make([]InboxStoreResult, stores)
		ackErrors := make([]error, seeded)
		ackRemoved := make([]int, seeded)
		start := make(chan struct{})
		var workers sync.WaitGroup
		workers.Add(2)
		go func() {
			defer workers.Done()
			<-start
			for i := range stores {
				storeResults[i], storeErrors[i] = writer.Store(recipient, inboxMessage{
					ID: fmt.Sprintf("new-%d", i), From: "current-sender",
					Message: strings.Repeat("n", 256), Timestamp: now,
				})
			}
		}()
		go func() {
			defer workers.Done()
			<-start
			for i := range seeded {
				ackRemoved[i], ackErrors[i] = receiver.Ack(recipient, []string{fmt.Sprintf("seed-%d", i)})
			}
		}()
		close(start)
		workers.Wait()

		pending, hasMore := writer.RetrievePending(recipient, 100)
		if hasMore {
			t.Fatal("bounded inbox unexpectedly has another page")
		}
		present := make(map[string]bool, len(pending))
		for _, entry := range pending {
			if present[entry.ID] {
				t.Fatalf("duplicate retained relay ID %q", entry.ID)
			}
			present[entry.ID] = true
		}
		stored, removed := 0, 0
		roundStoreConflicts, roundAckConflicts := 0, 0
		for i, err := range storeErrors {
			if err != nil {
				if !errors.Is(err, redis.TxFailedErr) {
					t.Fatalf("Store returned a non-conflict error: %v", err)
				}
				roundStoreConflicts++
				if storeResults[i] == InboxStoreResultStored || present[fmt.Sprintf("new-%d", i)] {
					t.Fatal("failed Store claimed success or committed its row")
				}
				continue
			}
			stored++
			if storeResults[i] != InboxStoreResultStored || !present[fmt.Sprintf("new-%d", i)] {
				t.Fatal("successful Store lost its row")
			}
		}
		for i, err := range ackErrors {
			if err != nil {
				if !errors.Is(err, redis.TxFailedErr) {
					t.Fatalf("Ack returned a non-conflict error: %v", err)
				}
				roundAckConflicts++
				if ackRemoved[i] != 0 || !present[fmt.Sprintf("seed-%d", i)] {
					t.Fatal("failed Ack claimed removal or removed its row")
				}
				continue
			}
			removed += ackRemoved[i]
			if ackRemoved[i] != 1 || present[fmt.Sprintf("seed-%d", i)] {
				t.Fatal("successful Ack did not remove exactly its row")
			}
		}
		if len(pending) != seeded+stored-removed {
			t.Fatalf("pending=%d, want seeded+stored-acked=%d", len(pending), seeded+stored-removed)
		}
		storeConflicts += roundStoreConflicts
		ackConflicts += roundAckConflicts
		t.Logf("burst=%d stores=%d/%d acks=%d/%d exhausted_store=%d exhausted_ack=%d pending=%d", round, stored, stores, removed, seeded, roundStoreConflicts, roundAckConflicts, len(pending))
	}
	t.Logf("rounds=%d store_attempts=%d ack_attempts=%d store_exhausted=%d ack_exhausted=%d elapsed=%s", rounds, rounds*stores, rounds*seeded, storeConflicts, ackConflicts, time.Since(started))
	if storeConflicts+ackConflicts > 0 {
		t.Fatalf("bounded two-worker Store/Ack burst exhausted WATCH retries: stores=%d acks=%d", storeConflicts, ackConflicts)
	}
}
