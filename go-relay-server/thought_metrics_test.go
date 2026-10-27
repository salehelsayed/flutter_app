package main

import (
	"bytes"
	"encoding/json"
	"errors"
	"fmt"
	"math"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"sort"
	"strings"
	"sync"
	"testing"
	"time"

	"github.com/axiomhq/hyperloglog"
	"github.com/prometheus/client_golang/prometheus"
	"github.com/prometheus/client_golang/prometheus/promhttp"
)

func newTestThoughtMetrics(t *testing.T, now *time.Time) *thoughtMetrics {
	t.Helper()
	m, err := newThoughtMetrics(filepath.Join(t.TempDir(), "thoughts-metrics.json"), func() time.Time { return *now })
	if err != nil {
		t.Fatal(err)
	}
	return m
}

func thoughtMetricEntry(id, sender string, created time.Time) inboxMessage {
	raw, _ := json.Marshal(map[string]any{
		"type": "post_create", "version": "2", "post_id": id,
		"event_id": "event-" + id, "sender_peer_id": sender,
		"created_at": created.UTC().Format(time.RFC3339Nano),
		"encrypted":  map[string]string{"kem": "fixture-kem", "ciphertext": "private-fixture-content", "nonce": "fixture-nonce"},
	})
	return inboxMessage{From: sender, Message: string(raw), Timestamp: created.UnixMilli()}
}

func assertThoughtWeek(t *testing.T, m *thoughtMetrics, week string, posts, posters uint64) {
	t.Helper()
	values, healthy := m.snapshot()
	if !healthy {
		t.Fatal("snapshot is not durable")
	}
	for _, value := range values {
		if value.week == week {
			if value.posts != posts || value.posters != posters {
				t.Fatalf("%s: posts/posters = %d/%d, want %d/%d", week, value.posts, value.posters, posts, posters)
			}
			return
		}
	}
	t.Fatalf("missing week %s", week)
}

func installThoughtMetrics(t *testing.T, m *thoughtMetrics) {
	t.Helper()
	prior := biz
	biz = newBusinessMetrics()
	biz.thoughts = m
	t.Cleanup(func() { biz = prior })
}

func TestThoughtMetricsInboxFanoutRetryDedup(t *testing.T) {
	now := time.Date(2026, 10, 26, 12, 0, 0, 0, time.UTC)
	m := newTestThoughtMetrics(t, &now)
	installThoughtMetrics(t, m)
	inbox := NewInboxStore(nil)
	entry := thoughtMetricEntry("thought-shared-across-fanout", "author-one-synthetic", now)
	for _, recipient := range []string{"recipient-one", "recipient-two", "recipient-three"} {
		for i := 0; i < 2; i++ {
			if _, err := inbox.Store(recipient, entry); err != nil {
				t.Fatal(err)
			}
		}
	}
	assertThoughtWeek(t, m, "2026-W44", 1, 1)
	// After custody is consumed, another accepted replay must still deduplicate.
	inbox.Retrieve("recipient-one", 100)
	if _, err := inbox.Store("recipient-one", entry); err != nil {
		t.Fatal(err)
	}
	assertThoughtWeek(t, m, "2026-W44", 1, 1)
	for _, next := range []inboxMessage{
		thoughtMetricEntry("thought-second-same-author", entry.From, now),
		thoughtMetricEntry("thought-third-other-author", "author-two-synthetic", now),
	} {
		if _, err := inbox.Store("recipient-one", next); err != nil {
			t.Fatal(err)
		}
	}
	assertThoughtWeek(t, m, "2026-W44", 3, 2)
}

type thoughtFailingInboxBackend struct{ InboxBackend }

func (b thoughtFailingInboxBackend) Store(string, inboxMessage) (InboxStoreResult, error) {
	return "", errors.New("owned storage failure")
}

