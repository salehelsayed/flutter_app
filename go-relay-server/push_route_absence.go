package main

import (
	"strings"
	"time"
)

type pushMissingRouteReason string

const (
	pushMissingRouteUnknown      pushMissingRouteReason = "unknown"
	pushMissingRouteUnregistered pushMissingRouteReason = "unregistered_by_client"
	pushMissingRouteRevoked      pushMissingRouteReason = "revoked_after_provider_rejection"
	pushRouteAbsenceTTL                                 = 24 * time.Hour
)

// This is retained removal evidence, not a complete registration history or a
// proof of the cause of an earlier lookup. Expired or unavailable history is unknown.
type missingPushRouteObservation struct {
	reason   pushMissingRouteReason
	platform string
}

func (observation missingPushRouteObservation) normalized() missingPushRouteObservation {
	switch observation.reason {
	case pushMissingRouteUnregistered, pushMissingRouteRevoked:
		platform := strings.ToLower(strings.TrimSpace(observation.platform))
		if platform != "ios" && platform != "android" {
			platform = "unknown"
		}
		return missingPushRouteObservation{reason: observation.reason, platform: platform}
	default:
		return missingPushRouteObservation{reason: pushMissingRouteUnknown, platform: "unknown"}
	}
}

func (observation missingPushRouteObservation) encode() string {
	observation = observation.normalized()
	return string(observation.reason) + "|" + observation.platform
}

func decodeMissingPushRouteObservation(raw string) missingPushRouteObservation {
	reason, platform, found := strings.Cut(raw, "|")
	if !found || (platform != "ios" && platform != "android" && platform != "unknown") {
		return missingPushRouteObservation{}.normalized()
	}
	return (missingPushRouteObservation{reason: pushMissingRouteReason(reason), platform: platform}).normalized()
}

func (ps *PushService) observeMissingRoute(peerID string) missingPushRouteObservation {
	if ps != nil && ps.tokenBackend != nil {
		if observer, ok := ps.tokenBackend.(interface {
			ObserveMissingRoute(string) missingPushRouteObservation
		}); ok {
			return observer.ObserveMissingRoute(peerID).normalized()
		}
	}
	return missingPushRouteObservation{}.normalized()
}
