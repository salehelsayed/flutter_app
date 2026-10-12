package main

import (
	"context"
	"crypto/rand"
	"encoding/hex"
	"errors"
	"fmt"
	"os"
	"time"

	"firebase.google.com/go/v4/messaging"
	"github.com/redis/go-redis/v9"
)

// SE-41 T4b: an owner-only subcommand, run over SSH on the relay host, that
// asks every installed app to run its signed update check now.
//
//	relay-server update-check-push            silent push (default)
//	relay-server update-check-push --ios-alert silent push plus a fixed iOS alert
//
// One send to the FCM topic update_check. The payload is exactly
// {"type":"update_check"}: the app trusts only its signed version file, never
// the push. The iOS alert carries only two loc-keys whose text is built into
// the app, so the relay cannot put words on the screen.
//
// Limits (Redis, so they survive a restart): one send per 6 h in any mode;
// alert mode at most once per 24 h, and it also counts toward the 6 h limit.
// Never VoIP/PushKit.
const (
	updateCheckTopic            = "update_check"
	updateCheckPayloadType      = "update_check"
	updateCheckAlertTitleLocKey = "UPDATE_CHECK_ALERT_TITLE"
	updateCheckAlertBodyLocKey  = "UPDATE_CHECK_ALERT_BODY"
	updateCheckSendInterval     = 6 * time.Hour
	updateCheckAlertInterval    = 24 * time.Hour
)

// buildUpdateCheckTopicMessage is the whole wire shape of both modes.
func buildUpdateCheckTopicMessage(iosAlert bool) *messaging.Message {
	headers := map[string]string{
		"apns-priority":  "5",
		"apns-push-type": "background",
	}
	aps := &messaging.Aps{ContentAvailable: true}
	if iosAlert {
		headers = map[string]string{
			"apns-priority":  "10",
			"apns-push-type": "alert",
		}
		aps.Alert = &messaging.ApsAlert{
			TitleLocKey: updateCheckAlertTitleLocKey,
			LocKey:      updateCheckAlertBodyLocKey,
		}
	}
	return &messaging.Message{
		Topic: updateCheckTopic,
		Data:  map[string]string{"type": updateCheckPayloadType},
		// Data-only on Android: no Notification block, so the app decides.
		Android: &messaging.AndroidConfig{Priority: "high"},
		APNS: &messaging.APNSConfig{
			Headers: headers,
			Payload: &messaging.APNSPayload{Aps: aps},
		},
	}
}

var errUpdateCheckRateLimited = errors.New("update-check push rate limited")

// updateCheckSendLimiter reserves a send slot before the provider call.
type updateCheckSendLimiter interface {
	// Reserve returns a release func when the send may go ahead, or
	// errUpdateCheckRateLimited (wrapped with the limit that applies).
	Reserve(ctx context.Context, iosAlert bool) (release func(context.Context) error, err error)
}

type redisUpdateCheckSendLimiter struct {
	client *redis.Client
	prefix string
}

func newRedisUpdateCheckSendLimiter(client *redis.Client, prefix string) *redisUpdateCheckSendLimiter {
	return &redisUpdateCheckSendLimiter{client: client, prefix: prefix}
}

func (l *redisUpdateCheckSendLimiter) keys() (send string, alert string) {
	return l.prefix + "se41:update_check_push:any", l.prefix + "se41:update_check_push:alert"
}

// KEYS[1] any-mode key (6 h), KEYS[2] alert key (24 h).
// ARGV[1] token, ARGV[2] 6 h ms, ARGV[3] 24 h ms, ARGV[4] "1" for alert mode.
var reserveRedisUpdateCheckSend = redis.NewScript(`
if redis.call("EXISTS", KEYS[1]) == 1 then
  return "limit_6h"
end
if ARGV[4] == "1" then
  if redis.call("EXISTS", KEYS[2]) == 1 then
    return "limit_24h_alert"
  end
  redis.call("SET", KEYS[2], ARGV[1], "PX", ARGV[3])
end
redis.call("SET", KEYS[1], ARGV[1], "PX", ARGV[2])
return "ok"
`)

// Releases only this run's reservation, after a failed provider call.
var releaseRedisUpdateCheckSend = redis.NewScript(`
for _, key in ipairs(KEYS) do
  if redis.call("GET", key) == ARGV[1] then
    redis.call("DEL", key)
  end
end
return 0
`)

