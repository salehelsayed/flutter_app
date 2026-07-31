package main

import (
	"bytes"
	"log"
	"strings"
	"testing"
	"time"

	"github.com/prometheus/client_golang/prometheus/testutil"
)

func TestRelayNotificationClosure_GroupReactionWakeEmptyNominationCounted(t *testing.T) {
	const (
		groupID = "group-reaction-empty-nomination"
		from    = "reactor-transport"
		author  = "author-transport"
	)
	fixture := newSignedGroupReactionFixture(t, groupID, "reactor-account", from)
	push := NewPushServiceWithBackend(newMemoryPushTokenStore())
	store := NewGroupInboxStore(500, 7*24*time.Hour)
	store.SetPush(push)
	store.SetGroupReactionPushEnabled(true)

	var journal bytes.Buffer
	previousWriter := log.Writer()
	log.SetOutput(&journal)
	t.Cleanup(func() { log.SetOutput(previousWriter) })

	counter := groupReactionWakeCounter.WithLabelValues("no_wake_recipients")
	before := testutil.ToFloat64(counter)
	emptyNomination := fixture.envelope(
		t,
		"empty-nomination-transition",
		"add",
		"empty-nomination-state",
		"target-message",
		[]string{author},
		nil,
	)
	if err := store.StoreWithPushRecipients(groupID, from, emptyNomination, []string{author}); err != nil {
		t.Fatalf("store empty nomination: %v", err)
	}
	if delta := testutil.ToFloat64(counter) - before; delta != 1 {
		t.Fatalf("no_wake_recipients delta = %v, want 1", delta)
	}
	if got := journal.String(); !strings.Contains(got, "[GROUP_REACTION_WAKE]") ||
		!strings.Contains(got, "no_wake_recipients") {
		t.Fatalf("reaction wake journal = %q, want attributed empty-nomination outcome", got)
	}

	nonEmptyNomination := fixture.envelope(
		t,
		"non-empty-nomination-transition",
		"add",
		"non-empty-nomination-state",
		"target-message",
		[]string{author},
		[]string{author},
	)
	if err := store.StoreWithPushRecipients(groupID, from, nonEmptyNomination, []string{author}); err != nil {
		t.Fatalf("store non-empty nomination: %v", err)
	}
	if err := store.StoreWithPushRecipients(
		"group-ordinary-message",
		from,
		opaqueGroupReplayEnvelope("ordinary-message"),
		[]string{author},
	); err != nil {
		t.Fatalf("store ordinary message: %v", err)
	}

	nilPushStore := NewGroupInboxStore(500, 7*24*time.Hour)
	nilPushStore.SetGroupReactionPushEnabled(true)
	nilPushEnvelope := fixture.envelope(
		t,
		"nil-push-transition",
		"add",
		"nil-push-state",
		"target-message",
		[]string{author},
		nil,
	)
	if err := nilPushStore.StoreWithPushRecipients(groupID, from, nilPushEnvelope, []string{author}); err != nil {
		t.Fatalf("store empty nomination without push service: %v", err)
	}
	if delta := testutil.ToFloat64(counter) - before; delta != 1 {
		t.Fatalf("negative cases changed no_wake_recipients delta to %v, want 1", delta)
	}
}

func TestRelayNotificationClosure_GroupReactionWakeIncapableSkipCounted(t *testing.T) {
	const (
		groupID   = "group-reaction-capability-observability"
		from      = "reactor-transport"
		capable   = "author-capable-transport"
		incapable = "author-incapable-transport"
	)
	fixture := newSignedGroupReactionFixture(t, groupID, "reactor-account", from)
	tokens := newMemoryPushTokenStore()
	tokens.RegisterToken(capable, "capable-token", "android", groupReactionCapability)
	tokens.RegisterToken(incapable, "incapable-token", "android", directReactionCapability)
	push := NewPushServiceWithBackend(tokens)
	recorder := newRecordingPushSender()
	push.sender = recorder.Send
	store := NewGroupInboxStore(500, 7*24*time.Hour)
	store.SetPush(push)
	store.SetGroupReactionPushEnabled(true)

	incapableCounter := groupReactionWakeCounter.WithLabelValues("incapable_skipped")
	attemptedCounter := groupReactionWakeCounter.WithLabelValues("attempted")
	beforeIncapable := testutil.ToFloat64(incapableCounter)
	beforeAttempted := testutil.ToFloat64(attemptedCounter)
	envelope := fixture.envelope(
		t,
		"capability-transition",
		"add",
		"capability-state",
		"target-message",
		[]string{capable, incapable},
		[]string{capable, incapable},
	)
	if err := store.StoreWithPushRecipients(
		groupID,
		from,
		envelope,
		[]string{capable, incapable},
	); err != nil {
		t.Fatalf("store mixed-capability nomination: %v", err)
	}
	waitForGroupReactionPushes(t, recorder, 1)

	if delta := testutil.ToFloat64(incapableCounter) - beforeIncapable; delta != 1 {
		t.Fatalf("incapable_skipped delta = %v, want 1", delta)
	}
	if delta := testutil.ToFloat64(attemptedCounter) - beforeAttempted; delta != 1 {
		t.Fatalf("attempted delta = %v, want 1", delta)
	}
}

func TestRelayNotificationClosure_GroupReactionWakeDuplicateSuppressedCounted(t *testing.T) {
	const (
		groupID = "group-reaction-duplicate-observability"
		from    = "reactor-transport"
		author  = "author-transport"
	)
	fixture := newSignedGroupReactionFixture(t, groupID, "reactor-account", from)
	store := NewGroupInboxStore(500, 7*24*time.Hour)
	store.SetGroupReactionPushEnabled(true)
	counter := groupReactionWakeCounter.WithLabelValues("duplicate_suppressed")
	before := testutil.ToFloat64(counter)
	envelope := fixture.envelope(
		t,
		"duplicate-transition",
		"add",
		"duplicate-state",
		"target-message",
		[]string{author},
		nil,
	)
	for attempt := 0; attempt < 2; attempt++ {
		if err := store.StoreWithPushRecipients(groupID, from, envelope, []string{author}); err != nil {
			t.Fatalf("store reaction attempt %d: %v", attempt+1, err)
		}
	}
	if delta := testutil.ToFloat64(counter) - before; delta != 1 {
		t.Fatalf("duplicate_suppressed delta = %v, want 1", delta)
	}

	ordinary := opaqueGroupReplayEnvelope("ordinary-duplicate-message")
	for attempt := 0; attempt < 2; attempt++ {
		if err := store.StoreWithPushRecipients(
			"group-ordinary-duplicate",
			from,
			ordinary,
			[]string{author},
		); err != nil {
			t.Fatalf("store ordinary duplicate attempt %d: %v", attempt+1, err)
		}
	}
	if delta := testutil.ToFloat64(counter) - before; delta != 1 {
		t.Fatalf("ordinary duplicate changed duplicate_suppressed delta to %v, want 1", delta)
	}
}
