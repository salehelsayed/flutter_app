package main

import (
	"bytes"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"os"
	"sort"
	"strings"
	"sync"
	"time"

	"github.com/axiomhq/hyperloglog"
	"github.com/prometheus/client_golang/prometheus"
)

const thoughtMetricsEnabledEnv = "MKNOON_RELAY_THOUGHT_METRICS_ENABLED"
const thoughtMetricsWeeks = 8
const thoughtSnapshotLimit = 512 * 1024

// Only dense cardinality registers are retained: no event, peer, recipient or
// content records, including the sparse HLL mode's per-input hash entries.
type thoughtWeek struct {
	posts, posters *hyperloglog.Sketch
}

type thoughtMetrics struct {
	mu         sync.Mutex
	flushMu    sync.Mutex
	weeks      map[string]thoughtWeek
	path       string
	now        func() time.Time
	write      func(string, []byte) error
	generation uint64
	saved      uint64
	healthy    bool
}

type thoughtWeekDisk struct {
	Start   string `json:"week_start"`
	Posts   []byte `json:"posts"`
	Posters []byte `json:"posters"`
}

type thoughtSnapshot struct {
	Version int               `json:"version"`
	Weeks   []thoughtWeekDisk `json:"weeks"`
}

type thoughtEstimate struct {
	week                      string
	posts, posters, returning uint64
}

func thoughtWeekStart(t time.Time) time.Time {
	u := t.UTC()
	day := time.Date(u.Year(), u.Month(), u.Day(), 0, 0, 0, 0, time.UTC)
	return day.AddDate(0, 0, -(int(day.Weekday())+6)%7)
}

// Opt in explicitly. Disabled analytics must not even read or create a snapshot.
func newConfiguredThoughtMetrics(path string, now func() time.Time) (*thoughtMetrics, error) {
	if !strings.EqualFold(strings.TrimSpace(os.Getenv(thoughtMetricsEnabledEnv)), "true") {
		return nil, nil
	}
	return newThoughtMetrics(path, now)
}

func newThoughtMetrics(path string, now func() time.Time) (*thoughtMetrics, error) {
	m := &thoughtMetrics{weeks: make(map[string]thoughtWeek), path: path, now: now, write: appDiagnosticAtomicWrite, healthy: true}
	if path == "" || now == nil {
		return nil, errors.New("thought snapshot path and clock required")
	}
	f, err := os.Open(path)
	if err == nil {
		raw, readErr := io.ReadAll(io.LimitReader(f, thoughtSnapshotLimit+1))
		_ = f.Close()
		if readErr != nil {
			return nil, readErr
		}
		if len(raw) > thoughtSnapshotLimit {
			return nil, errors.New("thought snapshot exceeds bound")
		}
		var disk thoughtSnapshot
		decoder := json.NewDecoder(bytes.NewReader(raw))
		decoder.DisallowUnknownFields()
		if err := decoder.Decode(&disk); err != nil {
			return nil, err
		}
		if decoder.Decode(new(any)) != io.EOF || disk.Version != 1 || len(disk.Weeks) > thoughtMetricsWeeks {
			return nil, errors.New("invalid thought snapshot")
		}
		for _, week := range disk.Weeks {
			start, err := time.Parse("2006-01-02", week.Start)
			if err != nil || !thoughtWeekStart(start).Equal(start) {
				return nil, errors.New("invalid thought week")
			}
			if _, duplicate := m.weeks[week.Start]; duplicate {
				return nil, errors.New("duplicate thought week")
			}
			posts, err := loadThoughtSketch(week.Posts)
			if err != nil {
				return nil, err
			}
			posters, err := loadThoughtSketch(week.Posters)
			if err != nil {
				return nil, err
			}
			m.weeks[week.Start] = thoughtWeek{posts: posts, posters: posters}
		}
	} else if !os.IsNotExist(err) {
		return nil, err
	}
	if err := m.flush(); err != nil {
		return nil, err
	}
	return m, nil
}

