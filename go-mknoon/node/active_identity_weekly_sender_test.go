package node

import (
	"context"
	"encoding/json"
	"reflect"
	"testing"
	"time"

	"github.com/mknoon/go-mknoon/activitycalendar"
)

type weeklySenderObserved struct {
	Action string   `json:"action"`
	Week   string   `json:"week"`
	Kinds  []string `json:"kinds"`
}

func queueWeeklySenderFixture(t *testing.T, h *b294Harness) {
	t.Helper()
	result, err := b29wCall(t, h, "flush", nil)
	if err != nil || !result.Queued {
		t.Fatalf("production flush admission failed: %v", err)
	}
}

func waitWeeklySenderAssertion(t *testing.T, h *b294Harness, action string) weeklySenderObserved {
	t.Helper()
	ctx, cancel := context.WithTimeout(context.Background(), 2*time.Second)
	defer cancel()
	for {
		for _, request := range h.transport.recorded() {
			var packet weeklySenderObserved
			if err := json.Unmarshal(request.raw, &packet); err != nil {
				t.Fatal(err)
			}
			if packet.Action == action {
				return packet
			}
		}
		select {
		case <-h.transport.changed:
		case <-ctx.Done():
			t.Fatalf("reporter did not send %s; observed %d exchanges", action, len(h.transport.recorded()))
		}
	}
}

func TestBL78WeeklySenderSendsFromOrdinaryMarks(t *testing.T) {
	for _, test := range []struct {
		op, action  string
		kinds, want []string
	}{
		{"markWeekly", "engagement_identity_v1", []string{"chat", "call", "group"}, []string{"active", "chat", "call", "group"}},
		{"markFeatureUse", "feature_use_identity_v1", []string{"photo_video"}, []string{"photo_video"}},
	} {
		t.Run(test.op, func(t *testing.T) {
			h := b294New(t)
			h.ready()
			h.transport.start(h.transportID, []string{b294Address(h.relayA, 4101)})
			week := activitycalendar.Week(h.clock.now())
			fields := map[string]any{"kinds": test.kinds}
			if test.op == "markWeekly" {
				fields["week"] = week
			} else {
				fields["occurredAtUnixMillis"] = h.clock.now().UnixMilli()
			}
			result, err := b29wCall(t, h, test.op, fields)
			if err != nil || !result.Accepted {
				t.Fatalf("qualifying mark was refused: %v", err)
			}
			packet := waitWeeklySenderAssertion(t, h, test.action)
			if packet.Week != week || !reflect.DeepEqual(packet.Kinds, test.want) {
				t.Fatalf("wrong weekly assertion: %+v", packet)
			}
			if b294Disk(t, h.config.StatePath).Marked {
				t.Fatal("weekly-only mark created daily activity")
			}
		})
	}
}

func TestBL78WeeklySenderFlushesExistingEngagementAndDailyIndependently(t *testing.T) {
	h := b294New(t)
	h.ready()
	h.transport.start(h.transportID, []string{b294Address(h.relayA, 4101)})
	h.mark()
	b29wMark(t, h, "chat", "call", "group")
	queueWeeklySenderFixture(t, h)
	waitWeeklySenderAssertion(t, h, "active_identity_v1")
	packet := waitWeeklySenderAssertion(t, h, "engagement_identity_v1")
	if packet.Week != activitycalendar.Week(h.clock.now()) ||
		!reflect.DeepEqual(packet.Kinds, []string{"active", "chat", "call", "group"}) {
		t.Fatalf("wrong weekly engagement assertion: %+v", packet)
	}
}

