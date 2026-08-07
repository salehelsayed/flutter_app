package main

import (
	"encoding/json"
	"testing"
	"time"

	"github.com/alicebob/miniredis/v2"
)

func directReactionCustodyTestEnvelope(
	t *testing.T,
	mutate func(map[string]interface{}),
) string {
	t.Helper()

	envelope := map[string]interface{}{
		"type":            "message_reaction",
		"version":         "2",
		"eventId":         "reaction-event",
		"action":          "add",
		"targetMessageId": "reaction-target",
		"senderPeerId":    "peer-sender",
		"encrypted": map[string]interface{}{
			"kem":        "fixture-kem",
			"ciphertext": "fixture-ciphertext",
			"nonce":      "fixture-nonce",
		},
	}
	if mutate != nil {
		mutate(envelope)
	}
	encoded, err := json.Marshal(envelope)
	if err != nil {
		t.Fatalf("marshal direct reaction custody fixture: %v", err)
	}
	return string(encoded)
}

func TestRelayNotificationClosure_DirectReactionCustodyIdentityEligibility(t *testing.T) {
	for _, action := range []string{"add", "remove"} {
		t.Run("complete v2 "+action, func(t *testing.T) {
			envelope := directReactionCustodyTestEnvelope(t, func(envelope map[string]interface{}) {
				envelope["eventId"] = "eligible-" + action
				envelope["action"] = action
			})
			want := directInboxReactionEventIDDedupePrefix + "eligible-" + action
			if got := extractDirectReactionCustodyDedupeKey(envelope); got != want {
				t.Fatalf("reaction custody key = %q, want %q", got, want)
			}
			if got := extractDirectInboxDedupeKey(envelope); got != want {
				t.Fatalf("central direct inbox key = %q, want %q", got, want)
			}

			_, recognized, wakeEligible := extractDirectReactionPushMetadata(envelope)
			if !recognized {
				t.Fatal("complete direct reaction was not recognized by wake parser")
			}
			if wakeEligible != (action == "add") {
				t.Fatalf("wake eligible = %t for %s, want %t", wakeEligible, action, action == "add")
			}
		})
	}

	baseEventFallback := directInboxTargetIDDedupePrefix + "reaction-event"
	tests := []struct {
		name    string
		message string
		want    string
	}{
		{
			name: "missing type",
			message: directReactionCustodyTestEnvelope(t, func(envelope map[string]interface{}) {
				delete(envelope, "type")
			}),
			want: "",
		},
		{
			name: "blank type",
			message: directReactionCustodyTestEnvelope(t, func(envelope map[string]interface{}) {
				envelope["type"] = ""
			}),
			want: "",
		},
		{
			name: "missing version",
			message: directReactionCustodyTestEnvelope(t, func(envelope map[string]interface{}) {
				delete(envelope, "version")
			}),
			want: baseEventFallback,
		},
		{
			name: "blank version",
			message: directReactionCustodyTestEnvelope(t, func(envelope map[string]interface{}) {
				envelope["version"] = ""
			}),
			want: baseEventFallback,
		},
		{
			name: "non-v2",
			message: directReactionCustodyTestEnvelope(t, func(envelope map[string]interface{}) {
				envelope["version"] = "1"
			}),
			want: baseEventFallback,
		},
		{
			name: "numeric version",
			message: directReactionCustodyTestEnvelope(t, func(envelope map[string]interface{}) {
				envelope["version"] = 2
			}),
			want: baseEventFallback,
		},
		{
			name: "whitespace version",
			message: directReactionCustodyTestEnvelope(t, func(envelope map[string]interface{}) {
				envelope["version"] = " 2"
			}),
			want: baseEventFallback,
		},
		{
			name: "whitespace type",
			message: directReactionCustodyTestEnvelope(t, func(envelope map[string]interface{}) {
				envelope["type"] = "message_reaction "
			}),
			want: "",
		},
		{
			name: "missing event",
			message: directReactionCustodyTestEnvelope(t, func(envelope map[string]interface{}) {
				delete(envelope, "eventId")
			}),
			want: "",
		},
		{
			name: "blank event",
			message: directReactionCustodyTestEnvelope(t, func(envelope map[string]interface{}) {
				envelope["eventId"] = ""
			}),
			want: "",
		},
		{
			name: "whitespace event",
			message: directReactionCustodyTestEnvelope(t, func(envelope map[string]interface{}) {
				envelope["eventId"] = " reaction-event"
			}),
			want: "",
		},
		{
			name: "missing action",
			message: directReactionCustodyTestEnvelope(t, func(envelope map[string]interface{}) {
				delete(envelope, "action")
			}),
			want: baseEventFallback,
		},
		{
			name: "blank action",
			message: directReactionCustodyTestEnvelope(t, func(envelope map[string]interface{}) {
				envelope["action"] = ""
			}),
			want: baseEventFallback,
		},
		{
			name: "whitespace action",
			message: directReactionCustodyTestEnvelope(t, func(envelope map[string]interface{}) {
				envelope["action"] = " add"
			}),
			want: baseEventFallback,
		},
		{
			name: "unsupported action",
			message: directReactionCustodyTestEnvelope(t, func(envelope map[string]interface{}) {
				envelope["action"] = "replace"
			}),
			want: baseEventFallback,
		},
		{
			name: "missing target",
			message: directReactionCustodyTestEnvelope(t, func(envelope map[string]interface{}) {
				delete(envelope, "targetMessageId")
			}),
			want: baseEventFallback,
		},
		{
			name: "blank target",
			message: directReactionCustodyTestEnvelope(t, func(envelope map[string]interface{}) {
				envelope["targetMessageId"] = ""
			}),
			want: baseEventFallback,
		},
		{
			name: "whitespace target",
			message: directReactionCustodyTestEnvelope(t, func(envelope map[string]interface{}) {
				envelope["targetMessageId"] = "reaction-target "
			}),
			want: baseEventFallback,
		},
		{
			name: "missing sender",
			message: directReactionCustodyTestEnvelope(t, func(envelope map[string]interface{}) {
				delete(envelope, "senderPeerId")
			}),
			want: baseEventFallback,
		},
		{
			name: "blank sender",
			message: directReactionCustodyTestEnvelope(t, func(envelope map[string]interface{}) {
				envelope["senderPeerId"] = ""
			}),
			want: baseEventFallback,
		},
		{
			name: "whitespace sender",
			message: directReactionCustodyTestEnvelope(t, func(envelope map[string]interface{}) {
				envelope["senderPeerId"] = " peer-sender"
			}),
			want: baseEventFallback,
		},
		{
			name: "missing encrypted object",
			message: directReactionCustodyTestEnvelope(t, func(envelope map[string]interface{}) {
				delete(envelope, "encrypted")
			}),
			want: baseEventFallback,
		},
		{
			name: "invalid encrypted object",
			message: directReactionCustodyTestEnvelope(t, func(envelope map[string]interface{}) {
				envelope["encrypted"] = "opaque"
			}),
			want: baseEventFallback,
		},
	}

	for _, member := range []string{"kem", "ciphertext", "nonce"} {
		member := member
		tests = append(tests,
			struct {
				name    string
				message string
				want    string
			}{
				name: "missing encrypted " + member,
				message: directReactionCustodyTestEnvelope(t, func(envelope map[string]interface{}) {
					delete(envelope["encrypted"].(map[string]interface{}), member)
				}),
				want: baseEventFallback,
			},
			struct {
				name    string
				message string
				want    string
			}{
				name: "blank encrypted " + member,
				message: directReactionCustodyTestEnvelope(t, func(envelope map[string]interface{}) {
					envelope["encrypted"].(map[string]interface{})[member] = ""
				}),
				want: baseEventFallback,
			},
			struct {
				name    string
				message string
				want    string
			}{
				name: "whitespace encrypted " + member,
				message: directReactionCustodyTestEnvelope(t, func(envelope map[string]interface{}) {
					envelope["encrypted"].(map[string]interface{})[member] = " value"
				}),
				want: baseEventFallback,
			},
		)
	}

	tests = append(tests,
		struct {
			name    string
			message string
			want    string
		}{
			name:    "legacy direct reaction",
			message: `{"type":"message_reaction","version":"2","senderPeerId":"peer-sender","encrypted":{"kem":"k","ciphertext":"c","nonce":"n"}}`,
			want:    "",
		},
		struct {
			name    string
			message string
			want    string
		}{
			name:    "malformed json",
			message: `{"type":"message_reaction"`,
			want:    "",
		},
		struct {
			name    string
			message string
			want    string
		}{
			name:    "ordinary chat target compatibility",
			message: directChatCustodyEnvelope("ordinary-chat-target", ""),
			want:    directInboxTargetIDDedupePrefix + "ordinary-chat-target",
		},
	)

	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			if got := extractDirectReactionCustodyDedupeKey(tc.message); got != "" {
				t.Fatalf("ineligible reaction custody helper key = %q, want empty", got)
			}
			if got := extractDirectInboxDedupeKey(tc.message); got != tc.want {
				t.Fatalf("central compatibility key = %q, want %q", got, tc.want)
			}
		})
	}
}

