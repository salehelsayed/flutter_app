package main

import (
	"bytes"
	"context"
	"crypto/ed25519"
	"crypto/rand"
	"encoding/base64"
	"encoding/json"
	"fmt"
	"sort"
	"strings"
	"testing"
	"time"

	"github.com/alicebob/miniredis/v2"
	"github.com/libp2p/go-libp2p/core/network"
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

func TestRelayNotificationClosure_GroupProtectedCustodyKinds(t *testing.T) {
	server := miniredis.RunT(t)
	backend := newAckCustodyRedisBackend(t, server, "ack-group-363:", 32)
	inbox := NewInboxStoreWithBackendAndCapacity(
		backend,
		NewPushServiceWithBackend(newMemoryPushTokenStore()),
		32,
	)
	inbox.SetAckCustodyAdmissionEnabled(true)
	env := setupInboxStreamEnv(t, inbox, NewGroupInboxStore(500, 7*24*time.Hour))
	sender := env.sender.ID().String()
	recipientA := env.recipient.ID().String()
	recipientB := env.intruder.ID().String()

	envelope := func(kind, logicalID, recipient string) string {
		typeValue := "linked_group_bootstrap_v1"
		if kind == ackCustodyGroupAuthorityKind {
			typeValue = "group_authority_v1"
		}
		return fmt.Sprintf(
			`{"type":%q,"version":"1","id":%q,"senderPeerId":%q,"recipientPeerId":%q,"encrypted":{"kem":"k","ciphertext":"c","nonce":"n"}}`,
			typeValue,
			logicalID,
			sender,
			recipient,
		)
	}

	bootstrapA := envelope(ackCustodyGroupBootstrapKind, "bootstrap-shared", recipientA)
	storedA := sendAckCustodyStoreRequest(
		t,
		env,
		recipientA,
		ackCustodyGroupBootstrapKind,
		ackCustodyContract,
		bootstrapA,
	)
	if storedA.Status != "OK" || storedA.StoreStatus != string(InboxStoreResultStored) {
		t.Fatalf("bootstrap A store = %#v", storedA)
	}
	duplicateA := sendAckCustodyStoreRequest(
		t,
		env,
		recipientA,
		ackCustodyGroupBootstrapKind,
		ackCustodyContract,
		bootstrapA,
	)
	if duplicateA.Status != "OK" || duplicateA.StoreStatus != string(InboxStoreResultDuplicate) {
		t.Fatalf("bootstrap A duplicate = %#v", duplicateA)
	}
	bootstrapB := envelope(ackCustodyGroupBootstrapKind, "bootstrap-shared", recipientB)
	storedB := sendAckCustodyStoreRequest(
		t,
		env,
		recipientB,
		ackCustodyGroupBootstrapKind,
		ackCustodyContract,
		bootstrapB,
	)
	if storedB.Status != "OK" || storedB.StoreStatus != string(InboxStoreResultStored) {
		t.Fatalf("bootstrap B independent store = %#v", storedB)
	}
	authority := sendAckCustodyStoreRequest(
		t,
		env,
		recipientA,
		ackCustodyGroupAuthorityKind,
		ackCustodyContract,
		envelope(ackCustodyGroupAuthorityKind, "authority-shared", recipientA),
	)
	if authority.Status != "OK" || authority.StoreStatus != string(InboxStoreResultStored) {
		t.Fatalf("authority store = %#v", authority)
	}
	longAuthorityID := "15:member_removed" + strings.Repeat("18:transition-segment", 8) + "17:" + recipientB
	if len(longAuthorityID) <= 128 || len(longAuthorityID) > 512 {
		t.Fatalf("long canonical authority id length = %d", len(longAuthorityID))
	}
	longAuthority := sendAckCustodyStoreRequest(
		t,
		env,
		recipientB,
		ackCustodyGroupAuthorityKind,
		ackCustodyContract,
		envelope(ackCustodyGroupAuthorityKind, longAuthorityID, recipientB),
	)
	if longAuthority.Status != "OK" || longAuthority.StoreStatus != string(InboxStoreResultStored) {
		t.Fatalf("long canonical authority store = %#v", longAuthority)
	}
	if backend.CountAckCustody(recipientA) != 2 || backend.CountAckCustody(recipientB) != 2 {
		t.Fatalf(
			"per-recipient protected counts = A:%d B:%d, want 2/2",
			backend.CountAckCustody(recipientA),
			backend.CountAckCustody(recipientB),
		)
	}

	for _, tc := range []struct {
		name      string
		kind      string
		message   string
		recipient string
	}{
		{
			name:      "target mismatch",
			kind:      ackCustodyGroupBootstrapKind,
			message:   envelope(ackCustodyGroupBootstrapKind, "target-mismatch", recipientB),
			recipient: recipientA,
		},
		{
			name:      "kind type crossing",
			kind:      ackCustodyGroupAuthorityKind,
			message:   envelope(ackCustodyGroupBootstrapKind, "kind-cross", recipientA),
			recipient: recipientA,
		},
		{
			name:      "content kind excluded",
			kind:      ackCustodyGroupAuthorityKind,
			message:   fmt.Sprintf(`{"type":"group_message","version":"1","id":"content","senderPeerId":%q,"recipientPeerId":%q,"encrypted":{"kem":"k","ciphertext":"c","nonce":"n"}}`, sender, recipientA),
			recipient: recipientA,
		},
		{
			name:      "malformed logical id",
			kind:      ackCustodyGroupBootstrapKind,
			message:   envelope(ackCustodyGroupBootstrapKind, "bad/id", recipientA),
			recipient: recipientA,
		},
	} {
		t.Run(tc.name, func(t *testing.T) {
			resp := sendAckCustodyStoreRequest(
				t,
				env,
				tc.recipient,
				tc.kind,
				ackCustodyContract,
				tc.message,
			)
			if resp.Status != "ERROR" || resp.ErrorCode != ackCustodyErrorIneligible {
				t.Fatalf("ineligible protected group response = %#v", resp)
			}
		})
	}

}

type tc364GroupContentFixture struct {
	groupID             string
	logicalSenderPeerID string
	transportPeerID     string
	publicKey           ed25519.PublicKey
	privateKey          ed25519.PrivateKey
}

func newTC364GroupContentFixture(
	t *testing.T,
	groupID string,
	logicalSenderPeerID string,
	transportPeerID string,
) tc364GroupContentFixture {
	t.Helper()
	publicKey, privateKey, err := ed25519.GenerateKey(rand.Reader)
	if err != nil {
		t.Fatalf("generate TC364 signing key: %v", err)
	}
	return tc364GroupContentFixture{
		groupID:             groupID,
		logicalSenderPeerID: logicalSenderPeerID,
		transportPeerID:     transportPeerID,
		publicKey:           publicKey,
		privateKey:          privateKey,
	}
}

func (f tc364GroupContentFixture) envelope(
	t *testing.T,
	payloadType string,
	contentEventID string,
	action string,
	recipients []string,
	variant string,
) string {
	t.Helper()
	recipients = append([]string(nil), recipients...)
	sort.Strings(recipients)
	recipientSetHash := groupReactionPeerSetHash(recipients)
	const authorityEventAt = "2026-08-13T12:34:56.123456Z"
	const authorityEventID = "authority-content-v1"
	const keyEpoch = int64(7)
	publicKey := base64.StdEncoding.EncodeToString(f.publicKey)
	ciphertext := "ciphertext-" + variant
	nonce := "nonce-" + variant
	signedFields := map[string]interface{}{
		"schemaVersion":          1,
		"kind":                   "group_offline_replay",
		"custodyKind":            ackCustodyGroupContentKind,
		"groupId":                f.groupID,
		"payloadType":            payloadType,
		"keyEpoch":               keyEpoch,
		"messageId":              contentEventID,
		"contentEventId":         contentEventID,
		"authorityEventAt":       authorityEventAt,
		"authorityEventId":       authorityEventID,
		"authorityKeyEpoch":      keyEpoch,
		"senderPeerId":           f.logicalSenderPeerID,
		"senderDeviceId":         "device-tc364",
		"senderTransportPeerId":  f.transportPeerID,
		"senderSigningPublicKey": publicKey,
		"senderKeyPackageId":     "key-package-tc364",
		"ciphertextHash":         sha256Hex(ciphertext),
		"nonceHash":              sha256Hex(nonce),
		"plaintextHash":          sha256Hex("plaintext-" + variant),
		"recipientPeerIds":       recipients,
		"recipientSetHash":       recipientSetHash,
	}
	signedPayload, err := canonicalGroupReactionJSON(signedFields)
	if err != nil {
		t.Fatalf("canonical TC364 signed payload: %v", err)
	}
	base := map[string]interface{}{
		"kind":                  "group_offline_replay",
		"version":               1,
		"custodyKind":           ackCustodyGroupContentKind,
		"groupId":               f.groupID,
		"payloadType":           payloadType,
		"keyEpoch":              keyEpoch,
		"messageId":             contentEventID,
		"contentEventId":        contentEventID,
		"authorityEventAt":      authorityEventAt,
		"authorityEventId":      authorityEventID,
		"authorityKeyEpoch":     keyEpoch,
		"senderPeerId":          f.logicalSenderPeerID,
		"senderDeviceId":        "device-tc364",
		"senderTransportPeerId": f.transportPeerID,
		"senderPublicKey":       publicKey,
		"senderKeyPackageId":    "key-package-tc364",
		"recipientPeerIds":      recipients,
		"recipientSetHash":      recipientSetHash,
		"ciphertext":            ciphertext,
		"nonce":                 nonce,
		"signatureAlgorithm":    "ed25519",
		"signedPayload":         signedPayload,
		"signature": base64.StdEncoding.EncodeToString(
			ed25519.Sign(f.privateKey, []byte(signedPayload)),
		),
	}
	if payloadType == "group_reaction" {
		baseJSON, err := canonicalGroupReactionJSON(base)
		if err != nil {
			t.Fatalf("canonical TC364 reaction base: %v", err)
		}
		extensionSignedFields := map[string]interface{}{
			"kind":                                  groupReactionNotificationKind,
			"version":                               1,
			"transitionId":                          contentEventID,
			"action":                                action,
			"targetMessageId":                       "target-message-tc364",
			"reactorPeerId":                         f.logicalSenderPeerID,
			"reactorTransportPeerId":                f.transportPeerID,
			"replayRecipientSetHash":                recipientSetHash,
			"notificationRecipientTransportPeerIds": recipients,
			"baseEnvelopeHash":                      sha256Hex(baseJSON),
		}
		extensionSignedPayload, err := canonicalGroupReactionJSON(extensionSignedFields)
		if err != nil {
			t.Fatalf("canonical TC364 reaction extension: %v", err)
		}
		extension := make(map[string]interface{}, len(extensionSignedFields)+2)
		for key, value := range extensionSignedFields {
			if key != "kind" {
				extension[key] = value
			}
		}
		extension["signatureAlgorithm"] = "ed25519"
		extension["signedPayload"] = extensionSignedPayload
		extension["signature"] = base64.StdEncoding.EncodeToString(
			ed25519.Sign(f.privateKey, []byte(extensionSignedPayload)),
		)
		base["notificationExtension"] = extension
	}
	encoded, err := canonicalGroupReactionJSON(base)
	if err != nil {
		t.Fatalf("canonical TC364 envelope: %v", err)
	}
	return encoded
}

func mutateTC364Envelope(
	t *testing.T,
	raw string,
	privateKey ed25519.PrivateKey,
	mutateEnvelope func(map[string]interface{}),
	mutateSigned func(map[string]interface{}),
) string {
	t.Helper()
	var envelope map[string]interface{}
	if err := json.Unmarshal([]byte(raw), &envelope); err != nil {
		t.Fatalf("decode TC364 envelope for mutation: %v", err)
	}
	if mutateSigned != nil {
		var signed map[string]interface{}
		if err := json.Unmarshal([]byte(envelope["signedPayload"].(string)), &signed); err != nil {
			t.Fatalf("decode TC364 signed payload for mutation: %v", err)
		}
		mutateSigned(signed)
		signedPayload, err := canonicalGroupReactionJSON(signed)
		if err != nil {
			t.Fatalf("canonical mutated TC364 signed payload: %v", err)
		}
		envelope["signedPayload"] = signedPayload
		envelope["signature"] = base64.StdEncoding.EncodeToString(
			ed25519.Sign(privateKey, []byte(signedPayload)),
		)
	}
	if mutateEnvelope != nil {
		mutateEnvelope(envelope)
	}
	encoded, err := canonicalGroupReactionJSON(envelope)
	if err != nil {
		t.Fatalf("canonical mutated TC364 envelope: %v", err)
	}
	return encoded
}

func withTC365GroupMediaManifest(
	t *testing.T,
	raw string,
	privateKey ed25519.PrivateKey,
	manifest ackCustodyGroupMediaManifest,
) (envelopeJSON string, manifestJSON string) {
	t.Helper()
	manifestJSON, err := canonicalGroupReactionJSON(manifest)
	if err != nil {
		t.Fatalf("canonical TC365 media manifest: %v", err)
	}
	manifestHash := sha256Hex(manifestJSON)
	var envelope map[string]interface{}
	if err := json.Unmarshal([]byte(raw), &envelope); err != nil {
		t.Fatalf("decode TC365 envelope base: %v", err)
	}
	var signed map[string]interface{}
	if err := json.Unmarshal([]byte(envelope["signedPayload"].(string)), &signed); err != nil {
		t.Fatalf("decode TC365 signed base: %v", err)
	}
	envelope["mediaManifest"] = manifestJSON
	envelope["mediaManifestHash"] = manifestHash
	signed["mediaManifestHash"] = manifestHash
	signedPayload, err := canonicalGroupReactionJSON(signed)
	if err != nil {
		t.Fatalf("canonical TC365 signed payload: %v", err)
	}
	envelope["signedPayload"] = signedPayload
	envelope["signature"] = base64.StdEncoding.EncodeToString(
		ed25519.Sign(privateKey, []byte(signedPayload)),
	)
	envelopeJSON, err = canonicalGroupReactionJSON(envelope)
	if err != nil {
		t.Fatalf("canonical TC365 envelope: %v", err)
	}
	return envelopeJSON, manifestJSON
}

func addTC364UnknownOuterField(
	t *testing.T,
	raw string,
	privateKey ed25519.PrivateKey,
) string {
	t.Helper()
	var envelope map[string]interface{}
	if err := json.Unmarshal([]byte(raw), &envelope); err != nil {
		t.Fatalf("decode TC364 unknown-field fixture: %v", err)
	}
	envelope["futureField"] = "must-fail-closed"
	if rawExtension, exists := envelope["notificationExtension"]; exists {
		extension, ok := rawExtension.(map[string]interface{})
		if !ok {
			t.Fatalf("TC364 reaction extension has type %T", rawExtension)
		}
		delete(envelope, "notificationExtension")
		baseJSON, err := canonicalGroupReactionJSON(envelope)
		if err != nil {
			t.Fatalf("canonical TC364 unknown-field reaction base: %v", err)
		}
		baseHash := sha256Hex(baseJSON)
		extension["baseEnvelopeHash"] = baseHash
		var signed map[string]interface{}
		if err := json.Unmarshal([]byte(extension["signedPayload"].(string)), &signed); err != nil {
			t.Fatalf("decode TC364 reaction extension signed payload: %v", err)
		}
		signed["baseEnvelopeHash"] = baseHash
		signedPayload, err := canonicalGroupReactionJSON(signed)
		if err != nil {
			t.Fatalf("canonical TC364 unknown-field extension payload: %v", err)
		}
		extension["signedPayload"] = signedPayload
		extension["signature"] = base64.StdEncoding.EncodeToString(
			ed25519.Sign(privateKey, []byte(signedPayload)),
		)
		envelope["notificationExtension"] = extension
	}
	encoded, err := canonicalGroupReactionJSON(envelope)
	if err != nil {
		t.Fatalf("canonical TC364 unknown-field envelope: %v", err)
	}
	return encoded
}

func replaceTC364NumberLexeme(
	t *testing.T,
	raw string,
	field string,
	from string,
	to string,
	occurrence int,
) string {
	t.Helper()
	needle := fmt.Sprintf(`%q:%s`, field, from)
	replacement := fmt.Sprintf(`%q:%s`, field, to)
	searchFrom := 0
	for index := 0; index <= occurrence; index++ {
		relative := strings.Index(raw[searchFrom:], needle)
		if relative < 0 {
			t.Fatalf(
				"TC364 numeric lexeme %s occurrence %d missing from %s",
				needle,
				occurrence,
				raw,
			)
		}
		absolute := searchFrom + relative
		if index == occurrence {
			return raw[:absolute] + replacement + raw[absolute+len(needle):]
		}
		searchFrom = absolute + len(needle)
	}
	t.Fatalf("unreachable TC364 numeric lexeme mutation")
	return ""
}

func TestRelayNotificationClosure_GroupContentProtectedCustody(t *testing.T) {
	server := miniredis.RunT(t)
	backend := newAckCustodyRedisBackend(t, server, "ack-group-364:", 32)
	inbox := NewInboxStoreWithBackendAndCapacity(
		backend,
		NewPushServiceWithBackend(newMemoryPushTokenStore()),
		32,
	)
	inbox.SetAckCustodyAdmissionEnabled(true)
	env := setupInboxStreamEnv(t, inbox, NewGroupInboxStore(500, 7*24*time.Hour))
	sender := env.sender.ID().String()
	recipientA := env.recipient.ID().String()
	recipientB := env.intruder.ID().String()
	fixture := newTC364GroupContentFixture(t, "group-content-tc364", "logical-author", sender)
	transitionID := "gr1:" + strings.Repeat("a", 32) + ":00000000000000000001:" + strings.Repeat("b", 32)
	recipients := []string{recipientB, recipientA}

	message := fixture.envelope(t, "group_message", transitionID, "", recipients, "message-v1")
	messageKey, ok := extractAckCustodyDedupeKeyForRecipient(
		ackCustodyGroupContentKind,
		message,
		sender,
		recipientA,
	)
	if !ok || messageKey != ackCustodyGroupContentMessagePrefix+transitionID {
		t.Fatalf("message parser key=%q ok=%v envelope=%s", messageKey, ok, message)
	}
	storedA := sendAckCustodyStoreRequest(
		t, env, recipientA, ackCustodyGroupContentKind, ackCustodyContract, message,
	)
	if storedA.Status != "OK" || storedA.StoreStatus != string(InboxStoreResultStored) {
		t.Fatalf("message A store = %#v", storedA)
	}
	duplicateA := sendAckCustodyStoreRequest(
		t, env, recipientA, ackCustodyGroupContentKind, ackCustodyContract, message,
	)
	if duplicateA.Status != "OK" || duplicateA.StoreStatus != string(InboxStoreResultDuplicate) {
		t.Fatalf("message A Redis-reparsed duplicate = %#v", duplicateA)
	}
	storedB := sendAckCustodyStoreRequest(
		t, env, recipientB, ackCustodyGroupContentKind, ackCustodyContract, message,
	)
	if storedB.Status != "OK" || storedB.StoreStatus != string(InboxStoreResultStored) {
		t.Fatalf("message B recipient-scoped store = %#v", storedB)
	}

	reaction := fixture.envelope(t, "group_reaction", transitionID, "add", recipients, "reaction-v1")
	reactionKey, ok := extractAckCustodyDedupeKeyForRecipient(
		ackCustodyGroupContentKind,
		reaction,
		sender,
		recipientA,
	)
	if !ok || reactionKey != ackCustodyGroupContentReactionPrefix+transitionID || reactionKey == messageKey {
		t.Fatalf("reaction parser key=%q ok=%v messageKey=%q", reactionKey, ok, messageKey)
	}
	storedReaction := sendAckCustodyStoreRequest(
		t, env, recipientA, ackCustodyGroupContentKind, ackCustodyContract, reaction,
	)
	if storedReaction.Status != "OK" || storedReaction.StoreStatus != string(InboxStoreResultStored) {
		t.Fatalf("reaction namespace store = %#v", storedReaction)
	}
	if backend.CountAckCustody(recipientA) != 2 || backend.CountAckCustody(recipientB) != 1 {
		t.Fatalf("protected counts A=%d B=%d, want 2/1",
			backend.CountAckCustody(recipientA), backend.CountAckCustody(recipientB))
	}

	conflict := fixture.envelope(t, "group_message", transitionID, "", recipients, "message-v2")
	conflictResp := sendAckCustodyStoreRequest(
		t, env, recipientA, ackCustodyGroupContentKind, ackCustodyContract, conflict,
	)
	if conflictResp.Status != "ERROR" || conflictResp.ErrorCode != ackCustodyErrorIdentityConflict {
		t.Fatalf("same-event conflicting protected bytes = %#v", conflictResp)
	}

	messageOnlyA := fixture.envelope(
		t,
		"group_message",
		"message-recipient-a-only",
		"",
		[]string{recipientA},
		"recipient-a-only",
	)
	wrongTransportFixture := newTC364GroupContentFixture(
		t,
		"group-content-tc364",
		"logical-author",
		recipientA,
	)
	invalidReaction := fixture.envelope(
		t,
		"group_reaction",
		"not-a-gr1-transition",
		"add",
		recipients,
		"bad-transition",
	)
	unknownMessageField := addTC364UnknownOuterField(t, message, fixture.privateKey)
	unknownReactionField := addTC364UnknownOuterField(t, reaction, fixture.privateKey)
	lexicalMessageOuterVersion := replaceTC364NumberLexeme(t, message, "version", "1", "1.0", 0)
	lexicalMessageKeyEpoch := replaceTC364NumberLexeme(t, message, "keyEpoch", "7", "7.0", 0)
	lexicalMessageAuthorityKeyEpoch := replaceTC364NumberLexeme(t, message, "authorityKeyEpoch", "7", "7.0", 0)
	lexicalReactionExtensionVersion := replaceTC364NumberLexeme(t, reaction, "version", "1", "1.0", 0)
	lexicalReactionOuterVersion := replaceTC364NumberLexeme(t, reaction, "version", "1", "1.0", 1)
	lexicalReactionKeyEpoch := replaceTC364NumberLexeme(t, reaction, "keyEpoch", "7", "7.0", 0)
	lexicalReactionAuthorityKeyEpoch := replaceTC364NumberLexeme(t, reaction, "authorityKeyEpoch", "7", "7.0", 0)
	for _, tc := range []struct {
		name      string
		kind      string
		recipient string
		message   string
	}{
		{name: "request recipient absent from signed ACL", kind: ackCustodyGroupContentKind, recipient: recipientB, message: messageOnlyA},
		{name: "authenticated sender differs from signed transport", kind: ackCustodyGroupContentKind, recipient: recipientA, message: wrongTransportFixture.envelope(t, "group_message", "wrong-transport", "", []string{recipientA}, "wrong-transport")},
		{name: "outer protected namespace crossing", kind: ackCustodyGroupAuthorityKind, recipient: recipientA, message: message},
		{name: "missing top-level inner discriminator", kind: ackCustodyGroupContentKind, recipient: recipientA, message: mutateTC364Envelope(t, message, fixture.privateKey, func(value map[string]interface{}) { delete(value, "custodyKind") }, nil)},
		{name: "missing signed inner discriminator", kind: ackCustodyGroupContentKind, recipient: recipientA, message: mutateTC364Envelope(t, message, fixture.privateKey, nil, func(value map[string]interface{}) { delete(value, "custodyKind") })},
		{name: "crossed signed inner discriminator", kind: ackCustodyGroupContentKind, recipient: recipientA, message: mutateTC364Envelope(t, message, fixture.privateKey, nil, func(value map[string]interface{}) { value["custodyKind"] = ackCustodyGroupAuthorityKind })},
		{name: "crossed group", kind: ackCustodyGroupContentKind, recipient: recipientA, message: mutateTC364Envelope(t, message, fixture.privateKey, func(value map[string]interface{}) { value["groupId"] = "other-group" }, nil)},
		{name: "crossed content event", kind: ackCustodyGroupContentKind, recipient: recipientA, message: mutateTC364Envelope(t, message, fixture.privateKey, func(value map[string]interface{}) { value["contentEventId"] = "other-event" }, nil)},
		{name: "crossed authority epoch", kind: ackCustodyGroupContentKind, recipient: recipientA, message: mutateTC364Envelope(t, message, fixture.privateKey, func(value map[string]interface{}) { value["authorityKeyEpoch"] = 8 }, nil)},
		{name: "noncanonical authority timestamp", kind: ackCustodyGroupContentKind, recipient: recipientA, message: mutateTC364Envelope(t, message, fixture.privateKey, func(value map[string]interface{}) { value["authorityEventAt"] = "2026-08-13T12:34:56.123Z" }, nil)},
		{name: "malformed reaction transition", kind: ackCustodyGroupContentKind, recipient: recipientA, message: invalidReaction},
		{name: "unknown message outer field", kind: ackCustodyGroupContentKind, recipient: recipientA, message: unknownMessageField},
		{name: "unknown reaction outer field", kind: ackCustodyGroupContentKind, recipient: recipientA, message: unknownReactionField},
		{name: "message outer version decimal token", kind: ackCustodyGroupContentKind, recipient: recipientA, message: lexicalMessageOuterVersion},
		{name: "message key epoch decimal token", kind: ackCustodyGroupContentKind, recipient: recipientA, message: lexicalMessageKeyEpoch},
		{name: "message authority key epoch decimal token", kind: ackCustodyGroupContentKind, recipient: recipientA, message: lexicalMessageAuthorityKeyEpoch},
		{name: "reaction extension version decimal token", kind: ackCustodyGroupContentKind, recipient: recipientA, message: lexicalReactionExtensionVersion},
		{name: "reaction outer version decimal token", kind: ackCustodyGroupContentKind, recipient: recipientA, message: lexicalReactionOuterVersion},
		{name: "reaction key epoch decimal token", kind: ackCustodyGroupContentKind, recipient: recipientA, message: lexicalReactionKeyEpoch},
		{name: "reaction authority key epoch decimal token", kind: ackCustodyGroupContentKind, recipient: recipientA, message: lexicalReactionAuthorityKeyEpoch},
	} {
		t.Run(tc.name, func(t *testing.T) {
			resp := sendAckCustodyStoreRequest(
				t, env, tc.recipient, tc.kind, ackCustodyContract, tc.message,
			)
			if resp.Status != "ERROR" || resp.ErrorCode != ackCustodyErrorIneligible {
				t.Fatalf("ineligible TC364 response = %#v", resp)
			}
		})
	}
	for name, raw := range map[string]string{
		"message unknown field":                     unknownMessageField,
		"reaction unknown field":                    unknownReactionField,
		"message outer version decimal token":       lexicalMessageOuterVersion,
		"message key epoch decimal token":           lexicalMessageKeyEpoch,
		"message authority key epoch decimal token": lexicalMessageAuthorityKeyEpoch,
		"reaction extension version decimal token":  lexicalReactionExtensionVersion,
		"reaction outer version decimal token":      lexicalReactionOuterVersion,
		"reaction key epoch decimal token":          lexicalReactionKeyEpoch,
		"reaction authority epoch decimal token":    lexicalReactionAuthorityKeyEpoch,
	} {
		if got := extractStoredAckCustodyDedupeKey(raw, sender, recipientA); got != "" {
			t.Fatalf("ineligible %s stored row was reparsed: %q", name, got)
		}
	}

	legacyReplay := `{"kind":"group_offline_replay","messageId":"legacy-replay-id"}`
	if got := extractStoredAckCustodyDedupeKey(legacyReplay, sender, recipientA); got != directInboxTargetIDDedupePrefix+"legacy-replay-id" {
		t.Fatalf("unmarked legacy replay stored key = %q", got)
	}
	missingDiscriminators := mutateTC364Envelope(
		t,
		message,
		fixture.privateKey,
		func(value map[string]interface{}) { delete(value, "custodyKind") },
		func(value map[string]interface{}) { delete(value, "custodyKind") },
	)
	if got := extractStoredAckCustodyDedupeKey(missingDiscriminators, sender, recipientA); got != "" {
		t.Fatalf("strict-only stored shape fell through to legacy dedupe: %q", got)
	}
	var malformedSigned map[string]interface{}
	if err := json.Unmarshal([]byte(message), &malformedSigned); err != nil {
		t.Fatalf("decode TC364 malformed-signed fixture: %v", err)
	}
	delete(malformedSigned, "custodyKind")
	for _, field := range []string{
		"contentEventId",
		"authorityEventAt",
		"authorityEventId",
		"authorityKeyEpoch",
	} {
		delete(malformedSigned, field)
	}
	malformedSigned["signedPayload"] = `{"custodyKind":"group_content_v1"`
	malformedSignedJSON, err := canonicalGroupReactionJSON(malformedSigned)
	if err != nil {
		t.Fatalf("encode TC364 malformed-signed fixture: %v", err)
	}
	if got := extractStoredAckCustodyDedupeKey(malformedSignedJSON, sender, recipientA); got != "" {
		t.Fatalf("malformed marked stored content fell through to legacy dedupe: %q", got)
	}
	malformedSigned["signedPayload"] = `{"contentEventId":"event-without-kind"`
	malformedStrictFieldJSON, err := canonicalGroupReactionJSON(malformedSigned)
	if err != nil {
		t.Fatalf("encode TC364 malformed strict-field fixture: %v", err)
	}
	if got := extractStoredAckCustodyDedupeKey(malformedStrictFieldJSON, sender, recipientA); got != "" {
		t.Fatalf("malformed strict-field stored content fell through to legacy dedupe: %q", got)
	}
}

func TestRelayNotificationClosure_GroupMediaBlobCustody(t *testing.T) {
	t.Setenv(mediaCustodyAdmissionEnabledEnv, "")
	mediaEnv := setupTestEnv(t)
	currentNow := directMediaCustodyTestNow
	mediaEnv.media.SetDirectMediaBlobCustodyNowForTest(func() time.Time { return currentNow })
	recipientA := mediaEnv.recipient.ID().String()
	recipientB := mediaEnv.intruder.ID().String()
	bodyA := []byte("TC365 encrypted image bytes")
	bodyB := []byte("TC365 encrypted voice bytes")

	disabledReq := directMediaCustodyUploadRequest(
		"group-disabled",
		recipientA,
		"application/octet-stream",
		bodyA,
	)
	disabledReq.CustodyKind = groupMediaBlobCustodyKind
	disabled, ready := directMediaCustodyUpload(t, mediaEnv, mediaEnv.sender, disabledReq, bodyA)
	if ready || disabled.ErrorCode != mediaCustodyErrorAdmissionOff ||
		disabled.StoreStatus != mediaCustodyStoreDisabled {
		t.Fatalf("group kind bypassed shared default-off admission: %#v ready=%v", disabled, ready)
	}
	mediaEnv.media.SetDirectMediaBlobCustodyAdmissionEnabled(true)

	type targetProofs struct {
		a mediaResponse
		b mediaResponse
	}
	uploadGroupAttachment := func(
		id string,
		mime string,
		body []byte,
		startAt time.Time,
	) targetProofs {
		t.Helper()
		requestFor := func(recipient string) mediaRequest {
			req := directMediaCustodyUploadRequest(id, recipient, mime, body)
			req.CustodyKind = groupMediaBlobCustodyKind
			return req
		}
		currentNow = startAt
		reqA := requestFor(recipientA)
		storedA, sawReady := directMediaCustodyUpload(t, mediaEnv, mediaEnv.sender, reqA, body)
		if !sawReady {
			t.Fatalf("%s target A upload=%#v", id, storedA)
		}
		requireDirectMediaCustodyProof(t, storedA, reqA, mediaCustodyStoreStored, "")

		currentNow = startAt.Add(time.Minute)
		reqB := requestFor(recipientB)
		storedB, sawReady := directMediaCustodyUpload(t, mediaEnv, mediaEnv.sender, reqB, body)
		if !sawReady {
			t.Fatalf("%s target B upload=%#v", id, storedB)
		}
		requireDirectMediaCustodyProof(t, storedB, reqB, mediaCustodyStoreStored, "")
		if storedA.ExpiresAtMs == storedB.ExpiresAtMs {
			t.Fatalf("%s target receipts collapsed to one expiry: %#v / %#v", id, storedA, storedB)
		}
		return targetProofs{a: storedA, b: storedB}
	}

	imageProofs := uploadGroupAttachment(
		"group-blob-a",
		"image/jpeg",
		bodyA,
		directMediaCustodyTestNow,
	)
	voiceProofs := uploadGroupAttachment(
		"group-blob-b",
		"audio/ogg",
		bodyB,
		directMediaCustodyTestNow.Add(2*time.Minute),
	)
	if imageProofs.a.ID == voiceProofs.a.ID ||
		imageProofs.a.ExpiresAtMs == voiceProofs.a.ExpiresAtMs {
		t.Fatalf("distinct attachment custody collapsed: image=%#v voice=%#v", imageProofs.a, voiceProofs.a)
	}

	// A marker carrying the additive kind must survive the incumbent exact
	// disk reparse before download and ACK use the unchanged actions.
	reopened, err := NewMediaStore(mediaEnv.media.dataDir)
	if err != nil {
		t.Fatalf("reopen group media custody markers: %v", err)
	}
	reopened.SetDirectMediaBlobCustodyAdmissionEnabled(true)
	reopened.SetDirectMediaBlobCustodyNowForTest(func() time.Time { return currentNow })
	installDirectMediaCustodyStore(t, mediaEnv, reopened)
	if meta := directMediaCustodyFindEntry(reopened, recipientA, imageProofs.a.ID); meta == nil || meta.CustodyKind != groupMediaBlobCustodyKind {
		t.Fatalf("reparsed group marker=%#v", meta)
	}
	downloadReq := directMediaCustodyExactRequest(imageProofs.a, "download")
	downloaded, gotBody := directMediaCustodyDownload(
		t,
		mediaEnv,
		mediaEnv.recipient,
		downloadReq,
	)
	if downloaded.Status != "OK" || downloaded.CustodyKind != groupMediaBlobCustodyKind ||
		!bytes.Equal(gotBody, bodyA) {
		t.Fatalf("group strict download=%#v body=%q", downloaded, gotBody)
	}
	ackReq := directMediaCustodyExactRequest(imageProofs.a, mediaCustodyAckAction)
	acked := directMediaCustodyRequest(t, mediaEnv, mediaEnv.recipient, ackReq)
	requireDirectMediaCustodyProof(t, acked, ackReq, "", mediaCustodyAckAcked)

	// Direct remains exact/idempotent, while crossing either exact kind under
	// the same recipient+ID is an identity conflict rather than a duplicate.
	currentNow = directMediaCustodyTestNow.Add(4 * time.Minute)
	directReq := directMediaCustodyUploadRequest(
		"direct-preserved-tc365",
		recipientA,
		"application/octet-stream",
		bodyA,
	)
	directStored, ready := directMediaCustodyUpload(t, mediaEnv, mediaEnv.sender, directReq, bodyA)
	if !ready {
		t.Fatalf("incumbent direct store=%#v", directStored)
	}
	requireDirectMediaCustodyProof(t, directStored, directReq, mediaCustodyStoreStored, "")
	directDuplicate, ready := directMediaCustodyUpload(t, mediaEnv, mediaEnv.sender, directReq, bodyA)
	if ready {
		t.Fatal("incumbent direct duplicate requested a body")
	}
	requireDirectMediaCustodyProof(t, directDuplicate, directReq, mediaCustodyStoreDuplicate, "")
	groupCrossing := directReq
	groupCrossing.CustodyKind = groupMediaBlobCustodyKind
	if crossed, sawReady := directMediaCustodyUpload(
		t,
		mediaEnv,
		mediaEnv.sender,
		groupCrossing,
		bodyA,
	); sawReady || crossed.ErrorCode != mediaCustodyErrorIdentityConflict {
		t.Fatalf("direct-to-group crossed identity=%#v ready=%v", crossed, sawReady)
	}
	directCrossing := directMediaCustodyUploadRequest(
		voiceProofs.a.ID,
		recipientA,
		voiceProofs.a.Mime,
		bodyB,
	)
	if crossed, sawReady := directMediaCustodyUpload(
		t,
		mediaEnv,
		mediaEnv.sender,
		directCrossing,
		bodyB,
	); sawReady || crossed.ErrorCode != mediaCustodyErrorIdentityConflict {
		t.Fatalf("group-to-direct crossed identity=%#v ready=%v", crossed, sawReady)
	}

	server := miniredis.RunT(t)
	backend := newAckCustodyRedisBackend(t, server, "ack-group-media-365:", 32)
	inbox := NewInboxStoreWithBackendAndCapacity(
		backend,
		NewPushServiceWithBackend(newMemoryPushTokenStore()),
		32,
	)
	inbox.SetAckCustodyAdmissionEnabled(true)
	contentNow := directMediaCustodyTestNow.Add(5 * time.Minute)
	inbox.SetAckCustodyNowForTest(func() time.Time { return contentNow })
	groupInbox := NewGroupInboxStore(500, 7*24*time.Hour)
	presence := NewPresenceStore()
	mediaEnv.server.SetStreamHandler(InboxProtocol, func(stream network.Stream) {
		HandleInboxStream(stream, inbox, groupInbox, mediaEnv.server, presence, nil)
	})
	inboxEnv := &inboxStreamEnv{
		server:    mediaEnv.server,
		sender:    mediaEnv.sender,
		recipient: mediaEnv.recipient,
		intruder:  mediaEnv.intruder,
		presence:  presence,
	}
	fixture := newTC364GroupContentFixture(
		t,
		"group-media-content-tc365",
		"logical-author-tc365",
		mediaEnv.sender.ID().String(),
	)
	messageID := "group-media-message-tc365"
	recipients := []string{recipientB, recipientA}
	manifestRecipients := canonicalGroupReactionPeerIDs(recipients)
	expiryVector := func(recipientAExpiry, recipientBExpiry int64) []int64 {
		expiriesByRecipient := map[string]int64{
			recipientA: recipientAExpiry,
			recipientB: recipientBExpiry,
		}
		result := make([]int64, 0, len(manifestRecipients))
		for _, recipient := range manifestRecipients {
			result = append(result, expiriesByRecipient[recipient])
		}
		return result
	}
	baseEnvelope := fixture.envelope(
		t,
		"group_message",
		messageID,
		"",
		recipients,
		"group-media-v1",
	)
	manifest := ackCustodyGroupMediaManifest{
		Schema:           "group_media_manifest_v1",
		GroupID:          fixture.groupID,
		MessageID:        messageID,
		CustodyKind:      groupMediaBlobCustodyKind,
		CustodyContract:  directMediaBlobCustodyContract,
		RecipientPeerIDs: manifestRecipients,
		Attachments: []ackCustodyGroupMediaManifestAttachment{
			{
				AttachmentID:        "attachment-a",
				CustodyBlobID:       imageProofs.a.ID,
				CiphertextSHA256:    imageProofs.a.ContentHash,
				CiphertextSize:      imageProofs.a.Size,
				MIME:                imageProofs.a.Mime,
				MediaType:           "image",
				EncryptionScheme:    "blob_aes_256_gcm_v1",
				EncryptionKeyBase64: "a2V5LWE=",
				EncryptionNonce:     "bm9uY2UtYQ==",
				ExpiresAtMs:         expiryVector(imageProofs.a.ExpiresAtMs, imageProofs.b.ExpiresAtMs),
			},
			{
				AttachmentID:        "attachment-b",
				CustodyBlobID:       voiceProofs.a.ID,
				CiphertextSHA256:    voiceProofs.a.ContentHash,
				CiphertextSize:      voiceProofs.a.Size,
				MIME:                voiceProofs.a.Mime,
				MediaType:           "audio",
				EncryptionScheme:    "blob_aes_256_gcm_v1",
				EncryptionKeyBase64: "a2V5LWI=",
				EncryptionNonce:     "bm9uY2UtYg==",
				ExpiresAtMs:         expiryVector(voiceProofs.a.ExpiresAtMs, voiceProofs.b.ExpiresAtMs),
			},
		},
	}
	mediaEnvelope, manifestJSON := withTC365GroupMediaManifest(
		t,
		baseEnvelope,
		fixture.privateKey,
		manifest,
	)
	var mediaWire map[string]interface{}
	if err := json.Unmarshal([]byte(mediaEnvelope), &mediaWire); err != nil {
		t.Fatalf("decode compact TC365 media envelope: %v", err)
	}
	var mediaSigned map[string]interface{}
	if err := json.Unmarshal([]byte(mediaWire["signedPayload"].(string)), &mediaSigned); err != nil {
		t.Fatalf("decode compact TC365 signed payload: %v", err)
	}
	if mediaWire["mediaManifest"] != manifestJSON ||
		mediaWire["mediaManifestHash"] != sha256Hex(manifestJSON) ||
		mediaSigned["mediaManifestHash"] != sha256Hex(manifestJSON) {
		t.Fatalf("compact TC365 binding mismatch outer=%#v signed=%#v", mediaWire, mediaSigned)
	}
	if _, duplicated := mediaSigned["mediaManifest"]; duplicated {
		t.Fatal("compact TC365 signed payload duplicated raw mediaManifest")
	}
	ceilingA := imageProofs.a.ExpiresAtMs
	ceilingB := imageProofs.b.ExpiresAtMs
	if ceilingA == ceilingB || ceilingA >= voiceProofs.a.ExpiresAtMs ||
		ceilingB >= voiceProofs.b.ExpiresAtMs {
		t.Fatalf("fixture did not produce target-specific minimums A=%d B=%d", ceilingA, ceilingB)
	}

	t.Run("Dart_AES-256-GCM_scheme", func(t *testing.T) {
		const canonicalScheme = `"encryptionScheme":"blob_aes_256_gcm_v1"`
		if got := strings.Count(manifestJSON, canonicalScheme); got != len(manifest.Attachments) {
			t.Fatalf("Dart-canonical scheme occurrences=%d want=%d manifest=%s", got, len(manifest.Attachments), manifestJSON)
		}
		gotCeiling, accepted := parseAckCustodyGroupMediaManifest(
			manifestJSON,
			fixture.groupID,
			messageID,
			manifestRecipients,
			recipientA,
		)
		if !accepted || gotCeiling != ceilingA {
			t.Fatalf("relay rejected Dart AES-256-GCM manifest: accepted=%v ceiling=%d want=%d", accepted, gotCeiling, ceilingA)
		}
	})

	t.Run("obsolete_relay-only_AES-GCM_alias", func(t *testing.T) {
		obsoleteManifestJSON := strings.ReplaceAll(
			manifestJSON,
			`"encryptionScheme":"blob_aes_256_gcm_v1"`,
			`"encryptionScheme":"blob_aes_gcm_v1"`,
		)
		if obsoleteManifestJSON == manifestJSON {
			t.Fatal("obsolete relay-only alias mutation was vacuous")
		}
		if _, accepted := parseAckCustodyGroupMediaManifest(
			obsoleteManifestJSON,
			fixture.groupID,
			messageID,
			manifestRecipients,
			recipientA,
		); accepted {
			t.Fatal("relay accepted obsolete blob_aes_gcm_v1 alias")
		}
	})

	for _, tc := range []struct {
		name      string
		recipient string
		ceiling   *int64
	}{
		{name: "omitted media ceiling", recipient: recipientA},
		{name: "A request swaps B ceiling", recipient: recipientA, ceiling: &ceilingB},
		{name: "B request swaps A ceiling", recipient: recipientB, ceiling: &ceilingA},
	} {
		t.Run(tc.name, func(t *testing.T) {
			resp := sendAckCustodyStoreRequestWithExpiryCeiling(
				t,
				inboxEnv,
				tc.recipient,
				ackCustodyGroupContentKind,
				ackCustodyContract,
				mediaEnvelope,
				tc.ceiling,
			)
			if resp.Status != "ERROR" || resp.ErrorCode != ackCustodyErrorIneligible {
				t.Fatalf("crossed/omitted group media ceiling=%#v", resp)
			}
		})
	}
	for _, tc := range []struct {
		name      string
		recipient string
		ceiling   *int64
	}{
		{name: "target A", recipient: recipientA, ceiling: &ceilingA},
		{name: "target B", recipient: recipientB, ceiling: &ceilingB},
	} {
		t.Run(tc.name, func(t *testing.T) {
			resp := sendAckCustodyStoreRequestWithExpiryCeiling(
				t,
				inboxEnv,
				tc.recipient,
				ackCustodyGroupContentKind,
				ackCustodyContract,
				mediaEnvelope,
				tc.ceiling,
			)
			if resp.Status != "OK" || resp.StoreStatus != string(InboxStoreResultStored) ||
				resp.ExpiresAtMs != *tc.ceiling {
				t.Fatalf("exact group media content store=%#v", resp)
			}
		})
	}
	if backend.CountAckCustody(recipientA) != 1 || backend.CountAckCustody(recipientB) != 1 {
		t.Fatalf("group media content counts A=%d B=%d",
			backend.CountAckCustody(recipientA), backend.CountAckCustody(recipientB))
	}

	contentNow = time.UnixMilli(ceilingA)
	expired := sendAckCustodyStoreRequestWithExpiryCeiling(
		t,
		inboxEnv,
		recipientA,
		ackCustodyGroupContentKind,
		ackCustodyContract,
		mediaEnvelope,
		&ceilingA,
	)
	if expired.Status != "ERROR" || expired.ErrorCode != ackCustodyErrorIneligible {
		t.Fatalf("expired group media ceiling=%#v", expired)
	}

	contentNow = directMediaCustodyTestNow.Add(5 * time.Minute)
	missingHash := mutateTC364Envelope(
		t,
		mediaEnvelope,
		fixture.privateKey,
		func(value map[string]interface{}) { delete(value, "mediaManifestHash") },
		func(value map[string]interface{}) { delete(value, "mediaManifestHash") },
	)
	badManifest := strings.Replace(manifestJSON, `"custodyBlobId":"group-blob-a"`, `"custodyBlobId":"group-blob-crossed"`, 1)
	crossedManifest := mutateTC364Envelope(
		t,
		mediaEnvelope,
		fixture.privateKey,
		func(value map[string]interface{}) { value["mediaManifest"] = badManifest },
		nil,
	)
	duplicatedSignedManifest := mutateTC364Envelope(
		t,
		mediaEnvelope,
		fixture.privateKey,
		nil,
		func(value map[string]interface{}) { value["mediaManifest"] = manifestJSON },
	)
	for name, malformed := range map[string]string{
		"missing manifest hash":          missingHash,
		"crossed manifest hash":          crossedManifest,
		"duplicated signed raw manifest": duplicatedSignedManifest,
	} {
		resp := sendAckCustodyStoreRequestWithExpiryCeiling(
			t,
			inboxEnv,
			recipientA,
			ackCustodyGroupContentKind,
			ackCustodyContract,
			malformed,
			&ceilingA,
		)
		if resp.Status != "ERROR" || resp.ErrorCode != ackCustodyErrorIneligible {
			t.Fatalf("%s response=%#v", name, resp)
		}
		if got := extractStoredAckCustodyDedupeKey(
			malformed,
			mediaEnv.sender.ID().String(),
			recipientA,
		); got != "" {
			t.Fatalf("%s stored reparse=%q", name, got)
		}
	}

	blobFree := fixture.envelope(
		t,
		"group_message",
		"group-blob-free-tc365",
		"",
		recipients,
		"blob-free",
	)
	blobFreeStored := sendAckCustodyStoreRequest(
		t,
		inboxEnv,
		recipientA,
		ackCustodyGroupContentKind,
		ackCustodyContract,
		blobFree,
	)
	if blobFreeStored.Status != "OK" ||
		blobFreeStored.StoreStatus != string(InboxStoreResultStored) ||
		blobFreeStored.ExpiresAtMs != contentNow.Add(maxMessageAge).UnixMilli() {
		t.Fatalf("blob-free Plan364 lifetime changed=%#v", blobFreeStored)
	}
	blobFreeBounded := sendAckCustodyStoreRequestWithExpiryCeiling(
		t,
		inboxEnv,
		recipientB,
		ackCustodyGroupContentKind,
		ackCustodyContract,
		blobFree,
		&ceilingB,
	)
	if blobFreeBounded.Status != "ERROR" || blobFreeBounded.ErrorCode != ackCustodyErrorIneligible {
		t.Fatalf("blob-free content accepted an unattached ceiling=%#v", blobFreeBounded)
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
