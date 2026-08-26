package main

import (
	"context"
	"errors"
	"strconv"
	"strings"
	"time"

	"firebase.google.com/go/v4/messaging"
)

const (
	opaqueWakeCapability = "opaque_wake_v1"
	opaqueWakeAPNSTopic  = "com.mknoon.app"
	opaqueWakeLifetime   = 5 * time.Minute
)

var errOpaqueWakeUnsupportedPlatform = errors.New("unsupported opaque wake platform")

func (ps *PushService) opaqueWakeNow() time.Time {
	if ps != nil && ps.now != nil {
		return ps.now()
	}
	return time.Now()
}

func buildOpaqueWakeMessage(platform string, now time.Time) (*messaging.Message, error) {
	switch strings.ToLower(strings.TrimSpace(platform)) {
	case "android":
		ttl := opaqueWakeLifetime
		return &messaging.Message{
			Data: map[string]string{
				"v": "1",
				"w": "1",
			},
			Android: &messaging.AndroidConfig{
				Priority:    "high",
				TTL:         &ttl,
				CollapseKey: "mailbox",
			},
		}, nil
	case "ios":
		expiresAt := now.Add(opaqueWakeLifetime).Unix()
		return &messaging.Message{
			APNS: &messaging.APNSConfig{
				Headers: map[string]string{
					"apns-push-type":   "alert",
					"apns-priority":    "10",
					"apns-topic":       opaqueWakeAPNSTopic,
					"apns-expiration":  strconv.FormatInt(expiresAt, 10),
					"apns-collapse-id": "mailbox",
				},
				Payload: &messaging.APNSPayload{
					Aps: &messaging.Aps{
						Alert: &messaging.ApsAlert{
							TitleLocKey: "NEW_MESSAGE_TITLE",
							LocKey:      "NEW_MESSAGE_BODY",
						},
						MutableContent: true,
						Sound:          "default",
						Category:       "MESSAGE_WAKE",
					},
					CustomData: map[string]interface{}{
						"v": "1",
					},
				},
			},
		}, nil
	default:
		return nil, errOpaqueWakeUnsupportedPlatform
	}
}

// mailboxDirty resolves an immutable opaque route privately and emits the
// fixed provider request for its registered platform. The opaque handle itself
// never becomes part of the provider message.
func (ps *PushService) mailboxDirty(ctx context.Context, route pushRouteLease) error {
	return ps.mailboxDirtyWithAdmission(ctx, route, nil)
}

func (ps *PushService) mailboxDirtyWithAdmission(
	ctx context.Context,
	route pushRouteLease,
	admissionIdentity *groupMessageDispatchAdmissionIdentity,
) error {
	return ps.sendPushRouteThroughGateway(
		ctx,
		route,
		func(platform string) (*messaging.Message, error) {
			return buildOpaqueWakeMessage(platform, ps.opaqueWakeNow())
		},
		false,
		admissionIdentity,
	)
}
