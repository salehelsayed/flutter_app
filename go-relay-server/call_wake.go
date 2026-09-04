package main

import (
	"context"
	"strconv"
	"time"

	"firebase.google.com/go/v4/messaging"
)

type pushServiceCallWakeDispatcher struct {
	push *PushService
}

// platformCallWakeDispatcher is the only production routing seam for call
// wakes. Each typed authority has exactly one provider; an unavailable iOS
// provider fails closed and is never handed to Firebase or an ordinary APNs
// notification path.
type platformCallWakeDispatcher struct {
	android CallWakeDispatcher
	ios     CallWakeDispatcher
}

func (d platformCallWakeDispatcher) DispatchCallWake(
	ctx context.Context,
	route CallWakeRoute,
	payload CallWakePayload,
) error {
	switch {
	case route.Kind == CallTokenKindStandard && route.Platform == "android":
		if d.android == nil {
			return ErrCallBackendUnavailable
		}
		return d.android.DispatchCallWake(ctx, route, payload)
	case route.Kind == CallTokenKindIOSVoIP && route.Platform == "ios":
		if d.ios == nil {
			return ErrCallBackendUnavailable
		}
		return d.ios.DispatchCallWake(ctx, route, payload)
	default:
		return ErrCallInvalidRequest
	}
}

func (d pushServiceCallWakeDispatcher) DispatchCallWake(
	ctx context.Context,
	route CallWakeRoute,
	payload CallWakePayload,
) error {
	if d.push == nil || (d.push.sender == nil && d.push.client == nil) {
		return ErrCallBackendUnavailable
	}
	message, err := buildCallWakeMessage(route, payload)
	if err != nil {
		return err
	}
	delays := d.push.retryDelays
	if len(delays) > 2 {
		delays = delays[:2]
	}
	for attempt := 0; attempt <= len(delays); attempt++ {
		_, sendErr := d.push.send(ctx, message)
		if sendErr == nil {
			return nil
		}
		if permanentPushErrorReason(sendErr) != "" {
			return ErrCallTokenInvalid
		}
		if attempt == len(delays) || !waitForRetryDelay(ctx, delays[attempt]) {
			return ErrCallBackendUnavailable
		}
	}
	return ErrCallBackendUnavailable
}

func buildCallWakeMessage(route CallWakeRoute, payload CallWakePayload) (*messaging.Message, error) {
	if route.Token == "" || payload.CallHandle == "" || payload.WakeHandle == "" ||
		payload.ExpiresAtMs <= 0 {
		return nil, ErrCallInvalidRequest
	}
	if route.Kind == CallTokenKindIOSVoIP && route.Platform == "ios" {
		// A PushKit token is not an ordinary APNs/FCM registration token. VC2-02
		// persists and selects this typed authority, but delivery belongs to the
		// later native PushKit slice and must not enter PushService or the NSE path.
		return nil, ErrCallBackendUnavailable
	}
	if route.Kind != CallTokenKindStandard || route.Platform != "android" {
		return nil, ErrCallInvalidRequest
	}
	data := map[string]string{
		"v": "1", "w": "call", "c": payload.CallHandle,
		"h": payload.WakeHandle, "e": strconv.FormatInt(payload.ExpiresAtMs, 10),
	}
	message := &messaging.Message{
		Token: route.Token,
		Data:  data,
		Android: &messaging.AndroidConfig{
			Priority: "high", TTL: durationPointer(time.Until(time.UnixMilli(payload.ExpiresAtMs))),
			CollapseKey: payload.CallHandle,
		},
	}
	return message, nil
}

func durationPointer(value time.Duration) *time.Duration {
	if value < 0 {
		value = 0
	}
	if value > CallMaxPreconnectTTL {
		value = CallMaxPreconnectTTL
	}
	return &value
}

var _ CallWakeDispatcher = pushServiceCallWakeDispatcher{}
var _ CallWakeDispatcher = platformCallWakeDispatcher{}
