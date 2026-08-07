package main

import (
	"testing"

	"github.com/alicebob/miniredis/v2"
)

func TestRedisDirectInboxChatEditsUseDistinctEventCustodyKeysInCrossedOrders(t *testing.T) {
	initial := directChatCustodyEnvelope("redis-target", "")
	editA := directChatCustodyEnvelope("redis-target", "redis-target")
	editB := directChatCustodyEnvelope("redis-target", "redis-edit-b")

	tests := []struct {
		name  string
		order []string
	}{
		{name: "initial then edits", order: []string{initial, editA, editB}},
		{name: "edits then initial", order: []string{editB, editA, initial}},
	}

	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			server := miniredis.RunT(t)
			backendA := newRedisInboxBackend(newTestRedisClient(t, server), "edit-dedupe:", 10)
			backendB := newRedisInboxBackend(newTestRedisClient(t, server), "edit-dedupe:", 10)
			const peerID = "peer-recipient"

			for i, message := range tc.order {
				backend := InboxBackend(backendA)
				if i%2 == 1 {
					backend = backendB
				}
				requireDirectInboxBackendResult(
					t,
					backend,
					peerID,
					message,
					InboxStoreResultStored,
				)
			}

			// A separate client rescans the durable list and must find the exact
			// edit event without collapsing either sibling event or the target.
			reopened := newRedisInboxBackend(newTestRedisClient(t, server), "edit-dedupe:", 10)
			requireDirectInboxBackendResult(
				t,
				reopened,
				peerID,
				tc.order[1],
				InboxStoreResultDuplicate,
			)
			if got := reopened.Count(peerID); got != 3 {
				t.Fatalf("pending Redis inbox rows = %d, want 3", got)
			}
		})
	}
}

func TestRedisDirectInboxLegacyEditWithoutEventIDKeepsTargetSemantics(t *testing.T) {
	server := miniredis.RunT(t)
	backendA := newRedisInboxBackend(newTestRedisClient(t, server), "legacy-edit:", 10)
	backendB := newRedisInboxBackend(newTestRedisClient(t, server), "legacy-edit:", 10)
	initial := directChatCustodyEnvelope("redis-legacy-target", "")
	legacyEdit := `{"type":"chat_message","version":"2","id":"redis-legacy-target","editedAt":"2026-08-07T10:00:00Z","senderPeerId":"peer-sender","encrypted":{"kem":"k","ciphertext":"legacy-edit","nonce":"n"}}`

	requireDirectInboxBackendResult(t, backendA, "peer-recipient", legacyEdit, InboxStoreResultStored)
	requireDirectInboxBackendResult(t, backendB, "peer-recipient", initial, InboxStoreResultDuplicate)
}
