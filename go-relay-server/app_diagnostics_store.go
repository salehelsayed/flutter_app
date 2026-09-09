package main

import (
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"errors"
	"os"
	"path/filepath"
	"strings"
	"sync"
	"time"
)

const appDiagnosticRetention = 14 * 24 * time.Hour
const appDiagnosticGlobalBytes = 128 << 20
const appDiagnosticOwnerBytes = 8 << 20
const appDiagnosticBucketEvents = 512
const appDiagnosticBucketBytes = 128 << 10
const appDiagnosticRecordBytes = 192 << 10
const appDiagnosticFinalSlots = 32
const appDiagnosticDiscardLimit = 256

type appDiagnosticConsent struct {
	Epoch        int64 `json:"consentEpoch"`
	Enabled      bool  `json:"enabled"`
	UpdatedAtMs  int64 `json:"updatedAtMs"`
	ClearEpoch   int64 `json:"clearEpoch,omitempty"`
	ErasePending bool  `json:"erasePending,omitempty"`
}
type appDiagnosticStoredEvent struct {
	ReceivedAtMs int64           `json:"receivedAtMs"`
	Event        json.RawMessage `json:"event"`
}
type appDiagnosticRecord struct {
	OwnerDigest            string                              `json:"ownerDigest"`
	ConsentEpoch           int64                               `json:"consentEpoch"`
	CreatedAtMs            int64                               `json:"createdAtMs"`
	Events                 []appDiagnosticStoredEvent          `json:"events"`
	Finals                 map[string]appDiagnosticStoredEvent `json:"finals"`
	DiscardedEventIDs      []string                            `json:"discardedEventIds,omitempty"`
	Dropped                uint64                              `json:"dropped"`
	DiscardLedgerSaturated bool                                `json:"discardLedgerSaturated,omitempty"`
}
type appDiagnosticStore struct {
	mu                sync.Mutex
	dir               string
	now               func() time.Time
	quota, ownerQuota int
	consent           map[string]appDiagnosticConsent
	records           map[string]*appDiagnosticRecord
	write             func(string, []byte) error
	remove            func(string) error
	stop              chan struct{}
	closeOnce         sync.Once
	sizes             map[string]int
	ownerSizes        map[string]int
	usedBytes         int
	eventIndex        map[string]string
}

