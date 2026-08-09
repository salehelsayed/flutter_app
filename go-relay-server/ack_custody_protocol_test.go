package main

import (
	"context"
	"fmt"
	"strings"
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
	return sendAckCustodyStoreRequestWithExpiryCeiling(
		t,
		env,
		recipient,
		kind,
		contract,
		message,
		nil,
	)
}

func sendAckCustodyStoreRequestWithExpiryCeiling(
	t *testing.T,
	env *inboxStreamEnv,
	recipient string,
	kind string,
	contract string,
	message string,
	ceiling *int64,
) inboxResponse {
	t.Helper()
	stream, err := env.sender.NewStream(context.Background(), env.server.ID(), InboxProtocol)
	if err != nil {
		t.Fatalf("open ack custody store stream: %v", err)
	}
	defer stream.Close()
	sendInboxReq(t, stream, inboxRequest{
		Action:                     ackCustodyStoreAction,
		To:                         recipient,
		Message:                    message,
		CustodyKind:                kind,
		CustodyContract:            contract,
		CustodyExpiresAtOrBeforeMs: ceiling,
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

func TestRelayNotificationClosure_DirectMutationCustody(t *testing.T) {
	server := miniredis.RunT(t)
	backend := newAckCustodyRedisBackend(t, server, "ack-mutation:", 16)
	inbox := NewInboxStoreWithBackendAndCapacity(
		backend,
		NewPushServiceWithBackend(newMemoryPushTokenStore()),
		16,
	)
	inbox.SetAckCustodyAdmissionEnabled(true)
	env := setupInboxStreamEnv(t, inbox, NewGroupInboxStore(500, 7*24*time.Hour))
	recipient := env.recipient.ID().String()
	sender := env.sender.ID().String()

	eligible := []struct {
		name    string
		message string
		prefix  string
	}{
		{
			name:    "exact edit",
			message: ackCustodyEditEnvelope("target", "edit-event", sender, "edit"),
			prefix:  directInboxEditEventIDDedupePrefix,
		},
		{
			name:    "exact deletion",
			message: ackCustodyDeletionEnvelope("deletion-event", sender, "deletion"),
			prefix:  directInboxDeletionEventIDDedupePrefix,
		},
	}
	for _, tc := range eligible {
		t.Run(tc.name, func(t *testing.T) {
			resp := sendAckCustodyStoreRequest(
				t,
				env,
				recipient,
				ackCustodyDirectMutationKind,
				ackCustodyContract,
				tc.message,
			)
			if resp.Status != "OK" ||
				resp.StoreStatus != string(InboxStoreResultStored) ||
				resp.CustodyContract != ackCustodyContract {
				t.Fatalf("mutation response = %#v", resp)
			}
			key, ok := extractAckCustodyDedupeKey(
				ackCustodyDirectMutationKind,
				tc.message,
				sender,
			)
			if !ok || !strings.HasPrefix(key, tc.prefix) {
				t.Fatalf("mutation key = %q, %v; want prefix %q", key, ok, tc.prefix)
			}
		})
	}

	ineligible := []struct {
		name    string
		kind    string
		message string
	}{
		{
			name:    "edit under reaction kind",
			kind:    ackCustodyDirectReactionKind,
			message: ackCustodyEditEnvelope("target-x", "cross-edit", sender, "edit"),
		},
		{
			name:    "reaction under mutation kind",
			kind:    ackCustodyDirectMutationKind,
			message: ackCustodyReactionEnvelope("cross-reaction", "add", "target", sender, "reaction"),
		},
		{
			name: "deletion with extra target id",
			kind: ackCustodyDirectMutationKind,
			message: fmt.Sprintf(
				`{"type":"message_deletion","version":"2","id":"target","eventId":"extra","senderPeerId":%q,"encrypted":{"kem":"k","ciphertext":"c","nonce":"n"}}`,
				sender,
			),
		},
		{
			name:    "sender mismatch",
			kind:    ackCustodyDirectMutationKind,
			message: ackCustodyDeletionEnvelope("mismatch", "forged", "deletion"),
		},
	}
	for _, tc := range ineligible {
		t.Run(tc.name, func(t *testing.T) {
			resp := sendAckCustodyStoreRequest(
				t,
				env,
				recipient,
				tc.kind,
				ackCustodyContract,
				tc.message,
			)
			if resp.Status != "ERROR" || resp.ErrorCode != ackCustodyErrorIneligible {
				t.Fatalf("ineligible mutation response = %#v", resp)
			}
		})
	}
}

func TestRelayNotificationClosure_DirectMediaEnvelopeExpiryCeiling(t *testing.T) {
	setup := func(t *testing.T, prefix string) (
		*miniredis.Miniredis,
		*redisInboxBackend,
		*InboxStore,
		*inboxStreamEnv,
		*time.Time,
	) {
		t.Helper()
		server := miniredis.RunT(t)
		backend := newAckCustodyRedisBackend(t, server, prefix, 32)
		inbox := NewInboxStoreWithBackendAndCapacity(
			backend,
			NewPushServiceWithBackend(newMemoryPushTokenStore()),
			32,
		)
		inbox.SetAckCustodyAdmissionEnabled(true)
		now := time.UnixMilli(2_000_000_000_000)
		inbox.SetAckCustodyNowForTest(func() time.Time { return now })
		env := setupInboxStreamEnv(t, inbox, NewGroupInboxStore(500, 7*24*time.Hour))
		return server, backend, inbox, env, &now
	}

	t.Run("exact bound persists atomically and duplicate cannot refresh", func(t *testing.T) {
		_, backend, _, env, now := setup(t, "media-expiry-exact:")
		recipient := env.recipient.ID().String()
		sender := env.sender.ID().String()
		ceiling := now.Add(2 * time.Hour).UnixMilli()
		message := ackCustodyTextEnvelope("media-exact", sender, "cipher")

		stored := sendAckCustodyStoreRequestWithExpiryCeiling(
			t,
			env,
			recipient,
			ackCustodyDirectTextKind,
			ackCustodyContract,
			message,
			&ceiling,
		)
		if stored.Status != "OK" ||
			stored.StoreStatus != string(InboxStoreResultStored) ||
			stored.ExpiresAtMs != ceiling {
			t.Fatalf("bounded store = %#v, want exact expiry %d", stored, ceiling)
		}
		protected := redisInboxMessagesForKey(t, backend, backend.ackCustodyKey(recipient))
		shadow := redisInboxMessagesForKey(t, backend, backend.key(recipient))
		if len(protected) != 1 || len(shadow) != 1 ||
			protected[0].ExpiresAtMs != ceiling || shadow[0].ExpiresAtMs != ceiling ||
			protected[0].ID != shadow[0].ID {
			t.Fatalf("bounded protected/shadow rows = %#v / %#v", protected, shadow)
		}
		original := protected[0]

		duplicate := sendAckCustodyStoreRequestWithExpiryCeiling(
			t,
			env,
			recipient,
			ackCustodyDirectTextKind,
			ackCustodyContract,
			message,
			&ceiling,
		)
		if duplicate.Status != "OK" ||
			duplicate.StoreStatus != string(InboxStoreResultDuplicate) ||
			duplicate.ExpiresAtMs != ceiling {
			t.Fatalf("exact bounded duplicate = %#v", duplicate)
		}
		if got := redisInboxMessagesForKey(t, backend, backend.ackCustodyKey(recipient)); len(got) != 1 || got[0].ID != original.ID ||
			got[0].From != original.From || got[0].Message != original.Message ||
			got[0].Timestamp != original.Timestamp ||
			got[0].ExpiresAtMs != original.ExpiresAtMs {
			t.Fatalf("exact duplicate changed protected authority: %#v want %#v", got, original)
		}

		changedCeiling := ceiling - time.Minute.Milliseconds()
		changed := sendAckCustodyStoreRequestWithExpiryCeiling(
			t,
			env,
			recipient,
			ackCustodyDirectTextKind,
			ackCustodyContract,
			message,
			&changedCeiling,
		)
		if changed.Status != "ERROR" || changed.ErrorCode != ackCustodyErrorIdentityConflict {
			t.Fatalf("changed ceiling = %#v, want identity conflict", changed)
		}
		omitted := sendAckCustodyStoreRequest(
			t,
			env,
			recipient,
			ackCustodyDirectTextKind,
			ackCustodyContract,
			message,
		)
		if omitted.Status != "ERROR" || omitted.ErrorCode != ackCustodyErrorIdentityConflict {
			t.Fatalf("omitted retry after bounded store = %#v, want identity conflict", omitted)
		}
	})

	t.Run("omission preserves text and reaction timestamp expiry bytes", func(t *testing.T) {
		_, backend, _, env, now := setup(t, "media-expiry-omitted:")
		recipient := env.recipient.ID().String()
		sender := env.sender.ID().String()
		for _, tc := range []struct {
			kind    string
			message string
		}{
			{
				kind:    ackCustodyDirectTextKind,
				message: ackCustodyTextEnvelope("omitted-text", sender, "text"),
			},
			{
				kind: ackCustodyDirectReactionKind,
				message: ackCustodyReactionEnvelope(
					"omitted-reaction",
					"add",
					"target",
					sender,
					"reaction",
				),
			},
		} {
			resp := sendAckCustodyStoreRequest(
				t,
				env,
				recipient,
				tc.kind,
				ackCustodyContract,
				tc.message,
			)
			if resp.Status != "OK" ||
				resp.ExpiresAtMs != now.Add(maxMessageAge).UnixMilli() {
				t.Fatalf("omitted %s response = %#v", tc.kind, resp)
			}
		}

		for _, key := range []string{backend.ackCustodyKey(recipient), backend.key(recipient)} {
			raw, err := backend.client.LRange(context.Background(), key, 0, -1).Result()
			if err != nil {
				t.Fatalf("read omitted rows: %v", err)
			}
			for _, payload := range raw {
				if strings.Contains(payload, `"expiresAtMs"`) {
					t.Fatalf("omitted custody changed frozen row bytes: %s", payload)
				}
			}
		}
	})

	t.Run("invalid bounds and reaction bounds are ineligible", func(t *testing.T) {
		_, backend, _, env, now := setup(t, "media-expiry-invalid:")
		recipient := env.recipient.ID().String()
		sender := env.sender.ID().String()
		zero := int64(0)
		expired := now.UnixMilli()
		tooLate := now.Add(maxMessageAge).Add(time.Millisecond).UnixMilli()
		reactionCeiling := now.Add(time.Hour).UnixMilli()
		for index, tc := range []struct {
			kind    string
			ceiling *int64
		}{
			{kind: ackCustodyDirectTextKind, ceiling: &zero},
			{kind: ackCustodyDirectTextKind, ceiling: &expired},
			{kind: ackCustodyDirectTextKind, ceiling: &tooLate},
			{kind: ackCustodyDirectReactionKind, ceiling: &reactionCeiling},
		} {
			message := ackCustodyTextEnvelope(fmt.Sprintf("invalid-%d", index), sender, "cipher")
			if tc.kind == ackCustodyDirectReactionKind {
				message = ackCustodyReactionEnvelope(
					fmt.Sprintf("invalid-%d", index),
					"add",
					"target",
					sender,
					"cipher",
				)
			}
			resp := sendAckCustodyStoreRequestWithExpiryCeiling(
				t,
				env,
				recipient,
				tc.kind,
				ackCustodyContract,
				message,
				tc.ceiling,
			)
			if resp.Status != "ERROR" || resp.ErrorCode != ackCustodyErrorIneligible {
				t.Fatalf("invalid bound %d response = %#v", index, resp)
			}
		}
		if backend.CountAckCustody(recipient) != 0 || backend.Count(recipient) != 0 {
			t.Fatal("invalid bounds wrote protected or shadow state")
		}
	})

	t.Run("ceiling bearing legacy-only row cannot promote", func(t *testing.T) {
		_, backend, _, env, now := setup(t, "media-expiry-promotion:")
		recipient := env.recipient.ID().String()
		sender := env.sender.ID().String()
		ceiling := now.Add(time.Hour).UnixMilli()
		message := ackCustodyTextEnvelope("legacy-only-ceiling", sender, "cipher")
		result, err := backend.Store(recipient, inboxMessage{
			From:        sender,
			Message:     message,
			Timestamp:   now.UnixMilli(),
			ExpiresAtMs: ceiling,
		})
		if err != nil || result != InboxStoreResultStored {
			t.Fatalf("seed legacy-only ceiling = (%q, %v)", result, err)
		}
		resp := sendAckCustodyStoreRequestWithExpiryCeiling(
			t,
			env,
			recipient,
			ackCustodyDirectTextKind,
			ackCustodyContract,
			message,
			&ceiling,
		)
		if resp.Status != "ERROR" || resp.ErrorCode != ackCustodyErrorIdentityConflict {
			t.Fatalf("ceiling promotion response = %#v", resp)
		}
		if backend.CountAckCustody(recipient) != 0 || backend.Count(recipient) != 1 {
			t.Fatal("ceiling-bearing legacy-only conflict changed authority")
		}
	})

	t.Run("protected and shadow expire together across read count and stats", func(t *testing.T) {
		_, backend, _, env, now := setup(t, "media-expiry-prune:")
		recipient := env.recipient.ID().String()
		sender := env.sender.ID().String()
		ceiling := now.Add(time.Hour).UnixMilli()
		resp := sendAckCustodyStoreRequestWithExpiryCeiling(
			t,
			env,
			recipient,
			ackCustodyDirectTextKind,
			ackCustodyContract,
			ackCustodyTextEnvelope("media-expiry-prune", sender, "cipher"),
			&ceiling,
		)
		if resp.Status != "OK" {
			t.Fatalf("bounded store before prune = %#v", resp)
		}
		*now = time.UnixMilli(ceiling)

		if backend.CountAckCustody(recipient) != 0 || backend.Count(recipient) != 0 {
			t.Fatal("count retained a row at its exact expiry bound")
		}
		if peers, messages := backend.AckCustodyStats(); peers != 0 || messages != 0 {
			t.Fatalf("protected stats at expiry = %d/%d", peers, messages)
		}
		if peers, messages := backend.Stats(); peers != 0 || messages != 0 {
			t.Fatalf("shadow stats at expiry = %d/%d", peers, messages)
		}
		legacy, hasMore := backend.Retrieve(recipient, 50)
		if len(legacy) != 0 || hasMore {
			t.Fatalf("legacy destructive read outlived ceiling: %#v more=%v", legacy, hasMore)
		}
		if got := redisInboxMessagesForKey(t, backend, backend.ackCustodyKey(recipient)); len(got) != 1 {
			t.Fatalf("legacy read addressed protected authority: %#v", got)
		}
		pending, hasMore, err := backend.RetrieveAckCustodyPending(recipient, 50)
		if err != nil || len(pending) != 0 || hasMore {
			t.Fatalf("protected read outlived ceiling: %#v more=%v err=%v", pending, hasMore, err)
		}
		if got := redisInboxMessagesForKey(t, backend, backend.ackCustodyKey(recipient)); len(got) != 0 {
			t.Fatalf("expired protected row was not pruned: %#v", got)
		}
	})
}