func TestThoughtMetricsIgnoresUnrelatedMalformedAndUncommitted(t *testing.T) {
	now := time.Date(2026, 10, 26, 12, 0, 0, 0, time.UTC)
	m := newTestThoughtMetrics(t, &now)
	installThoughtMetrics(t, m)
	inbox := NewInboxStore(nil)
	valid := thoughtMetricEntry("valid-shape-uncommitted-thought", "synthetic-author", now)
	for _, raw := range []string{
		`{"type":"chat_message","post_id":"unrelated"}`,
		`{"type":"post_retract","post_id":"unrelated"}`,
		`{invalid`,
		`{"type":"post_create","sender_peer_id":"synthetic-author","created_at":"2026-10-26T12:00:00Z"}`,
		strings.Replace(valid.Message, "synthetic-author", "spoofed-author", 1),
		strings.Replace(valid.Message, "2026-10-26T12:00:00Z", "invalid-time", 1),
		thoughtMetricEntry("too-old", valid.From, now.AddDate(0, 0, -56)).Message,
		thoughtMetricEntry("future-week", valid.From, now.AddDate(0, 0, 7)).Message,
	} {
		if _, err := inbox.Store("owned-recipient", inboxMessage{From: valid.From, Message: raw, Timestamp: now.UnixMilli()}); err != nil {
			t.Fatal(err)
		}
	}
	failed := NewInboxStoreWithBackend(thoughtFailingInboxBackend{newMemoryInboxBackend()}, nil)
	if _, err := failed.Store("owned-recipient", valid); err == nil {
		t.Fatal("failure control did not reach the backend")
	}
	assertThoughtWeek(t, m, "2026-W44", 0, 0)
}

func TestThoughtMetricsISOWeekRolloverLateRetryAndRetention(t *testing.T) {
	now := time.Date(2021, 1, 3, 23, 59, 0, 0, time.UTC)
	m := newTestThoughtMetrics(t, &now)
	old := thoughtMetricEntry("before-ISO-year-rollover", "same-author", now)
	m.record(old)
	now = now.Add(2 * time.Minute)
	assertThoughtWeek(t, m, "2021-W01", 0, 0)
	m.record(old)
	assertThoughtWeek(t, m, "2020-W53", 1, 1)
	assertThoughtWeek(t, m, "2021-W01", 0, 0)
	m.record(thoughtMetricEntry("after-ISO-year-rollover", old.From, now))
	assertThoughtWeek(t, m, "2021-W01", 1, 1)
	for i := 0; i < 7; i++ {
		now = now.AddDate(0, 0, 7)
		m.record(thoughtMetricEntry(now.Format(time.RFC3339), old.From, now))
	}
	values, _ := m.snapshot()
	if len(values) != 8 || values[0].week != "2021-W01" || values[7].week != "2021-W08" {
		t.Fatalf("expected current + 7 calendar weeks, got %+v", values)
	}
	if err := m.flush(); err != nil {
		t.Fatal(err)
	}
	reloaded, err := newThoughtMetrics(m.path, func() time.Time { return now })
	if err != nil {
		t.Fatal(err)
	}
	if got, _ := reloaded.snapshot(); len(got) != 8 {
		t.Fatal("eight retained weeks did not survive snapshot reload")
	}
	// Quiet gaps expire calendar weeks, not merely the eighth nonempty bucket.
	now = now.AddDate(0, 0, 56)
	biz := newBusinessMetrics()
	biz.thoughts = m
	biz.CheckAndResetPeriods()
	restarted, err := newThoughtMetrics(m.path, func() time.Time { return now })
	if err != nil {
		t.Fatal(err)
	}
	values, _ = restarted.snapshot()
	if len(values) != 1 || values[0].posts != 0 || values[0].posters != 0 {
		t.Fatalf("expired calendar buckets survived cleanup/restart: %+v", values)
	}
}