func appDiagnosticOwner(actor string) string {
	h := sha256.Sum256([]byte("mknoon.app-diagnostics.owner.v1\x00" + actor))
	return hex.EncodeToString(h[:])
}
func appDiagnosticBucket(owner string, e map[string]any) string {
	id, _ := e["attemptId"].(string)
	if id == "" {
		id, _ = e["traceId"].(string)
	}
	if id == "" {
		id, _ = e["runId"].(string)
	}
	h := sha256.Sum256([]byte(owner + "\x00" + e["runId"].(string) + "\x00" + id))
	return hex.EncodeToString(h[:])
}
func appDiagnosticAtomicWrite(path string, raw []byte) error {
	f, err := os.CreateTemp(filepath.Dir(path), ".app-diagnostic-*")
	if err != nil {
		return err
	}
	tmp := f.Name()
	defer os.Remove(tmp)
	if err = f.Chmod(0600); err == nil {
		_, err = f.Write(raw)
	}
	if err == nil {
		err = f.Sync()
	}
	closeErr := f.Close()
	if err == nil {
		err = closeErr
	}
	if err != nil {
		return err
	}
	if err = os.Rename(tmp, path); err != nil {
		return err
	}
	dir, err := os.Open(filepath.Dir(path))
	if err != nil {
		return err
	}
	defer dir.Close()
	return dir.Sync()
}
func newAppDiagnosticStore(dir string, quota int, now func() time.Time) (*appDiagnosticStore, error) {
	if dir == "" {
		return nil, errors.New("app diagnostics directory required")
	}
	if err := os.MkdirAll(dir, 0700); err != nil {
		return nil, err
	}
	info, err := os.Lstat(dir)
	if err != nil || !info.IsDir() || info.Mode()&os.ModeSymlink != 0 {
		return nil, errors.New("invalid app diagnostic directory")
	}
	if err = os.Chmod(dir, 0700); err != nil {
		return nil, err
	}
	if quota <= 0 {
		quota = appDiagnosticGlobalBytes
	}
	if now == nil {
		now = time.Now
	}
	s := &appDiagnosticStore{dir: dir, now: now, quota: quota, ownerQuota: appDiagnosticOwnerBytes, consent: map[string]appDiagnosticConsent{}, records: map[string]*appDiagnosticRecord{}, write: appDiagnosticAtomicWrite, remove: os.Remove, stop: make(chan struct{})}
	private := filepath.Join(dir, "consent.json")
	if info, err := os.Lstat(private); err == nil {
		if info.Mode()&os.ModeSymlink != 0 || info.Size() > 4<<20 {
			return nil, errors.New("invalid app diagnostic consent")
		}
		raw, err := os.ReadFile(private)
		if err != nil {
			return nil, err
		}
		if appDiagnosticDecode(raw, &s.consent) != nil {
			return nil, errors.New("invalid app diagnostic consent")
		}
	} else if !os.IsNotExist(err) {
		return nil, err
	}
	entries, err := os.ReadDir(dir)
	if err != nil {
		return nil, err
	}
	total := 0
	for _, entry := range entries {
		name := entry.Name()
		if !strings.HasSuffix(name, ".json") || !appDiagnosticHash.MatchString(strings.TrimSuffix(name, ".json")) {
			continue
		}
		info, err := entry.Info()
		if err != nil || !info.Mode().IsRegular() || info.Size() > appDiagnosticRecordBytes {
			return nil, errors.New("invalid app diagnostic file")
		}
		total += int(info.Size())
		if total > quota+appDiagnosticRecordBytes {
			return nil, errors.New("app diagnostic quota exceeded")
		}
		raw, err := os.ReadFile(filepath.Join(dir, name))
		if err != nil {
			return nil, err
		}
		var r appDiagnosticRecord
		if appDiagnosticDecode(raw, &r) != nil || !appDiagnosticHash.MatchString(r.OwnerDigest) || len(r.Events) > appDiagnosticBucketEvents || len(r.Finals) > appDiagnosticFinalSlots || len(r.DiscardedEventIDs) > appDiagnosticDiscardLimit {
			return nil, errors.New("invalid app diagnostic record")
		}
		if r.Finals == nil {
			r.Finals = map[string]appDiagnosticStoredEvent{}
		}
		for _, row := range append(append([]appDiagnosticStoredEvent{}, r.Events...), appDiagnosticFinalEvents(&r)...) {
			if _, err := validateAppDiagnosticEvent(row.Event, false); err != nil {
				return nil, errors.New("invalid app diagnostic event")
			}
		}
		s.records[strings.TrimSuffix(name, ".json")] = &r
	}
	if err := s.expireLocked(); err != nil {
		return nil, err
	}
	// Disabled consent was durably committed before erase; restart completes an interrupted erase.
	for key, r := range s.records {
		if c := s.consent[r.OwnerDigest]; !c.Enabled || c.ErasePending || c.Epoch != r.ConsentEpoch {
			if err := s.remove(filepath.Join(dir, key+".json")); err != nil && !os.IsNotExist(err) {
				return nil, err
			}
			s.unindexRecord(key)
			delete(s.records, key)
		}
	}
	for owner, c := range s.consent {
		if c.ErasePending {
			c.ErasePending = false
			s.consent[owner] = c
		}
	}
	if err := s.persistConsent(s.consent); err != nil {
		return nil, err
	}
	for key, r := range s.records {
		s.indexRecord(key, r)
	}
	go func() {
		ticker := time.NewTicker(time.Hour)
		defer ticker.Stop()
		for {
			select {
			case <-s.stop:
				return
			case <-ticker.C:
				s.mu.Lock()
				_ = s.expireLocked()
				s.mu.Unlock()
			}
		}
	}()
	return s, nil
}
func appDiagnosticFinalEvents(r *appDiagnosticRecord) []appDiagnosticStoredEvent {
	rows := make([]appDiagnosticStoredEvent, 0, len(r.Finals))
	for _, e := range r.Finals {
		rows = append(rows, e)
	}
	return rows
}
func (s *appDiagnosticStore) close() {
	if s != nil {
		s.closeOnce.Do(func() { close(s.stop) })
	}
}
func (s *appDiagnosticStore) state(actor string) appDiagnosticConsent {
	s.mu.Lock()
	defer s.mu.Unlock()
	return s.consent[appDiagnosticOwner(actor)]
}
func (s *appDiagnosticStore) persistConsent(next map[string]appDiagnosticConsent) error {
	raw, err := json.Marshal(next)
	if err != nil {
		return err
	}
	return s.write(filepath.Join(s.dir, "consent.json"), raw)
}
func (s *appDiagnosticStore) configure(actor string, enabled bool, epoch int64, clear bool) error {
	s.mu.Lock()
	defer s.mu.Unlock()
	if actor == "" || epoch <= 0 {
		return errAppDiagnosticInvalid
	}
	owner := appDiagnosticOwner(actor)
	old := s.consent[owner]
	if epoch < old.Epoch || (!clear && epoch == old.Epoch && old.Enabled != enabled) {
		return errors.New("stale_epoch")
	}
	if _, exists := s.consent[owner]; !exists && len(s.consent) >= 10000 {
		return errors.New("quota_exceeded")
	}
	if clear && old.ClearEpoch == epoch && !old.ErasePending {
		return nil
	}
	if clear {
		enabled = old.Enabled
	}
	next := make(map[string]appDiagnosticConsent, len(s.consent)+1)
	for k, v := range s.consent {
		next[k] = v
	}
	c := old
	c.Epoch = epoch
	c.Enabled = enabled
	c.UpdatedAtMs = s.now().UnixMilli()
	if clear {
		c.ClearEpoch = epoch
	}
	c.ErasePending = c.ErasePending || clear || !enabled || (old.Epoch > 0 && epoch > old.Epoch)
	next[owner] = c
	if err := s.persistConsent(next); err != nil {
		return err
	}
	s.consent = next
	if c.ErasePending {
		for key, r := range s.records {
			if r.OwnerDigest != owner {
				continue
			}
			if err := s.remove(filepath.Join(s.dir, key+".json")); err != nil && !os.IsNotExist(err) {
				return err
			}
			s.unindexRecord(key)
			delete(s.records, key)
		}
		c.ErasePending = false
		next[owner] = c
		if err := s.persistConsent(next); err != nil {
			c.ErasePending = true
			s.consent[owner] = c
			return err
		}
		s.consent = next
	}
	return nil
}
func (s *appDiagnosticStore) expireLocked() error {
	now := s.now().UnixMilli()
	for key, r := range s.records {
		if now-r.CreatedAtMs <= appDiagnosticRetention.Milliseconds() {
			continue
		}
		if err := s.remove(filepath.Join(s.dir, key+".json")); err != nil && !os.IsNotExist(err) {
			return err
		}
		s.unindexRecord(key)
		delete(s.records, key)
	}
	next := make(map[string]appDiagnosticConsent, len(s.consent))
	for k, c := range s.consent {
		if now-c.UpdatedAtMs <= appDiagnosticRetention.Milliseconds() {
			next[k] = c
		}
	}
	if len(next) != len(s.consent) {
		if err := s.persistConsent(next); err != nil {
			return err
		}
		s.consent = next
	}
	for key, r := range s.records {
		c, exists := s.consent[r.OwnerDigest]
		if exists && c.Enabled && c.Epoch == r.ConsentEpoch {
			continue
		}
		if err := s.remove(filepath.Join(s.dir, key+".json")); err != nil && !os.IsNotExist(err) {
			return err
		}
		s.unindexRecord(key)
		delete(s.records, key)
	}

	return nil
}

