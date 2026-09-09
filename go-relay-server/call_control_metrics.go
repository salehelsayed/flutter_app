package main

import (
	"log"

	"github.com/prometheus/client_golang/prometheus"
	"github.com/prometheus/client_golang/prometheus/promauto"
)

var callControlRequestsCounter = promauto.NewCounterVec(prometheus.CounterOpts{
	Name: "relay_call_control_requests_total",
	Help: "Call-control handler results by fixed action, outcome and wake status; not media connection or response delivery outcomes.",
}, []string{"action", "outcome", "wake"})

// Observation uses only fixed classifications. Never pass request bodies,
// identities, handles, token material or provider error text to telemetry.
func recordCallControlRequest(action string, response callControlWireResponse, wakeStatus CallWakeStatus) {
	if !isCallControlAction(action) {
		action = "unknown"
	}
	outcome := callControlMetricOutcome(action, response)
	wake := "not_applicable"
	if action == callStoreAction {
		switch wakeStatus {
		case "":
			wake = "not_attempted"
		case CallWakeStatusDispatched:
			wake = "dispatched"
		case CallWakeStatusFailed:
			wake = "failed"
		default:
			wake = "unknown"
		}
	}
	callControlRequestsCounter.WithLabelValues(action, outcome, wake).Inc()
	// These bounded fields retain journal timestamps for failures and authority
	// withdrawal. Successful retrieve/ACK polling never creates log traffic.
	if response.Status != "OK" || wake == "failed" ||
		action == callCancelAction || action == callEndpointRevokeAction ||
		action == callTokenRevokeAction || action == callWakeHandleRevokeAction {
		log.Printf("call_control action=%s outcome=%s wake=%s", action, outcome, wake)
	}
}

func callControlMetricOutcome(action string, response callControlWireResponse) string {
	if response.Status != "OK" {
		switch response.ErrorCode {
		case "CALL_INVALID_REQUEST", "CALL_UNAUTHORIZED", "CALL_IDENTITY_CONFLICT",
			"CALL_REPLAY", "CALL_EXPIRY_INVALID", "CALL_ENVELOPE_TOO_LARGE",
			"CALL_RECIPIENT_CAPACITY", "CALL_EVENT_CAPACITY", "CALL_BYTE_CAPACITY",
			"CALL_RATE_LIMITED", "CALL_STALE_EPOCH", "CALL_BACKEND_UNAVAILABLE":
			return response.ErrorCode
		default:
			return "CALL_BACKEND_UNAVAILABLE"
		}
	}
	switch action {
	case callStoreAction:
		switch CallStoreStatus(response.StoreStatus) {
		case CallStoreStatusStored:
			return "stored"
		case CallStoreStatusDuplicate:
			return "duplicate"
		default:
			return "unknown"
		}
	case callRetrieveAction:
		if len(response.Events) > 0 {
			return "events"
		}
		return "empty"
	case callAckAction:
		if response.Acked > 0 {
			return "acked"
		}
		return "noop"
	case callCancelAction:
		if response.Canceled {
			return "canceled"
		}
		return "noop"
	case callEndpointRevokeAction, callTokenRevokeAction, callWakeHandleRevokeAction:
		if response.Revoked != nil && *response.Revoked {
			return "revoked"
		}
		return "noop"
	case callEndpointGetAction:
		if response.Found {
			return "found"
		}
		return "not_found"
	case callEndpointSetAction, callWakeHandleSetAction, callTokenSetAction:
		return "ok"
	default:
		return "unknown"
	}
}