func TestThoughtMetricsRestartPersistenceAndPrivacy(t *testing.T) {
	now := time.Date(2026, 10, 26, 12, 0, 0, 0, time.UTC)
	m := newTestThoughtMetrics(t, &now)
	entry := thoughtMetricEntry("private-thought-id-never-in-snapshot", "private-author-id-never-in-snapshot", now)
	m.record(entry)
	if err := m.flush(); err != nil {
		t.Fatal(err)
	}
	restarted, err := newThoughtMetrics(m.path, func() time.Time { return now })
	if err != nil {
		t.Fatal(err)
	}
	restarted.record(entry)
	assertThoughtWeek(t, restarted, "2026-W44", 1, 1)
	raw, err := os.ReadFile(m.path)
	if err != nil {
		t.Fatal(err)
	}
	for _, forbidden := range []string{entry.From, "private-thought-id-never-in-snapshot", "private-fixture-content", "post_id", "sender_peer_id", "encrypted", "recipient"} {
		if bytes.Contains(raw, []byte(forbidden)) {
			t.Fatalf("aggregate file retained forbidden data category %q", forbidden)
		}
	}
	var disk thoughtSnapshot
	if err := json.Unmarshal(raw, &disk); err != nil {
		t.Fatal(err)
	}
	for _, week := range disk.Weeks {
		for _, sketch := range [][]byte{week.Posts, week.Posters} {
			if len(sketch) != 8+(1<<14) || sketch[3] != 0 {
				t.Fatal("retained a sparse/per-input representation instead of dense registers")
			}
		}
	}
	info, _ := os.Stat(m.path)
	if info.Mode().Perm() != 0600 {
		t.Fatalf("snapshot permissions = %o, want 600", info.Mode().Perm())
	}
	files, _ := os.ReadDir(filepath.Dir(m.path))
	if len(files) != 1 {
		t.Fatal("unexpected retained temporary files")
	}
}

func TestThoughtMetricsScrapeContractAndWriteFailureRecovery(t *testing.T) {
	now := time.Date(2026, 10, 26, 12, 0, 0, 0, time.UTC)
	m := newTestThoughtMetrics(t, &now)
	installThoughtMetrics(t, m)
	inbox := NewInboxStore(nil)
	originalPath := m.path
	m.path = filepath.Join(filepath.Dir(m.path), "missing-owned-directory", "thoughts.json")
	entry := thoughtMetricEntry("private-thought-scrape-fixture", "private-author-scrape-fixture", now)
	if status, err := inbox.Store("private-recipient-scrape-fixture", entry); err != nil || status != InboxStoreResultStored {
		t.Fatalf("metric write failure changed accepted custody: %s %v", status, err)
	}
	if err := m.flush(); err == nil {
		t.Fatal("missing directory did not exercise a snapshot write failure")
	}
	registry := prometheus.NewRegistry()
	registry.MustRegister(m)
	scrape := func() string {
		rec := httptest.NewRecorder()
		promhttp.HandlerFor(registry, promhttp.HandlerOpts{}).ServeHTTP(rec, httptest.NewRequest(http.MethodGet, "/metrics", nil))
		if rec.Code != http.StatusOK {
			t.Fatalf("scrape status = %d", rec.Code)
		}
		return rec.Body.String()
	}
	body := scrape()
	for _, want := range []string{
		`relay_thoughts_weekly_estimated{week="2026-W44"} 1`,
		`relay_thought_posters_weekly_estimated{week="2026-W44"} 1`,
		`relay_thought_returning_posters_weekly_estimated{week="2026-W44"} 0`,
		"relay_thoughts_snapshot_healthy 0", "Lower-bound coverage", "direct-only", "Estimated",
	} {
		if !strings.Contains(body, want) {
			t.Fatalf("missing scrape contract %q", want)
		}
	}
	for _, forbidden := range []string{entry.From, "private-thought-scrape-fixture", "private-recipient-scrape-fixture", "private-fixture-content"} {
		if strings.Contains(body, forbidden) {
			t.Fatal("private metadata leaked in metric output")
		}
	}
	m.path = originalPath
	if err := m.flush(); err != nil {
		t.Fatal(err)
	}
	if !strings.Contains(scrape(), "relay_thoughts_snapshot_healthy 1") {
		t.Fatal("pending aggregate write did not recover")
	}
	restarted, err := newThoughtMetrics(m.path, func() time.Time { return now })
	if err != nil {
		t.Fatal(err)
	}
	assertThoughtWeek(t, restarted, "2026-W44", 1, 1)
}

