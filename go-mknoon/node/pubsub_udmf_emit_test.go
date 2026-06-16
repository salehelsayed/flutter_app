package node

import (
	"errors"
	"strings"
	"testing"

	"github.com/mknoon/go-mknoon/internal"
)

// UDM-F: the group:key_epoch_behind diagnostic must carry the privacy-safe wire
// messageId (so the Dart self-heal can re-pull the missing key) and must NEVER
// leak ciphertext / nonce / signature / key material. Unit-tested via the
// synchronous emit path (bare &Node{eventCallback}) — no networking.
func TestEmitGroupKeyEpochBehind_CarriesMessageIdNoSecrets(t *testing.T) {
	collector := &testEventCollector{}
	n := &Node{eventCallback: collector}
	env := &internal.GroupEnvelope{
		Type:            "group_message",
		GroupId:         "group-udmf",
		MessageId:       "msg-udmf-1",
		SenderId:        "peer-sender",
		SenderPublicKey: "PUBKEY-not-secret",
		Signature:       "SECRET_SIGNATURE",
		KeyEpoch:        7,
		Encrypted: internal.GroupEncryptedPayload{
			Ciphertext: "SECRET_CIPHERTEXT",
			Nonce:      "SECRET_NONCE",
		},
	}

	n.emitGroupKeyEpochBehind("group-udmf", env, 3)

	events := collector.snapshot()
	if len(events) != 1 {
		t.Fatalf("expected exactly 1 emitted event, got %d", len(events))
	}
	ev := events[0]
	for _, want := range []string{
		"group:key_epoch_behind", "msg-udmf-1", "group-udmf",
		"peer-sender", "\"keyEpoch\":7", "\"localKeyEpoch\":3",
	} {
		if !strings.Contains(ev, want) {
			t.Fatalf("key_epoch_behind missing %q in %s", want, ev)
		}
	}
	for _, secret := range []string{"SECRET_CIPHERTEXT", "SECRET_NONCE", "SECRET_SIGNATURE"} {
		if strings.Contains(ev, secret) {
			t.Fatalf("key_epoch_behind LEAKED %q in %s", secret, ev)
		}
	}
}

// UDM-F: group:decryption_failed gains an additive privacy-safe messageId while
// still excluding all secret material.
func TestEmitGroupDecryptionFailed_CarriesMessageIdNoSecrets(t *testing.T) {
	collector := &testEventCollector{}
	n := &Node{eventCallback: collector}
	env := &internal.GroupEnvelope{
		Type:      "group_message",
		GroupId:   "group-df",
		MessageId: "msg-df-1",
		SenderId:  "peer-s",
		Signature: "SECRET_SIGNATURE",
		KeyEpoch:  5,
		Encrypted: internal.GroupEncryptedPayload{
			Ciphertext: "SECRET_CIPHERTEXT",
			Nonce:      "SECRET_NONCE",
		},
	}
	keyInfo := &GroupKeyInfo{KeyEpoch: 4}

	n.emitGroupDecryptionFailed("group-df", env, keyInfo, errors.New("no group key available for epoch 5"), 12)

	events := collector.snapshot()
	if len(events) != 1 {
		t.Fatalf("expected exactly 1 emitted event, got %d", len(events))
	}
	ev := events[0]
	for _, want := range []string{
		"group:decryption_failed", "msg-df-1", "group-df",
		"peer-s", "\"keyEpoch\":5", "\"localKeyEpoch\":4",
	} {
		if !strings.Contains(ev, want) {
			t.Fatalf("decryption_failed missing %q in %s", want, ev)
		}
	}
	for _, secret := range []string{"SECRET_CIPHERTEXT", "SECRET_NONCE", "SECRET_SIGNATURE"} {
		if strings.Contains(ev, secret) {
			t.Fatalf("decryption_failed LEAKED %q in %s", secret, ev)
		}
	}
}
