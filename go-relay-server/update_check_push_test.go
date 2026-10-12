package main

import (
	"context"
	"encoding/json"
	"errors"
	"io"
	"net/http"
	"os"
	"strings"
	"testing"
	"time"

	firebase "firebase.google.com/go/v4"
	"firebase.google.com/go/v4/messaging"
	"github.com/alicebob/miniredis/v2"
	"github.com/redis/go-redis/v9"
	"google.golang.org/api/option"
)

func updateCheckLimiterOn(t *testing.T, server *miniredis.Miniredis) *redisUpdateCheckSendLimiter {
	t.Helper()
	client := redis.NewClient(&redis.Options{Addr: server.Addr()})
	t.Cleanup(func() { _ = client.Close() })
	return newRedisUpdateCheckSendLimiter(client, "test:")
}

// The FCM wire JSON, as the provider receives it.
func updateCheckWire(t *testing.T, iosAlert bool) map[string]any {
	t.Helper()
	raw, err := json.Marshal(buildUpdateCheckTopicMessage(iosAlert))
	if err != nil {
		t.Fatal(err)
	}
	var wire map[string]any
	if err := json.Unmarshal(raw, &wire); err != nil {
		t.Fatal(err)
	}
	return wire
}

func TestUpdateCheckPushSilentShape(t *testing.T) {
	msg := buildUpdateCheckTopicMessage(false)
	if msg.Topic != "update_check" || msg.Token != "" || msg.Condition != "" {
		t.Fatalf("must be one topic send: %+v", msg)
	}
	if len(msg.Data) != 1 || msg.Data["type"] != "update_check" {
		t.Fatalf("payload must be exactly {type:update_check}: %v", msg.Data)
	}
	if msg.Notification != nil || msg.Android.Notification != nil {
		t.Fatal("Android must be data-only")
	}
	if msg.Android.Priority != "high" {
		t.Fatalf("android priority = %q", msg.Android.Priority)
	}
	h := msg.APNS.Headers
	if h["apns-priority"] != "5" || h["apns-push-type"] != "background" || len(h) != 2 {
		t.Fatalf("silent APNs headers = %v", h)
	}
	aps := msg.APNS.Payload.Aps
	if !aps.ContentAvailable || aps.Alert != nil || aps.AlertString != "" || aps.MutableContent {
		t.Fatalf("silent aps = %+v", aps)
	}
	wire := updateCheckWire(t, false)
	apsWire := wire["apns"].(map[string]any)["payload"].(map[string]any)["aps"].(map[string]any)
	if _, ok := apsWire["alert"]; ok {
		t.Fatal("no aps.alert without --ios-alert")
	}
	if apsWire["content-available"] != float64(1) {
		t.Fatalf("content-available = %v", apsWire["content-available"])
	}
}

func TestUpdateCheckPushAlertShape(t *testing.T) {
	msg := buildUpdateCheckTopicMessage(true)
	h := msg.APNS.Headers
	if h["apns-priority"] != "10" || h["apns-push-type"] != "alert" || len(h) != 2 {
		t.Fatalf("alert APNs headers = %v", h)
	}
	if len(msg.Data) != 1 || msg.Data["type"] != "update_check" || msg.Notification != nil {
		t.Fatal("alert mode keeps the single-field data payload and no notification block")
	}
	wire := updateCheckWire(t, true)
	aps := wire["apns"].(map[string]any)["payload"].(map[string]any)["aps"].(map[string]any)
	if aps["content-available"] != float64(1) {
		t.Fatal("alert mode keeps content-available:1")
	}
	if _, ok := aps["mutable-content"]; ok {
		t.Fatal("no mutable-content")
	}
	alert := aps["alert"].(map[string]any)
	want := map[string]any{
		"title-loc-key": "UPDATE_CHECK_ALERT_TITLE",
		"loc-key":       "UPDATE_CHECK_ALERT_BODY",
	}
	if len(alert) != len(want) {
		t.Fatalf("alert must hold only the two loc-keys: %v", alert)
	}
	for k, v := range want {
		if alert[k] != v {
			t.Fatalf("alert[%s] = %v", k, alert[k])
		}
	}
	raw, _ := json.Marshal(wire)
	for _, forbidden := range []string{"loc-args", "title\":", "body\":", "http", "voip"} {
		if strings.Contains(string(raw), forbidden) {
			t.Fatalf("wire contains %q: %s", forbidden, raw)
		}
	}
}

