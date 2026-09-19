package node

import (
	"context"
	"errors"
	"net"
	"syscall"

	"github.com/libp2p/go-libp2p/p2p/net/swarm"
)

// Diagnostic annotations retain the classified sentinel, not the raw transport
// error (which can contain peer IDs, addresses and handshake material).
// They are advisory and cannot authorize a credential/media fallback.
type turnCredentialFailureDetail struct {
	cause  error
	fields map[string]any
}

func (e *turnCredentialFailureDetail) Error() string { return e.cause.Error() }
func (e *turnCredentialFailureDetail) Unwrap() error { return e.cause }

func annotateTurnCredentialFailure(classified error, stage string, original error) error {
	kind, dial := turnCredentialDiagnosticKind(original)
	fields := map[string]any{"stage": stage, "kind": kind}
	if dial != nil {
		root, _ := turnCredentialDiagnosticKind(dial.Cause)
		kinds := make([]string, 0, 8)
		seen := make(map[string]bool)
		count := len(dial.DialErrors)
		if count > 8 {
			count = 8
		}
		for _, attempt := range dial.DialErrors[:count] {
			item, _ := turnCredentialDiagnosticKind(attempt.Cause)
			if !seen[item] {
				kinds = append(kinds, item)
				seen[item] = true
			}
		}
		fields["dialCauseKind"] = root
		fields["dialTransportKinds"] = kinds
		fields["dialAttemptCount"] = count
		fields["dialComplete"] = dial.Skipped == 0 && len(dial.DialErrors) > 0
		fields["dialTruncated"] = dial.Skipped != 0 || len(dial.DialErrors) > count
		fields["dialAllTransient"] = classified == ErrTurnCredentialsUnavailable
	}
	return &turnCredentialFailureDetail{cause: classified, fields: fields}
}

// TurnCredentialFailureDiagnostics exposes a bounded local failure category to
// the native bridge. Neither error text nor arbitrary relay codes are returned.
func TurnCredentialFailureDiagnostics(err error) map[string]any {
	var detail *turnCredentialFailureDetail
	if errors.As(err, &detail) {
		copy := make(map[string]any, len(detail.fields))
		for key, value := range detail.fields {
			if list, ok := value.([]string); ok {
				value = append([]string(nil), list...)
			}
			copy[key] = value
		}
		return copy
	}
	var relay *TurnCredentialsRelayError
	if errors.As(err, &relay) && relay != nil {
		kind := "relay_unknown"
		switch relay.Code {
		case "TURN_CREDENTIALS_UNAUTHORIZED":
			kind = "relay_unauthorized"
		case "TURN_CREDENTIALS_INVALID_REQUEST":
			kind = "relay_invalid_request"
		case "TURN_CREDENTIALS_RATE_LIMITED", "RATE_LIMITED":
			kind = "relay_rate_limited"
		case "TURN_CREDENTIALS_UNAVAILABLE":
			kind = "relay_unavailable"
		}
		return map[string]any{"stage": "relay_response", "kind": kind}
	}
	kind := "unknown"
	switch err {
	case ErrTurnCredentialsInvalidResponse:
		kind = "invalid_response"
	case ErrTurnCredentialsUnsupported:
		kind = "unsupported"
	case ErrTurnCredentialsUnavailable:
		kind = "unavailable"
	case ErrTurnCredentialsRejected:
		kind = "rejected"
	}
	return map[string]any{"stage": "unspecified", "kind": kind}
}

func turnCredentialDiagnosticKind(err error) (string, *swarm.DialError) {
	for depth := 0; err != nil && depth < 32; depth++ {
		switch err {
		case context.DeadlineExceeded:
			return "deadline", nil
		case context.Canceled:
			return "canceled", nil
		case syscall.ENETDOWN:
			return "network_down", nil
		case syscall.ENETUNREACH:
			return "network_unreachable", nil
		case syscall.EHOSTUNREACH:
			return "host_unreachable", nil
		case syscall.ECONNREFUSED:
			return "connection_refused", nil
		case syscall.ECONNRESET:
			return "connection_reset", nil
		case syscall.ENETRESET:
			return "network_reset", nil
		case syscall.ETIMEDOUT:
			return "timed_out", nil
		case syscall.EACCES, syscall.EPERM:
			return "permission_denied", nil
		case syscall.EADDRNOTAVAIL:
			return "address_unavailable", nil
		case swarm.ErrDialBackoff:
			return "dial_backoff", nil
		case swarm.ErrDialRefusedBlackHole:
			return "dial_blackhole", nil
		case swarm.ErrNoTransport:
			return "no_transport", nil
		case swarm.ErrAllDialsFailed:
			return "all_dials_failed", nil
		case swarm.ErrNoAddresses:
			return "no_addresses", nil
		case swarm.ErrNoGoodAddresses:
			return "no_good_addresses", nil
		}
		switch typed := err.(type) {
		case *swarm.DialError:
			if typed != nil {
				return "dial_aggregate", typed
			}
		case *net.DNSError:
			if typed != nil {
				if typed.IsTimeout {
					return "dns_timeout", nil
				}
				if typed.IsNotFound {
					return "dns_not_found", nil
				}
				return "dns_other", nil
			}
		case interface{ Unwrap() []error }:
			return "joined_errors", nil
		}
		next := errors.Unwrap(err)
		if next == nil {
			return "unknown", nil
		}
		err = next
	}
	if err != nil {
		return "chain_limit", nil
	}
	return "unknown", nil
}
