package main

import (
	"encoding/json"
	"strings"
	"testing"

	mcrypto "github.com/mknoon/go-mknoon/crypto"
)

// TestV1EnvelopeMatchesFlutter verifies that buildV1Envelope produces JSON
// that exactly matches the Flutter MessagePayload.toJson() wire format.
func TestV1EnvelopeMatchesFlutter(t *testing.T) {
	envelope, msgID, err := buildV1Envelope(
		"Hello from test",
		"12D3KooWSenderPeerId",
		"TestUser",
		nil,
	)
	if err != nil {
		t.Fatalf("buildV1Envelope: %v", err)
	}

	if msgID == "" {
		t.Error("msgID should not be empty")
	}

	// Parse and verify structure.
	var parsed map[string]interface{}
	if err := json.Unmarshal([]byte(envelope), &parsed); err != nil {
		t.Fatalf("unmarshal: %v", err)
	}

	// Top-level fields.
	if parsed["type"] != "chat_message" {
		t.Errorf("type=%v, want chat_message", parsed["type"])
	}
	if parsed["version"] != "1" {
		t.Errorf("version=%v, want 1", parsed["version"])
	}

	// Payload fields.
	payload, ok := parsed["payload"].(map[string]interface{})
	if !ok {
		t.Fatal("payload is not a map")
	}
	if payload["id"] != msgID {
		t.Errorf("id=%v, want %s", payload["id"], msgID)
	}
	if payload["text"] != "Hello from test" {
		t.Errorf("text=%v", payload["text"])
	}
	if payload["senderPeerId"] != "12D3KooWSenderPeerId" {
		t.Errorf("senderPeerId=%v", payload["senderPeerId"])
	}
	if payload["senderUsername"] != "TestUser" {
		t.Errorf("senderUsername=%v", payload["senderUsername"])
	}
	if payload["timestamp"] == nil || payload["timestamp"] == "" {
		t.Error("timestamp should be set")
	}

	// Verify no extra top-level fields that Flutter wouldn't expect.
	expectedTopKeys := map[string]bool{"type": true, "version": true, "payload": true}
	for k := range parsed {
		if !expectedTopKeys[k] {
			t.Errorf("unexpected top-level key: %s", k)
		}
	}
}

// TestV1EnvelopeWithOptionalFields verifies optional fields.
func TestV1EnvelopeWithOptionalFields(t *testing.T) {
	opts := map[string]interface{}{
		"quotedMessageId": "quote-123",
		"media": []map[string]interface{}{
			{"id": "m1", "mimeType": "image/png", "width": 100, "height": 100},
		},
	}

	envelope, _, err := buildV1Envelope(
		"Reply text",
		"12D3KooWSender",
		"User",
		opts,
	)
	if err != nil {
		t.Fatalf("buildV1Envelope: %v", err)
	}

	var parsed struct {
		Payload struct {
			QuotedMessageId string                   `json:"quotedMessageId"`
			Media           []map[string]interface{} `json:"media"`
		} `json:"payload"`
	}
	if err := json.Unmarshal([]byte(envelope), &parsed); err != nil {
		t.Fatalf("unmarshal: %v", err)
	}

	if parsed.Payload.QuotedMessageId != "quote-123" {
		t.Errorf("quotedMessageId=%s, want quote-123", parsed.Payload.QuotedMessageId)
	}
	if len(parsed.Payload.Media) != 1 {
		t.Fatalf("media len=%d, want 1", len(parsed.Payload.Media))
	}
	if parsed.Payload.Media[0]["id"] != "m1" {
		t.Errorf("media[0].id=%v", parsed.Payload.Media[0]["id"])
	}
}

