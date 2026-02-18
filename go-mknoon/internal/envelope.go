package internal

import "encoding/json"

// V1Envelope is the unencrypted wire format.
// { "type": "chat_message", "version": "1", "payload": { "id": "...", "text": "...", "timestamp": "..." } }
type V1Envelope struct {
	Type    string                 `json:"type"`
	Version string                 `json:"version"`
	Payload map[string]interface{} `json:"payload"`
}

// V2Encrypted holds the encrypted fields of a v2 envelope.
type V2Encrypted struct {
	Kem        string `json:"kem"`
	Ciphertext string `json:"ciphertext"`
	Nonce      string `json:"nonce"`
}

// V2Envelope is the post-quantum encrypted wire format.
// { "version": "2", "encrypted": { "kem": "...", "ciphertext": "...", "nonce": "..." } }
type V2Envelope struct {
	Version   string      `json:"version"`
	Encrypted V2Encrypted `json:"encrypted"`
}

// ParseEnvelopeVersion reads the "version" field from a JSON message to determine
// whether it's a v1 or v2 envelope. Returns "1", "2", or "" if unknown.
func ParseEnvelopeVersion(data []byte) string {
	var peek struct {
		Version string `json:"version"`
	}
	if err := json.Unmarshal(data, &peek); err != nil {
		return ""
	}
	if peek.Version == "2" {
		return "2"
	}
	// v1 has version "1" or may have "type" field
	if peek.Version == "1" {
		return "1"
	}
	// Check for type field (v1 marker)
	var peek2 struct {
		Type string `json:"type"`
	}
	if err := json.Unmarshal(data, &peek2); err == nil && peek2.Type != "" {
		return "1"
	}
	return ""
}

// MarshalV1 creates a v1 envelope JSON string.
func MarshalV1(msgType string, payload map[string]interface{}) (string, error) {
	env := V1Envelope{
		Type:    msgType,
		Version: "1",
		Payload: payload,
	}
	b, err := json.Marshal(env)
	if err != nil {
		return "", err
	}
	return string(b), nil
}

// MarshalV2 creates a v2 envelope JSON string.
func MarshalV2(kem, ciphertext, nonce string) (string, error) {
	env := V2Envelope{
		Version: "2",
		Encrypted: V2Encrypted{
			Kem:        kem,
			Ciphertext: ciphertext,
			Nonce:      nonce,
		},
	}
	b, err := json.Marshal(env)
	if err != nil {
		return "", err
	}
	return string(b), nil
}

// ParseV2Envelope parses a v2 envelope and returns the encrypted fields.
func ParseV2Envelope(data []byte) (*V2Encrypted, error) {
	var env V2Envelope
	if err := json.Unmarshal(data, &env); err != nil {
		return nil, err
	}
	return &env.Encrypted, nil
}

// ParseV1Envelope parses a v1 envelope and returns the full struct.
func ParseV1Envelope(data []byte) (*V1Envelope, error) {
	var env V1Envelope
	if err := json.Unmarshal(data, &env); err != nil {
		return nil, err
	}
	return &env, nil
}
