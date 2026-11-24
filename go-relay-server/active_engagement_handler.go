package main

import (
	"bytes"
	"crypto/ed25519"
	"encoding/base64"
	"encoding/json"
	"errors"
	"slices"
	"strings"

	libp2pcrypto "github.com/libp2p/go-libp2p/core/crypto"
	"github.com/libp2p/go-libp2p/core/network"
	"github.com/libp2p/go-libp2p/core/peer"
	"github.com/mknoon/go-mknoon/activitycalendar"
)

const activeEngagementAction = "engagement_identity_v1"

type activeEngagementWireRequest struct {
	Action        string   `json:"action"`
	Version       int      `json:"version"`
	Week          string   `json:"week"`
	Kinds         []string `json:"kinds"`
	AccountPeerID string   `json:"accountPeerId"`
	Signature     string   `json:"signature"`
}

type activeEngagementWireData struct {
	Supported bool `json:"supported"`
	Accepted  bool `json:"accepted"`
}

type activeEngagementWireResponse struct {
	Status    string                    `json:"status"`
	Version   int                       `json:"version"`
	ErrorCode string                    `json:"errorCode,omitempty"`
	Data      *activeEngagementWireData `json:"data,omitempty"`
}

func decodeWeeklyIdentityRequest(raw []byte, action string) (activeEngagementWireRequest, bool) {
	var request activeEngagementWireRequest
	if len(raw) > 2048 {
		return request, false
	}
	if appDiagnosticDecode(raw, &request) != nil {
		return request, false
	}
	// The shared decoder rejects duplicates/trailing data, but JSON struct tags
	// also accept case aliases. Require the exact six keys and explicit values.
	var fields map[string]json.RawMessage
	if json.Unmarshal(raw, &fields) != nil || len(fields) != 6 {
		return request, false
	}
	for _, name := range []string{"action", "version", "week", "kinds", "accountPeerId", "signature"} {
		value, exists := fields[name]
		if !exists || bytes.Equal(bytes.TrimSpace(value), []byte("null")) {
			return request, false
		}
	}
	_, err := activitycalendar.ParseWeek(request.Week)
	return request, request.Action == action && request.Version == 1 && err == nil
}

func activeEngagementResponse(raw []byte, authenticatedPeerID string, store *activeIdentityStore) activeEngagementWireResponse {
	invalid := activeEngagementWireResponse{Status: "ERROR", Version: 1, ErrorCode: "ACTIVE_ENGAGEMENT_INVALID_REQUEST"}
	request, valid := decodeWeeklyIdentityRequest(raw, activeEngagementAction)
	if !valid {
		return invalid
	}
	kinds, validKinds := parseActiveEngagementKinds(request.Kinds)
	if !validKinds || !verifyWeeklyIdentityProof(request, authenticatedPeerID) {
		return invalid
	}
	if store == nil {
		return activeEngagementWireResponse{Status: "OK", Version: 1, Data: &activeEngagementWireData{}}
	}
	store.mu.Lock()
	enabled := store.engagementEnabled
	store.mu.Unlock()
	if !enabled {
		return activeEngagementWireResponse{Status: "OK", Version: 1, Data: &activeEngagementWireData{}}
	}
	// The shared store owns the current-week check and durable generation barrier.
	if err := store.admitEngagement(request.Week, request.AccountPeerID, kinds); err != nil {
		if errors.Is(err, errActiveIdentityStoreDay) || errors.Is(err, errActiveIdentityStoreInput) ||
			errors.Is(err, errActiveIdentityAccount) || errors.Is(err, activitycalendar.ErrInvalidWeek) || errors.Is(err, errActiveEngagementKinds) {
			return invalid
		}
		return activeEngagementWireResponse{Status: "ERROR", Version: 1, ErrorCode: "ACTIVE_ENGAGEMENT_STORAGE_UNAVAILABLE"}
	}
	return activeEngagementWireResponse{Status: "OK", Version: 1, Data: &activeEngagementWireData{Supported: true, Accepted: true}}
}

// The transport identity comes from the authenticated stream.
func verifyWeeklyIdentityProof(request activeEngagementWireRequest, authenticatedPeerID string) bool {
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
	proof := []byte("mknoon/activity-account-proof/v1\x00" + request.Action + "\x001\x00" + request.Week + "\x00" + strings.Join(request.Kinds, ",") + "\x00" + request.AccountPeerID + "\x00" + authenticatedPeerID)
	verified, err := publicKey.Verify(proof, signature)
	return err == nil && verified
}

func handleActiveEngagementRequest(s network.Stream, raw []byte, authenticatedPeerID string, store *activeIdentityStore) {
	writeWeeklyIdentityResponse(s, activeEngagementResponse(raw, authenticatedPeerID, store))
}

func writeWeeklyIdentityResponse(s network.Stream, result activeEngagementWireResponse) {
	response, err := json.Marshal(result)
	if err != nil {
		return
	}
	_ = writeFrame(s, response)
}

func parseActiveEngagementKinds(kinds []string) (activeEngagementKinds, bool) {
	if len(kinds) == 0 || kinds[0] != "active" {
		return 0, false
	}
	bits, valid := orderedWeeklyKindBits(kinds, []string{"active", "chat", "call", "group"})
	return activeEngagementKinds(bits), valid
}

func orderedWeeklyKindBits(kinds, order []string) (uint8, bool) {
	if len(kinds) == 0 || len(kinds) > len(order) {
		return 0, false
	}
	previous := -1
	var bits uint8
	for _, kind := range kinds {
		index := slices.Index(order, kind)
		if index <= previous {
			return 0, false
		}
		previous = index
		bits |= uint8(1) << index
	}
	return bits, true
}