func TestBL78WeeklySenderRestoresFeatureOnlyMarkWithoutActivity(t *testing.T) {
	h := b294New(t)
	h.ready()
	want := []string{"voice_message", "photo_video", "video_call", "translation", "voice_to_text", "view_3d"}
	result, err := b29wCall(t, h, "markFeatureUse", map[string]any{
		"kinds": want, "occurredAtUnixMillis": h.clock.now().UnixMilli(),
	})
	if err != nil || !result.Accepted {
		t.Fatalf("qualifying feature-only mark was refused: %v", err)
	}
	h.reopen()
	h.ready()
	h.transport.start(h.transportID, []string{b294Address(h.relayA, 4101)})
	queueWeeklySenderFixture(t, h)
	packet := waitWeeklySenderAssertion(t, h, "feature_use_identity_v1")
	if packet.Week != activitycalendar.Week(h.clock.now()) || !reflect.DeepEqual(packet.Kinds, want) {
		t.Fatalf("wrong feature-only weekly assertion: %+v", packet)
	}
	if got := b294Disk(t, h.config.StatePath); got.Marked || len(got.Acknowledged) != 0 {
		t.Fatal("feature-only usage created daily activity")
	}
	b29wWant(t, b29wProject(t, h), []string{}, map[string][]string{})
}

func TestBL78WeeklySenderRetiresFeatureMarksAcrossConsentEpoch(t *testing.T) {
	h := b294New(t)
	h.ready()
	fields := map[string]any{
		"kinds": []string{"view_3d"}, "occurredAtUnixMillis": h.clock.now().UnixMilli(),
	}
	result, err := b29wCall(t, h, "markFeatureUse", fields)
	if err != nil || !result.Accepted {
		t.Fatalf("mark before consent change failed: %v", err)
	}
	stale := b29wRequest(t, h, "markFeatureUse", fields)
	off := h.config.Fence
	off.Revision++
	off.ConsentEpoch++
	h.publish(off, false, false)
	if err := h.reporter.configure(ActiveIdentityReporterConfig{
		Fence: off, StatePath: h.config.StatePath,
	}); err != nil {
		t.Fatal(err)
	}
	h.config.Fence.Revision = off.Revision + 1
	h.config.Fence.ConsentEpoch = off.ConsentEpoch + 1
	h.reopen()
	h.ready()
	node := &Node{activeIdentityReporter: h.reporter}
	if _, err := node.ActiveIdentityReporterV1(stale); err != ErrActiveIdentityReporterStale {
		t.Fatalf("late feature request got %v, want stale", err)
	}
	if disk := b294Disk(t, h.config.StatePath); disk.FeatureUse != nil || disk.Weekly != nil || disk.Marked {
		t.Fatal("new consent epoch restored past usage or active marks")
	}
}

func TestBL78WeeklySenderOneUnsupportedFamilyPreservesOtherAcknowledgements(t *testing.T) {
	h := b294New(t)
	h.ready()
	h.transport.start(h.transportID, []string{b294Address(h.relayA, 4101)})
	b29wMark(t, h, "chat")
	result, err := b29wCall(t, h, "markFeatureUse", map[string]any{
		"kinds": []string{"translation"}, "occurredAtUnixMillis": h.clock.now().UnixMilli(),
	})
	if err != nil || !result.Accepted {
		t.Fatalf("feature mark failed: %v", err)
	}
	h.transport.onExchange(func(_ context.Context, _ RelayInfo, raw []byte) ([]byte, error) {
		var packet weeklySenderObserved
		if err := json.Unmarshal(raw, &packet); err != nil {
			return nil, err
		}
		if packet.Action == "feature_use_identity_v1" {
			return []byte(`{"status":"ERROR","error":"Unknown action: feature_use_identity_v1"}`), nil
		}
		return []byte(b294ACK), nil
	})
	flush := func() {
		t.Helper()
		_ = b294Result(t, h.async(func() error {
			h.reporter.flushWeekly(h.config.Fence)
			return nil
		}), "weekly transport flush")
	}
	flush()
	b29wWant(t, b29wProject(t, h), []string{"active", "chat"}, map[string][]string{h.relayA: {"active", "chat"}})
	if disk := b294Disk(t, h.config.StatePath); disk.FeatureUse == nil || len(disk.FeatureUse.Acknowledged) != 0 {
		t.Fatal("older relay acknowledged an unsupported feature assertion")
	}
	if len(h.transport.recorded()) != 2 {
		t.Fatal("weekly families were not exchanged independently")
	}
	flush()
	if len(h.transport.recorded()) != 2 {
		t.Fatal("an acknowledged or unsupported family was sent again before retry was due")
	}
}
