package main

import (
	"context"
	"errors"
	"fmt"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"

	"github.com/mknoon/go-mknoon/activitycalendar"
	"github.com/prometheus/client_golang/prometheus"
	"github.com/prometheus/client_golang/prometheus/promhttp"
)

func b29RuntimeScrape(t *testing.T, inbox *InboxStore) string {
	t.Helper()
	collector, ok := any(inbox).(prometheus.Collector)
	if !ok {
		t.Fatal("production InboxStore has no active-identity/engagement Prometheus collector")
	}
	registry := prometheus.NewRegistry()
	if err := registry.Register(collector); err != nil {
		t.Fatal(err)
	}
	rec := httptest.NewRecorder()
	promhttp.HandlerFor(registry, promhttp.HandlerOpts{}).ServeHTTP(rec, httptest.NewRequest(http.MethodGet, "/metrics", nil))
	if rec.Code != http.StatusOK {
		t.Fatalf("scrape status=%d body=%s", rec.Code, rec.Body.String())
	}
	return rec.Body.String()
}

func b29RuntimeContains(t *testing.T, body string, lines ...string) {
	t.Helper()
	for _, line := range lines {
		if !strings.Contains(body, line+"\n") {
			t.Fatalf("missing metric %q in %s", line, body)
		}
	}
}

func b29RuntimeNoEstimates(t *testing.T, body string) {
	t.Helper()
	for _, line := range strings.Split(body, "\n") {
		if strings.HasPrefix(line, "relay_active_identities_estimated{") || strings.HasPrefix(line, "relay_engagement_weekly_estimated{") {
			t.Fatalf("unavailable aggregate exposed as a measured row: %s", line)
		}
	}
}

func b29RuntimeEnvironment(t *testing.T, enabled, weekly string) string {
	t.Helper()
	path := filepath.Join(t.TempDir(), "private-counter", "activity.json")
	t.Setenv("MKNOON_RELAY_ACTIVE_IDENTITIES_ENABLED", enabled)
	t.Setenv("MKNOON_RELAY_ENGAGEMENT_ENABLED", weekly)
	t.Setenv("MKNOON_RELAY_ACTIVE_IDENTITIES_KEY", strings.Repeat("r", 32)) // Public deterministic fixture, never an operator secret.
	t.Setenv("MKNOON_RELAY_ACTIVE_IDENTITIES_SNAPSHOT_PATH", path)
	t.Setenv("APNS_VOIP_PUSH_ENABLED", "false")
	t.Setenv("APP_DIAGNOSTICS_DIR", t.TempDir())
	return path
}

func b29RuntimeBootstrap(t *testing.T) *controlPlaneStores {
	t.Helper()
	ctx, cancel := context.WithTimeout(context.Background(), 2*time.Second)
	t.Cleanup(cancel)
	stores, err := newControlPlaneStores(ctx, backendConfig{Kind: backendKindMemory}, DefaultServerLimits(), filepath.Join(t.TempDir(), "absent-public-fixture.json"))
	if err != nil {
		t.Fatalf("optional counter affected control-plane startup: %v", err)
	}
	t.Cleanup(func() { _ = stores.Close() })
	return stores
}

func TestB29RuntimeBootstrapBindsDurableStore(t *testing.T) {
	path := b29RuntimeEnvironment(t, "true", "true")
	stores := b29RuntimeBootstrap(t)
	store := stores.Inbox.activeIdentities
	if store == nil {
		t.Fatal("real control-plane bootstrap leaves activeIdentities nil despite explicit valid configuration")
	}
	if store.path != path || !store.engagementEnabled {
		t.Fatal("bootstrap ignored dedicated private snapshot or weekly flag")
	}
	key, account := b293Account(t, 91)
	_, transport := b293Account(t, 92)
	week := activitycalendar.Week(store.now())
	b29E1Ack(t, activeEngagementResponse(b293Raw(t, b29E1Request(t, key, week, account, transport, []string{"active", "chat"})), transport, store))
	b29RuntimeContains(t, b29RuntimeScrape(t, stores.Inbox), "relay_active_identities_storage_ready 1", "relay_engagement_storage_ready 1", fmt.Sprintf("relay_engagement_weekly_estimated{kind=\"chat\",week=\"%s\"} 1", week))
	if err := stores.Close(); err != nil {
		t.Fatal(err)
	}
	restarted := b29RuntimeBootstrap(t)
	if restarted.Inbox.activeIdentities == nil {
		t.Fatal("restart lost runtime binding")
	}
	b29RuntimeContains(t, b29RuntimeScrape(t, restarted.Inbox), fmt.Sprintf("relay_engagement_weekly_estimated{kind=\"chat\",week=\"%s\"} 1", week))
	for _, file := range []string{path, filepath.Dir(path)} {
		info, err := os.Stat(file)
		if err != nil || info.Mode().Perm()&0077 != 0 {
			t.Fatalf("counter storage is not private: %s %v", file, err)
		}
	}
}

