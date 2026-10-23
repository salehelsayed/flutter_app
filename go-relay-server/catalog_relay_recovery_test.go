package main

import (
	"context"
	"encoding/json"
	"fmt"
	"reflect"
	"testing"
	"time"

	"github.com/libp2p/go-libp2p/core/host"
	"github.com/libp2p/go-libp2p/core/network"
)

// Reuse the existing authenticated local relay fixture and its real framed
// handler. Each request has a bounded stream; the same hosts survive rejection.
func catalogRelayRequest(t *testing.T, env *inboxStreamEnv, actor host.Host, req inboxRequest) inboxResponse {
	t.Helper()
	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()
	stream, err := actor.NewStream(ctx, env.server.ID(), InboxProtocol)
	if err != nil {
		t.Fatal(err)
	}
	defer stream.Close()
	// mocknet accepts SetDeadline without enforcing it. Reset our own stream
	// at the bound so a wedged handler fails this test instead of waiting forever.
	deadline := time.AfterFunc(5*time.Second, func() { _ = stream.Reset() })
	defer deadline.Stop()
	if err := stream.SetDeadline(time.Now().Add(5 * time.Second)); err != nil {
		t.Fatal(err)
	}
	sendInboxReq(t, stream, req)
	return recvInboxResp(t, stream)
}

func TestRG003DirectRetainedPagesExpiryAckAndLaterDelivery(t *testing.T) {
	if maxMessageAge != 7*24*time.Hour {
		t.Fatal("catalog retention contract requires seven-day direct custody")
	}
	backend := newMemoryInboxBackend()
	push := NewPushServiceWithBackend(newMemoryPushTokenStore())
	inbox := NewInboxStoreWithBackend(backend, push)
	groups := NewGroupInboxStore(maxMessagesPerGroup, groupMessageTTL)
	env := setupInboxStreamEnv(t, inbox, groups)
	recipient := env.recipient.ID().String()
	store := func(id string) {
		t.Helper()
		response := catalogRelayRequest(t, env, env.sender, inboxRequest{
			Action: "store", To: recipient,
			Message: fmt.Sprintf(`{"type":"chat_message","version":"1","payload":{"id":%q,"text":%q}}`, id, id),
		})
		if response.Status != "OK" || response.StoreStatus != string(InboxStoreResultStored) {
			t.Fatalf("store failed: status=%s store=%s", response.Status, response.StoreStatus)
		}
	}
	store("expired")
	for i := 0; i < 7; i++ {
		store(fmt.Sprintf("retained-%d", i))
	}
	// Advance only fixture records, without sleeping for days or changing the
	// production clock. Both sides of the actual relay TTL have a one-day margin.
	now := time.Now()
	backend.mu.Lock()
	for i := range backend.store[recipient] {
		age := 6 * 24 * time.Hour
		if i == 0 {
			age = 8 * 24 * time.Hour
		}
		backend.store[recipient][i].Timestamp = now.Add(-age).UnixMilli()
	}
	backend.mu.Unlock()

	var received []string
	seen := map[string]bool{}
	for page := 0; page < 4; page++ {
		request := inboxRequest{Action: "retrieve_pending", Limit: 2}
		first := catalogRelayRequest(t, env, env.recipient, request)
		if first.Status != "OK" || len(first.Messages) == 0 {
			t.Fatalf("page %d not delivered: status=%s count=%d", page, first.Status, len(first.Messages))
		}
		// Until exact ACK, redelivery is the same page with the same relay IDs.
		replay := catalogRelayRequest(t, env, env.recipient, request)
		if !reflect.DeepEqual(first.Messages, replay.Messages) || first.HasMore != replay.HasMore {
			t.Fatal("pending page changed before ACK")
		}
		ids := make([]string, 0, len(first.Messages))
		for _, message := range first.Messages {
			if seen[message.ID] {
				t.Fatal("ACKed relay entry appeared on a later page")
			}
			seen[message.ID] = true
			ids = append(ids, message.ID)
			var envelope struct {
				Payload struct {
					ID string `json:"id"`
				} `json:"payload"`
			}
			if err := json.Unmarshal([]byte(message.Message), &envelope); err != nil {
				t.Fatal(err)
			}
			received = append(received, envelope.Payload.ID)
		}
		ack := catalogRelayRequest(t, env, env.recipient, inboxRequest{Action: "ack", EntryIds: ids})
		if ack.Status != "OK" || ack.Acked != len(ids) {
			t.Fatal("exact page ACK failed")
		}
		if first.HasMore != (page < 3) {
			t.Fatalf("incorrect hasMore on page %d", page)
		}
		if page == 0 {
			// Replace the real handler's store owner over the same backend. This is
			// a logical store-owner restart, not a Redis/process durability claim.
			restarted := NewInboxStoreWithBackend(backend, push)
			env.server.SetStreamHandler(InboxProtocol, func(stream network.Stream) {
				HandleInboxStream(stream, restarted, groups, env.server, env.presence, nil)
			})
		}
	}
	want := []string{"retained-0", "retained-1", "retained-2", "retained-3", "retained-4", "retained-5", "retained-6"}
	if !reflect.DeepEqual(received, want) {
		t.Fatalf("retained FIFO differs: got %v want %v", received, want)
	}
	if response := catalogRelayRequest(t, env, env.recipient, inboxRequest{Action: "retrieve_pending"}); response.Status != "NO_MESSAGES" {
		t.Fatal("expired or ACKed backlog remains")
	}
	store("later-live")
	later := catalogRelayRequest(t, env, env.recipient, inboxRequest{Action: "retrieve_pending"})
	if later.Status != "OK" || len(later.Messages) != 1 || later.HasMore {
		t.Fatal("expiry/catchup wedged later valid custody")
	}
	ack := catalogRelayRequest(t, env, env.recipient, inboxRequest{Action: "ack", EntryIds: []string{later.Messages[0].ID}})
	if ack.Status != "OK" || ack.Acked != 1 || inbox.Count(recipient) != 0 {
		t.Fatal("later custody did not converge after exact ACK")
	}
}