func (l *redisUpdateCheckSendLimiter) Reserve(
	ctx context.Context,
	iosAlert bool,
) (func(context.Context) error, error) {
	if l == nil || l.client == nil {
		return nil, errors.New("update-check limiter unavailable")
	}
	token, err := randomUpdateCheckToken()
	if err != nil {
		return nil, err
	}
	sendKey, alertKey := l.keys()
	mode := "0"
	if iosAlert {
		mode = "1"
	}
	verdict, err := reserveRedisUpdateCheckSend.Run(
		ctx,
		l.client,
		[]string{sendKey, alertKey},
		token,
		updateCheckSendInterval.Milliseconds(),
		updateCheckAlertInterval.Milliseconds(),
		mode,
	).Text()
	if err != nil {
		return nil, fmt.Errorf("reserve update-check send: %w", err)
	}
	if verdict != "ok" {
		return nil, fmt.Errorf("%w: %s", errUpdateCheckRateLimited, verdict)
	}
	release := func(ctx context.Context) error {
		return releaseRedisUpdateCheckSend.Run(ctx, l.client, []string{sendKey, alertKey}, token).Err()
	}
	return release, nil
}

func randomUpdateCheckToken() (string, error) {
	buf := make([]byte, 16)
	if _, err := rand.Read(buf); err != nil {
		return "", err
	}
	return hex.EncodeToString(buf), nil
}

// updateCheckPushRejected is true only for provider answers that clearly
// mean FCM did not accept the message. A deadline, a network error or a
// server error may come after FCM accepted it, so those keep the slot.
func updateCheckPushRejected(err error) bool {
	return messaging.IsInvalidArgument(err) ||
		messaging.IsThirdPartyAuthError(err) ||
		messaging.IsSenderIDMismatch(err)
}

// sendUpdateCheckPush reserves a slot and sends once. A failed send gives
// the slot back only when the provider clearly rejected it; otherwise
// slotKept is true, so a retried --ios-alert cannot alert twice in a day.
// The provider error is returned verbatim (PushService.send never wraps it).
func sendUpdateCheckPush(
	ctx context.Context,
	limiter updateCheckSendLimiter,
	send func(context.Context, *messaging.Message) (string, error),
	iosAlert bool,
) (name string, slotKept bool, err error) {
	release, err := limiter.Reserve(ctx, iosAlert)
	if err != nil {
		return "", false, err
	}
	name, sendErr := send(ctx, buildUpdateCheckTopicMessage(iosAlert))
	if sendErr != nil {
		if updateCheckPushRejected(sendErr) {
			_ = release(ctx)
			return "", false, sendErr
		}
		return "", true, sendErr
	}
	return name, false, nil
}

// updateCheckKeptSlotHint names the keys this run reserved and how to clear
// them by hand, for when the owner is sure the failed send never arrived.
func updateCheckKeptSlotHint(limiter *redisUpdateCheckSendLimiter, iosAlert bool) string {
	sendKey, alertKey := limiter.keys()
	keys := sendKey
	if iosAlert {
		keys += " " + alertKey
	}
	return "the send failed but may have reached FCM, so its limit slot is kept (" + keys + ").\n" +
		"Only if you are sure nothing was delivered, clear it on the relay host with:\n" +
		"  sudo bash -c 'set -a; . /etc/mknoon/relay-server.env; set +a; redis-cli -u \"$REDIS_URL\" DEL " + keys + "'"
}

func runUpdateCheckPushCLI(args []string) error {
	iosAlert := false
	switch {
	case len(args) == 0:
	case len(args) == 1 && args[0] == "--ios-alert":
		iosAlert = true
	default:
		return errors.New("usage: update-check-push [--ios-alert]")
	}
	config := loadBackendConfigFromEnv()
	if config.Kind != backendKindRedis || config.RedisURL == "" {
		return errors.New("update-check-push requires RELAY_BACKEND=redis and REDIS_URL (the limits must survive a restart)")
	}
	fcmPath := os.Getenv("FIREBASE_SERVICE_ACCOUNT")
	if fcmPath == "" {
		return errors.New("FIREBASE_SERVICE_ACCOUNT is required")
	}
	client, err := newRedisClientFromURL(config.RedisURL)
	if err != nil {
		return err
	}
	defer client.Close()

	ctx, cancel := context.WithTimeout(context.Background(), 30*time.Second)
	defer cancel()
	push := NewPushService(ctx, fcmPath)
	if push.client == nil {
		return errors.New("firebase messaging is unavailable")
	}
	limiter := newRedisUpdateCheckSendLimiter(client, config.RedisPrefix)
	name, slotKept, err := sendUpdateCheckPush(ctx, limiter, push.send, iosAlert)
	if err != nil {
		if slotKept {
			fmt.Fprintln(os.Stderr, "update-check-push: "+updateCheckKeptSlotHint(limiter, iosAlert))
		}
		return err
	}
	mode := "silent"
	if iosAlert {
		mode = "ios-alert"
	}
	fmt.Printf("update-check-push: sent topic=%s mode=%s message=%s\n", updateCheckTopic, mode, name)
	return nil
}
