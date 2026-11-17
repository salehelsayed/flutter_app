package node

import (
	"bytes"
	"encoding/json"
	"errors"
	"os"
	"reflect"
	"strings"
	"testing"
	"time"

	"github.com/mknoon/go-mknoon/activitycalendar"
)

// Exercise the existing public operation envelope so the RED compiles before
// the new local operations and optional occurrence field exist.
func b29wRequest(t *testing.T, h *b294Harness, op string, fields map[string]any) ActiveIdentityReporterLocalRequest {
	t.Helper()
	f := h.config.Fence
	packet := map[string]any{"version": 1, "op": op, "revision": f.Revision, "consentEpoch": f.ConsentEpoch, "profileBinding": f.ProfileBinding, "accountPeerId": f.AccountPeerID}
	for key, value := range fields {
		packet[key] = value
	}
	raw, err := json.Marshal(packet)
	if err != nil {
		t.Fatal(err)
	}
	var request ActiveIdentityReporterLocalRequest
	if err := json.Unmarshal(raw, &request); err != nil {
		t.Fatal(err)
	}
	return request
}

func b29wCall(t *testing.T, h *b294Harness, op string, fields map[string]any) (ActiveIdentityReporterLocalResult, error) {
	t.Helper()
	request := b29wRequest(t, h, op, fields)
	n := &Node{activeIdentityReporter: h.reporter}
	type response struct {
		result ActiveIdentityReporterLocalResult
		err    error
	}
	done := make(chan response, 1)
	h.workers.Add(1)
	go func() {
		defer h.workers.Done()
		result, err := n.ActiveIdentityReporterV1(request)
		done <- response{result, err}
	}()
	select {
	case got := <-done:
		return got.result, got.err
	case <-time.After(2 * time.Second):
		t.Fatal("weekly local operation exceeded its fixed 2s fixture bound")
		return ActiveIdentityReporterLocalResult{}, nil
	}
}

type b29wProjection struct {
	Week            string
	StartUnixMillis int64
	EndUnixMillis   int64
	Kinds           []string
	Acknowledged    []struct {
		RelayPeerID string
		Kinds       []string
	}
}

func b29wProject(t *testing.T, h *b294Harness) b29wProjection {
	t.Helper()
	result, err := b29wCall(t, h, "weeklyProjection", nil)
	if err != nil {
		t.Fatalf("current owner weekly projection refused: %v", err)
	}
	raw, err := json.Marshal(result)
	if err != nil {
		t.Fatal(err)
	}
	var envelope struct{ Weekly *b29wProjection }
	if json.Unmarshal(raw, &envelope) != nil || envelope.Weekly == nil {
		t.Fatal("weekly projection omitted its bounded local result")
	}
	return *envelope.Weekly
}

func b29wMark(t *testing.T, h *b294Harness, kinds ...string) {
	t.Helper()
	result, err := b29wCall(t, h, "markWeekly", map[string]any{"week": activitycalendar.Week(h.clock.now()), "kinds": kinds})
	if err != nil || !result.Accepted {
		t.Fatalf("current-week kind mark was not accepted: %v", err)
	}
}

func b29wACK(t *testing.T, h *b294Harness, relay string, kinds ...string) {
	t.Helper()
	result, err := b29wCall(t, h, "ackWeekly", map[string]any{"week": activitycalendar.Week(h.clock.now()), "relayPeerId": relay, "kinds": kinds})
	if err != nil || !result.Accepted {
		t.Fatalf("current-week independent ACK was not accepted: %v", err)
	}
}

func b29wWant(t *testing.T, got b29wProjection, kinds []string, acknowledgements map[string][]string) {
	t.Helper()
	if !reflect.DeepEqual(got.Kinds, kinds) {
		t.Fatalf("weekly kinds=%v want %v", got.Kinds, kinds)
	}
	actual := map[string][]string{}
	for _, ack := range got.Acknowledged {
		if _, duplicate := actual[ack.RelayPeerID]; duplicate {
			t.Fatal("projection duplicated a relay ACK")
		}
		actual[ack.RelayPeerID] = ack.Kinds
	}
	if !reflect.DeepEqual(actual, acknowledgements) {
		t.Fatalf("independent weekly ACKs=%v want %v", actual, acknowledgements)
	}
}

