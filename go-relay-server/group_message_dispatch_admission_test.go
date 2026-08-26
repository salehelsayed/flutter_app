package main

import (
	"bytes"
	"context"
	"errors"
	"log"
	"strings"
	"testing"
	"time"

	"github.com/alicebob/miniredis/v2"
	"github.com/prometheus/client_golang/prometheus/testutil"
	"github.com/redis/go-redis/v9"
)

type failingGroupMessageDispatchAdmissionBackend struct {
	err error
}

func (b failingGroupMessageDispatchAdmissionBackend) TryAcquire(
	context.Context,
	groupMessageDispatchAdmissionIdentity,
) (groupMessageDispatchAdmissionLease, bool, error) {
	return groupMessageDispatchAdmissionLease{}, false, b.err
}

func (failingGroupMessageDispatchAdmissionBackend) Release(
	context.Context,
	groupMessageDispatchAdmissionLease,
) error {
	return nil
}

func TestGroupMessageDispatchAdmissionIdentityIsExactAndDomainSeparated(t *testing.T) {
	base, ok := newGroupMessageDispatchAdmissionIdentity("recipient-a", "group-a", "message-a")
	if !ok {
		t.Fatal("complete exact identity was rejected")
	}
	baseKey := base.storageKey()
	if baseKey == "" {
		t.Fatal("complete exact identity produced an empty storage key")
	}
	for _, raw := range []string{"recipient-a", "group-a", "message-a"} {
		if strings.Contains(baseKey, raw) {
			t.Fatalf("storage key leaked raw identity component %q: %q", raw, baseKey)
		}
	}

	cases := []struct {
		name      string
		recipient string
		groupID   string
		messageID string
	}{
		{name: "other recipient", recipient: "recipient-b", groupID: "group-a", messageID: "message-a"},
		{name: "other group", recipient: "recipient-a", groupID: "group-b", messageID: "message-a"},
		{name: "other message", recipient: "recipient-a", groupID: "group-a", messageID: "message-b"},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			identity, valid := newGroupMessageDispatchAdmissionIdentity(tc.recipient, tc.groupID, tc.messageID)
			if !valid {
				t.Fatal("complete identity was rejected")
			}
			if got := identity.storageKey(); got == baseKey {
				t.Fatalf("independent identity reused base storage key %q", got)
			}
		})
	}

	for _, tc := range []struct {
		name      string
		recipient string
		groupID   string
		messageID string
	}{
		{name: "blank recipient", recipient: "", groupID: "group-a", messageID: "message-a"},
		{name: "blank group", recipient: "recipient-a", groupID: " ", messageID: "message-a"},
		{name: "blank message", recipient: "recipient-a", groupID: "group-a", messageID: ""},
		{name: "noncanonical whitespace", recipient: "recipient-a", groupID: "group-a", messageID: " message-a"},
	} {
		t.Run(tc.name, func(t *testing.T) {
			if _, valid := newGroupMessageDispatchAdmissionIdentity(tc.recipient, tc.groupID, tc.messageID); valid {
				t.Fatal("invalid admission identity was accepted")
			}
		})
	}
}

func TestMemoryGroupMessageDispatchAdmissionExactClaimReleaseAndExpiry(t *testing.T) {
	const ttl = 5 * time.Minute
	now := time.Unix(1_700_000_000, 0)
	backend := newMemoryGroupMessageDispatchAdmissionBackend(ttl)
	backend.now = func() time.Time { return now }
	identity, ok := newGroupMessageDispatchAdmissionIdentity("recipient", "group", "message")
	if !ok {
		t.Fatal("fixture identity rejected")
	}

	first, acquired, err := backend.TryAcquire(context.Background(), identity)
	if err != nil || !acquired {
		t.Fatalf("first acquire = (%#v, %v, %v), want acquired", first, acquired, err)
	}
	if _, acquired, err := backend.TryAcquire(context.Background(), identity); err != nil || acquired {
		t.Fatalf("duplicate acquire = (%v, %v), want suppressed", acquired, err)
	}

	wrongOwner := first
	wrongOwner.owner = "not-the-current-owner"
	if err := backend.Release(context.Background(), wrongOwner); err != nil {
		t.Fatalf("wrong-owner release: %v", err)
	}
	if _, acquired, err := backend.TryAcquire(context.Background(), identity); err != nil || acquired {
		t.Fatalf("wrong-owner release cleared claim: acquired=%v err=%v", acquired, err)
	}

	if err := backend.Release(context.Background(), first); err != nil {
		t.Fatalf("owner release: %v", err)
	}
	second, acquired, err := backend.TryAcquire(context.Background(), identity)
	if err != nil || !acquired {
		t.Fatalf("acquire after release = (%#v, %v, %v), want acquired", second, acquired, err)
	}
	if second.owner == first.owner {
		t.Fatalf("released claim reused owner %q", second.owner)
	}
	otherIdentity, ok := newGroupMessageDispatchAdmissionIdentity("other-recipient", "group", "message")
	if !ok {
		t.Fatal("other fixture identity rejected")
	}
	if _, acquired, err := backend.TryAcquire(context.Background(), otherIdentity); err != nil || !acquired {
		t.Fatalf("independent pre-expiry acquire = (%v, %v), want acquired", acquired, err)
	}
	if got := len(backend.claims); got != 2 {
		t.Fatalf("memory claim count before expiry = %d, want 2", got)
	}

	now = now.Add(ttl)
	if _, acquired, err := backend.TryAcquire(context.Background(), identity); err != nil || !acquired {
		t.Fatalf("acquire at expiry = (%v, %v), want acquired", acquired, err)
	}
	if got := len(backend.claims); got != 1 {
		t.Fatalf("memory claim count after lazy expiry prune = %d, want 1", got)
	}
}