func directReactionCustodyNamespaceFixtures() []string {
	const (
		crossTypeRawID = "cross-type-raw-id"
		siblingTarget  = "shared-reaction-target"
	)
	return []string{
		directChatCustodyEnvelope(crossTypeRawID, ""),
		directChatCustodyEnvelope("chat-edit-target", crossTypeRawID),
		directReactionEnvelope(crossTypeRawID, "add", siblingTarget, "peer-sender"),
		directReactionEnvelope("remove-sibling-event", "remove", siblingTarget, "peer-sender"),
	}
}

func requireDirectReactionCustodyFixtureReplays(
	t *testing.T,
	backend InboxBackend,
	peerID string,
	fixtures []string,
) {
	t.Helper()
	for _, message := range fixtures {
		requireDirectInboxBackendResult(
			t,
			backend,
			peerID,
			message,
			InboxStoreResultDuplicate,
		)
	}
}

func directInboxEntryID(t *testing.T, backend InboxBackend, peerID, message string) string {
	t.Helper()
	pending, _ := backend.RetrievePending(peerID, 50)
	for _, entry := range pending {
		if entry.Message == message {
			return entry.ID
		}
	}
	t.Fatalf("pending inbox has no entry for %q", message)
	return ""
}

func TestRelayNotificationClosure_DirectReactionCustodyNamespacesMemoryAndRebuilds(t *testing.T) {
	fixtures := directReactionCustodyNamespaceFixtures()
	orders := [][]string{
		fixtures,
		{fixtures[3], fixtures[2], fixtures[1], fixtures[0]},
	}

	for index, order := range orders {
		t.Run("crossed order "+string(rune('A'+index)), func(t *testing.T) {
			backend := newMemoryInboxBackend()
			const peerID = "peer-memory-recipient"
			for _, message := range order {
				requireDirectInboxBackendResult(t, backend, peerID, message, InboxStoreResultStored)
			}
			requireDirectReactionCustodyFixtureReplays(t, backend, peerID, fixtures)
			if got := backend.Count(peerID); got != len(fixtures) {
				t.Fatalf("memory custody rows = %d, want %d", got, len(fixtures))
			}
		})
	}

	t.Run("limited overflow rebuild", func(t *testing.T) {
		backend := newMemoryInboxBackendWithLimits(3)
		const peerID = "peer-limited-recipient"
		for _, message := range fixtures[:3] {
			requireDirectInboxBackendResult(t, backend, peerID, message, InboxStoreResultStored)
		}
		requireDirectInboxBackendResult(t, backend, peerID, fixtures[3], InboxStoreResultStored)

		for _, retained := range fixtures[1:] {
			requireDirectInboxBackendResult(t, backend, peerID, retained, InboxStoreResultDuplicate)
		}
		// The shipped overflow contract evicts the oldest row and returns stored;
		// its removed custody key must disappear from the rebuilt set.
		requireDirectInboxBackendResult(t, backend, peerID, fixtures[0], InboxStoreResultStored)
		if got := backend.Count(peerID); got != 3 {
			t.Fatalf("limited custody rows = %d, want 3", got)
		}
	})

	t.Run("ack rebuild", func(t *testing.T) {
		backend := newMemoryInboxBackend()
		const peerID = "peer-ack-recipient"
		for _, message := range fixtures {
			requireDirectInboxBackendResult(t, backend, peerID, message, InboxStoreResultStored)
		}

		ackedMessage := fixtures[2]
		entryID := directInboxEntryID(t, backend, peerID, ackedMessage)
		if removed, err := backend.Ack(peerID, []string{entryID}); err != nil || removed != 1 {
			t.Fatalf("Ack(reaction ADD) = %d, %v; want 1, nil", removed, err)
		}
		for _, retained := range []string{fixtures[0], fixtures[1], fixtures[3]} {
			requireDirectInboxBackendResult(t, backend, peerID, retained, InboxStoreResultDuplicate)
		}
		requireDirectInboxBackendResult(t, backend, peerID, ackedMessage, InboxStoreResultStored)
	})
}

