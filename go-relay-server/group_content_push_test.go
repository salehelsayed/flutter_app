package main

import (
	"fmt"
	"strings"
	"testing"
	"time"

	"github.com/alicebob/miniredis/v2"
)

// G26 regression suite.
//
// Strict-authority group sends never touch the group topic: they store one
// signed `group_offline_replay` envelope per recipient into the DIRECT inbox
// under the `group_content_v1` custody namespace. Before this lane existed the
// relay stored those envelopes and then went silent — no push, no wake, no
// counter — because the direct push seam only understood `envelope["type"]`,
// which a replay envelope does not have.

const testStrictGroupID = "g-strict-content-0000000000000001"

func strictGroupContentEnvelope(
	payloadType string,
	groupID string,
	senderTransportPeerID string,
	messageID string,
	keyEpoch int,
) string {
	return fmt.Sprintf(
		`{"kind":"group_offline_replay","version":1,"groupId":%q,"payloadType":%q,`+
			`"keyEpoch":%d,"messageId":%q,"senderPeerId":"sender-account",`+
			`"senderDeviceId":"sender-device","senderTransportPeerId":%q,`+
			`"senderPublicKey":"sender-public-key","recipientSetHash":"set-hash",`+
			`"ciphertext":"strict-ciphertext","nonce":"strict-nonce",`+
			`"signatureAlgorithm":"ed25519","signedPayload":"{}","signature":"sig",`+
			`"custodyKind":"group_content_v1","contentEventId":%q,`+
			`"authorityEventAt":"2026-08-19T09:00:00.000000Z",`+
			`"authorityEventId":"a-strict-authority-000000000001","authorityKeyEpoch":%d}`,
		groupID,
		payloadType,
		keyEpoch,
		messageID,
		senderTransportPeerID,
		messageID,
		keyEpoch,
	)
}

// The root cause, pinned so it cannot silently come back: the generic chat
// extractor cannot see strict group content at all. If someone ever "simplifies"
// the dedicated lane away by adding a case here instead, this row still holds —
// but the lane's own end-to-end row is what proves a push is actually sent.
func TestExtractChatPushMetadata_StrictGroupContentIsInvisible(t *testing.T) {
	message := strictGroupContentEnvelope(
		groupContentPayloadTypeMessage,
		testStrictGroupID,
		"transport-sender",
		"m-strict-content-000000000000001",
		7,
	)
	if metadata := extractChatPushMetadata(message); metadata.ShouldNotify {
		t.Fatalf("extractChatPushMetadata(strict group content).ShouldNotify = true, want false; "+
			"a replay envelope has no `type` field, so it must reach the dedicated lane: %#v", metadata)
	}
	if _, recognized, _ := extractDirectReactionPushMetadata(message); recognized {
		t.Fatal("strict group content must not be recognized as a direct reaction")
	}
}

