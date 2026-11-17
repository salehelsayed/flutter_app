package bridge

import (
	"bytes"
	"encoding/json"
	"strings"
	"testing"
	"time"

	"github.com/mknoon/go-mknoon/activitycalendar"
)

func b29wBridgeProjection(t *testing.T, h *b294BridgeHarness) map[string]any {
	t.Helper()
	_, response := h.call(ActiveIdentityReporterV1, h.packet("weeklyProjection", h.fence))
	data := b294BridgeSuccess(t, response, "weekly", "revision", "consentEpoch")
	weekly, ok := data["weekly"].(map[string]any)
	if !ok || len(weekly) != 5 {
		t.Fatal("weekly projection omitted its exact local shape")
	}
	for _, key := range []string{"week", "startUnixMillis", "endUnixMillis", "kinds", "acknowledged"} {
		if _, exists := weekly[key]; !exists {
			t.Fatalf("weekly projection omitted %s", key)
		}
	}
	return weekly
}

func b29wBridgeMark(t *testing.T, h *b294BridgeHarness) string {
	t.Helper()
	weekly := b29wBridgeProjection(t, h)
	week, ok := weekly["week"].(string)
	if !ok {
		t.Fatal("weekly projection did not return its canonical week")
	}
	packet := h.packet("markWeekly", h.fence)
	packet["week"], packet["kinds"] = week, []string{"chat"}
	_, response := h.call(ActiveIdentityReporterV1, packet)
	data := b294BridgeSuccess(t, response, "accepted", "revision", "consentEpoch")
	if data["accepted"] != true {
		t.Fatal("valid weekly kind mark was not admitted")
	}
	return week
}

func TestB29WBridgeWeeklyProjectionAndACKAreLocalAndKeepLegacyReplies(t *testing.T) {
	h := b294BridgeNew(t)
	h.publish(h.fence, true, false)
	h.configure(h.fence, true, false, h.root, true)
	week := b29wBridgeMark(t, h)
	if b294BridgeDisk(t, h.path).Marked {
		t.Fatal("weekly-only mark silently created a daily event")
	}
	packet := h.packet("ackWeekly", h.fence)
	relay := bridgeB294OtherAccount(t)
	packet["week"], packet["relayPeerId"], packet["kinds"] = week, relay, []string{"active", "chat"}
	raw, response := h.call(ActiveIdentityReporterV1, packet)
	data := b294BridgeSuccess(t, response, "accepted", "revision", "consentEpoch")
	if data["accepted"] != true || h.n.Host() != nil {
		t.Fatal("local ACK was not durable without creating a network host")
	}
	weekly := b29wBridgeProjection(t, h)
	acks, ok := weekly["acknowledged"].([]any)
	if !ok || len(acks) != 1 {
		t.Fatal("local projection lost its independent weekly relay ACK")
	}
	h.mark(h.fence)
	if len(b294BridgeDisk(t, h.path).Acknowledged) != 0 {
		t.Fatal("weekly ACK was copied into the daily ACK domain")
	}
	_, response = h.call(ActiveIdentityReporterV1, h.packet("flush", h.fence))
	b294BridgeSuccess(t, response, "queued", "revision", "consentEpoch")
	for _, secret := range []string{h.root, h.fence.AccountPeerID, h.fence.ProfileBinding, h.path, "signature", "occurredAt"} {
		if strings.Contains(raw, secret) || bytes.Contains(b294BridgeBytes(t, h.path), []byte(secret)) {
			t.Fatal("weekly local receipt/state exposed private configuration or event history")
		}
	}
}

