package main

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"sync"
	"testing"
	"time"

	"github.com/alicebob/miniredis/v2"
)

func ackCustodyTextEnvelope(id, sender, ciphertext string) string {
	return fmt.Sprintf(
		`{"type":"chat_message","version":"2","id":%q,"senderPeerId":%q,"encrypted":{"kem":"kem","ciphertext":%q,"nonce":"nonce"}}`,
		id,
		sender,
		ciphertext,
	)
}

func ackCustodyReactionEnvelope(id, action, target, sender, ciphertext string) string {
	return fmt.Sprintf(
		`{"type":"message_reaction","version":"2","eventId":%q,"action":%q,"targetMessageId":%q,"senderPeerId":%q,"encrypted":{"kem":"kem","ciphertext":%q,"nonce":"nonce"}}`,
		id,
		action,
		target,
		sender,
		ciphertext,
	)
}

func ackCustodyEditEnvelope(target, event, sender, ciphertext string) string {
	return fmt.Sprintf(
		`{"type":"chat_message","version":"2","id":%q,"eventId":%q,"senderPeerId":%q,"encrypted":{"kem":"kem","ciphertext":%q,"nonce":"nonce"}}`,
		target,
		event,
		sender,
		ciphertext,
	)
}

func ackCustodyDeletionEnvelope(event, sender, ciphertext string) string {
	return fmt.Sprintf(
		`{"type":"message_deletion","version":"2","eventId":%q,"senderPeerId":%q,"encrypted":{"kem":"kem","ciphertext":%q,"nonce":"nonce"}}`,
		event,
		sender,
		ciphertext,
	)
}

func newAckCustodyRedisBackend(
	t *testing.T,
	server *miniredis.Miniredis,
	prefix string,
	capacity int,
) *redisInboxBackend {
	t.Helper()
	return newRedisInboxBackend(newTestRedisClient(t, server), prefix, capacity)
}

func requireAckCustodyBackendStore(
	t *testing.T,
	backend *redisInboxBackend,
	peerID string,
	entry inboxMessage,
	dedupeKey string,
	want InboxStoreResult,
) inboxMessage {
	t.Helper()
	result, stored, err := backend.StoreAckCustody(peerID, entry, dedupeKey)
	if err != nil {
		t.Fatalf("StoreAckCustody() error: %v", err)
	}
	if result != want {
		t.Fatalf("StoreAckCustody() result = %q, want %q", result, want)
	}
	return stored
}

func redisInboxMessagesForKey(
	t *testing.T,
	backend *redisInboxBackend,
	key string,
) []inboxMessage {
	t.Helper()
	raw, err := backend.client.LRange(context.Background(), key, 0, -1).Result()
	if err != nil {
		t.Fatalf("LRange(%q): %v", key, err)
	}
	messages := make([]inboxMessage, 0, len(raw))
	for _, payload := range raw {
		var message inboxMessage
		if err := json.Unmarshal([]byte(payload), &message); err != nil {
			t.Fatalf("decode %q: %v", key, err)
		}
		messages = append(messages, message)
	}
	return messages
}

func assertAtomicShadowPair(
	t *testing.T,
	backend *redisInboxBackend,
	peerID string,
	want inboxMessage,
) {
	t.Helper()
	protected := redisInboxMessagesForKey(t, backend, backend.ackCustodyKey(peerID))
	legacy := redisInboxMessagesForKey(t, backend, backend.key(peerID))
	if len(protected) != 1 || len(legacy) != 1 {
		t.Fatalf("physical copies = protected:%d legacy:%d, want 1/1", len(protected), len(legacy))
	}
	for lane, got := range map[string]inboxMessage{
		"protected": protected[0],
		"legacy":    legacy[0],
	} {
		if got.ID != want.ID || got.Timestamp != want.Timestamp ||
			got.From != want.From || got.Message != want.Message {
			t.Fatalf("%s copy = %#v, want exact %#v", lane, got, want)
		}
	}
}