func TestRedisGroupMessageDispatchAdmissionIsSharedAndOwnerChecked(t *testing.T) {
	server := miniredis.RunT(t)
	client := redis.NewClient(&redis.Options{Addr: server.Addr()})
	t.Cleanup(func() { _ = client.Close() })
	const ttl = 5 * time.Minute
	firstBackend := newRedisGroupMessageDispatchAdmissionBackend(client, "tc398:", ttl)
	secondBackend := newRedisGroupMessageDispatchAdmissionBackend(client, "tc398:", ttl)
	identity, ok := newGroupMessageDispatchAdmissionIdentity("recipient", "group", "message")
	if !ok {
		t.Fatal("fixture identity rejected")
	}

	first, acquired, err := firstBackend.TryAcquire(context.Background(), identity)
	if err != nil || !acquired {
		t.Fatalf("first Redis acquire = (%#v, %v, %v), want acquired", first, acquired, err)
	}
	if _, acquired, err := secondBackend.TryAcquire(context.Background(), identity); err != nil || acquired {
		t.Fatalf("second process duplicate acquire = (%v, %v), want suppressed", acquired, err)
	}

	wrongOwner := first
	wrongOwner.owner = "not-the-current-owner"
	if err := secondBackend.Release(context.Background(), wrongOwner); err != nil {
		t.Fatalf("wrong-owner Redis release: %v", err)
	}
	if _, acquired, err := secondBackend.TryAcquire(context.Background(), identity); err != nil || acquired {
		t.Fatalf("wrong-owner Redis release cleared claim: acquired=%v err=%v", acquired, err)
	}

	if err := firstBackend.Release(context.Background(), first); err != nil {
		t.Fatalf("owner Redis release: %v", err)
	}
	if _, acquired, err := secondBackend.TryAcquire(context.Background(), identity); err != nil || !acquired {
		t.Fatalf("Redis acquire after owner release = (%v, %v), want acquired", acquired, err)
	}

	server.FastForward(ttl)
	if _, acquired, err := firstBackend.TryAcquire(context.Background(), identity); err != nil || !acquired {
		t.Fatalf("Redis acquire after TTL = (%v, %v), want acquired", acquired, err)
	}
}

func TestGroupMessageDispatchAdmissionBackendErrorFailsClosedWithoutIdentityLeak(t *testing.T) {
	const (
		recipient = "tc398-private-recipient"
		groupID   = "tc398-private-group"
		messageID = "tc398-private-message"
	)
	tokens := newMemoryPushTokenStore()
	if err := tokens.RegisterToken(recipient, "tc398-private-provider-token", "ios"); err != nil {
		t.Fatalf("register iOS route: %v", err)
	}
	push := NewPushServiceWithBackend(tokens)
	push.groupMessageDispatchAdmission = failingGroupMessageDispatchAdmissionBackend{
		err: errors.New("tc398-private-storage-error"),
	}
	recorder := newRecordingPushSender()
	push.sender = recorder.Send
	admissionErrorBefore := testutil.ToFloat64(
		groupMessageDispatchAdmissionCounter.WithLabelValues("error"),
	)
	dispatchSuppressedBefore := testutil.ToFloat64(
		groupMessageDispatchCounter.WithLabelValues("group_inbox", "suppressed"),
	)
	var logs bytes.Buffer
	previousWriter := log.Writer()
	log.SetOutput(&logs)
	t.Cleanup(func() { log.SetOutput(previousWriter) })

	push.SendGroupNotification(
		context.Background(),
		recipient,
		groupID,
		"tc398-private-sender",
		messageID,
		ordinaryGroupCiphertextEnvelope(16),
	)

	if got := recorder.SendCallCount(); got != 0 {
		t.Fatalf("admission uncertainty reached provider %d time(s), want fail-closed", got)
	}
	if delta := testutil.ToFloat64(
		groupMessageDispatchAdmissionCounter.WithLabelValues("error"),
	) - admissionErrorBefore; delta != 1 {
		t.Fatalf("admission error metric delta = %v, want 1", delta)
	}
	if delta := testutil.ToFloat64(
		groupMessageDispatchCounter.WithLabelValues("group_inbox", "suppressed"),
	) - dispatchSuppressedBefore; delta != 1 {
		t.Fatalf("fail-closed dispatch suppressed delta = %v, want 1", delta)
	}
	for _, private := range []string{
		recipient,
		groupID,
		messageID,
		"tc398-private-provider-token",
		"tc398-private-storage-error",
	} {
		if strings.Contains(logs.String(), private) {
			t.Fatalf("admission error log leaked private value %q: %q", private, logs.String())
		}
	}
}
