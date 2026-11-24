package main

import (
	"bytes"
	"crypto/hmac"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"errors"
	"log"
	"os"
	"path/filepath"
	"strings"
	"sync"
	"time"

	"github.com/axiomhq/hyperloglog"
	"github.com/mknoon/go-mknoon/activitycalendar"
)

const (
	featureUseRetention = 8
	featureUseKindCount = len(featureUseNames)
)

var errFeatureUseWeek = errors.New("feature use week is not current")

type featureUseEstimate struct {
	Week   string
	Counts [featureUseKindCount]uint64
}

type featureUseWeek struct {
	featureUseEstimate
	sketches [featureUseKindCount]*hyperloglog.Sketch
}

type featureUseWeekDisk struct {
	Week     string   `json:"week"`
	Sketches [][]byte `json:"sketches"`
}

type featureUseDisk struct {
	Version int                  `json:"version"`
	KeyID   string               `json:"key_id"`
	Weeks   []featureUseWeekDisk `json:"weeks"`
}

type featureUseStore struct {
	writeMu sync.Mutex
	mu      sync.Mutex
	path    string
	key     []byte
	keyID   string
	now     func() time.Time
	write   func(string, []byte) error

	// mu protects the published snapshot. Its rows and sketches are immutable.
	weeks   []featureUseWeek
	healthy bool
}

func initFeatureUseFromEnvironment() *featureUseStore {
	enabled := strings.ToLower(strings.TrimSpace(os.Getenv("MKNOON_RELAY_FEATURE_USE_ENABLED")))
	if enabled == "" || enabled == "false" {
		return nil
	}
	if enabled == "true" {
		store, err := newFeatureUseStore(os.Getenv("MKNOON_RELAY_ACTIVE_IDENTITIES_SNAPSHOT_PATH"),
			[]byte(os.Getenv("MKNOON_RELAY_ACTIVE_IDENTITIES_KEY")), time.Now)
		if err == nil {
			return store
		}
	}
	log.Print("[FEATURE_USE] Counter unavailable")
	return nil
}

func newFeatureUseStore(activityPath string, key []byte, now func() time.Time) (*featureUseStore, error) {
	if !filepath.IsAbs(activityPath) || filepath.Base(activityPath) == "." || filepath.Base(activityPath) == ".." ||
		strings.ContainsRune(activityPath, '\x00') || os.IsPathSeparator(activityPath[len(activityPath)-1]) || now == nil {
		return nil, errActiveIdentityStoreInput
	}
	if len(key) != sha256.Size {
		return nil, errActiveIdentityKey
	}
	domain := hmac.New(sha256.New, key)
	_, _ = domain.Write([]byte("mknoon/feature-use/v1\x00"))
	store := &featureUseStore{
		path:  activityPath + ".feature-use",
		key:   domain.Sum(nil),
		now:   now,
		write: appDiagnosticAtomicWrite,
	}
	keyMarker := hmac.New(sha256.New, store.key)
	_, _ = keyMarker.Write([]byte("snapshot-key\x00"))
	store.keyID = hex.EncodeToString(keyMarker.Sum(nil))
	if parent, err := os.Lstat(filepath.Dir(store.path)); err == nil && parent.Mode().Perm() != 0700 {
		return nil, errActiveIdentityStoreStorage
	}
	if err := activeIdentityPrepareSnapshotDirectory(store.path); err != nil {
		return nil, err
	}
	if info, err := os.Lstat(store.path); err == nil && info.Mode().Perm()&0077 != 0 {
		return nil, errActiveIdentityStoreSnapshot
	}
	raw, exists, err := activeIdentityReadSnapshot(store.path)
	if err != nil {
		return nil, err
	}
	if exists {
		store.weeks, err = decodeFeatureUseSnapshot(raw, store.keyID)
		if err != nil {
			return nil, err
		}
	}
	if err := store.advance(); err != nil {
		return nil, err
	}
	return store, nil
}

func (s *featureUseStore) advance() error {
	return s.update("", "", 0)
}

