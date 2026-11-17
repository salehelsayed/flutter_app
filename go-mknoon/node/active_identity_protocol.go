package node

import (
	"bytes"
	"crypto/ed25519"
	"encoding/base64"
	"encoding/json"
	"errors"
	"io"

	libp2pcrypto "github.com/libp2p/go-libp2p/core/crypto"
	"github.com/libp2p/go-libp2p/core/peer"
	"github.com/mknoon/go-mknoon/activitycalendar"
)

const (
	activeIdentityProtocolAction = "active_identity_v1"
	activeIdentityProtocolLimit  = 2048
)

type activeIdentityProtocolResult uint8

const (
	activeIdentityRetryable activeIdentityProtocolResult = iota
	activeIdentityAcknowledged
	activeIdentityUnsupported
)

var (
	errActiveIdentityInvalidRequest  = errors.New("invalid active identity request")
	errActiveIdentityInvalidResponse = errors.New("invalid active identity response")
	errActiveIdentityRelayFailure    = errors.New("active identity relay did not accept the assertion")
)

// privateKeyBase64 is padded base64 of the account's raw 64-byte Ed25519 key.
// The proof binds that account to the caller's authenticated transport identity.
func buildActiveIdentityRequest(day, accountPeerID, transportPeerID, privateKeyBase64 string) ([]byte, error) {
	if _, err := activitycalendar.Parse(day); err != nil {
		return nil, errActiveIdentityInvalidRequest
	}
	if len(accountPeerID) > activeIdentityProtocolLimit || len(transportPeerID) > activeIdentityProtocolLimit ||
		len(privateKeyBase64) != base64.StdEncoding.EncodedLen(ed25519.PrivateKeySize) {
		return nil, errActiveIdentityInvalidRequest
	}
	account, err := peer.Decode(accountPeerID)
	if err != nil || account.String() != accountPeerID {
		return nil, errActiveIdentityInvalidRequest
	}
	transport, err := peer.Decode(transportPeerID)
	if err != nil || transport.String() != transportPeerID {
		return nil, errActiveIdentityInvalidRequest
	}
	rawKey, err := base64.StdEncoding.Strict().DecodeString(privateKeyBase64)
	if err != nil || len(rawKey) != ed25519.PrivateKeySize || base64.StdEncoding.EncodeToString(rawKey) != privateKeyBase64 {
		return nil, errActiveIdentityInvalidRequest
	}
	// A raw Ed25519 key contains both seed and public key; refuse inconsistent
	// halves rather than signing a proof that the claimed account cannot verify.
	if !bytes.Equal(ed25519.NewKeyFromSeed(rawKey[:ed25519.SeedSize]), rawKey) {
		return nil, errActiveIdentityInvalidRequest
	}
	key, err := libp2pcrypto.UnmarshalEd25519PrivateKey(rawKey)
	if err != nil {
		return nil, errActiveIdentityInvalidRequest
	}
	root, err := peer.IDFromPrivateKey(key)
	if err != nil || root != account {
		return nil, errActiveIdentityInvalidRequest
	}
	proof := []byte("mknoon/activity-account-proof/v1\x00" + activeIdentityProtocolAction + "\x001\x00" + day + "\x00" + accountPeerID + "\x00" + transportPeerID)
	signature := ed25519.Sign(ed25519.PrivateKey(rawKey), proof)
	request := struct {
		Action        string `json:"action"`
		Version       int    `json:"version"`
		Day           string `json:"day"`
		AccountPeerID string `json:"accountPeerId"`
		Signature     string `json:"signature"`
	}{activeIdentityProtocolAction, 1, day, accountPeerID, base64.StdEncoding.EncodeToString(signature)}
	raw, err := json.Marshal(request)
	if err != nil || len(raw) > activeIdentityProtocolLimit {
		return nil, errActiveIdentityInvalidRequest
	}
	return raw, nil
}

