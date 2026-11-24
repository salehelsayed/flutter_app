package main

import "github.com/libp2p/go-libp2p/core/network"

const featureUseAction = "feature_use_identity_v1"

var featureUseNames = [...]string{
	"voice_message",
	"photo_video",
	"video_call",
	"translation",
	"voice_to_text",
	"view_3d",
}

func featureUseResponse(raw []byte, authenticatedPeerID string, store *featureUseStore) activeEngagementWireResponse {
	invalid := activeEngagementWireResponse{Status: "ERROR", Version: 1, ErrorCode: "FEATURE_USE_INVALID_REQUEST"}
	request, valid := decodeWeeklyIdentityRequest(raw, featureUseAction)
	if !valid {
		return invalid
	}
	kinds, validKinds := orderedWeeklyKindBits(request.Kinds, featureUseNames[:])
	if !validKinds || !verifyWeeklyIdentityProof(request, authenticatedPeerID) {
		return invalid
	}
	if store == nil {
		return activeEngagementWireResponse{Status: "OK", Version: 1, Data: &activeEngagementWireData{}}
	}
	switch store.update(request.Week, request.AccountPeerID, kinds) {
	case nil:
		return activeEngagementWireResponse{Status: "OK", Version: 1, Data: &activeEngagementWireData{Supported: true, Accepted: true}}
	case errFeatureUseWeek:
		return invalid
	default:
		return activeEngagementWireResponse{Status: "ERROR", Version: 1, ErrorCode: "FEATURE_USE_STORAGE_UNAVAILABLE"}
	}
}

func handleFeatureUseRequest(s network.Stream, raw []byte, authenticatedPeerID string, store *featureUseStore) {
	writeWeeklyIdentityResponse(s, featureUseResponse(raw, authenticatedPeerID, store))
}