func TestB29WReporterLegacyDailyMarkAlsoSetsWeeklyActiveWithoutWeeklyACK(t *testing.T) {
	h := b294New(t)
	h.ready()
	h.mark()
	b29wWant(t, b29wProject(t, h), []string{"active"}, map[string][]string{})
	h.transport.start(h.transportID, []string{b294Address(h.relayA, 4101), b294Address(h.relayB, 4102)})
	h.flush()
	if got := b294Disk(t, h.config.StatePath); !got.Marked || len(got.Acknowledged) != 2 {
		t.Fatal("weekly projection changed daily durable marks/relay ACKs")
	}
	b29wWant(t, b29wProject(t, h), []string{"active"}, map[string][]string{})
	b294Proofs(t, h.transport.recorded(), h.config)
}

func TestB29WReporterProjectionUsesBerlinISOYearAndCalendarWeekInterval(t *testing.T) {
	for _, tc := range []struct {
		day, week string
		hours     time.Duration
	}{{"2021-01-01", "2020-W53", 168}, {"2026-03-29", "2026-W13", 167}, {"2026-10-25", "2026-W43", 169}} {
		t.Run(tc.day, func(t *testing.T) {
			h := b294New(t)
			h.clock.set(b294Midnight(t, tc.day).Add(time.Hour))
			h.ready()
			before := b294Read(t, h.config.StatePath)
			got := b29wProject(t, h)
			start, err := activitycalendar.ParseWeek(tc.week)
			if err != nil || got.Week != tc.week || got.StartUnixMillis != start.UnixMilli() || got.EndUnixMillis != start.AddDate(0, 0, 7).UnixMilli() || got.EndUnixMillis-got.StartUnixMillis != int64(tc.hours*time.Hour/time.Millisecond) {
				t.Fatalf("wrong Berlin ISO-week interval: %+v error=%v", got, err)
			}
			b29wWant(t, got, []string{}, map[string][]string{})
			if !bytes.Equal(before, b294Read(t, h.config.StatePath)) {
				t.Fatal("reading an interval created or rewrote activity")
			}
		})
	}
}

func TestB29WReporterACKsAreIndependentByRelayAndCapturedKinds(t *testing.T) {
	h := b294New(t)
	h.ready()
	b29wMark(t, h, "chat")
	b29wACK(t, h, h.relayA, "active")
	b29wMark(t, h, "call")
	// This late ACK came from the earlier active+chat projection. It must not
	// consume the subsequently admitted call bit, or acknowledge another relay.
	b29wACK(t, h, h.relayA, "active", "chat")
	b29wWant(t, b29wProject(t, h), []string{"active", "chat", "call"}, map[string][]string{h.relayA: {"active", "chat"}})
	b29wACK(t, h, h.relayB, "active", "chat", "call")
	b29wACK(t, h, h.relayB, "active", "chat", "call")
	b29wMark(t, h, "group")
	b29wWant(t, b29wProject(t, h), []string{"active", "chat", "call", "group"}, map[string][]string{h.relayA: {"active", "chat"}, h.relayB: {"active", "chat", "call"}})
	if got := b294Disk(t, h.config.StatePath); got.Marked || len(got.Acknowledged) != 0 || len(h.transport.recorded()) != 0 {
		t.Fatal("weekly-only marks/ACKs changed daily state or dispatched a network request")
	}
}

func TestB29WReporterWeeklyRetrySurvivesDailyMidnightAndRestart(t *testing.T) {
	h := b294New(t)
	h.ready()
	h.mark()
	b29wMark(t, h, "chat")
	b29wACK(t, h, h.relayA, "active")
	h.clock.set(b294Midnight(t, "2026-03-29"))
	h.flush()
	if got := b294Disk(t, h.config.StatePath); got.Day != "2026-03-29" || got.Marked || len(got.Acknowledged) != 0 {
		t.Fatal("daily midnight preservation control failed")
	}
	h.reopen()
	h.ready()
	b29wWant(t, b29wProject(t, h), []string{"active", "chat"}, map[string][]string{h.relayA: {"active"}})
}