func TestUpdateCheckPushLimitsSurviveARestart(t *testing.T) {
	server := miniredis.RunT(t)
	ctx := context.Background()
	sent := 0
	send := func(context.Context, *messaging.Message) (string, error) {
		sent++
		return "projects/p/messages/1", nil
	}

	if _, _, err := sendUpdateCheckPush(ctx, updateCheckLimiterOn(t, server), send, false); err != nil {
		t.Fatal(err)
	}
	// A new process (new client) on the same Redis still sees the limit.
	_, _, err := sendUpdateCheckPush(ctx, updateCheckLimiterOn(t, server), send, false)
	if !errors.Is(err, errUpdateCheckRateLimited) || !strings.Contains(err.Error(), "limit_6h") {
		t.Fatalf("second silent send within 6 h: %v", err)
	}
	// Alert mode also obeys the shared 6 h limit.
	_, _, err = sendUpdateCheckPush(ctx, updateCheckLimiterOn(t, server), send, true)
	if !errors.Is(err, errUpdateCheckRateLimited) {
		t.Fatalf("alert within 6 h of any send: %v", err)
	}

	server.FastForward(6*time.Hour + time.Second)
	if _, _, err := sendUpdateCheckPush(ctx, updateCheckLimiterOn(t, server), send, true); err != nil {
		t.Fatalf("alert after 6 h: %v", err)
	}
	// The alert counted toward the 6 h limit...
	if _, _, err := sendUpdateCheckPush(ctx, updateCheckLimiterOn(t, server), send, false); !errors.Is(err, errUpdateCheckRateLimited) {
		t.Fatalf("silent right after an alert: %v", err)
	}
	// ...and another alert waits 24 h, while silent sends resume after 6 h.
	server.FastForward(6*time.Hour + time.Second)
	if _, _, err := sendUpdateCheckPush(ctx, updateCheckLimiterOn(t, server), send, true); err == nil ||
		!strings.Contains(err.Error(), "limit_24h_alert") {
		t.Fatalf("second alert within 24 h: %v", err)
	}
	if _, _, err := sendUpdateCheckPush(ctx, updateCheckLimiterOn(t, server), send, false); err != nil {
		t.Fatalf("silent 12 h after the alert: %v", err)
	}
	server.FastForward(18*time.Hour + time.Second)
	if _, _, err := sendUpdateCheckPush(ctx, updateCheckLimiterOn(t, server), send, true); err != nil {
		t.Fatalf("alert after 24 h: %v", err)
	}
	if sent != 4 {
		t.Fatalf("provider sends = %d, want 4", sent)
	}
}

type fakeFirebaseError struct{ code string }

func (e *fakeFirebaseError) Error() string { return "provider: " + e.code }

// fcmAnswer makes the real Firebase messaging client receive one canned HTTP
// answer (or transport error), so the errors are the SDK's own types.
type fcmAnswer struct {
	status int
	body   string
	err    error
}

func (a fcmAnswer) RoundTrip(r *http.Request) (*http.Response, error) {
	if a.err != nil {
		return nil, a.err
	}
	return &http.Response{
		StatusCode: a.status,
		Header:     http.Header{"Content-Type": {"application/json"}},
		Body:       io.NopCloser(strings.NewReader(a.body)),
		Request:    r,
	}, nil
}

func realFCMSend(t *testing.T, answer fcmAnswer) func(context.Context, *messaging.Message) (string, error) {
	t.Helper()
	ctx := context.Background()
	app, err := firebase.NewApp(ctx, &firebase.Config{ProjectID: "se41-test"},
		option.WithHTTPClient(&http.Client{Transport: answer}))
	if err != nil {
		t.Fatal(err)
	}
	client, err := app.Messaging(ctx)
	if err != nil {
		t.Fatal(err)
	}
	return client.Send
}

func fcmErrorBody(status, fcmCode string) string {
	return `{"error":{"code":400,"message":"rejected","status":"` + status + `","details":[` +
		`{"@type":"type.googleapis.com/google.firebase.fcm.v1.FcmError","errorCode":"` + fcmCode + `"}]}}`
}

func TestUpdateCheckPushClearRejectionReleasesTheSlot(t *testing.T) {
	for name, answer := range map[string]fcmAnswer{
		"invalid argument":   {status: 400, body: fcmErrorBody("INVALID_ARGUMENT", "INVALID_ARGUMENT")},
		"third party auth":   {status: 401, body: fcmErrorBody("UNAUTHENTICATED", "THIRD_PARTY_AUTH_ERROR")},
		"sender id mismatch": {status: 403, body: fcmErrorBody("PERMISSION_DENIED", "SENDER_ID_MISMATCH")},
	} {
		t.Run(name, func(t *testing.T) {
			server := miniredis.RunT(t)
			ctx := context.Background()
			_, kept, err := sendUpdateCheckPush(ctx, updateCheckLimiterOn(t, server), realFCMSend(t, answer), true)
			if err == nil || kept || !updateCheckPushRejected(err) {
				t.Fatalf("kept=%v err=%v", kept, err)
			}
			// The refused send gave its slot back: the owner may retry at once.
			ok := func(context.Context, *messaging.Message) (string, error) { return "m", nil }
			if _, _, err := sendUpdateCheckPush(ctx, updateCheckLimiterOn(t, server), ok, true); err != nil {
				t.Fatalf("retry after a clear rejection: %v", err)
			}
		})
	}
}