func parseActiveIdentityResponse(raw []byte) (activeIdentityProtocolResult, error) {
	if len(raw) > activeIdentityProtocolLimit {
		return activeIdentityRetryable, errActiveIdentityInvalidResponse
	}
	fields, ok := activeIdentityResponseObject(raw)
	if !ok {
		return activeIdentityRetryable, errActiveIdentityInvalidResponse
	}
	status, ok := activeIdentityResponseString(fields["status"])
	if !ok {
		return activeIdentityRetryable, errActiveIdentityInvalidResponse
	}
	switch status {
	case "OK":
		if len(fields) != 3 || !bytes.Equal(bytes.TrimSpace(fields["version"]), []byte("1")) {
			return activeIdentityRetryable, errActiveIdentityInvalidResponse
		}
		data, ok := activeIdentityResponseObject(fields["data"])
		if !ok || len(data) != 2 {
			return activeIdentityRetryable, errActiveIdentityInvalidResponse
		}
		// Comparing JSON literals preserves required boolean types and refuses
		// null, missing fields, aliases, and numeric/string substitutes.
		supported := bytes.TrimSpace(data["supported"])
		accepted := bytes.TrimSpace(data["accepted"])
		if bytes.Equal(supported, []byte("false")) && bytes.Equal(accepted, []byte("false")) {
			return activeIdentityUnsupported, nil
		}
		if bytes.Equal(supported, []byte("true")) {
			if bytes.Equal(accepted, []byte("true")) {
				return activeIdentityAcknowledged, nil
			}
			if bytes.Equal(accepted, []byte("false")) {
				return activeIdentityRetryable, nil
			}
		}
	case "ERROR":
		if version, exists := fields["version"]; exists {
			if len(fields) != 3 || !bytes.Equal(bytes.TrimSpace(version), []byte("1")) {
				return activeIdentityRetryable, errActiveIdentityInvalidResponse
			}
			code, ok := activeIdentityResponseString(fields["errorCode"])
			if ok && (code == "ACTIVE_IDENTITY_INVALID_REQUEST" || code == "ACTIVE_IDENTITY_STORAGE_UNAVAILABLE") {
				return activeIdentityRetryable, errActiveIdentityRelayFailure
			}
			return activeIdentityRetryable, errActiveIdentityInvalidResponse
		}
		// Only the exact legacy refusal proves feature absence. Unrelated
		// errors must not disable future attempts or acknowledge this one.
		if len(fields) != 2 && len(fields) != 3 {
			return activeIdentityRetryable, errActiveIdentityInvalidResponse
		}
		if len(fields) == 3 {
			code, ok := activeIdentityResponseString(fields["errorCode"])
			if !ok || code != "" {
				return activeIdentityRetryable, errActiveIdentityInvalidResponse
			}
		}
		message, ok := activeIdentityResponseString(fields["error"])
		if ok && message == "Unknown action: active_identity_v1" {
			return activeIdentityUnsupported, nil
		}
	}
	return activeIdentityRetryable, errActiveIdentityInvalidResponse
}

// Decode keys explicitly: encoding/json's struct matching accepts case aliases,
// and decoding directly into a map would silently replace duplicate members.
func activeIdentityResponseObject(raw []byte) (map[string]json.RawMessage, bool) {
	decoder := json.NewDecoder(bytes.NewReader(raw))
	opening, err := decoder.Token()
	if err != nil || opening != json.Delim('{') {
		return nil, false
	}
	fields := make(map[string]json.RawMessage)
	for decoder.More() {
		token, err := decoder.Token()
		name, ok := token.(string)
		if err != nil || !ok {
			return nil, false
		}
		if _, duplicate := fields[name]; duplicate {
			return nil, false
		}
		var value json.RawMessage
		if decoder.Decode(&value) != nil {
			return nil, false
		}
		fields[name] = value
	}
	closing, err := decoder.Token()
	if err != nil || closing != json.Delim('}') || decoder.Decode(new(any)) != io.EOF {
		return nil, false
	}
	return fields, true
}

func activeIdentityResponseString(raw []byte) (string, bool) {
	var value *string
	if json.Unmarshal(raw, &value) != nil || value == nil {
		return "", false
	}
	return *value, true
}