func (s *featureUseStore) update(week, account string, kinds uint8) error {
	s.writeMu.Lock()
	defer s.writeMu.Unlock()

	at := s.now()
	if at.IsZero() {
		return errActiveIdentityStoreStorage
	}
	current := activitycalendar.Week(at)
	if week != "" && week != current {
		return errFeatureUseWeek
	}
	window, err := activitycalendar.WeekWindowEnding(current, featureUseRetention)
	if err != nil {
		return errActiveIdentityStoreStorage
	}

	s.mu.Lock()
	weeks, healthy := s.weeks, s.healthy
	s.mu.Unlock()

	row := featureUseWeek{featureUseEstimate: featureUseEstimate{Week: current}}
	if n := len(weeks); n != 0 && weeks[n-1].Week >= current {
		if weeks[n-1].Week > current {
			return errActiveIdentityStoreStorage
		}
		if kinds == 0 && healthy {
			return nil
		}
		row = weeks[n-1]
	} else {
		for i := range row.sketches {
			row.sketches[i] = hyperloglog.NewNoSparse()
		}
	}
	for i, name := range featureUseNames {
		if kinds&(1<<i) != 0 {
			mac := hmac.New(sha256.New, s.key)
			_, _ = mac.Write([]byte(current + "\x00" + name + "\x00" + account))
			sketch := row.sketches[i].Clone()
			sketch.Insert(mac.Sum(nil))
			row.sketches[i] = sketch
			row.Counts[i] = sketch.Estimate()
		}
	}
	next := make([]featureUseWeek, 0, featureUseRetention)
	for _, saved := range weeks {
		if saved.Week >= window[0] && saved.Week < current {
			next = append(next, saved)
		}
	}
	next = append(next, row)
	err = s.persist(next)

	s.mu.Lock()
	s.healthy = err == nil
	if s.healthy {
		s.weeks = next
	}
	s.mu.Unlock()
	return err
}

func (s *featureUseStore) estimates() ([]featureUseEstimate, bool) {
	at := s.now()
	if at.IsZero() {
		return nil, false
	}
	current := activitycalendar.Week(at)
	window, err := activitycalendar.WeekWindowEnding(current, featureUseRetention)
	if err != nil {
		return nil, false
	}

	s.mu.Lock()
	defer s.mu.Unlock()
	if !s.healthy || len(s.weeks) == 0 || s.weeks[len(s.weeks)-1].Week > current {
		return nil, false
	}
	estimates := make([]featureUseEstimate, 0, len(s.weeks))
	for _, row := range s.weeks {
		if row.Week >= window[0] {
			estimates = append(estimates, row.featureUseEstimate)
		}
	}
	return estimates, true
}

func (s *featureUseStore) persist(weeks []featureUseWeek) error {
	disk := featureUseDisk{Version: 1, KeyID: s.keyID, Weeks: make([]featureUseWeekDisk, 0, len(weeks))}
	for _, saved := range weeks {
		row := featureUseWeekDisk{Week: saved.Week, Sketches: make([][]byte, 0, featureUseKindCount)}
		for _, sketch := range saved.sketches {
			data, err := sketch.MarshalBinary()
			if err != nil {
				return errActiveIdentityStoreStorage
			}
			row.Sketches = append(row.Sketches, data)
		}
		disk.Weeks = append(disk.Weeks, row)
	}
	raw, err := json.Marshal(disk)
	if err != nil || len(raw) > activeIdentityStoreSnapshotLimit || s.write(s.path, raw) != nil {
		return errActiveIdentityStoreStorage
	}
	return nil
}

func decodeFeatureUseSnapshot(raw []byte, keyID string) ([]featureUseWeek, error) {
	var disk featureUseDisk
	if appDiagnosticDecode(raw, &disk) != nil || disk.Version != 1 || len(disk.Weeks) == 0 || len(disk.Weeks) > featureUseRetention {
		return nil, errActiveIdentityStoreSnapshot
	}
	if disk.KeyID != keyID {
		return nil, errActiveIdentityStoreKeyEpoch
	}
	window, err := activitycalendar.WeekWindowEnding(disk.Weeks[len(disk.Weeks)-1].Week, featureUseRetention)
	if err != nil {
		return nil, errActiveIdentityStoreSnapshot
	}
	prototype, err := hyperloglog.NewNoSparse().MarshalBinary()
	if err != nil {
		return nil, errActiveIdentityStoreSnapshot
	}
	weeks := make([]featureUseWeek, 0, len(disk.Weeks))
	previous := ""
	for _, saved := range disk.Weeks {
		if _, err := activitycalendar.ParseWeek(saved.Week); err != nil || saved.Week < window[0] ||
			saved.Week <= previous || len(saved.Sketches) != featureUseKindCount {
			return nil, errActiveIdentityStoreSnapshot
		}
		row := featureUseWeek{featureUseEstimate: featureUseEstimate{Week: saved.Week}}
		for i, data := range saved.Sketches {
			if len(data) != len(prototype) || !bytes.Equal(data[:8], prototype[:8]) {
				return nil, errActiveIdentityStoreSnapshot
			}
			for _, rank := range data[8:] {
				if rank > 65-prototype[1] {
					return nil, errActiveIdentityStoreSnapshot
				}
			}
			sketch := new(hyperloglog.Sketch)
			if sketch.UnmarshalBinary(data) != nil {
				return nil, errActiveIdentityStoreSnapshot
			}
			row.sketches[i] = sketch
			row.Counts[i] = sketch.Estimate()
		}
		weeks = append(weeks, row)
		previous = saved.Week
	}
	return weeks, nil
}
