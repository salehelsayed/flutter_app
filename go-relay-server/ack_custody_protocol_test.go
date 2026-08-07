package main

import (
	"context"
	"fmt"
	"testing"
	"time"

	"github.com/alicebob/miniredis/v2"
)

func sendAckCustodyStoreRequest(
	t *testing.T,
	env *inboxStreamEnv,
	recipient string,
	kind string,
	contract string,
	message string,
) inboxResponse {
	t.Helper()
	stream, err := env.sender.NewStream(context.Background(), env.server.ID(), InboxProtocol)
	if err != nil {
		t.Fatalf("open ack custody store stream: %v", err)
	}
	defer stream.Close()
	sendInboxReq(t, stream, inboxRequest{
		Action:          ackCustodyStoreAction,
		To:              recipient,
		Message:         message,
		CustodyKind:     kind,
		CustodyContract: contract,
	})
	return recvInboxResp(t, stream)
}

func TestRelayNotificationClosure_AckCustodyEligibilityIsNarrow(t *testing.T) {
	server := miniredis.RunT(t)
	backend := newAckCustodyRedisBackend(t, server, "ack-eligibility:", 32)
	tokenStore := newMemoryPushTokenStore()
	push := NewPushServiceWithBackend(tokenStore)
	recorder := newRecordingPushSender()
	push.sender = recorder.Send
	inbox := NewInboxStoreWithBackendAndCapacity(backend, push, 32)
	inbox.SetAckCustodyAdmissionEnabled(true)
	groupInbox := NewGroupInboxStore(500, 7*24*time.Hour)
	env := setupInboxStreamEnv(t, inbox, groupInbox)
	recipient := env.recipient.ID().String()
	sender := env.sender.ID().String()

	eligible := []struct {
		name    string
		kind    string
		message string
	}{
		{
			name:    "direct text v108",
			kind:    ackCustodyDirectTextKind,
			message: ackCustodyTextEnvelope("eligible-text", sender, "cipher-text"),
		},
		{
			name:    "direct reaction add v109",
			kind:    ackCustodyDirectReactionKind,
			message: ackCustodyReactionEnvelope("eligible-add", "add", "target", sender, "cipher-add"),
		},
		{
			name:    "direct reaction remove v109",
			kind:    ackCustodyDirectReactionKind,
			message: ackCustodyReactionEnvelope("eligible-remove", "remove", "target", sender, "cipher-remove"),
		},
	}
	for _, tc := range eligible {
		t.Run(tc.name, func(t *testing.T) {
			resp := sendAckCustodyStoreRequest(
				t,
				env,
				recipient,
				tc.kind,
				ackCustodyContract,
				tc.message,
			)
			if resp.Status != "OK" ||
				resp.StoreStatus != string(InboxStoreResultStored) ||
				resp.CustodyContract != ackCustodyContract {
				t.Fatalf("eligible response = %#v, want exact protected receipt", resp)
			}
		})
	}
	if count := backend.CountAckCustody(recipient); count != len(eligible) {
		t.Fatalf("eligible protected count = %d, want %d", count, len(eligible))
	}
	beforeLegacy := backend.Count(recipient)
	beforeProtected := backend.CountAckCustody(recipient)
	beforePush := recorder.SendCallCount()

	ineligible := []struct {
		name     string
		kind     string
		contract string
		message  string
	}{
		{
			name:     "chat edit event id",
			kind:     ackCustodyDirectTextKind,
			contract: ackCustodyContract,
			message: fmt.Sprintf(
				`{"type":"chat_message","version":"2","id":"edit-target","eventId":"edit-event","senderPeerId":%q,"encrypted":{"kem":"k","ciphertext":"c","nonce":"n"}}`,
				sender,
			),
		},
		{
			name:     "message deletion",
			kind:     ackCustodyDirectTextKind,
			contract: ackCustodyContract,
			message:  fmt.Sprintf(`{"type":"message_deletion","version":"2","id":"delete","senderPeerId":%q,"encrypted":{"kem":"k","ciphertext":"c","nonce":"n"}}`, sender),
		},
		{
			name:     "contact request",
			kind:     ackCustodyDirectTextKind,
			contract: ackCustodyContract,
			message:  fmt.Sprintf(`{"type":"contact_request","version":"2","id":"contact","senderPeerId":%q,"encrypted":{"kem":"k","ciphertext":"c","nonce":"n"}}`, sender),
		},
		{
			name:     "group message",
			kind:     ackCustodyDirectTextKind,
			contract: ackCustodyContract,
			message:  fmt.Sprintf(`{"type":"group_message","version":"2","id":"group","senderPeerId":%q,"encrypted":{"kem":"k","ciphertext":"c","nonce":"n"}}`, sender),
		},
		{name: "malformed", kind: ackCustodyDirectTextKind, contract: ackCustodyContract, message: `{"type":`},
		{name: "unknown kind", kind: "generic", contract: ackCustodyContract, message: ackCustodyTextEnvelope("generic", sender, "c")},
		{name: "missing request contract", kind: ackCustodyDirectTextKind, message: ackCustodyTextEnvelope("missing-contract", sender, "c")},
		{name: "mutated request contract", kind: ackCustodyDirectTextKind, contract: "ack_or_expiry_v2", message: ackCustodyTextEnvelope("mutated-contract", sender, "c")},
		{name: "sender mismatch", kind: ackCustodyDirectTextKind, contract: ackCustodyContract, message: ackCustodyTextEnvelope("mismatch", "forged-peer", "c")},
		{
			name:     "extra outer group field",
			kind:     ackCustodyDirectTextKind,
			contract: ackCustodyContract,
			message:  fmt.Sprintf(`{"type":"chat_message","version":"2","id":"extra","groupId":"group","senderPeerId":%q,"encrypted":{"kem":"k","ciphertext":"c","nonce":"n"}}`, sender),
		},
		{
			name:     "incomplete encrypted fields",
			kind:     ackCustodyDirectTextKind,
			contract: ackCustodyContract,
			message:  fmt.Sprintf(`{"type":"chat_message","version":"2","id":"incomplete","senderPeerId":%q,"encrypted":{"kem":"k","ciphertext":"","nonce":"n"}}`, sender),
		},
		{
			name:     "reaction unsupported action",
			kind:     ackCustodyDirectReactionKind,
			contract: ackCustodyContract,
			message:  ackCustodyReactionEnvelope("reaction-invalid", "dance", "target", sender, "c"),
		},
		{
			name:     "reaction missing target",
			kind:     ackCustodyDirectReactionKind,
			contract: ackCustodyContract,
			message:  ackCustodyReactionEnvelope("reaction-no-target", "add", "", sender, "c"),
		},
	}
	for _, tc := range ineligible {
		t.Run(tc.name, func(t *testing.T) {
			resp := sendAckCustodyStoreRequest(
				t,
				env,
				recipient,
				tc.kind,
				tc.contract,
				tc.message,
			)
			if resp.Status != "ERROR" || resp.ErrorCode != ackCustodyErrorIneligible {
				t.Fatalf("ineligible response = %#v, want CUSTODY_INELIGIBLE", resp)
			}
			if resp.CustodyContract != "" || resp.StoreStatus != "" {
				t.Fatalf("ineligible response carried accepting fields: %#v", resp)
			}
		})
	}

	// Allow any eligible no-token push goroutine to settle; invalid shapes must
	// never reach the sender and neither physical lane may change.
	time.Sleep(20 * time.Millisecond)
	if got := backend.CountAckCustody(recipient); got != beforeProtected {
		t.Fatalf("protected lane changed on exclusions: got %d want %d", got, beforeProtected)
	}
	if got := backend.Count(recipient); got != beforeLegacy {
		t.Fatalf("legacy shadow lane changed on exclusions: got %d want %d", got, beforeLegacy)
	}
	if got := recorder.SendCallCount(); got != beforePush {
		t.Fatalf("push sender calls changed on exclusions: got %d want %d", got, beforePush)
	}
}
