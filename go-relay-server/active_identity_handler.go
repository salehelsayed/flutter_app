package main

import (
	"bytes"
	"crypto/ed25519"
	"encoding/base64"
	"encoding/json"
	"errors"

	libp2pcrypto "github.com/libp2p/go-libp2p/core/crypto"
	"github.com/libp2p/go-libp2p/core/network"
	"github.com/libp2p/go-libp2p/core/peer"
	"github.com/mknoon/go-mknoon/activitycalendar"
)

const activeIdentityAction = "active_identity_v1"

type activeIdentityWireRequest struct {
	Action        string `json:"action"`
	Version       int    `json:"version"`
	Day           string `json:"day"`
	AccountPeerID string `json:"accountPeerId"`
	Signature     string `json:"signature"`
}

type activeIdentityWireData struct {
	Supported bool `json:"supported"`
	Accepted  bool `json:"accepted"`
}

type activeIdentityWireResponse struct {
	Status    string                  `json:"status"`
	Version   int                     `json:"version"`
	ErrorCode string                  `json:"errorCode,omitempty"`
	Data      *activeIdentityWireData `json:"data,omitempty"`
}

// The transport identity is authenticated input, never a caller-selected field.
func activeIdentityResponse(raw []byte, authenticatedPeerID string, store *activeIdentityStore) activeIdentityWireResponse {
	invalid := activeIdentityWireResponse{Status: "ERROR", Version: 1, ErrorCode: "ACTIVE_IDENTITY_INVALID_REQUEST"}
	if len(raw) > 2048 {
		return invalid
	}
	var request activeIdentityWireRequest
	if appDiagnosticDecode(raw, &request) != nil {
		return invalid
	}
	// The shared decoder rejects duplicates/trailing data, but JSON struct tags
	// also accept case aliases. Require the exact five keys and explicit values.
	var fields map[string]json.RawMessage
	if json.Unmarshal(raw, &fields) != nil || len(fields) != 5 {
		return invalid
	}
	for _, name := range []string{"action", "version", "day", "accountPeerId", "signature"} {
		value, exists := fields[name]
		if !exists || bytes.Equal(bytes.TrimSpace(value), []byte("null")) {
			return invalid
		}
	}
	if request.Action != activeIdentityAction || request.Version != 1 {
		return invalid
	}
	if _, err := activitycalendar.Parse(request.Day); err != nil {
		return invalid
	}
	if !verifyActiveIdentityProof(request, authenticatedPeerID) {
		return invalid
	}
	if store == nil {
		return activeIdentityWireResponse{Status: "OK", Version: 1, Data: &activeIdentityWireData{}}
	}
	// admit owns the authoritative day check and the durable generation barrier.
	if err := store.admit(request.Day, request.AccountPeerID); err != nil {
		if errors.Is(err, errActiveIdentityStoreDay) || errors.Is(err, errActiveIdentityStoreInput) ||
			errors.Is(err, errActiveIdentityAccount) || errors.Is(err, activitycalendar.ErrInvalidDay) {
			return invalid
		}
		return activeIdentityWireResponse{Status: "ERROR", Version: 1, ErrorCode: "ACTIVE_IDENTITY_STORAGE_UNAVAILABLE"}
	}
	return activeIdentityWireResponse{Status: "OK", Version: 1, Data: &activeIdentityWireData{Supported: true, Accepted: true}}
}

func verifyActiveIdentityProof(request activeIdentityWireRequest, authenticatedPeerID string) bool {
	account, err := peer.Decode(request.AccountPeerID)
	if err != nil || account.String() != request.AccountPeerID {
		return false
	}
	transport, err := peer.Decode(authenticatedPeerID)
	if err != nil || transport.String() != authenticatedPeerID {
		return false
	}
	publicKey, err := account.ExtractPublicKey()
	if err != nil || publicKey == nil || publicKey.Type() != libp2pcrypto.Ed25519 {
		return false
	}
	signature, err := base64.StdEncoding.DecodeString(request.Signature)
	if err != nil || len(signature) != ed25519.SignatureSize || base64.StdEncoding.EncodeToString(signature) != request.Signature {
		return false
	}
	proof := []byte("mknoon/activity-account-proof/v1\x00" + activeIdentityAction + "\x001\x00" + request.Day + "\x00" + request.AccountPeerID + "\x00" + authenticatedPeerID)
	verified, err := publicKey.Verify(proof, signature)
	return err == nil && verified
}

func handleActiveIdentityRequest(s network.Stream, raw []byte, authenticatedPeerID string, store *activeIdentityStore) {
	response, err := json.Marshal(activeIdentityResponse(raw, authenticatedPeerID, store))
	if err != nil {
		return
	}
	_ = writeFrame(s, response)
}
