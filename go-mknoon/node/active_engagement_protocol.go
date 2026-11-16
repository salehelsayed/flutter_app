package node

import (
	"bytes"
	"crypto/ed25519"
	"encoding/base64"
	"encoding/json"
	"errors"
	"strings"

	libp2pcrypto "github.com/libp2p/go-libp2p/core/crypto"
	"github.com/libp2p/go-libp2p/core/peer"
	"github.com/mknoon/go-mknoon/activitycalendar"
)

const (
	activeEngagementProtocolAction = "engagement_identity_v1"
	activeEngagementProtocolLimit  = 2048
)

type activeEngagementProtocolResult uint8

const (
	activeEngagementRetryable activeEngagementProtocolResult = iota
	activeEngagementAcknowledged
	activeEngagementUnsupported
)

var (
	errActiveEngagementInvalidRequest  = errors.New("invalid active engagement request")
	errActiveEngagementInvalidResponse = errors.New("invalid active engagement response")
	errActiveEngagementRelayFailure    = errors.New("active engagement relay did not accept the assertion")
)

// privateKeyBase64 is padded base64 of the account's raw 64-byte Ed25519 key.
// The proof binds that account to the caller's authenticated transport identity.
func buildActiveEngagementRequest(week string, kinds []string, accountPeerID, transportPeerID, privateKeyBase64 string) ([]byte, error) {
	if _, err := activitycalendar.ParseWeek(week); err != nil || !validActiveEngagementKinds(kinds) {
		return nil, errActiveEngagementInvalidRequest
	}
	if len(accountPeerID) > activeEngagementProtocolLimit || len(transportPeerID) > activeEngagementProtocolLimit ||
		len(privateKeyBase64) != base64.StdEncoding.EncodedLen(ed25519.PrivateKeySize) {
		return nil, errActiveEngagementInvalidRequest
	}
	account, err := peer.Decode(accountPeerID)
	if err != nil || account.String() != accountPeerID {
		return nil, errActiveEngagementInvalidRequest
	}
	transport, err := peer.Decode(transportPeerID)
	if err != nil || transport.String() != transportPeerID {
		return nil, errActiveEngagementInvalidRequest
	}
	rawKey, err := base64.StdEncoding.Strict().DecodeString(privateKeyBase64)
	if err != nil || len(rawKey) != ed25519.PrivateKeySize || base64.StdEncoding.EncodeToString(rawKey) != privateKeyBase64 {
		return nil, errActiveEngagementInvalidRequest
	}
	// A raw Ed25519 key contains both seed and public key; refuse inconsistent
	// halves rather than signing a proof that the claimed account cannot verify.
	if !bytes.Equal(ed25519.NewKeyFromSeed(rawKey[:ed25519.SeedSize]), rawKey) {
		return nil, errActiveEngagementInvalidRequest
	}
	key, err := libp2pcrypto.UnmarshalEd25519PrivateKey(rawKey)
	if err != nil {
		return nil, errActiveEngagementInvalidRequest
	}
	root, err := peer.IDFromPrivateKey(key)
	if err != nil || root != account {
		return nil, errActiveEngagementInvalidRequest
	}
	proof := []byte("mknoon/activity-account-proof/v1\x00" + activeEngagementProtocolAction + "\x001\x00" + week + "\x00" + strings.Join(kinds, ",") + "\x00" + accountPeerID + "\x00" + transportPeerID)
	signature := ed25519.Sign(ed25519.PrivateKey(rawKey), proof)
	request := struct {
		Action        string   `json:"action"`
		Version       int      `json:"version"`
		Week          string   `json:"week"`
		Kinds         []string `json:"kinds"`
		AccountPeerID string   `json:"accountPeerId"`
		Signature     string   `json:"signature"`
	}{activeEngagementProtocolAction, 1, week, kinds, accountPeerID, base64.StdEncoding.EncodeToString(signature)}
	raw, err := json.Marshal(request)
	if err != nil || len(raw) > activeEngagementProtocolLimit {
		return nil, errActiveEngagementInvalidRequest
	}
	return raw, nil
}

func parseActiveEngagementResponse(raw []byte) (activeEngagementProtocolResult, error) {
	if len(raw) > activeEngagementProtocolLimit {
		return activeEngagementRetryable, errActiveEngagementInvalidResponse
	}
	fields, ok := activeIdentityResponseObject(raw)
	if !ok {
		return activeEngagementRetryable, errActiveEngagementInvalidResponse
	}
	status, ok := activeIdentityResponseString(fields["status"])
	if !ok {
		return activeEngagementRetryable, errActiveEngagementInvalidResponse
	}
	switch status {
	case "OK":
		if len(fields) != 3 || !bytes.Equal(bytes.TrimSpace(fields["version"]), []byte("1")) {
			return activeEngagementRetryable, errActiveEngagementInvalidResponse
		}
		data, ok := activeIdentityResponseObject(fields["data"])
		if !ok || len(data) != 2 {
			return activeEngagementRetryable, errActiveEngagementInvalidResponse
		}
		// Comparing JSON literals preserves required boolean types and refuses
		// null, missing fields, aliases, and numeric/string substitutes.
		supported := bytes.TrimSpace(data["supported"])
		accepted := bytes.TrimSpace(data["accepted"])
		if bytes.Equal(supported, []byte("false")) && bytes.Equal(accepted, []byte("false")) {
			return activeEngagementUnsupported, nil
		}
		if bytes.Equal(supported, []byte("true")) {
			if bytes.Equal(accepted, []byte("true")) {
				return activeEngagementAcknowledged, nil
			}
			if bytes.Equal(accepted, []byte("false")) {
				return activeEngagementRetryable, nil
			}
		}
	case "ERROR":
		if version, exists := fields["version"]; exists {
			if len(fields) != 3 || !bytes.Equal(bytes.TrimSpace(version), []byte("1")) {
				return activeEngagementRetryable, errActiveEngagementInvalidResponse
			}
			code, ok := activeIdentityResponseString(fields["errorCode"])
			if ok && (code == "ACTIVE_ENGAGEMENT_INVALID_REQUEST" || code == "ACTIVE_ENGAGEMENT_STORAGE_UNAVAILABLE") {
				return activeEngagementRetryable, errActiveEngagementRelayFailure
			}
			return activeEngagementRetryable, errActiveEngagementInvalidResponse
		}
		// Only the exact legacy refusal proves feature absence. Unrelated
		// errors must not disable future attempts or acknowledge this one.
		if len(fields) != 2 && len(fields) != 3 {
			return activeEngagementRetryable, errActiveEngagementInvalidResponse
		}
		if len(fields) == 3 {
			code, ok := activeIdentityResponseString(fields["errorCode"])
			if !ok || code != "" {
				return activeEngagementRetryable, errActiveEngagementInvalidResponse
			}
		}
		message, ok := activeIdentityResponseString(fields["error"])
		if ok && message == "Unknown action: engagement_identity_v1" {
			return activeEngagementUnsupported, nil
		}
	}
	return activeEngagementRetryable, errActiveEngagementInvalidResponse
}

// The fixed ordering makes the signed comma-separated list unambiguous.
func validActiveEngagementKinds(kinds []string) bool {
	if len(kinds) < 1 || len(kinds) > 4 || kinds[0] != "active" {
		return false
	}
	previous := -1
	for _, kind := range kinds {
		index := -1
		for i, name := range []string{"active", "chat", "call", "group"} {
			if name == kind {
				index = i
				break
			}
		}
		if index <= previous {
			return false
		}
		previous = index
	}
	return true
}