func loadThoughtSketch(raw []byte) (*hyperloglog.Sketch, error) {
	sketch := hyperloglog.NewNoSparse()
	prototype, _ := sketch.MarshalBinary()
	// Validate the fixed dense encoding before entering the library decoder.
	if len(raw) != len(prototype) || !bytes.Equal(raw[:8], prototype[:8]) {
		return nil, errors.New("invalid dense thought sketch")
	}
	return sketch, sketch.UnmarshalBinary(raw)
}

func (m *thoughtMetrics) rotateLocked() {
	current := thoughtWeekStart(m.now())
	oldest := current.AddDate(0, 0, -7*(thoughtMetricsWeeks-1)).Format("2006-01-02")
	key := current.Format("2006-01-02")
	for week := range m.weeks {
		if week < oldest || week > key {
			delete(m.weeks, week)
			m.generation++
		}
	}
	if _, exists := m.weeks[key]; !exists {
		m.weeks[key] = thoughtWeek{hyperloglog.NewNoSparse(), hyperloglog.NewNoSparse()}
		m.generation++
	}
}

// Called only after accepted inbox storage. Use authored UTC ISO week, not
// retry/recipient delivery time, so a late replay cannot create another week.
// Only existing outer routing metadata is read; no encrypted content is opened.
func (m *thoughtMetrics) record(entry inboxMessage) {
	var envelope struct {
		Type    string `json:"type"`
		PostID  string `json:"post_id"`
		Sender  string `json:"sender_peer_id"`
		Created string `json:"created_at"`
	}
	if json.Unmarshal([]byte(entry.Message), &envelope) != nil || envelope.Type != "post_create" ||
		envelope.PostID == "" || entry.From == "" || envelope.Sender != entry.From {
		return
	}
	created, err := time.Parse(time.RFC3339Nano, envelope.Created)
	if err != nil {
		return
	}
	m.mu.Lock()
	defer m.mu.Unlock()
	m.rotateLocked()
	current := thoughtWeekStart(m.now())
	start := thoughtWeekStart(created)
	if start.After(current) || start.Before(current.AddDate(0, 0, -7*(thoughtMetricsWeeks-1))) {
		return
	}
	key := start.Format("2006-01-02")
	week, exists := m.weeks[key]
	if !exists {
		week = thoughtWeek{hyperloglog.NewNoSparse(), hyperloglog.NewNoSparse()}
		m.weeks[key] = week
	}
	week.posts.Insert([]byte(envelope.PostID))
	week.posters.Insert([]byte(entry.From))
	m.generation++
}

// Only the periodic/shutdown path writes. Copy bounded registers under mu, then
// release it before marshalling or filesystem work: slow storage cannot hold
// up inbox Store, push, or a scrape. Serialize writers independently of record.
func (m *thoughtMetrics) flush() error {
	m.flushMu.Lock()
	defer m.flushMu.Unlock()
	m.mu.Lock()
	m.rotateLocked()
	if m.generation == m.saved {
		m.mu.Unlock()
		return nil
	}
	generation := m.generation
	keys := m.keysLocked()
	weeks := make([]thoughtWeek, 0, len(keys))
	for _, key := range keys {
		week := m.weeks[key]
		weeks = append(weeks, thoughtWeek{week.posts.Clone(), week.posters.Clone()})
	}
	m.mu.Unlock()
	disk := thoughtSnapshot{Version: 1}
	for i, key := range keys {
		week := weeks[i]
		posts, _ := week.posts.MarshalBinary()
		posters, _ := week.posters.MarshalBinary()
		disk.Weeks = append(disk.Weeks, thoughtWeekDisk{key, posts, posters})
	}
	raw, err := json.Marshal(disk)
	if err == nil {
		// Reuse the existing private atomic file/rename + directory-sync writer.
		err = m.write(m.path, raw)
	}
	m.mu.Lock()
	defer m.mu.Unlock()
	m.healthy = err == nil
	if err == nil {
		// Updates arriving during I/O remain dirty for the next flush.
		m.saved = generation
	}
	return err
}