func TestThoughtMetricsBlockedWriterDoesNotDelayStoreOrPush(t *testing.T) {
	now := time.Date(2026, 10, 26, 12, 0, 0, 0, time.UTC)
	m := newTestThoughtMetrics(t, &now)
	installThoughtMetrics(t, m)
	m.record(thoughtMetricEntry("before-blocked-snapshot", "author-before-snapshot", now))
	started, release := make(chan struct{}), make(chan struct{})
	var releaseOnce sync.Once
	unblock := func() { releaseOnce.Do(func() { close(release) }) }
	defer unblock()
	write := m.write
	m.write = func(path string, raw []byte) error {
		close(started)
		<-release
		return write(path, raw)
	}
	flushed := make(chan error, 1)
	go func() { flushed <- m.flush() }()
	select {
	case <-started:
	case <-time.After(2 * time.Second):
		t.Fatal("snapshot writer did not enter the controlled delay")
	}
	// The writer remains blocked until BOTH accepted Store and real push gateway
	// invocation finish. No elapsed-time guess or mock Store replaces this path.
	tokens := newMemoryPushTokenStore()
	tokens.RegisterToken("owned-thought-recipient", "fixture-push-token", "android")
	push := NewPushServiceWithBackend(tokens)
	recorder := newRecordingPushSender()
	push.sender = recorder.Send
	inbox := NewInboxStore(push)
	stored := make(chan error, 1)
	go func() {
		status, err := inbox.Store("owned-thought-recipient", thoughtMetricEntry("during-blocked-snapshot", "author-during-snapshot", now))
		if err == nil && status != InboxStoreResultStored {
			err = errors.New("Store did not accept the fixture")
		}
		stored <- err
	}()
	select {
	case err := <-stored:
		if err != nil {
			t.Fatal(err)
		}
	case <-time.After(2 * time.Second):
		t.Fatal("accepted inbox Store waited for snapshot I/O")
	}
	select {
	case <-recorder.sentSignal:
	case <-time.After(2 * time.Second):
		t.Fatal("push gateway waited for snapshot I/O")
	}
	assertThoughtWeek(t, m, "2026-W44", 2, 2)
	unblock()
	if err := <-flushed; err != nil {
		t.Fatal(err)
	}
	m.write = write
	// The first write captured only the earlier generation. The update accepted
	// during I/O must remain pending and survive the next flush + restart.
	if err := m.flush(); err != nil {
		t.Fatal(err)
	}
	restarted, err := newThoughtMetrics(m.path, func() time.Time { return now })
	if err != nil {
		t.Fatal(err)
	}
	assertThoughtWeek(t, restarted, "2026-W44", 2, 2)
}

func TestThoughtMetricsRejectsInvalidSnapshot(t *testing.T) {
	now := time.Date(2026, 10, 26, 12, 0, 0, 0, time.UTC)
	m := newTestThoughtMetrics(t, &now)
	dense, _ := hyperloglog.NewNoSparse().MarshalBinary()
	for _, raw := range [][]byte{
		[]byte(`{"version":1,"weeks":[],"peer_ids":["must-not-load"]}`),
		[]byte(`{"version":1,"weeks":[]} {"extra":true}`),
		[]byte(`{"version":999,"weeks":[]}`),
		[]byte(strings.Repeat(" ", thoughtSnapshotLimit+1)),
	} {
		if err := os.WriteFile(m.path, raw, 0600); err != nil {
			t.Fatal(err)
		}
		if _, err := newThoughtMetrics(m.path, func() time.Time { return now }); err == nil {
			t.Fatal("invalid snapshot accepted")
		}
	}
	for _, bad := range [][]byte{{1}, dense[:len(dense)-1], append([]byte{99}, dense[1:]...)} {
		if _, err := loadThoughtSketch(bad); err == nil {
			t.Fatal("malformed dense sketch accepted")
		}
	}
}