func TestUpdateCheckPushUnclearFailureKeepsTheSlot(t *testing.T) {
	for name, answer := range map[string]fcmAnswer{
		"deadline":       {err: context.DeadlineExceeded},
		"network":        {err: errors.New("connection reset by peer")},
		"internal error": {status: 400, body: fcmErrorBody("INTERNAL", "INTERNAL")},
	} {
		t.Run(name, func(t *testing.T) {
			server := miniredis.RunT(t)
			ctx := context.Background()
			_, kept, err := sendUpdateCheckPush(ctx, updateCheckLimiterOn(t, server), realFCMSend(t, answer), true)
			if err == nil || !kept || updateCheckPushRejected(err) {
				t.Fatalf("kept=%v err=%v", kept, err)
			}
			ok := func(context.Context, *messaging.Message) (string, error) { return "m", nil }
			for _, alert := range []bool{true, false} {
				if _, _, err := sendUpdateCheckPush(ctx, updateCheckLimiterOn(t, server), ok, alert); !errors.Is(err, errUpdateCheckRateLimited) {
					t.Fatalf("alert=%v retry must stay limited: %v", alert, err)
				}
			}
		})
	}
}

func TestUpdateCheckPushProviderErrorIsVerbatim(t *testing.T) {
	server := miniredis.RunT(t)
	providerErr := &fakeFirebaseError{code: "UNAVAILABLE"}
	failing := func(context.Context, *messaging.Message) (string, error) { return "", providerErr }
	_, kept, err := sendUpdateCheckPush(context.Background(), updateCheckLimiterOn(t, server), failing, false)
	if err != providerErr || !kept {
		t.Fatalf("provider error must come back unwrapped with the slot kept, got kept=%v %#v", kept, err)
	}
}

func TestUpdateCheckKeptSlotHintNamesOnlyThisRunsKeys(t *testing.T) {
	limiter := newRedisUpdateCheckSendLimiter(nil, "relay:")
	silent := updateCheckKeptSlotHint(limiter, false)
	if !strings.Contains(silent, "DEL relay:se41:update_check_push:any'") || strings.Contains(silent, ":alert") {
		t.Fatalf("silent hint: %s", silent)
	}
	alert := updateCheckKeptSlotHint(limiter, true)
	if !strings.Contains(alert, "DEL relay:se41:update_check_push:any relay:se41:update_check_push:alert'") {
		t.Fatalf("alert hint: %s", alert)
	}
}

func TestUpdateCheckPushCLIRefusesWithoutRedisAndBadArgs(t *testing.T) {
	t.Setenv("RELAY_BACKEND", "memory")
	if err := runUpdateCheckPushCLI(nil); err == nil || !strings.Contains(err.Error(), "RELAY_BACKEND=redis") {
		t.Fatalf("memory backend: %v", err)
	}
	for _, args := range [][]string{{"--ios-alert", "x"}, {"--alert"}, {"--ios-alert=true"}} {
		if err := runUpdateCheckPushCLI(args); err == nil || !strings.Contains(err.Error(), "usage") {
			t.Fatalf("args %v: %v", args, err)
		}
	}
}

func TestUpdateCheckPushSendStaysUnwrapped(t *testing.T) {
	// T4b keeps PushService.send as it is: the provider error is returned as is.
	providerErr := &fakeFirebaseError{code: "INTERNAL"}
	ps := &PushService{sender: func(context.Context, *messaging.Message) (string, error) { return "", providerErr }}
	if _, err := ps.send(context.Background(), buildUpdateCheckTopicMessage(false)); err != providerErr {
		t.Fatalf("send wrapped the provider error: %#v", err)
	}
}

func TestUpdateCheckPushIsARelaySubcommand(t *testing.T) {
	source, err := os.ReadFile("main.go")
	if err != nil {
		t.Fatal(err)
	}
	if !strings.Contains(string(source), "case \"update-check-push\":\n\t\t\tif err := runUpdateCheckPushCLI(os.Args[2:]); err != nil {") {
		t.Fatal("main.go must dispatch update-check-push to runUpdateCheckPushCLI")
	}
}