func TestB29WReporterMondayExpiresOldWeekMarksAndLateACKs(t *testing.T) {
	h := b294New(t)
	h.clock.set(b294Midnight(t, "2026-03-29").Add(12 * time.Hour))
	h.ready()
	b29wMark(t, h, "call")
	oldWeek := activitycalendar.Week(h.clock.now())
	h.clock.set(b294Midnight(t, "2026-03-30"))
	h.flush()
	before := b294Read(t, h.config.StatePath)
	for _, op := range []string{"markWeekly", "ackWeekly"} {
		fields := map[string]any{"week": oldWeek, "kinds": []string{"active"}}
		if op == "ackWeekly" {
			fields["relayPeerId"] = h.relayA
		}
		_, err := b29wCall(t, h, op, fields)
		b294Fixed(t, err, errActiveIdentityReporterStale)
	}
	b29wWant(t, b29wProject(t, h), []string{}, map[string][]string{})
	if !bytes.Equal(before, b294Read(t, h.config.StatePath)) || len(h.transport.recorded()) != 0 {
		t.Fatal("closed-week input changed state or backfilled network activity")
	}
}

func TestB29WReporterWeeklyMarksAndACKsNeedDurabilityAndCurrentOwner(t *testing.T) {
	h := b294New(t)
	h.ready()
	b29wMark(t, h, "group")
	h.files.onWrite(func(string, []byte) error { return errors.New("public weekly writer refusal") })
	_, err := b29wCall(t, h, "ackWeekly", map[string]any{"week": activitycalendar.Week(h.clock.now()), "relayPeerId": h.relayA, "kinds": []string{"active", "group"}})
	b294Fixed(t, err, errActiveIdentityReporterStorage)
	b29wWant(t, b29wProject(t, h), []string{"active", "group"}, map[string][]string{})
	h.files.onWrite(nil)
	request := b29wRequest(t, h, "ackWeekly", map[string]any{"week": activitycalendar.Week(h.clock.now()), "relayPeerId": h.relayA, "kinds": []string{"active", "group"}})
	barrier := b294NewBarrier(t)
	h.files.onWrite(func(string, []byte) error { return barrier.block() })
	n := &Node{activeIdentityReporter: h.reporter}
	ack := h.async(func() error { _, err := n.ActiveIdentityReporterV1(request); return err })
	b294Wait(t, barrier.entered, "weekly ACK durable writer")
	select {
	case err := <-ack:
		t.Fatalf("weekly ACK returned before its durable writer: %v", err)
	default:
	}
	off := h.config.Fence
	off.Revision++
	off.ConsentEpoch++
	h.publish(off, false, false)
	barrier.open()
	err = b294Result(t, ack, "weekly ACK after OFF")
	if !errors.Is(err, errActiveIdentityReporterStale) && !errors.Is(err, errActiveIdentityReporterUnavailable) {
		t.Fatalf("old-owner ACK crossed OFF publication: %v", err)
	}
	h.files.onWrite(nil)
	h.config.Fence = off
	h.config.RootPrivateKeyBase64 = ""
	if err := h.reporter.configure(h.config); err != nil {
		t.Fatal(err)
	}
	_, err = b29wCall(t, h, "weeklyProjection", nil)
	b294Fixed(t, err, errActiveIdentityReporterStale)
}