func TestRelayNotificationClosure_DirectReactionCustodyNamespacesRedis(t *testing.T) {
	fixtures := directReactionCustodyNamespaceFixtures()
	orders := [][]string{
		fixtures,
		{fixtures[3], fixtures[2], fixtures[1], fixtures[0]},
	}

	for index, order := range orders {
		t.Run("crossed order "+string(rune('A'+index)), func(t *testing.T) {
			server := miniredis.RunT(t)
			backendA := newRedisInboxBackend(newTestRedisClient(t, server), "reaction-custody:", 10)
			backendB := newRedisInboxBackend(newTestRedisClient(t, server), "reaction-custody:", 10)
			const peerID = "peer-redis-recipient"

			for i, message := range order {
				backend := InboxBackend(backendA)
				if i%2 == 1 {
					backend = backendB
				}
				requireDirectInboxBackendResult(t, backend, peerID, message, InboxStoreResultStored)
			}

			reopened := newRedisInboxBackend(newTestRedisClient(t, server), "reaction-custody:", 10)
			requireDirectReactionCustodyFixtureReplays(t, reopened, peerID, fixtures)
			if got := reopened.Count(peerID); got != len(fixtures) {
				t.Fatalf("Redis custody rows = %d, want %d", got, len(fixtures))
			}

			ackedMessage := fixtures[3]
			entryID := directInboxEntryID(t, reopened, peerID, ackedMessage)
			if removed, err := reopened.Ack(peerID, []string{entryID}); err != nil || removed != 1 {
				t.Fatalf("Redis Ack(reaction REMOVE) = %d, %v; want 1, nil", removed, err)
			}
			rescanned := newRedisInboxBackend(newTestRedisClient(t, server), "reaction-custody:", 10)
			for _, retained := range fixtures[:3] {
				requireDirectInboxBackendResult(t, rescanned, peerID, retained, InboxStoreResultDuplicate)
			}
			requireDirectInboxBackendResult(t, rescanned, peerID, ackedMessage, InboxStoreResultStored)
		})
	}
}