func TestThoughtMetricsConcurrentRetryAndScrape(t *testing.T) {
	now := time.Date(2026, 10, 26, 12, 0, 0, 0, time.UTC)
	m := newTestThoughtMetrics(t, &now)
	entry := thoughtMetricEntry("same-concurrent-thought", "same-concurrent-author", now)
	var wg sync.WaitGroup
	for i := 0; i < 16; i++ {
		wg.Add(1)
		go func() {
			defer wg.Done()
			m.record(entry)
			m.snapshot()
		}()
	}
	wg.Wait()
	assertThoughtWeek(t, m, "2026-W44", 1, 1)
}

func TestThoughtMetricsDefaultOff(t *testing.T) {
	t.Setenv(thoughtMetricsEnabledEnv, "")
	if err := os.Unsetenv(thoughtMetricsEnabledEnv); err != nil {
		t.Fatal(err)
	}
	// An invalid path/clock would fail initialization if the unset flag did
	// anything with the snapshot.
	if m, err := newConfiguredThoughtMetrics("", nil); m != nil || err != nil {
		t.Fatalf("unset flag initialized analytics: %v %v", m, err)
	}
	now := time.Date(2026, 10, 26, 12, 0, 0, 0, time.UTC)
	path := filepath.Join(t.TempDir(), "thoughts.json")
	for _, disabled := range []string{"", "false", "FALSE", "1", "yes", "typo"} {
		t.Setenv(thoughtMetricsEnabledEnv, disabled)
		if m, err := newConfiguredThoughtMetrics(path, func() time.Time { return now }); m != nil || err != nil {
			t.Fatalf("flag %q initialized analytics: %v %v", disabled, m, err)
		}
		if _, err := os.Stat(path); !os.IsNotExist(err) {
			t.Fatalf("disabled analytics touched snapshot: %v", err)
		}
	}
	t.Setenv(thoughtMetricsEnabledEnv, " true ")
	if m, err := newConfiguredThoughtMetrics(path, func() time.Time { return now }); m == nil || err != nil {
		t.Fatalf("explicit true did not initialize: %v %v", m, err)
	}
	if err := os.WriteFile(path, []byte("corrupt snapshot"), 0600); err != nil {
		t.Fatal(err)
	}
	t.Setenv(thoughtMetricsEnabledEnv, "false")
	if m, err := newConfiguredThoughtMetrics(path, nil); m != nil || err != nil {
		t.Fatalf("disabled analytics read corrupt snapshot: %v %v", m, err)
	}
	t.Setenv(thoughtMetricsEnabledEnv, "true")
	if m, err := newConfiguredThoughtMetrics(path, func() time.Time { return now }); m != nil || err == nil {
		t.Fatal("enabled corrupt snapshot must disable analytics with an error")
	}
}

