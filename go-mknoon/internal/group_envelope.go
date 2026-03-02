package internal

import (
	"encoding/json"
	"fmt"
)

// GroupEncryptedPayload holds the encrypted fields of a v3 group envelope.
type GroupEncryptedPayload struct {
	Ciphertext string `json:"ciphertext"`
	Nonce      string `json:"nonce"`
}

// GroupEnvelope is the v3 group message wire format.
// {
//   "version": "3", "type": "group_message",
//   "groupId": "...", "senderId": "...", "senderPublicKey": "...",
//   "signature": "...", "keyEpoch": 0,
//   "encrypted": { "ciphertext": "...", "nonce": "..." }
// }
type GroupEnvelope struct {
	Version         string                `json:"version"`
	Type            string                `json:"type"`
	GroupId         string                `json:"groupId"`
	SenderId        string                `json:"senderId"`
	SenderPublicKey string                `json:"senderPublicKey"`
	Signature       string                `json:"signature"`
	KeyEpoch        int                   `json:"keyEpoch"`
	Encrypted       GroupEncryptedPayload `json:"encrypted"`
}

// GroupMessagePayload is the inner payload that gets encrypted inside a group
// envelope. It contains the actual message text and metadata.
type GroupMessagePayload struct {
	Text      string                 `json:"text"`
	Timestamp string                 `json:"timestamp"`
	Username  string                 `json:"username,omitempty"`
	Extra     map[string]interface{} `json:"extra,omitempty"`
}

// MarshalGroupEnvelope serializes a GroupEnvelope to a JSON string.
func MarshalGroupEnvelope(env *GroupEnvelope) (string, error) {
	b, err := json.Marshal(env)
	if err != nil {
		return "", fmt.Errorf("marshal group envelope: %w", err)
	}
	return string(b), nil
}

// ParseGroupEnvelope deserializes a JSON string into a GroupEnvelope.
// Returns an error if the JSON is invalid or if required fields are missing.
func ParseGroupEnvelope(data string) (*GroupEnvelope, error) {
	var env GroupEnvelope
	if err := json.Unmarshal([]byte(data), &env); err != nil {
		return nil, fmt.Errorf("parse group envelope: %w", err)
	}

	// Validate required fields.
	if env.GroupId == "" {
		return nil, fmt.Errorf("parse group envelope: missing groupId")
	}

	return &env, nil
}

// IsGroupEnvelope checks whether a JSON string is a v3 group message envelope
// by inspecting the version and type fields.
func IsGroupEnvelope(data string) bool {
	var peek struct {
		Version string `json:"version"`
		Type    string `json:"type"`
	}
	if err := json.Unmarshal([]byte(data), &peek); err != nil {
		return false
	}
	return peek.Version == "3" && peek.Type == "group_message"
}

// MarshalGroupPayload serializes a GroupMessagePayload to a JSON string.
func MarshalGroupPayload(payload *GroupMessagePayload) (string, error) {
	b, err := json.Marshal(payload)
	if err != nil {
		return "", fmt.Errorf("marshal group payload: %w", err)
	}
	return string(b), nil
}

// ParseGroupPayload deserializes a JSON string into a GroupMessagePayload.
func ParseGroupPayload(data string) (*GroupMessagePayload, error) {
	var payload GroupMessagePayload
	if err := json.Unmarshal([]byte(data), &payload); err != nil {
		return nil, fmt.Errorf("parse group payload: %w", err)
	}
	return &payload, nil
}