func (m *thoughtMetrics) keysLocked() []string {
	keys := make([]string, 0, len(m.weeks))
	for key := range m.weeks {
		keys = append(keys, key)
	}
	sort.Strings(keys)
	return keys
}

func (m *thoughtMetrics) snapshot() ([]thoughtEstimate, bool) {
	m.mu.Lock()
	m.rotateLocked()
	keys := m.keysLocked()
	weeks := make([]thoughtWeek, 0, len(keys))
	for _, key := range keys {
		value := m.weeks[key]
		weeks = append(weeks, thoughtWeek{value.posts.Clone(), value.posters.Clone()})
	}
	healthy := m.healthy
	m.mu.Unlock()

	// Compute only from bounded copies: prefix unions and estimates must not
	// hold the inbox register lock. No new identifiers or sketches are retained.
	prior := hyperloglog.NewNoSparse()
	var result []thoughtEstimate
	for i, key := range keys {
		start, _ := time.Parse("2006-01-02", key)
		year, week := start.ISOWeek()
		value := weeks[i]
		posters := value.posters.Estimate()
		earlier := prior.Estimate()
		// All sketches use the same validated dense p14 encoding, so Merge
		// cannot encounter its only error (different precision).
		_ = prior.Merge(value.posters)
		union := prior.Estimate()
		var returning uint64
		if posters+earlier > union {
			returning = min(posters+earlier-union, posters, earlier)
		}
		result = append(result, thoughtEstimate{
			week:  fmt.Sprintf("%04d-W%02d", year, week),
			posts: value.posts.Estimate(), posters: posters, returning: returning,
		})
	}
	return result, healthy
}

var thoughtPostsDesc = prometheus.NewDesc("relay_thoughts_weekly_estimated", "Estimated distinct relay-inboxed Thoughts by authored UTC ISO week. Lower-bound coverage: direct-only deliveries are unseen; HLL estimates may err in either direction.", []string{"week"}, nil)
var thoughtPostersDesc = prometheus.NewDesc("relay_thought_posters_weekly_estimated", "Estimated distinct senders of relay-inboxed Thoughts by authored UTC ISO week. Lower-bound coverage, not verified people.", []string{"week"}, nil)
var thoughtReturningDesc = prometheus.NewDesc("relay_thought_returning_posters_weekly_estimated", "Estimated senders in this authored UTC ISO week and any earlier retained week (eight-week window). Not all-time returning people; direct-only deliveries are unseen; small-cohort HLL intersection estimates can err.", []string{"week"}, nil)
var thoughtSnapshotDesc = prometheus.NewDesc("relay_thoughts_snapshot_healthy", "Last aggregate snapshot write succeeded (1) or failed (0). New updates are buffered until periodic/shutdown flush. Missing Thought series mean unavailable, not zero.", nil, nil)

func (m *thoughtMetrics) Describe(ch chan<- *prometheus.Desc) {
	ch <- thoughtPostsDesc
	ch <- thoughtPostersDesc
	ch <- thoughtReturningDesc
	ch <- thoughtSnapshotDesc
}

func (m *thoughtMetrics) Collect(ch chan<- prometheus.Metric) {
	weeks, healthy := m.snapshot()
	for _, week := range weeks {
		ch <- prometheus.MustNewConstMetric(thoughtPostsDesc, prometheus.GaugeValue, float64(week.posts), week.week)
		ch <- prometheus.MustNewConstMetric(thoughtPostersDesc, prometheus.GaugeValue, float64(week.posters), week.week)
		ch <- prometheus.MustNewConstMetric(thoughtReturningDesc, prometheus.GaugeValue, float64(week.returning), week.week)
	}
	value := 0.0
	if healthy {
		value = 1
	}
	ch <- prometheus.MustNewConstMetric(thoughtSnapshotDesc, prometheus.GaugeValue, value)
}