func TestThoughtMetricsReturningAcrossEarlierWeeksAndRestart(t *testing.T) {
	first := time.Date(2026, 10, 5, 12, 0, 0, 0, time.UTC)
	now := first.AddDate(0, 0, 21)
	m := newTestThoughtMetrics(t, &now)
	for week, senders := range [][]string{{"alice"}, {"bob"}, {"alice", "charlie"}, {"alice", "bob", "dave"}} {
		for _, sender := range senders {
			entry := thoughtMetricEntry(fmt.Sprintf("returning-%d-%s", week, sender), sender, first.AddDate(0, 0, 7*week))
			m.record(entry)
			m.record(entry) // Fanout/retry must not inflate returning posters.
		}
	}
	assertReturning := func(metrics *thoughtMetrics, expected map[string]uint64) {
		t.Helper()
		values, _ := metrics.snapshot()
		for _, value := range values {
			want, exists := expected[value.week]
			if !exists || value.returning != want {
				t.Fatalf("%s returning=%d, want %d (exists=%v)", value.week, value.returning, want, exists)
			}
			delete(expected, value.week)
		}
		if len(expected) != 0 {
			t.Fatalf("missing weeks: %v", expected)
		}
	}
	assertReturning(m, map[string]uint64{"2026-W41": 0, "2026-W42": 0, "2026-W43": 1, "2026-W44": 2})
	if err := m.flush(); err != nil {
		t.Fatal(err)
	}
	restarted, err := newThoughtMetrics(m.path, func() time.Time { return now })
	if err != nil {
		t.Fatal(err)
	}
	assertReturning(restarted, map[string]uint64{"2026-W41": 0, "2026-W42": 0, "2026-W43": 1, "2026-W44": 2})
	// W41 and W42 expire. Alice's W43 occurrence is now the earliest
	// retained one: this is an eight-week observation, not all-time history.
	now = first.AddDate(0, 0, 7*9)
	assertReturning(restarted, map[string]uint64{"2026-W43": 0, "2026-W44": 1, "2026-W50": 0})
}

func TestThoughtMetricsReturningSmallCohortAccuracy(t *testing.T) {
	// Synthetic IDs only. Compare dense p14 intersections with exact test-only
	// truth for pilot weeks 3/4; this is empirical error, not a confidence bound.
	const trials = 128
	first := time.Date(2026, 10, 5, 12, 0, 0, 0, time.UTC)
	for _, size := range []int{20, 50, 100} {
		for _, pattern := range []string{"rotating", "all-new", "all-returning"} {
			t.Run(fmt.Sprintf("n%d/%s", size, pattern), func(t *testing.T) {
				var errors []int
				for trial := 0; trial < trials; trial++ {
					now := first.AddDate(0, 0, 21)
					m := &thoughtMetrics{weeks: make(map[string]thoughtWeek), now: func() time.Time { return now }, healthy: true}
					prior := make(map[string]bool)
					truth := make([]int, 4)
					for week := 0; week < 4; week++ {
						offset := 0
						if pattern == "all-new" {
							offset = week * size
						} else if pattern == "rotating" && week != 3 {
							offset = week * size / 2
						}
						for person := offset; person < offset+size; person++ {
							sender := fmt.Sprintf("synthetic-%d-%d-%s-%d", size, trial, pattern, person)
							if prior[sender] {
								truth[week]++
							}
							m.record(thoughtMetricEntry(fmt.Sprintf("post-%d-%s", week, sender), sender, first.AddDate(0, 0, 7*week)))
							prior[sender] = true
						}
					}
					values, _ := m.snapshot()
					for week := 2; week < 4; week++ {
						error := int(math.Abs(float64(int(values[week].returning) - truth[week])))
						errors = append(errors, error)
						// A practical regression bound for these fixed cohorts,
						// deliberately looser than the reported observations.
						if error > 5 {
							t.Fatalf("trial=%d week=%d estimate=%d truth=%d error=%d", trial, week+1, values[week].returning, truth[week], error)
						}
					}
				}
				sort.Ints(errors)
				sum := 0
				for _, error := range errors {
					sum += error
				}
				t.Logf("dense p14: n=%d pattern=%s samples=%d mean_absolute_error=%.4f p95_absolute_error=%d max_absolute_error=%d", size, pattern, len(errors), float64(sum)/float64(len(errors)), errors[(95*len(errors)+99)/100-1], errors[len(errors)-1])
			})
		}
	}
}
