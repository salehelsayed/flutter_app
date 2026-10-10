package main

import (
	"context"
	"errors"

	"firebase.google.com/go/v4/messaging"
	"github.com/redis/go-redis/v9"
)

// callFailure carries a fixed failure class beside a call-control sentinel, so
// the journal can say why a wake failed or a request was refused. The class is
// always one of the constants below or a fixed permanentPushErrorReason value;
// it never holds provider text, identities or token material.
type callFailure struct {
	class string
	err   error
}

func (f callFailure) Error() string { return f.err.Error() + " (" + f.class + ")" }

func (f callFailure) Unwrap() error { return f.err }

const (
	callFailureWakeInFlight   = "wake_in_flight"
	callFailureDeadline       = "deadline"
	callFailureCanceled       = "canceled"
	callFailureTxConflict     = "tx_conflict"
	callFailureTokenInvalid   = "token_invalid"
	callFailureInvalidRequest = "invalid_request"
	callFailureUnavailable    = "unavailable"
	callFailureOther          = "other"
)

// errCallWakeInFlight refuses a terminal step while a wake provider call for
// the same row has not returned. Clients see CALL_BACKEND_UNAVAILABLE.
var errCallWakeInFlight = callFailure{class: callFailureWakeInFlight, err: ErrCallBackendUnavailable}

func callFailureClass(err error) string {
	var failure callFailure
	switch {
	case err == nil:
		return ""
	case errors.As(err, &failure):
		return failure.class
	case errors.Is(err, context.DeadlineExceeded):
		return callFailureDeadline
	case errors.Is(err, context.Canceled):
		return callFailureCanceled
	case errors.Is(err, redis.TxFailedErr):
		return callFailureTxConflict
	case errors.Is(err, ErrCallTokenInvalid):
		return callFailureTokenInvalid
	case errors.Is(err, ErrCallInvalidRequest):
		return callFailureInvalidRequest
	case errors.Is(err, ErrCallBackendUnavailable):
		return callFailureUnavailable
	default:
		return callFailureOther
	}
}

// fcmCallWakeFailureClass classifies the last transient Firebase error of a
// call wake whose retries ran out.
func fcmCallWakeFailureClass(ctx context.Context, err error) string {
	switch {
	case ctx.Err() != nil:
		return callFailureClass(ctx.Err())
	case messaging.IsUnavailable(err):
		return "fcm_unavailable"
	case messaging.IsInternal(err):
		return "fcm_internal"
	case messaging.IsQuotaExceeded(err):
		return "fcm_quota"
	case messaging.IsThirdPartyAuthError(err):
		return "fcm_auth"
	case messaging.IsInvalidArgument(err):
		return "fcm_invalid_argument"
	case errors.Is(err, context.DeadlineExceeded):
		return callFailureDeadline
	default:
		return "fcm_other"
	}
}
