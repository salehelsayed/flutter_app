package main

import (
	"bytes"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"os"
	"sort"
	"sync"
	"time"

	"github.com/axiomhq/hyperloglog"
	"github.com/prometheus/client_golang/prometheus"
)

const thoughtMetricsWeeks = 8
const thoughtSnapshotLimit = 512 * 1024

// Only dense cardinality registers are retained: no event, peer, recipient or
// content records, including the sparse HLL mode's per-input hash entries.
type thoughtWeek struct {
	posts, posters *hyperloglog.Sketch
}

type thoughtMetrics struct {
	mu      sync.Mutex
	weeks   map[string]thoughtWeek
	path    string
	now     func() time.Time
	dirty   bool
	healthy bool
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
	week           string
	posts, posters uint64
}

func thoughtWeekStart(t time.Time) time.Time {
	u := t.UTC()
	day := time.Date(u.Year(), u.Month(), u.Day(), 0, 0, 0, 0, time.UTC)
	return day.AddDate(0, 0, -(int(day.Weekday())+6)%7)
}

func newThoughtMetrics(path string, now func() time.Time) (*thoughtMetrics, error) {
	m := &thoughtMetrics{weeks: make(map[string]thoughtWeek), path: path, now: now, healthy: true}
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
	m.rotateLocked()
	if err := m.persistLocked(); err != nil {
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
			m.dirty = true
		}
	}
	if _, exists := m.weeks[key]; !exists {
		m.weeks[key] = thoughtWeek{hyperloglog.NewNoSparse(), hyperloglog.NewNoSparse()}
		m.dirty = true
	}
}

// Called only after accepted inbox storage. Use authored UTC ISO week, not
// retry/recipient delivery time, so a late replay cannot create another week.
// Only existing outer routing metadata is read; no encrypted content is opened.
func (m *thoughtMetrics) record(entry inboxMessage) error {
	var envelope struct {
		Type    string `json:"type"`
		PostID  string `json:"post_id"`
		Sender  string `json:"sender_peer_id"`
		Created string `json:"created_at"`
	}
	if json.Unmarshal([]byte(entry.Message), &envelope) != nil || envelope.Type != "post_create" ||
		envelope.PostID == "" || entry.From == "" || envelope.Sender != entry.From {
		return nil
	}
	created, err := time.Parse(time.RFC3339Nano, envelope.Created)
	if err != nil {
		return nil
	}
	m.mu.Lock()
	defer m.mu.Unlock()
	m.rotateLocked()
	current := thoughtWeekStart(m.now())
	start := thoughtWeekStart(created)
	if start.After(current) || start.Before(current.AddDate(0, 0, -7*(thoughtMetricsWeeks-1))) {
		return m.persistLocked()
	}
	key := start.Format("2006-01-02")
	week, exists := m.weeks[key]
	if !exists {
		week = thoughtWeek{hyperloglog.NewNoSparse(), hyperloglog.NewNoSparse()}
		m.weeks[key] = week
		m.dirty = true
	}
	beforePosts, _ := week.posts.MarshalBinary()
	beforePosters, _ := week.posters.MarshalBinary()
	week.posts.Insert([]byte(envelope.PostID))
	week.posters.Insert([]byte(entry.From))
	afterPosts, _ := week.posts.MarshalBinary()
	afterPosters, _ := week.posters.MarshalBinary()
	m.dirty = m.dirty || !bytes.Equal(beforePosts, afterPosts) || !bytes.Equal(beforePosters, afterPosters)
	return m.persistLocked()
}

func (m *thoughtMetrics) persistLocked() error {
	if !m.dirty {
		return nil
	}
	disk := thoughtSnapshot{Version: 1}
	for _, key := range m.keysLocked() {
		week := m.weeks[key]
		posts, _ := week.posts.MarshalBinary()
		posters, _ := week.posters.MarshalBinary()
		disk.Weeks = append(disk.Weeks, thoughtWeekDisk{key, posts, posters})
	}
	raw, err := json.Marshal(disk)
	if err == nil {
		// Reuse the existing private atomic file/rename + directory-sync writer.
		err = appDiagnosticAtomicWrite(m.path, raw)
	}
	m.healthy = err == nil
	if err == nil {
		m.dirty = false
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
	defer m.mu.Unlock()
	m.rotateLocked()
	_ = m.persistLocked() // Exposed separately; never fail accepted message custody.
	var result []thoughtEstimate
	for _, key := range m.keysLocked() {
		start, _ := time.Parse("2006-01-02", key)
		year, week := start.ISOWeek()
		label := fmt.Sprintf("%04d-W%02d", year, week)
		value := m.weeks[key]
		result = append(result, thoughtEstimate{label, value.posts.Estimate(), value.posters.Estimate()})
	}
	return result, m.healthy
}

var thoughtPostsDesc = prometheus.NewDesc("relay_thoughts_weekly_estimated", "Estimated distinct relay-inboxed Thoughts by authored UTC ISO week. Lower-bound coverage: direct-only deliveries are unseen; HLL estimates may err in either direction.", []string{"week"}, nil)
var thoughtPostersDesc = prometheus.NewDesc("relay_thought_posters_weekly_estimated", "Estimated distinct senders of relay-inboxed Thoughts by authored UTC ISO week. Lower-bound coverage, not verified people or returning posters.", []string{"week"}, nil)
var thoughtSnapshotDesc = prometheus.NewDesc("relay_thoughts_snapshot_healthy", "Whether the aggregate Thought snapshot is durably saved (1) or a write is pending after failure (0). Missing Thought series mean unavailable, not zero.", nil, nil)

func (m *thoughtMetrics) Describe(ch chan<- *prometheus.Desc) {
	ch <- thoughtPostsDesc
	ch <- thoughtPostersDesc
	ch <- thoughtSnapshotDesc
}

func (m *thoughtMetrics) Collect(ch chan<- prometheus.Metric) {
	weeks, healthy := m.snapshot()
	for _, week := range weeks {
		ch <- prometheus.MustNewConstMetric(thoughtPostsDesc, prometheus.GaugeValue, float64(week.posts), week.week)
		ch <- prometheus.MustNewConstMetric(thoughtPostersDesc, prometheus.GaugeValue, float64(week.posters), week.week)
	}
	value := 0.0
	if healthy {
		value = 1
	}
	ch <- prometheus.MustNewConstMetric(thoughtSnapshotDesc, prometheus.GaugeValue, value)
}