// TestV2EnvelopeMatchesFlutter verifies that buildV2Envelope produces JSON
// that matches Flutter's MessagePayload.buildEncryptedEnvelope() format.
//
// Flutter v2 format includes "type" and "senderPeerId" as cleartext fields —
// unlike Go's internal/envelope.go MarshalV2 which omits them.
func TestV2EnvelopeMatchesFlutter(t *testing.T) {
	// Generate recipient ML-KEM keys.
	kp, err := mcrypto.MlKemKeygen()
	if err != nil {
		t.Fatalf("MlKemKeygen: %v", err)
	}

	envelope, msgID, err := buildV2Envelope(
		"Secret message",
		"12D3KooWSenderPeerId",
		"TestUser",
		kp.PublicKey,
		nil,
	)
	if err != nil {
		t.Fatalf("buildV2Envelope: %v", err)
	}

	if msgID == "" {
		t.Error("msgID should not be empty")
	}

	// Parse and verify structure.
	var parsed map[string]interface{}
	if err := json.Unmarshal([]byte(envelope), &parsed); err != nil {
		t.Fatalf("unmarshal: %v", err)
	}

	// Flutter's v2 includes these cleartext fields (unlike Go's internal envelope).
	if parsed["type"] != "chat_message" {
		t.Errorf("type=%v, want chat_message", parsed["type"])
	}
	if parsed["version"] != "2" {
		t.Errorf("version=%v, want 2", parsed["version"])
	}
	if parsed["senderPeerId"] != "12D3KooWSenderPeerId" {
		t.Errorf("senderPeerId=%v", parsed["senderPeerId"])
	}

	// Encrypted block.
	encrypted, ok := parsed["encrypted"].(map[string]interface{})
	if !ok {
		t.Fatal("encrypted is not a map")
	}
	if encrypted["kem"] == nil || encrypted["kem"] == "" {
		t.Error("kem should be set")
	}
	if encrypted["ciphertext"] == nil || encrypted["ciphertext"] == "" {
		t.Error("ciphertext should be set")
	}
	if encrypted["nonce"] == nil || encrypted["nonce"] == "" {
		t.Error("nonce should be set")
	}

	// Should NOT have a "payload" key (that's v1).
	if parsed["payload"] != nil {
		t.Error("v2 should not have payload key")
	}

	// Verify we can decrypt it with the recipient's secret key.
	payload, err := parseV2Envelope(envelope, kp.SecretKey)
	if err != nil {
		t.Fatalf("parseV2Envelope: %v", err)
	}
	if payload["text"] != "Secret message" {
		t.Errorf("decrypted text=%v, want 'Secret message'", payload["text"])
	}
	if payload["id"] != msgID {
		t.Errorf("decrypted id=%v, want %s", payload["id"], msgID)
	}
	if payload["senderPeerId"] != "12D3KooWSenderPeerId" {
		t.Errorf("decrypted senderPeerId=%v", payload["senderPeerId"])
	}
}

// TestV2EnvelopeDecryptedByGoInternal verifies that a v2 envelope built by
// the test peer can be decrypted using the Go crypto package directly.
func TestV2EnvelopeDecryptedByGoInternal(t *testing.T) {
	kp, err := mcrypto.MlKemKeygen()
	if err != nil {
		t.Fatalf("MlKemKeygen: %v", err)
	}

	envelope, _, err := buildV2Envelope(
		"Cross-verify message",
		"12D3KooWSender",
		"User",
		kp.PublicKey,
		nil,
	)
	if err != nil {
		t.Fatalf("buildV2Envelope: %v", err)
	}

	// Extract encrypted fields.
	var parsed struct {
		Encrypted struct {
			Kem        string `json:"kem"`
			Ciphertext string `json:"ciphertext"`
			Nonce      string `json:"nonce"`
		} `json:"encrypted"`
	}
	if err := json.Unmarshal([]byte(envelope), &parsed); err != nil {
		t.Fatalf("unmarshal: %v", err)
	}

	// Decrypt using raw crypto package.
	plaintext, err := mcrypto.DecryptMessage(
		kp.SecretKey,
		parsed.Encrypted.Kem,
		parsed.Encrypted.Ciphertext,
		parsed.Encrypted.Nonce,
	)
	if err != nil {
		t.Fatalf("DecryptMessage: %v", err)
	}

	var inner map[string]interface{}
	if err := json.Unmarshal([]byte(plaintext), &inner); err != nil {
		t.Fatalf("unmarshal inner: %v", err)
	}

	if inner["text"] != "Cross-verify message" {
		t.Errorf("text=%v", inner["text"])
	}
}

// TestParseV1Envelope verifies parsing of v1 envelopes.
func TestParseV1Envelope(t *testing.T) {
	envelope := `{"type":"chat_message","version":"1","payload":{"id":"abc","text":"hello","senderPeerId":"peer1","senderUsername":"user1","timestamp":"2024-01-01T00:00:00Z"}}`

	payload, err := parseV1Envelope(envelope)
	if err != nil {
		t.Fatalf("parseV1Envelope: %v", err)
	}

	if payload["id"] != "abc" {
		t.Errorf("id=%v", payload["id"])
	}
	if payload["text"] != "hello" {
		t.Errorf("text=%v", payload["text"])
	}
}

// TestParseV1EnvelopeRejectsNonChat verifies parsing rejects non-chat types.
func TestParseV1EnvelopeRejectsNonChat(t *testing.T) {
	envelope := `{"type":"contact_request","version":"1","payload":{}}`

	_, err := parseV1Envelope(envelope)
	if err == nil {
		t.Error("expected error for non-chat type")
	}
	if !strings.Contains(err.Error(), "unexpected type") {
		t.Errorf("expected 'unexpected type' error, got: %v", err)
	}
}

// TestParseV1EnvelopeRejectsV2 verifies parsing rejects v2 envelopes.
func TestParseV1EnvelopeRejectsV2(t *testing.T) {
	envelope := `{"type":"chat_message","version":"2","encrypted":{}}`

	_, err := parseV1Envelope(envelope)
	if err == nil {
		t.Error("expected error for v2 envelope")
	}
}