func TestB29RuntimeUnavailableAndWeeklyOff(t *testing.T) {
	for _, test := range []struct{ name, enabled, weekly, key string }{
		{"disabled", "false", "true", strings.Repeat("r", 32)},
		{"invalid-key", "true", "true", "public-short-fixture"},
		{"invalid-enabled", "perhaps", "true", strings.Repeat("r", 32)},
	} {
		t.Run(test.name, func(t *testing.T) {
			b29RuntimeEnvironment(t, test.enabled, test.weekly)
			t.Setenv("MKNOON_RELAY_ACTIVE_IDENTITIES_KEY", test.key)
			stores := b29RuntimeBootstrap(t)
			if stores.Inbox.activeIdentities != nil {
				t.Fatal("disabled/invalid configuration admitted a counter")
			}
			body := b29RuntimeScrape(t, stores.Inbox)
			b29RuntimeContains(t, body, "relay_active_identities_storage_ready 0", "relay_engagement_storage_ready 0")
			b29RuntimeNoEstimates(t, body)
		})
	}
	t.Run("weekly-off-preserves-daily", func(t *testing.T) {
		b29RuntimeEnvironment(t, "true", "false")
		stores := b29RuntimeBootstrap(t)
		store := stores.Inbox.activeIdentities
		if store == nil || store.engagementEnabled {
			t.Fatal("weekly OFF must retain the live daily runtime")
		}
		if err := store.admit(activitycalendar.Day(store.now()), "public-daily-account"); err != nil {
			t.Fatal(err)
		}
		body := b29RuntimeScrape(t, stores.Inbox)
		b29RuntimeContains(t, body, "relay_active_identities_storage_ready 1", "relay_engagement_storage_ready 0")
		b29RuntimeNoEstimates(t, body) // Fresh partial day is absent, never zero-filled.
	})
}

func TestB29RuntimeCollectorDurableCalendarAndKinds(t *testing.T) {
	clock := &b29StoreClock{at: b29StoreMidnight(t, "2026-03-29")}
	store := b29EngagementStore(t, clock)
	inbox := NewInboxStore(nil)
	inbox.activeIdentities = store
	b29StoreAdmit(t, store, "2026-03-29", "public-person-a")
	b29EngagementAdmit(t, store, clock, "public-person-a", activeEngagementChat|activeEngagementCall)
	b29EngagementAdmit(t, store, clock, "public-group-only", activeEngagementGroup)
	body := b29RuntimeScrape(t, inbox)
	for _, kind := range []string{"active", "chat", "call", "group", "reciprocal"} {
		want := 1
		if kind == "active" {
			want = 2
		}
		b29RuntimeContains(t, body, fmt.Sprintf("relay_engagement_weekly_estimated{kind=\"%s\",week=\"2026-W13\"} %d", kind, want))
	}
	if strings.Contains(body, "relay_active_identities_estimated{") {
		t.Fatal("open daily bucket exposed as archive point")
	}
	// Berlin's DST day has 23 hours; weekly rollover and finalized daily triples remain independent.
	b29StoreAdvance(t, store, clock, b29StoreMidnight(t, "2026-03-30"))
	body = b29RuntimeScrape(t, inbox)
	for _, window := range []string{"1d", "7d", "30d"} {
		b29RuntimeContains(t, body, fmt.Sprintf("relay_active_identities_estimated{day=\"2026-03-29\",window=\"%s\"} 1", window))
	}
	b29RuntimeContains(t, body, "relay_engagement_weekly_estimated{kind=\"active\",week=\"2026-W14\"} 0", "relay_engagement_weekly_estimated{kind=\"reciprocal\",week=\"2026-W13\"} 1")
	for _, private := range []string{"public-person-a", "public-group-only", "signature", "pairDigest", "accountPeerId"} {
		if strings.Contains(body, private) {
			t.Fatalf("private input escaped into scrape: %s", private)
		}
	}
}