func TestRelayNotificationClosure_DirectReactionDuplicateDoesNotRefanoutPush(t *testing.T) {
	inbox, recorder := configuredReactionInbox(t)
	const (
		peerID        = "peer-recipient"
		senderPeerID  = "peer-alice"
		targetMessage = "same-target-for-add-and-remove"
	)
	add := directReactionEnvelope("custody-add-event", "add", targetMessage, senderPeerID)
	remove := directReactionEnvelope("custody-remove-event", "remove", targetMessage, senderPeerID)

	store := func(message string, want InboxStoreResult) {
		t.Helper()
		result, err := inbox.Store(peerID, inboxMessage{
			From:      senderPeerID,
			Message:   message,
			Timestamp: time.Now().UnixMilli(),
			WakeToken: "reaction-wake-alice",
		})
		if err != nil || result != want {
			t.Fatalf("Store() = %q, %v; want %q, nil", result, err, want)
		}
	}

	store(add, InboxStoreResultStored)
	push := waitForRecordedPush(t, recorder)
	if got := sentRoutingString(push, "event_id"); got != "custody-add-event" {
		t.Fatalf("push event_id = %q, want custody-add-event", got)
	}
	if got := sentRoutingString(push, "target_message_id"); got != targetMessage {
		t.Fatalf("push target_message_id = %q, want %q", got, targetMessage)
	}
	if got := extractMessageId(add); got != "custody-add-event" {
		t.Fatalf("extractMessageId(ADD) = %q, want unchanged event identity", got)
	}

	store(add, InboxStoreResultDuplicate)
	assertNoRecordedPush(t, recorder)

	store(remove, InboxStoreResultStored)
	assertNoRecordedPush(t, recorder)
	store(remove, InboxStoreResultDuplicate)
	assertNoRecordedPush(t, recorder)

	if got := inbox.Count(peerID); got != 2 {
		t.Fatalf("same-target ADD/REMOVE custody rows = %d, want 2", got)
	}
	if got := recorder.SendCallCount(); got != 1 {
		t.Fatalf("reaction push fanout count = %d, want exactly 1 ADD wake", got)
	}
}