func TestExtractGroupContentPushMetadata(t *testing.T) {
	const (
		groupID   = testStrictGroupID
		transport = "transport-sender"
		messageID = "m-strict-content-000000000000001"
	)

	t.Run("accepts a complete strict group message", func(t *testing.T) {
		metadata, recognized, eligible := extractGroupContentPushMetadata(
			strictGroupContentEnvelope(groupContentPayloadTypeMessage, groupID, transport, messageID, 7),
		)
		if !recognized || !eligible {
			t.Fatalf("recognized=%v eligible=%v, want both true", recognized, eligible)
		}
		if metadata.GroupID != groupID ||
			metadata.SenderTransportPeerID != transport ||
			metadata.MessageID != messageID ||
			metadata.PayloadType != groupContentPayloadTypeMessage {
			t.Fatalf("metadata = %#v", metadata)
		}
	})

	// Reactions share the custody namespace but carry their own audience rule
	// (author-only alerting). Routing them onto the group-message push would
	// alert every member, so they are recognized-and-declined, never ignored.
	t.Run("declines a strict group reaction without falling through", func(t *testing.T) {
		metadata, recognized, eligible := extractGroupContentPushMetadata(
			strictGroupContentEnvelope(groupContentPayloadTypeReaction, groupID, transport, messageID, 7),
		)
		if !recognized {
			t.Fatal("a strict group reaction must be RECOGNIZED so it cannot fall through to the chat switch")
		}
		if eligible {
			t.Fatal("a strict group reaction must not be eligible for the group-message push")
		}
		if metadata.PayloadType != groupContentPayloadTypeReaction {
			t.Fatalf("payloadType = %q", metadata.PayloadType)
		}
	})

	// The group-topic reaction wake also uses `group_offline_replay`, but
	// without `custodyKind`. That shape must stay outside this lane entirely.
	t.Run("ignores a replay envelope that is not ack custody", func(t *testing.T) {
		message := fmt.Sprintf(
			`{"kind":"group_offline_replay","version":1,"groupId":%q,"payloadType":"group_reaction",`+
				`"messageId":"legacy-state","senderTransportPeerId":%q,"ciphertext":"c","nonce":"n"}`,
			groupID,
			transport,
		)
		if _, recognized, _ := extractGroupContentPushMetadata(message); recognized {
			t.Fatal("a non-custody replay envelope must not be recognized by the group content lane")
		}
	})

	t.Run("ignores unrelated and malformed envelopes", func(t *testing.T) {
		for name, message := range map[string]string{
			"chat message": `{"type":"chat_message","payload":{"id":"m1"}}`,
			"not json":     `{`,
			"wrong kind":   `{"kind":"something_else","custodyKind":"group_content_v1"}`,
		} {
			if _, recognized, _ := extractGroupContentPushMetadata(message); recognized {
				t.Fatalf("%s must not be recognized", name)
			}
		}
	})

	// Every field below is one the push cannot route without. A partially
	// addressed wake is worse than silent custody: it would wake a recipient
	// who then cannot resolve what woke them.
	t.Run("declines when a routing field is missing", func(t *testing.T) {
		for name, message := range map[string]string{
			"no group id":  strictGroupContentEnvelope(groupContentPayloadTypeMessage, "", transport, messageID, 7),
			"no transport": strictGroupContentEnvelope(groupContentPayloadTypeMessage, groupID, "", messageID, 7),
			"no message id": strictGroupContentEnvelope(
				groupContentPayloadTypeMessage, groupID, transport, "", 7),
		} {
			_, recognized, eligible := extractGroupContentPushMetadata(message)
			if !recognized || eligible {
				t.Fatalf("%s: recognized=%v eligible=%v, want recognized and NOT eligible",
					name, recognized, eligible)
			}
		}
	})

	t.Run("declines a version it does not understand", func(t *testing.T) {
		message := `{"kind":"group_offline_replay","version":2,"custodyKind":"group_content_v1",` +
			`"payloadType":"group_message","groupId":"g","messageId":"m",` +
			`"senderTransportPeerId":"t","ciphertext":"c","nonce":"n"}`
		_, recognized, eligible := extractGroupContentPushMetadata(message)
		if !recognized || eligible {
			t.Fatalf("recognized=%v eligible=%v, want recognized and NOT eligible", recognized, eligible)
		}
	})
}

func newStrictGroupContentInbox(t *testing.T, enabled bool) (*InboxStore, *recordingPushSender, string) {
	t.Helper()
	tokens := newMemoryPushTokenStore()
	push := NewPushServiceWithBackend(tokens)
	recorder := newRecordingPushSender()
	push.sender = recorder.Send
	inbox := NewInboxStore(push)
	inbox.SetGroupContentPushEnabled(enabled)

	const recipient = "recipient-peer"
	if err := tokens.RegisterToken(recipient, "recipient-token", "android"); err != nil {
		t.Fatalf("register token: %v", err)
	}
	return inbox, recorder, recipient
}

// The causal row. Before the fix this stored silently and sent nothing.
func TestInboxStore_StrictGroupContentWakesTheRecipient(t *testing.T) {
	inbox, recorder, recipient := newStrictGroupContentInbox(t, true)

	const (
		transport = "transport-sender"
		messageID = "m-strict-content-000000000000001"
	)
	entry := inboxMessage{
		From: transport,
		Message: strictGroupContentEnvelope(
			groupContentPayloadTypeMessage, testStrictGroupID, transport, messageID, 7),
		Timestamp: time.Now().UnixMilli(),
	}
	requireInboxStoreResult(t, inbox, recipient, entry, InboxStoreResultStored)
	waitForGroupReactionPushes(t, recorder, 1)

	data := recorder.LastMessage().Data
	// The recipient routes on `type` alone, so these are the keys that decide
	// whether a card renders or the push is dropped on the floor.
	for key, want := range map[string]string{
		"type":                     "group_message",
		"groupId":                  testStrictGroupID,
		"sender_transport_peer_id": transport,
		"message_id":               messageID,
		"keyEpoch":                 "7",
		"ciphertext":               "strict-ciphertext",
		"nonce":                    "strict-nonce",
	} {
		if data[key] != want {
			t.Fatalf("push data[%q] = %q, want %q (full data: %#v)", key, data[key], want, data)
		}
	}
	if data["preview_unavailable"] != "" {
		t.Fatalf("a well-formed strict group message must carry its ciphertext, not the routing-only fallback: %#v", data)
	}
}

