package main

import (
	"sync"
	"sync/atomic"
	"time"

	"github.com/axiomhq/hyperloglog"
)

// hllRegister wraps a HyperLogLog sketch with a mutex.
// Peer IDs are hashed internally — the original ID is never stored
// and cannot be recovered from the sketch.
type hllRegister struct {
	mu  sync.Mutex
	hll *hyperloglog.Sketch
}

func newHLLRegister() *hllRegister {
	return &hllRegister{hll: hyperloglog.New()}
}

func (r *hllRegister) Insert(peerID string) {
	r.mu.Lock()
	r.hll.Insert([]byte(peerID))
	r.mu.Unlock()
}

func (r *hllRegister) Estimate() uint64 {
	r.mu.Lock()
	defer r.mu.Unlock()
	return r.hll.Estimate()
}

func (r *hllRegister) Reset() {
	r.mu.Lock()
	r.hll = hyperloglog.New()
	r.mu.Unlock()
}

// businessMetrics holds aggregate-only, privacy-safe counters.
// No peer IDs are stored. All metrics are either HLL sketches
// (irreversible hashes) or simple numeric counters.
type businessMetrics struct {
	dailyHLL   *hllRegister
	weeklyHLL  *hllRegister
	monthlyHLL *hllRegister

	messagesDailyCount     atomic.Int64
	mediaUploadsDailyCount atomic.Int64

	mu           sync.Mutex
	currentDay   int
	currentWeek  int
	currentMonth time.Month
}

// Package-level singleton — nil-guarded at call sites.
var biz *businessMetrics

func newBusinessMetrics() *businessMetrics {
	now := time.Now().UTC()
	_, week := now.ISOWeek()
	return &businessMetrics{
		dailyHLL:     newHLLRegister(),
		weeklyHLL:    newHLLRegister(),
		monthlyHLL:   newHLLRegister(),
		currentDay:   now.YearDay(),
		currentWeek:  week,
		currentMonth: now.Month(),
	}
}

// RecordPeerSeen feeds a peer ID into all three HLL registers.
// The HLL hashes the input internally — the original peer ID
// is discarded and cannot be recovered.
func (bm *businessMetrics) RecordPeerSeen(peerID string) {
	bm.dailyHLL.Insert(peerID)
	bm.weeklyHLL.Insert(peerID)
	bm.monthlyHLL.Insert(peerID)
}

// RecordMessageStored increments the daily message counter.
func (bm *businessMetrics) RecordMessageStored() {
	bm.messagesDailyCount.Add(1)
}

// RecordMediaUploaded increments the daily media upload counter.
func (bm *businessMetrics) RecordMediaUploaded() {
	bm.mediaUploadsDailyCount.Add(1)
}

// CheckAndResetPeriods resets HLL registers and daily counters
// when a time boundary (day/week/month) has been crossed.
// Called from the stats ticker every 60 seconds.
func (bm *businessMetrics) CheckAndResetPeriods() {
	now := time.Now().UTC()
	day := now.YearDay()
	_, week := now.ISOWeek()
	month := now.Month()

	bm.mu.Lock()
	defer bm.mu.Unlock()

	if day != bm.currentDay {
		bm.dailyHLL.Reset()
		bm.messagesDailyCount.Store(0)
		bm.mediaUploadsDailyCount.Store(0)
		bm.currentDay = day
	}

	if week != bm.currentWeek {
		bm.weeklyHLL.Reset()
		bm.currentWeek = week
	}

	if month != bm.currentMonth {
		bm.monthlyHLL.Reset()
		bm.currentMonth = month
	}
}
