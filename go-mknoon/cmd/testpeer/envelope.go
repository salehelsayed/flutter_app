package main

import (
	"encoding/json"
	"fmt"
	"time"

	"github.com/google/uuid"
	mcrypto "github.com/mknoon/go-mknoon/crypto"
)

// buildV1Envelope creates a v1 plaintext envelope matching Flutter's wire format:
//
//	{
//	  "type": "chat_message",
//	  "version": "1",
//	  "payload": {
//	    "id": "<uuid>",
//	    "text": "...",
//	    "senderPeerId": "...",
//	    "senderUsername": "...",
//	    "timestamp": "...",
//	    "quotedMessageId": "..."   // optional
//	    "media": [...]             // optional
//	  }
//	}
func buildV1Envelope(text, senderPeerId, senderUsername string, opts map[string]interface{}) (string, string, error) {
	msgID := ""
	if mid, ok := opts["messageId"].(string); ok && mid != "" {
		msgID = mid
	} else {
		msgID = uuid.New().String()
	}
	ts := time.Now().UTC().Format(time.RFC3339Nano)

	payload := map[string]interface{}{
		"id":             msgID,
		"text":           text,
		"senderPeerId":   senderPeerId,
		"senderUsername":  senderUsername,
		"timestamp":      ts,
	}

	if qid, ok := opts["quotedMessageId"].(string); ok && qid != "" {
		payload["quotedMessageId"] = qid
	}
	if media, ok := opts["media"]; ok {
		payload["media"] = media
	}

	envelope := map[string]interface{}{
		"type":    "chat_message",
		"version": "1",
		"payload": payload,
	}

	b, err := json.Marshal(envelope)
	if err != nil {
		return "", "", fmt.Errorf("marshal v1 envelope: %w", err)
	}
	return string(b), msgID, nil
}

// buildV2Envelope creates a v2 encrypted envelope matching Flutter's wire format:
//
//	{
//	  "type": "chat_message",
//	  "version": "2",
//	  "senderPeerId": "...",
//	  "encrypted": {
//	    "kem": "...",
//	    "ciphertext": "...",
//	    "nonce": "..."
//	  }
//	}
//
// Note: Flutter's v2 format includes "type" and "senderPeerId" as cleartext,
// unlike Go's internal/envelope.go which omits them. The CLI peer must produce
// the Flutter format for compatibility.
func buildV2Envelope(
	text, senderPeerId, senderUsername string,
	recipientMlKemPublicKey string,
	opts map[string]interface{},
) (string, string, error) {
	msgID := ""
	if mid, ok := opts["messageId"].(string); ok && mid != "" {
		msgID = mid
	} else {
		msgID = uuid.New().String()
	}
	ts := time.Now().UTC().Format(time.RFC3339Nano)

	// Build the inner payload (plaintext to encrypt).
	inner := map[string]interface{}{
		"id":             msgID,
		"text":           text,
		"senderPeerId":   senderPeerId,
		"senderUsername":  senderUsername,
		"timestamp":      ts,
	}

	if qid, ok := opts["quotedMessageId"].(string); ok && qid != "" {
		inner["quotedMessageId"] = qid
	}
	if media, ok := opts["media"]; ok {
		inner["media"] = media
	}

	innerJSON, err := json.Marshal(inner)
	if err != nil {
		return "", "", fmt.Errorf("marshal inner payload: %w", err)
	}

	// Encrypt using ML-KEM-768 + AES-256-GCM.
	encrypted, err := mcrypto.EncryptMessage(recipientMlKemPublicKey, string(innerJSON))
	if err != nil {
		return "", "", fmt.Errorf("encrypt message: %w", err)
	}

	// Build Flutter-compatible v2 envelope.
	envelope := map[string]interface{}{
		"type":         "chat_message",
		"version":      "2",
		"senderPeerId": senderPeerId,
		"encrypted": map[string]string{
			"kem":        encrypted.Kem,
			"ciphertext": encrypted.Ciphertext,
			"nonce":      encrypted.Nonce,
		},
	}

	b, err := json.Marshal(envelope)
	if err != nil {
		return "", "", fmt.Errorf("marshal v2 envelope: %w", err)
	}
	return string(b), msgID, nil
}

// parseV1Envelope parses a received v1 envelope and returns the payload fields.
func parseV1Envelope(data string) (map[string]interface{}, error) {
	var env struct {
		Type    string                 `json:"type"`
		Version string                 `json:"version"`
		Payload map[string]interface{} `json:"payload"`
	}
	if err := json.Unmarshal([]byte(data), &env); err != nil {
		return nil, fmt.Errorf("unmarshal: %w", err)
	}
	if env.Type != "chat_message" {
		return nil, fmt.Errorf("unexpected type: %s", env.Type)
	}
	if env.Version != "1" {
		return nil, fmt.Errorf("unexpected version: %s", env.Version)
	}
	if env.Payload == nil {
		return nil, fmt.Errorf("missing payload")
	}
	return env.Payload, nil
}

// parseV2Envelope parses a received v2 envelope and decrypts using the
// recipient's ML-KEM secret key.
func parseV2Envelope(data string, ownMlKemSecretKey string) (map[string]interface{}, error) {
	var env struct {
		Type         string `json:"type"`
		Version      string `json:"version"`
		SenderPeerId string `json:"senderPeerId"`
		Encrypted    struct {
			Kem        string `json:"kem"`
			Ciphertext string `json:"ciphertext"`
			Nonce      string `json:"nonce"`
		} `json:"encrypted"`
	}
	if err := json.Unmarshal([]byte(data), &env); err != nil {
		return nil, fmt.Errorf("unmarshal: %w", err)
	}
	if env.Type != "chat_message" {
		return nil, fmt.Errorf("unexpected type: %s", env.Type)
	}
	if env.Version != "2" {
		return nil, fmt.Errorf("unexpected version: %s", env.Version)
	}

	plaintext, err := mcrypto.DecryptMessage(
		ownMlKemSecretKey,
		env.Encrypted.Kem,
		env.Encrypted.Ciphertext,
		env.Encrypted.Nonce,
	)
	if err != nil {
		return nil, fmt.Errorf("decrypt: %w", err)
	}

	var payload map[string]interface{}
	if err := json.Unmarshal([]byte(plaintext), &payload); err != nil {
		return nil, fmt.Errorf("unmarshal decrypted payload: %w", err)
	}
	return payload, nil
}