func TestB29WReporterDisposalPreservesWeeklyButProfileAndEpochRetireIt(t *testing.T) {
	for _, mode := range []string{"disposal", "profile", "epoch"} {
		t.Run(mode, func(t *testing.T) {
			h := b294New(t)
			h.ready()
			b29wMark(t, h, "chat")
			b29wACK(t, h, h.relayA, "active")
			if mode == "disposal" {
				empty := h.config.Fence
				empty.Revision++
				empty.ProfileBinding, empty.AccountPeerID = "", ""
				h.publish(empty, true, true)
				if err := h.reporter.configure(ActiveIdentityReporterConfig{Fence: empty, StatePath: h.config.StatePath, PreservePendingOnUnarm: true}); err != nil {
					t.Fatal(err)
				}
				h.config.Fence.Revision = empty.Revision + 1
			} else {
				h.config.Fence.Revision++
				if mode == "profile" {
					h.config.Fence.ProfileBinding = "v1:" + strings.Repeat("b", 64)
				} else {
					h.config.Fence.ConsentEpoch++
				}
			}
			h.reopen()
			h.ready()
			if mode == "disposal" {
				b29wWant(t, b29wProject(t, h), []string{"active", "chat"}, map[string][]string{h.relayA: {"active"}})
			} else {
				b29wWant(t, b29wProject(t, h), []string{}, map[string][]string{})
			}
		})
	}
}

func TestB29WReporterOccurrenceRejectsFutureOrOverTwoMinuteAge(t *testing.T) {
	for _, delta := range []time.Duration{time.Millisecond, -2*time.Minute - time.Millisecond} {
		t.Run(delta.String(), func(t *testing.T) {
			h := b294New(t)
			h.ready()
			before := b294Read(t, h.config.StatePath)
			_, err := b29wCall(t, h, "mark", map[string]any{"occurredAtUnixMillis": h.clock.now().Add(delta).UnixMilli()})
			b294Fixed(t, err, errActiveIdentityReporterInput)
			if !bytes.Equal(before, b294Read(t, h.config.StatePath)) {
				t.Fatal("invalid occurrence fell back to processing-time activity")
			}
		})
	}
}

func TestB29WReporterOccurrenceUsesOnlyStillOpenDayAndWeek(t *testing.T) {
	for _, tc := range []struct {
		day                     string
		accepted, daily, weekly bool
	}{{"2026-03-28", true, true, true}, {"2026-03-29", true, false, true}, {"2026-03-30", false, false, false}} {
		t.Run(tc.day, func(t *testing.T) {
			h := b294New(t)
			now := b294Midnight(t, tc.day).Add(time.Second)
			if tc.daily {
				now = now.Add(time.Hour)
			}
			h.clock.set(now)
			h.ready()
			result, err := b29wCall(t, h, "mark", map[string]any{"occurredAtUnixMillis": now.Add(-2 * time.Second).UnixMilli()})
			if err != nil || result.Accepted != tc.accepted || b294Disk(t, h.config.StatePath).Marked != tc.daily {
				t.Fatalf("occurrence admission reattributed a closed period: result=%+v error=%v", result, err)
			}
			kinds := []string{}
			if tc.weekly {
				kinds = []string{"active"}
			}
			b29wWant(t, b29wProject(t, h), kinds, map[string][]string{})
			h.transport.start(h.transportID, []string{b294Address(h.relayA, 4101)})
			h.flush()
			if !tc.daily && len(h.transport.recorded()) != 0 {
				t.Fatal("closed-day occurrence dispatched a current-day assertion")
			}
		})
	}
}

func TestB29WReporterLegacySnapshotLoadsWithoutInventingWeeklyHistory(t *testing.T) {
	h := b294New(t)
	h.ready()
	h.mark()
	var fields map[string]json.RawMessage
	if err := json.Unmarshal(b294Read(t, h.config.StatePath), &fields); err != nil {
		t.Fatal(err)
	}
	delete(fields, "weekly")
	raw, err := json.Marshal(fields)
	if err != nil {
		t.Fatal(err)
	}
	h.reopen()
	if err := os.WriteFile(h.config.StatePath, raw, 0600); err != nil {
		t.Fatal(err)
	}
	h.ready()
	if !b294Disk(t, h.config.StatePath).Marked {
		t.Fatal("weekly support discarded a valid legacy daily snapshot")
	}
	b29wWant(t, b29wProject(t, h), []string{}, map[string][]string{})
}