func TestB29RuntimeCollectorFinalizesSignedMarksAfterRestart(t *testing.T) {
	const day = "2026-03-29"
	start := b29StoreMidnight(t, day)
	closeDay := b29StoreMidnight(t, "2026-03-30")
	for _, test := range []struct {
		name      string
		restartAt time.Time
	}{
		{"same-day", start.Add(12 * time.Hour)},
		{"across-midnight", closeDay.Add(2 * time.Minute)},
	} {
		t.Run(test.name, func(t *testing.T) {
			clock := &b29StoreClock{at: start}
			store := b29NewStore(t, clock)
			key, account := b293Account(t, 41)
			otherKey, otherAccount := b293Account(t, 44)
			_, firstTransport := b293Account(t, 42)
			_, secondTransport := b293Account(t, 43)
			firstMark := b293Raw(t, b293Request(t, key, day, account, firstTransport))
			linkedMark := b293Raw(t, b293Request(t, key, day, account, secondTransport))
			otherMark := b293Raw(t, b293Request(t, otherKey, day, otherAccount, firstTransport))
			b293Ack(t, activeIdentityResponse(firstMark, firstTransport, store))
			b293Ack(t, activeIdentityResponse(linkedMark, secondTransport, store))
			b293Ack(t, activeIdentityResponse(otherMark, firstTransport, store))

			clock.set(test.restartAt)
			reopened, err := newActiveIdentityStore(store.path, b29StoreKey(), clock.now)
			if err != nil {
				t.Fatal(err)
			}
			inbox := NewInboxStore(nil)
			inbox.activeIdentities = reopened
			if test.restartAt.Before(closeDay) {
				b29RuntimeNoEstimates(t, b29RuntimeScrape(t, inbox))
				b293Ack(t, activeIdentityResponse(firstMark, firstTransport, reopened))
				b29StoreAdvance(t, reopened, clock, closeDay)
			}

			body := b29RuntimeScrape(t, inbox)
			for _, window := range []string{"1d", "7d", "30d"} {
				b29RuntimeContains(t, body, fmt.Sprintf("relay_active_identities_estimated{day=%q,window=%q} 2", day, window))
			}
		})
	}
}

func TestB29RuntimeCollectorFailedWriteWithholdsAllRows(t *testing.T) {
	clock := &b29StoreClock{at: b29StoreMidnight(t, "2026-10-24")}
	store := b29EngagementStore(t, clock)
	inbox := NewInboxStore(nil)
	inbox.activeIdentities = store
	b29StoreAdmit(t, store, "2026-10-24", "public-account")
	b29StoreAdvance(t, store, clock, b29StoreMidnight(t, "2026-10-25"))
	originalWrite := store.write
	store.write = func(string, []byte) error { return errors.New("public injected persistence failure") }
	if err := store.admitEngagement("2026-W43", "public-new-account", activeEngagementCall); err == nil {
		t.Fatal("write failure was not exercised")
	}
	body := b29RuntimeScrape(t, inbox)
	b29RuntimeContains(t, body, "relay_active_identities_storage_ready 0", "relay_engagement_storage_ready 0")
	b29RuntimeNoEstimates(t, body)
	store.write = originalWrite
	if err := store.flush(); err != nil {
		t.Fatal(err)
	}
	body = b29RuntimeScrape(t, inbox)
	b29RuntimeContains(t, body, "relay_active_identities_storage_ready 1", "relay_engagement_storage_ready 1", "relay_engagement_weekly_estimated{kind=\"call\",week=\"2026-W43\"} 1", "relay_active_identities_estimated{day=\"2026-10-24\",window=\"1d\"} 1")
}

func TestB29RuntimeCollectorRetainsEightISOWeeks(t *testing.T) {
	clock := &b29StoreClock{at: b29StoreMidnight(t, "2026-12-28")}
	store := b29EngagementStore(t, clock)
	inbox := NewInboxStore(nil)
	inbox.activeIdentities = store
	for i := 0; i < 9; i++ {
		if i > 0 {
			b29StoreAdvance(t, store, clock, clock.now().AddDate(0, 0, 7))
		}
		b29EngagementAdmit(t, store, clock, "public-same-person", activeEngagementChat|activeEngagementCall)
	}
	body := b29RuntimeScrape(t, inbox)
	rows := 0
	for _, line := range strings.Split(body, "\n") {
		if strings.HasPrefix(line, "relay_engagement_weekly_estimated{") {
			rows++
		}
	}
	if rows != 8*5 || strings.Contains(body, `week="2026-W53"`) {
		t.Fatalf("retention rows=%d; want five coherent kinds for exactly eight weeks", rows)
	}
	b29RuntimeContains(t, body, "relay_engagement_weekly_estimated{kind=\"reciprocal\",week=\"2027-W01\"} 1", "relay_engagement_weekly_estimated{kind=\"active\",week=\"2027-W08\"} 1")
}