func TestRG003GroupRetainedEpochPagesAndExpiredCursor(t *testing.T) {
	if groupMessageTTL != 7*24*time.Hour {
		t.Fatal("catalog retention contract requires seven-day group custody")
	}
	backend := newMemoryGroupInboxBackend(maxMessagesPerGroup, groupMessageTTL)
	groups := NewGroupInboxStoreWithBackend(backend)
	push := NewPushServiceWithBackend(newMemoryPushTokenStore())
	env := setupInboxStreamEnv(t, NewInboxStore(push), groups)
	const groupID = testCanonicalGroupCursorID
	var expected []string
	for epoch := 2; epoch <= 10; epoch++ {
		payload := fmt.Sprintf(`{"kind":"group_offline_replay","version":1,"payloadType":"group_message","keyEpoch":%d,"messageId":"retained-epoch-%d","ciphertext":"opaque-%d","nonce":"fixture"}`, epoch, epoch, epoch)
		response := catalogRelayRequest(t, env, env.sender, inboxRequest{
			Action: "group_store", GroupId: groupID, Message: payload,
			RecipientPeerIds: []string{env.recipient.ID().String()},
		})
		if response.Status != "OK" {
			t.Fatal("group store failed")
		}
		if epoch >= 3 {
			expected = append(expected, payload)
		}
	}
	now := time.Now()
	backend.mu.Lock()
	expiredCursor := backend.messages[groupID][0].ID
	for i := range backend.messages[groupID] {
		age := 6 * 24 * time.Hour
		if i == 0 {
			age = 8 * 24 * time.Hour
		}
		backend.messages[groupID][i].Timestamp = now.Add(-age).UnixMilli()
	}
	backend.mu.Unlock()
	groups.Prune()

	var actual []string
	seen := map[string]bool{}
	cursor := expiredCursor
	var lastEntryID string
	for page := 0; page < 3; page++ {
		response := catalogRelayRequest(t, env, env.recipient, inboxRequest{
			Action: "group_retrieve_cursor", GroupId: groupID, Cursor: cursor, Limit: 3,
		})
		if response.Status != "OK" || len(response.GroupMessages) == 0 {
			t.Fatalf("group page %d missing", page)
		}
		if page == 0 && len(response.HistoryGaps) == 0 {
			t.Fatal("expired cursor did not report its history gap")
		}
		for _, message := range response.GroupMessages {
			if seen[message.ID] {
				t.Fatal("duplicate group relay entry across pages")
			}
			seen[message.ID] = true
			actual = append(actual, message.Message)
			lastEntryID = message.ID
		}
		if (response.NextCursor == "") != (page == 2) {
			t.Fatalf("incorrect group continuation on page %d", page)
		}
		cursor = response.NextCursor
	}
	if !reflect.DeepEqual(actual, expected) {
		t.Fatal("retained opaque epoch envelopes were lost, reordered or modified")
	}
	// The relay does not decrypt or enforce the application's eight-generation
	// key ring; exact opaque epochs 3..10 are custody proof, not key availability.
	intruder := catalogRelayRequest(t, env, env.intruder, inboxRequest{
		Action: "group_retrieve_cursor", GroupId: groupID, Limit: 50,
	})
	if intruder.Status != "NO_MESSAGES" || len(intruder.GroupMessages) != 0 {
		t.Fatal("retained pages escaped recipient authorization")
	}
	laterPayload := `{"kind":"group_offline_replay","version":1,"payloadType":"group_message","keyEpoch":11,"messageId":"later-epoch-11","ciphertext":"opaque-later","nonce":"fixture"}`
	stored := catalogRelayRequest(t, env, env.sender, inboxRequest{
		Action: "group_store", GroupId: groupID, Message: laterPayload,
		RecipientPeerIds: []string{env.recipient.ID().String()},
	})
	if stored.Status != "OK" {
		t.Fatal("later group store failed")
	}
	later := catalogRelayRequest(t, env, env.recipient, inboxRequest{
		Action: "group_retrieve_cursor", GroupId: groupID, Cursor: lastEntryID, Limit: 3,
	})
	if later.Status != "OK" || len(later.GroupMessages) != 1 || later.GroupMessages[0].Message != laterPayload || later.NextCursor != "" {
		t.Fatal("expiry/cursor catchup wedged later group delivery")
	}
}