// Accepted/discarded IDs are durable before acknowledgement. Global/owner/disk
// pressure is retryable; a full immutable bucket uses a bounded distinct-ID ledger.
func (s *appDiagnosticStore) append(actor string, epoch int64, raw []byte) (string, string) {
	e, err := validateAppDiagnosticEvent(raw, false)
	if err != nil {
		return "rejected", "invalid_request"
	}
	if actor == "" {
		return "rejected", "invalid_request"
	}
	s.mu.Lock()
	defer s.mu.Unlock()
	if err := s.expireLocked(); err != nil {
		return "retry", "sink_unavailable"
	}
	owner := appDiagnosticOwner(actor)
	c := s.consent[owner]
	if c.ErasePending {
		return "retry", "sink_unavailable"
	}
	if !c.Enabled {
		return "retry", "diagnostics_disabled"
	}
	if epoch <= 0 || epoch != c.Epoch {
		return "retry", "stale_epoch"
	}
	eventID := e["eventId"].(string)
	bucket := appDiagnosticBucket(owner, e)
	occurred, _ := e["occurredAtMs"].(json.Number).Int64()
	if occurred < s.now().Add(-appDiagnosticRetention).UnixMilli() || occurred > s.now().Add(5*time.Minute).UnixMilli() {
		return "rejected", "invalid_request"
	}
	canonical, _ := json.Marshal(e)
	eventKey := owner + ":" + eventID
	if known, exists := s.eventIndex[eventKey]; exists {
		if known == "discarded" {
			return "rejected", "quota_exceeded"
		}
		digest := sha256.Sum256(canonical)
		if known == hex.EncodeToString(digest[:]) {
			return "accepted", "none"
		}
		return "rejected", "invalid_request"
	}
	prior := s.records[bucket]
	var record appDiagnosticRecord
	if prior != nil {
		encoded, _ := json.Marshal(prior)
		_ = json.Unmarshal(encoded, &record)
	} else {
		record = appDiagnosticRecord{OwnerDigest: owner, ConsentEpoch: epoch, CreatedAtMs: s.now().UnixMilli(), Finals: map[string]appDiagnosticStoredEvent{}}
	}
	if record.Finals == nil {
		record.Finals = map[string]appDiagnosticStoredEvent{}
	}
	row := appDiagnosticStoredEvent{ReceivedAtMs: s.now().UnixMilli(), Event: canonical}
	final := e["stage"] == "finish" || e["stage"] == "crash" || e["stage"] == "hang"
	result, reason := "accepted", "none"
	if final {
		slot := e["feature"].(string) + ":" + e["source"].(string)
		if e["stage"] == "crash" || e["stage"] == "hang" {
			slot += ":" + eventID
		}
		if _, exists := record.Finals[slot]; exists {
			// Producer terminal records are immutable per feature/attempt/source.
			return "rejected", "invalid_request"
		}
		if len(record.Finals) >= appDiagnosticFinalSlots {
			return "rejected", "quota_exceeded"
		}
		record.Finals[slot] = row
	} else {
		size := 0
		for _, existing := range record.Events {
			size += len(existing.Event)
		}
		if len(record.Events) >= appDiagnosticBucketEvents || size+len(canonical) > appDiagnosticBucketBytes {
			result, reason = "rejected", "quota_exceeded"
			if len(record.DiscardedEventIDs) < appDiagnosticDiscardLimit {
				record.DiscardedEventIDs = append(record.DiscardedEventIDs, eventID)
				record.Dropped++
			} else {
				record.DiscardLedgerSaturated = true
			}
		} else {
			record.Events = append(record.Events, row)
		}
	}
	encoded, _ := json.Marshal(&record)
	for final && len(encoded) > appDiagnosticRecordBytes && len(record.Events) > 0 {
		var evicted struct {
			EventID string `json:"eventId"`
		}
		_ = json.Unmarshal(record.Events[0].Event, &evicted)
		if len(record.DiscardedEventIDs) < appDiagnosticDiscardLimit {
			record.DiscardedEventIDs = append(record.DiscardedEventIDs, evicted.EventID)
		} else {
			record.DiscardLedgerSaturated = true
		}
		record.Events = record.Events[1:]
		record.Dropped++
		encoded, _ = json.Marshal(&record)
	}
	if len(encoded) > appDiagnosticRecordBytes {
		return "retry", "quota_exceeded"
	}
	total := s.usedBytes - s.sizes[bucket] + len(encoded)
	owned := s.ownerSizes[owner] - s.sizes[bucket] + len(encoded)
	if total > s.quota || owned > s.ownerQuota {
		return "retry", "quota_exceeded"
	}
	if err := s.write(filepath.Join(s.dir, bucket+".json"), encoded); err != nil {
		return "retry", "sink_unavailable"
	}
	s.unindexRecord(bucket)
	s.records[bucket] = &record
	s.indexRecord(bucket, &record)
	return result, reason
}