func TestInboxStore_StrictGroupContentStaysSilentWhenDisabled(t *testing.T) {
	inbox, recorder, recipient := newStrictGroupContentInbox(t, false)

	const transport = "transport-sender"
	entry := inboxMessage{
		From: transport,
		Message: strictGroupContentEnvelope(
			groupContentPayloadTypeMessage, testStrictGroupID, transport,
			"m-strict-content-000000000000002", 7),
		Timestamp: time.Now().UnixMilli(),
	}
	// Custody is unaffected by the flag — only the wake is gated.
	requireInboxStoreResult(t, inbox, recipient, entry, InboxStoreResultStored)
	assertNoAdditionalGroupReactionPush(t, recorder, 0)
	if inbox.Count(recipient) != 1 {
		t.Fatalf("stored count = %d, want 1: the kill switch must never drop custody", inbox.Count(recipient))
	}
}

func TestInboxStore_StrictGroupReactionStaysSilentCustody(t *testing.T) {
	inbox, recorder, recipient := newStrictGroupContentInbox(t, true)

	const transport = "transport-sender"
	entry := inboxMessage{
		From: transport,
		Message: strictGroupContentEnvelope(
			groupContentPayloadTypeReaction, testStrictGroupID, transport,
			"m-strict-content-000000000000003", 7),
		Timestamp: time.Now().UnixMilli(),
	}
	requireInboxStoreResult(t, inbox, recipient, entry, InboxStoreResultStored)
	assertNoAdditionalGroupReactionPush(t, recorder, 0)
}

// An unusable epoch degrades to the routing-only push the ordinary group lane
// already uses. Still a wake, still a card — just a generic one. Silence is the
// one outcome this lane must never produce for a well-addressed message.
func TestInboxStore_StrictGroupContentWithUnusableEpochStillWakes(t *testing.T) {
	inbox, recorder, recipient := newStrictGroupContentInbox(t, true)

	const (
		transport = "transport-sender"
		messageID = "m-strict-content-000000000000004"
	)
	entry := inboxMessage{
		From: transport,
		Message: strictGroupContentEnvelope(
			groupContentPayloadTypeMessage, testStrictGroupID, transport, messageID, 0),
		Timestamp: time.Now().UnixMilli(),
	}
	requireInboxStoreResult(t, inbox, recipient, entry, InboxStoreResultStored)
	waitForGroupReactionPushes(t, recorder, 1)

	data := recorder.LastMessage().Data
	if data["type"] != "group_message" || data["groupId"] != testStrictGroupID {
		t.Fatalf("routing keys must survive the fallback: %#v", data)
	}
	if data["preview_unavailable"] != "1" {
		t.Fatalf("an unusable epoch must degrade to the routing-only fallback: %#v", data)
	}
}

// Default-OFF matches every sibling push flag. Deploying the binary therefore
// changes nothing until the operator sets the env var — which is also what
// makes this safe to ship to a relay with no staging twin.
func TestLoadGroupContentPushEnabledFromEnv(t *testing.T) {
	for value, want := range map[string]bool{
		"1": true, "true": true, "TRUE": true, " true ": true,
		"0": false, "false": false, "": false, "yes": false,
	} {
		t.Setenv(groupContentPushEnabledEnv, value)
		if got := loadGroupContentPushEnabledFromEnv(); got != want {
			t.Fatalf("%s=%q -> %v, want %v", groupContentPushEnabledEnv, value, got, want)
		}
	}
}