func TestRG004RejectedRelayRequestsPreserveValidDelivery(t *testing.T) {
	push := NewPushServiceWithBackend(newMemoryPushTokenStore())
	inbox := NewInboxStore(push)
	groups := NewGroupInboxStore(maxMessagesPerGroup, groupMessageTTL)
	env := setupInboxStreamEnv(t, inbox, groups)
	recipient := env.recipient.ID().String()
	baseline := `{"type":"chat_message","version":"1","payload":{"id":"preserved-history","text":"preserved-before-rejection"}}`
	if stored := catalogRelayRequest(t, env, env.sender, inboxRequest{Action: "store", To: recipient, Message: baseline}); stored.Status != "OK" {
		t.Fatal("baseline history store failed")
	}
	initial := catalogRelayRequest(t, env, env.recipient, inboxRequest{Action: "retrieve_pending"})
	if len(initial.Messages) != 1 || initial.Messages[0].Message != baseline {
		t.Fatal("baseline custody unavailable")
	}
	preservedID := initial.Messages[0].ID
	for _, rejection := range []string{"malformed_json", "unknown_action", "missing_recipient_acl", "spoofed_group_sender"} {
		t.Run(rejection, func(t *testing.T) {
			before := inbox.Count(recipient)
			var response inboxResponse
			if rejection == "malformed_json" {
				ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
				defer cancel()
				stream, err := env.sender.NewStream(ctx, env.server.ID(), InboxProtocol)
				if err != nil {
					t.Fatal(err)
				}
				defer stream.Close()
				deadline := time.AfterFunc(5*time.Second, func() { _ = stream.Reset() })
				defer deadline.Stop()
				if err := stream.SetDeadline(time.Now().Add(5 * time.Second)); err != nil {
					t.Fatal(err)
				}
				if err := writeFrame(stream, []byte(`{"action":`)); err != nil {
					t.Fatal(err)
				}
				response = recvInboxResp(t, stream)
			} else {
				request := inboxRequest{Action: "unsupported_catalog_fixture"}
				if rejection != "unknown_action" {
					request = inboxRequest{Action: "group_store", GroupId: testCanonicalGroupAuthID, Message: "rejected"}
					if rejection == "spoofed_group_sender" {
						request.From = env.intruder.ID().String()
						request.RecipientPeerIds = []string{recipient}
					}
				}
				response = catalogRelayRequest(t, env, env.sender, request)
			}
			if response.Status != "ERROR" || inbox.Count(recipient) != before {
				t.Fatal("invalid request was admitted or changed direct custody")
			}
			wantError := map[string]string{
				"malformed_json":        "invalid JSON",
				"unknown_action":        "Unknown action: unsupported_catalog_fixture",
				"missing_recipient_acl": "Missing required field: recipientPeerIds",
				"spoofed_group_sender":  "not authorized",
			}[rejection]
			if response.Error != wantError {
				t.Fatalf("request did not exercise its intended rejection branch: got %q want %q", response.Error, wantError)
			}
			if stored := groups.Retrieve(testCanonicalGroupAuthID, 0); len(stored) != 0 {
				t.Fatal("invalid request changed group custody")
			}
			// Do not restart the relay, replace its stores, reconnect the hosts or
			// call the app listener directly after the rejection.
			payload := fmt.Sprintf(`{"type":"chat_message","version":"1","payload":{"id":%q,"text":"valid-after-rejection"}}`, rejection)
			stored := catalogRelayRequest(t, env, env.sender, inboxRequest{Action: "store", To: recipient, Message: payload})
			if stored.Status != "OK" || stored.StoreStatus != string(InboxStoreResultStored) {
				t.Fatal("valid store wedged after rejection")
			}
			page := catalogRelayRequest(t, env, env.recipient, inboxRequest{Action: "retrieve_pending"})
			if page.Status != "OK" || len(page.Messages) != 2 || page.Messages[0].ID != preservedID || page.Messages[0].Message != baseline || page.Messages[1].Message != payload || page.HasMore {
				t.Fatal("valid message was lost, duplicated or changed after rejection")
			}
			ack := catalogRelayRequest(t, env, env.recipient, inboxRequest{Action: "ack", EntryIds: []string{page.Messages[1].ID}})
			if ack.Status != "OK" || ack.Acked != 1 || inbox.Count(recipient) != 1 {
				t.Fatal("valid post-rejection custody did not clear with exact ACK")
			}
		})
	}
	remaining := catalogRelayRequest(t, env, env.recipient, inboxRequest{Action: "retrieve_pending"})
	if len(remaining.Messages) != 1 || remaining.Messages[0].ID != preservedID || remaining.Messages[0].Message != baseline {
		t.Fatal("rejection or later ACK corrupted retained history")
	}
}