// Indexes contain only private owner digests and canonical event hashes. They
// avoid scanning or serializing the whole retained archive on each upload.
func (s *appDiagnosticStore) indexRecord(key string, r *appDiagnosticRecord) {
	if s.sizes == nil {
		s.sizes = map[string]int{}
		s.ownerSizes = map[string]int{}
		s.eventIndex = map[string]string{}
	}
	raw, _ := json.Marshal(r)
	s.sizes[key] = len(raw)
	s.usedBytes += len(raw)
	s.ownerSizes[r.OwnerDigest] += len(raw)
	for _, row := range append(append([]appDiagnosticStoredEvent{}, r.Events...), appDiagnosticFinalEvents(r)...) {
		e, err := validateAppDiagnosticEvent(row.Event, false)
		if err != nil {
			continue
		}
		canonical, _ := json.Marshal(e)
		digest := sha256.Sum256(canonical)
		s.eventIndex[r.OwnerDigest+":"+e["eventId"].(string)] = hex.EncodeToString(digest[:])
	}
	for _, id := range r.DiscardedEventIDs {
		s.eventIndex[r.OwnerDigest+":"+id] = "discarded"
	}
}
func (s *appDiagnosticStore) unindexRecord(key string) {
	r := s.records[key]
	if r == nil || s.sizes == nil {
		return
	}
	size := s.sizes[key]
	s.usedBytes -= size
	s.ownerSizes[r.OwnerDigest] -= size
	delete(s.sizes, key)
	if s.ownerSizes[r.OwnerDigest] == 0 {
		delete(s.ownerSizes, r.OwnerDigest)
	}
	for _, row := range append(append([]appDiagnosticStoredEvent{}, r.Events...), appDiagnosticFinalEvents(r)...) {
		var e struct {
			EventID string `json:"eventId"`
		}
		_ = json.Unmarshal(row.Event, &e)
		delete(s.eventIndex, r.OwnerDigest+":"+e.EventID)
	}
	for _, id := range r.DiscardedEventIDs {
		delete(s.eventIndex, r.OwnerDigest+":"+id)
	}
}