func TestRelayNotificationClosure_AckCustodyBackendContract(t *testing.T) {
	t.Run("redis", func(t *testing.T) {
		server := miniredis.RunT(t)
		backend := newAckCustodyRedisBackend(t, server, "ack-backend:", 2)
		peerID := "peer-recipient"
		envelope := ackCustodyTextEnvelope("text-1", "peer-sender", "cipher-1")
		entry := inboxMessage{
			ID:        "relay-1",
			From:      "peer-sender",
			Message:   envelope,
			Timestamp: time.Now().UnixMilli(),
		}
		stored := requireAckCustodyBackendStore(
			t,
			backend,
			peerID,
			entry,
			directInboxTargetIDDedupePrefix+"text-1",
			InboxStoreResultStored,
		)
		assertAtomicShadowPair(t, backend, peerID, stored)
		if backend.CountAckCustody(peerID) != 1 || backend.Count(peerID) != 1 {
			t.Fatal("expected one authoritative row and one legacy shadow")
		}
	})

	t.Run("duplicate_at_full_preserves_expiry", func(t *testing.T) {
		server := miniredis.RunT(t)
		backend := newAckCustodyRedisBackend(t, server, "ack-full:", 1)
		peerID := "peer-recipient"
		envelope := ackCustodyTextEnvelope("text-1", "peer-sender", "cipher-1")
		original := inboxMessage{
			ID:        "relay-original",
			From:      "peer-sender",
			Message:   envelope,
			Timestamp: time.Now().Add(-time.Hour).UnixMilli(),
		}
		stored := requireAckCustodyBackendStore(
			t,
			backend,
			peerID,
			original,
			directInboxTargetIDDedupePrefix+"text-1",
			InboxStoreResultStored,
		)
		duplicate := original
		duplicate.ID = "relay-retry-must-not-win"
		duplicate.Timestamp = time.Now().UnixMilli()
		got := requireAckCustodyBackendStore(
			t,
			backend,
			peerID,
			duplicate,
			directInboxTargetIDDedupePrefix+"text-1",
			InboxStoreResultDuplicate,
		)
		if got.ID != stored.ID || got.Timestamp != stored.Timestamp {
			t.Fatalf("duplicate refreshed identity/expiry: got %#v want %#v", got, stored)
		}

		newEnvelope := ackCustodyTextEnvelope("text-2", "peer-sender", "cipher-2")
		result, _, err := backend.StoreAckCustody(
			peerID,
			inboxMessage{From: "peer-sender", Message: newEnvelope, Timestamp: time.Now().UnixMilli()},
			directInboxTargetIDDedupePrefix+"text-2",
		)
		if err != nil || result != InboxStoreResultRejectedFull {
			t.Fatalf("distinct store at cap = (%q, %v), want rejected_full", result, err)
		}
		assertAtomicShadowPair(t, backend, peerID, stored)
	})

	t.Run("expired_legacy_not_promoted", func(t *testing.T) {
		server := miniredis.RunT(t)
		backend := newAckCustodyRedisBackend(t, server, "ack-expired:", 2)
		peerID := "peer-recipient"
		envelope := ackCustodyTextEnvelope("text-expired", "peer-sender", "cipher")
		expired := inboxMessage{
			ID:        "relay-expired",
			From:      "peer-sender",
			Message:   envelope,
			Timestamp: time.Now().Add(-maxMessageAge - time.Minute).UnixMilli(),
		}
		payload, err := json.Marshal(expired)
		if err != nil {
			t.Fatal(err)
		}
		if err := backend.client.RPush(context.Background(), backend.key(peerID), payload).Err(); err != nil {
			t.Fatal(err)
		}
		fresh := expired
		fresh.ID = "relay-fresh"
		fresh.Timestamp = time.Now().UnixMilli()
		stored := requireAckCustodyBackendStore(
			t,
			backend,
			peerID,
			fresh,
			directInboxTargetIDDedupePrefix+"text-expired",
			InboxStoreResultStored,
		)
		if stored.ID != fresh.ID || stored.Timestamp != fresh.Timestamp {
			t.Fatalf("expired legacy row was promoted: got %#v want fresh %#v", stored, fresh)
		}
		assertAtomicShadowPair(t, backend, peerID, fresh)
	})

	t.Run("identity_conflict_sender_or_bytes", func(t *testing.T) {
		for _, mutation := range []struct {
			name    string
			from    string
			message string
		}{
			{
				name:    "sender",
				from:    "peer-other",
				message: ackCustodyTextEnvelope("text-1", "peer-sender", "cipher-1"),
			},
			{
				name:    "bytes",
				from:    "peer-sender",
				message: ackCustodyTextEnvelope("text-1", "peer-sender", "cipher-mutated"),
			},
		} {
			t.Run(mutation.name, func(t *testing.T) {
				server := miniredis.RunT(t)
				backend := newAckCustodyRedisBackend(t, server, "ack-conflict:", 2)
				peerID := "peer-recipient"
				original := inboxMessage{
					ID:        "relay-original",
					From:      "peer-sender",
					Message:   ackCustodyTextEnvelope("text-1", "peer-sender", "cipher-1"),
					Timestamp: time.Now().UnixMilli(),
				}
				requireAckCustodyBackendStore(
					t,
					backend,
					peerID,
					original,
					directInboxTargetIDDedupePrefix+"text-1",
					InboxStoreResultStored,
				)
				result, _, err := backend.StoreAckCustody(
					peerID,
					inboxMessage{
						From:      mutation.from,
						Message:   mutation.message,
						Timestamp: time.Now().UnixMilli(),
					},
					directInboxTargetIDDedupePrefix+"text-1",
				)
				if result != "" || !errors.Is(err, errAckCustodyIdentityConflict) {
					t.Fatalf("conflict = (%q, %v), want identity conflict", result, err)
				}
				assertAtomicShadowPair(t, backend, peerID, original)
			})
		}
	})

	t.Run("concurrent_same_key_different_bytes_one_winner", func(t *testing.T) {
		server := miniredis.RunT(t)
		backendA := newAckCustodyRedisBackend(t, server, "ack-race-key:", 2)
		backendB := newAckCustodyRedisBackend(t, server, "ack-race-key:", 2)
		peerID := "peer-recipient"
		start := make(chan struct{})
		type outcome struct {
			result InboxStoreResult
			err    error
		}
		outcomes := make(chan outcome, 2)
		var wg sync.WaitGroup
		for i, backend := range []*redisInboxBackend{backendA, backendB} {
			wg.Add(1)
			go func(index int, candidate *redisInboxBackend) {
				defer wg.Done()
				<-start
				result, _, err := candidate.StoreAckCustody(
					peerID,
					inboxMessage{
						From:      "peer-sender",
						Message:   ackCustodyTextEnvelope("same-key", "peer-sender", fmt.Sprintf("cipher-%d", index)),
						Timestamp: time.Now().UnixMilli(),
					},
					directInboxTargetIDDedupePrefix+"same-key",
				)
				outcomes <- outcome{result: result, err: err}
			}(i, backend)
		}
		close(start)
		wg.Wait()
		close(outcomes)
		stored := 0
		conflicted := 0
		for outcome := range outcomes {
			switch {
			case outcome.result == InboxStoreResultStored && outcome.err == nil:
				stored++
			case outcome.result == "" && errors.Is(outcome.err, errAckCustodyIdentityConflict):
				conflicted++
			default:
				t.Fatalf("unexpected race outcome: (%q, %v)", outcome.result, outcome.err)
			}
		}
		if stored != 1 || conflicted != 1 || backendA.CountAckCustody(peerID) != 1 || backendA.Count(peerID) != 1 {
			t.Fatalf("race result stored=%d conflicted=%d protected=%d legacy=%d", stored, conflicted, backendA.CountAckCustody(peerID), backendA.Count(peerID))
		}
	})

	t.Run("concurrent_distinct_at_last_slot", func(t *testing.T) {
		server := miniredis.RunT(t)
		backendA := newAckCustodyRedisBackend(t, server, "ack-race-cap:", 2)
		backendB := newAckCustodyRedisBackend(t, server, "ack-race-cap:", 2)
		peerID := "peer-recipient"
		seed := inboxMessage{
			ID:        "relay-seed",
			From:      "peer-sender",
			Message:   ackCustodyTextEnvelope("seed", "peer-sender", "seed"),
			Timestamp: time.Now().Add(-time.Second).UnixMilli(),
		}
		requireAckCustodyBackendStore(t, backendA, peerID, seed, directInboxTargetIDDedupePrefix+"seed", InboxStoreResultStored)

		start := make(chan struct{})
		results := make(chan InboxStoreResult, 2)
		var wg sync.WaitGroup
		for i, backend := range []*redisInboxBackend{backendA, backendB} {
			wg.Add(1)
			go func(index int, candidate *redisInboxBackend) {
				defer wg.Done()
				<-start
				id := fmt.Sprintf("distinct-%d", index)
				result, _, err := candidate.StoreAckCustody(
					peerID,
					inboxMessage{
						From:      "peer-sender",
						Message:   ackCustodyTextEnvelope(id, "peer-sender", id),
						Timestamp: time.Now().UnixMilli(),
					},
					directInboxTargetIDDedupePrefix+id,
				)
				if err != nil {
					t.Errorf("race StoreAckCustody: %v", err)
				}
				results <- result
			}(i, backend)
		}
		close(start)
		wg.Wait()
		close(results)
		stored := 0
		rejected := 0
		for result := range results {
			if result == InboxStoreResultStored {
				stored++
			} else if result == InboxStoreResultRejectedFull {
				rejected++
			} else {
				t.Fatalf("unexpected cap race result %q", result)
			}
		}
		pending, _, err := backendA.RetrieveAckCustodyPending(peerID, 10)
		if err != nil {
			t.Fatal(err)
		}
		seedFound := false
		for _, message := range pending {
			if message.ID == seed.ID {
				seedFound = true
			}
		}
		if stored != 1 || rejected != 1 || len(pending) != 2 || !seedFound {
			t.Fatalf("last-slot race stored=%d rejected=%d pending=%d seedFound=%v", stored, rejected, len(pending), seedFound)
		}
	})
}