// The production path. Strict group content never reaches `InboxStore.Store` —
// it arrives through the ack-custody store, whose admission validates the
// signature, the canonical signed payload and the recipient set before anything
// is persisted. Proving the wake on the plain store alone would be the same
// class of gap that let G19 ship: a host row passing on a path the real traffic
// does not take.
func TestStoreAckCustody_StrictGroupContentWakesTheRecipient(t *testing.T) {
	server := miniredis.RunT(t)
	backend := newAckCustodyRedisBackend(t, server, "ack-group-g26:", 32)
	tokens := newMemoryPushTokenStore()
	push := NewPushServiceWithBackend(tokens)
	recorder := newRecordingPushSender()
	push.sender = recorder.Send
	inbox := NewInboxStoreWithBackendAndCapacity(backend, push, 32)
	inbox.SetAckCustodyAdmissionEnabled(true)
	inbox.SetGroupContentPushEnabled(true)

	env := setupInboxStreamEnv(t, inbox, NewGroupInboxStore(500, 7*24*time.Hour))
	sender := env.sender.ID().String()
	recipient := env.recipient.ID().String()
	if err := tokens.RegisterToken(recipient, "recipient-token", "android"); err != nil {
		t.Fatalf("register token: %v", err)
	}

	fixture := newTC364GroupContentFixture(t, "group-content-g26", "logical-author", sender)
	contentEventID := "gr1:" + strings.Repeat("a", 32) + ":00000000000000000001:" + strings.Repeat("b", 32)
	message := fixture.envelope(t, "group_message", contentEventID, "", []string{recipient}, "g26-message")

	stored := sendAckCustodyStoreRequest(
		t, env, recipient, ackCustodyGroupContentKind, ackCustodyContract, message,
	)
	if stored.Status != "OK" || stored.StoreStatus != string(InboxStoreResultStored) {
		t.Fatalf("ack custody store = %#v", stored)
	}
	waitForGroupReactionPushes(t, recorder, 1)

	data := recorder.LastMessage().Data
	if data["type"] != "group_message" {
		t.Fatalf("push type = %q, want group_message (full data: %#v)", data["type"], data)
	}
	if data["groupId"] != "group-content-g26" {
		t.Fatalf("push groupId = %q (full data: %#v)", data["groupId"], data)
	}
	if data["sender_transport_peer_id"] != sender {
		t.Fatalf("push sender_transport_peer_id = %q, want %q", data["sender_transport_peer_id"], sender)
	}
	if data["message_id"] != contentEventID {
		t.Fatalf("push message_id = %q, want %q", data["message_id"], contentEventID)
	}
}

// The same production path with the kill switch off: custody is unaffected and
// the recipient is not woken.
func TestStoreAckCustody_StrictGroupContentSilentWhenDisabled(t *testing.T) {
	server := miniredis.RunT(t)
	backend := newAckCustodyRedisBackend(t, server, "ack-group-g26-off:", 32)
	tokens := newMemoryPushTokenStore()
	push := NewPushServiceWithBackend(tokens)
	recorder := newRecordingPushSender()
	push.sender = recorder.Send
	inbox := NewInboxStoreWithBackendAndCapacity(backend, push, 32)
	inbox.SetAckCustodyAdmissionEnabled(true)
	inbox.SetGroupContentPushEnabled(false)

	env := setupInboxStreamEnv(t, inbox, NewGroupInboxStore(500, 7*24*time.Hour))
	sender := env.sender.ID().String()
	recipient := env.recipient.ID().String()
	if err := tokens.RegisterToken(recipient, "recipient-token", "android"); err != nil {
		t.Fatalf("register token: %v", err)
	}

	fixture := newTC364GroupContentFixture(t, "group-content-g26-off", "logical-author", sender)
	contentEventID := "gr1:" + strings.Repeat("c", 32) + ":00000000000000000002:" + strings.Repeat("d", 32)
	message := fixture.envelope(t, "group_message", contentEventID, "", []string{recipient}, "g26-off")

	stored := sendAckCustodyStoreRequest(
		t, env, recipient, ackCustodyGroupContentKind, ackCustodyContract, message,
	)
	if stored.Status != "OK" || stored.StoreStatus != string(InboxStoreResultStored) {
		t.Fatalf("ack custody store = %#v", stored)
	}
	assertNoAdditionalGroupReactionPush(t, recorder, 0)
}