func TestB29WBridgeWeeklyAndOccurrenceSchemasRejectSmuggling(t *testing.T) {
	for _, tc := range []struct {
		name, op string
		edit     func(map[string]any)
	}{
		{"unknown-kind", "markWeekly", func(m map[string]any) { m["kinds"] = []string{"unknown"} }},
		{"invented-reciprocal", "markWeekly", func(m map[string]any) { m["kinds"] = []string{"reciprocal"} }},
		{"duplicate-kind", "markWeekly", func(m map[string]any) { m["kinds"] = []string{"chat", "chat"} }},
		{"empty-kinds", "markWeekly", func(m map[string]any) { m["kinds"] = []string{} }},
		{"null-kinds", "markWeekly", func(m map[string]any) { m["kinds"] = nil }},
		{"string-kinds", "markWeekly", func(m map[string]any) { m["kinds"] = "chat" }},
		{"missing-week", "markWeekly", func(m map[string]any) { delete(m, "week") }},
		{"null-week", "markWeekly", func(m map[string]any) { m["week"] = nil }},
		{"noncanonical-week", "markWeekly", func(m map[string]any) { m["week"] = "2026-W1" }},
		{"counterparty", "markWeekly", func(m map[string]any) { m["contactPeerId"] = "private-forbidden-contact" }},
		{"pair-digest", "markWeekly", func(m map[string]any) { m["pairDigest"] = "private-forbidden-digest" }},
		{"group-id", "markWeekly", func(m map[string]any) { m["groupId"] = "private-forbidden-group" }},
		{"occurrence-on-weekly", "markWeekly", func(m map[string]any) { m["occurredAtUnixMillis"] = time.Now().UnixMilli() }},
		{"invalid-relay", "ackWeekly", func(m map[string]any) { m["relayPeerId"] = "private-invalid-relay" }},
		{"missing-relay", "ackWeekly", func(m map[string]any) { delete(m, "relayPeerId") }},
		{"null-relay", "ackWeekly", func(m map[string]any) { m["relayPeerId"] = nil }},
		{"unmarked-ACK-kind", "ackWeekly", func(m map[string]any) { m["kinds"] = []string{"call"} }},
		{"projection-with-kind", "weeklyProjection", func(m map[string]any) { m["kinds"] = []string{"active"} }},
		{"null-occurrence", "mark", func(m map[string]any) { m["occurredAtUnixMillis"] = nil }},
		{"string-occurrence", "mark", func(m map[string]any) { m["occurredAtUnixMillis"] = "1790000000000" }},
		{"decimal-occurrence", "mark", func(m map[string]any) { m["occurredAtUnixMillis"] = 1.5 }},
		{"occurrence-on-flush", "flush", func(m map[string]any) { m["occurredAtUnixMillis"] = time.Now().UnixMilli() }},
	} {
		t.Run(tc.name, func(t *testing.T) {
			h := b294BridgeNew(t)
			h.publish(h.fence, true, false)
			h.configure(h.fence, true, false, h.root, true)
			week := b29wBridgeMark(t, h)
			packet := h.packet(tc.op, h.fence)
			if tc.op == "markWeekly" || tc.op == "ackWeekly" {
				packet["week"], packet["kinds"] = week, []string{"chat"}
			}
			if tc.op == "ackWeekly" {
				packet["relayPeerId"] = bridgeB294OtherAccount(t)
			}
			tc.edit(packet)
			before := b294BridgeBytes(t, h.path)
			raw, response := h.call(ActiveIdentityReporterV1, packet)
			b294BridgeError(t, response, "INVALID_INPUT")
			if strings.Contains(raw, "private-") || !bytes.Equal(before, b294BridgeBytes(t, h.path)) {
				t.Fatal("refused weekly/occurrence input leaked fields or changed state")
			}
		})
	}
}

func TestB29WBridgeCapturedWeekAndFullFenceRejectLateWeeklyACK(t *testing.T) {
	h := b294BridgeNew(t)
	h.control()
	week := b29wBridgeMark(t, h)
	start, err := activitycalendar.ParseWeek(week)
	if err != nil {
		t.Fatal(err)
	}
	for _, target := range []string{activitycalendar.Week(start.AddDate(0, 0, -7)), activitycalendar.Week(start.AddDate(0, 0, 7))} {
		packet := h.packet("ackWeekly", h.fence)
		packet["week"], packet["kinds"], packet["relayPeerId"] = target, []string{"active"}, bridgeB294OtherAccount(t)
		_, response := h.call(ActiveIdentityReporterV1, packet)
		b294BridgeError(t, response, "ACTIVE_IDENTITY_REPORTER_STALE")
	}
	for _, field := range []string{"revision", "consentEpoch", "profileBinding", "accountPeerId"} {
		packet := h.packet("ackWeekly", h.fence)
		packet["week"], packet["kinds"], packet["relayPeerId"] = week, []string{"active"}, bridgeB294OtherAccount(t)
		if field == "revision" || field == "consentEpoch" {
			packet[field] = packet[field].(int64) + 1
		} else if field == "profileBinding" {
			packet[field] = "v1:" + strings.Repeat("b", 64)
		} else {
			packet[field] = bridgeB294OtherAccount(t)
		}
		_, response := h.call(ActiveIdentityReporterV1, packet)
		b294BridgeError(t, response, "ACTIVE_IDENTITY_REPORTER_STALE")
	}
	weekly := b29wBridgeProjection(t, h)
	if raw, err := json.Marshal(weekly["acknowledged"]); err != nil || string(raw) != "[]" {
		t.Fatal("late captured week/owner ACK affected current-week state")
	}
}
