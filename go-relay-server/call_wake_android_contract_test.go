package main

import (
	"testing"
	"time"
)

func TestVC204AndroidCallWakeIsStrictlyOpaqueDataOnly(t *testing.T) {
	now := time.Now()
	expiresAt := now.Add(45 * time.Second)
	message, err := buildCallWakeMessage(
		CallWakeRoute{
			Kind:     CallTokenKindStandard,
			Platform: "android",
			Token:    "fixture-token",
		},
		CallWakePayload{
			CallHandle: "11111111111141118111111111111111",
			WakeHandle: "22222222222242228222222222222222",
			ExpiresAtMs: expiresAt.UnixMilli(),
		},
	)
	if err != nil || message == nil {
		t.Fatal("Android call wake was not constructed")
	}
	if message.Notification != nil {
		t.Fatal("Android call wake must not contain an FCM notification payload")
	}
	if message.Android == nil || message.Android.Notification != nil {
		t.Fatal("Android call wake must use data-only Android delivery")
	}
	if message.Android.Priority != "high" {
		t.Fatal("Android call wake must remain high priority")
	}
	if message.Android.TTL == nil || *message.Android.TTL <= 0 ||
		*message.Android.TTL > CallMaxPreconnectTTL {
		t.Fatal("Android call wake TTL must remain positive and bounded")
	}
	if message.Android.CollapseKey != message.Data["c"] {
		t.Fatal("Android call wake collapse key must remain the opaque call handle")
	}
	if len(message.Data) != 5 || message.Data["v"] != "1" ||
		message.Data["w"] != "call" || message.Data["c"] == "" ||
		message.Data["h"] == "" || message.Data["e"] == "" {
		t.Fatal("Android call wake must retain the exact bounded opaque grammar")
	}
}
