package main

import (
	"bytes"
	"crypto/hmac"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"errors"
	"io"
	"os"
	"path/filepath"
	"sort"
	"strings"
	"sync"
	"time"

	"github.com/axiomhq/hyperloglog"
	"github.com/mknoon/go-mknoon/activitycalendar"
)

const (
	activeIdentityStoreVersion       = 1
	activeIdentityStoreCalendar      = "Europe/Berlin"
	activeIdentityStoreSnapshotLimit = 2 << 20
	activeIdentityObservationPeriod  = time.Minute
	// The live ticker may be delayed by a tick. Restart recovery still requires
	// a durable observation within one period.
	activeIdentityLiveGapLimit = 2 * activeIdentityObservationPeriod
)

var (
	errActiveIdentityStoreInput    = errors.New("invalid active identity store input")
	errActiveIdentityStoreDay      = errors.New("active identity day is not current")
	errActiveIdentityStoreSnapshot = errors.New("invalid active identity snapshot")
	errActiveIdentityStoreKeyEpoch = errors.New("active identity snapshot key epoch differs")
	errActiveIdentityStoreStorage  = errors.New("active identity persistence unavailable")
)

type activeIdentityFinalized struct {
	Day     string                 `json:"day"`
	Counts  activeIdentityEstimate `json:"counts"`
	Partial bool                   `json:"partial,omitempty"`
}

type activeIdentityOpenDay struct {
	Day             string    `json:"day"`
	ObservingFrom   time.Time `json:"observing_from"`
	FullDayEligible bool      `json:"full_day_eligible"`
}

type activeIdentityDayDisk struct {
	Day    string `json:"day"`
	Sketch []byte `json:"sketch"`
}

// Coverage fields are optional so old snapshots still load. Older binaries
// cannot read the new fields because their decoder rejects unknown fields.
type activeIdentityStoreDisk struct {
	Version          int                       `json:"version"`
	Calendar         string                    `json:"calendar"`
	KeyID            string                    `json:"key_id"`
	Generation       uint64                    `json:"generation"`
	MeasurementStart time.Time                 `json:"measurement_start"`
	ObservedAt       *time.Time                `json:"observed_at,omitempty"`
	OpenDay          activeIdentityOpenDay     `json:"open_day"`
	Days             []activeIdentityDayDisk   `json:"days"`
	Finalized        []activeIdentityFinalized `json:"finalized"`
	Engagement       *activeEngagementDisk     `json:"engagement,omitempty"`
}

// mu owns the calendar, sketches, and generations. flushMu serializes snapshots;
// filesystem I/O never holds mu. Only durable copies may be published.
type activeIdentityStore struct {
	mu, flushMu       sync.Mutex
	path, keyID       string
	now               func() time.Time
	write             func(string, []byte) error
	sketches          *activeDailySketches
	measurementStart  time.Time
	observedAt        time.Time
	openDay           activeIdentityOpenDay
	finals            []activeIdentityFinalized
	durableFinals     []activeIdentityFinalized
	generation        uint64
	saved             uint64
	healthy           bool
	engagementEnabled bool
	weeks             map[string]*activeEngagementSketches
	durableEngagement []activeEngagementWeek
}

func newActiveIdentityStoreWithEngagement(path string, key []byte, now func() time.Time, enabled bool) (*activeIdentityStore, error) {
	if path == "" || now == nil {
		return nil, errActiveIdentityStoreInput
	}
	if strings.ContainsRune(path, '\x00') || os.IsPathSeparator(path[len(path)-1]) ||
		filepath.Base(path) == "." || filepath.Base(path) == ".." {
		return nil, errActiveIdentityStoreInput
	}
	sketches, err := newActiveDailySketches(key)
	if err != nil {
		return nil, err
	}
	mac := hmac.New(sha256.New, sketches.key)
	_, _ = mac.Write([]byte("mknoon/active-identities/v1/snapshot-key\x00"))
	s := &activeIdentityStore{
		path: path, keyID: hex.EncodeToString(mac.Sum(nil)),
		now: now, write: appDiagnosticAtomicWrite, sketches: sketches, engagementEnabled: enabled,
	}
	s.mu.Lock()
	at := s.now()
	s.mu.Unlock()
	if at.IsZero() {
		return nil, errActiveIdentityStoreInput
	}
	today := activitycalendar.Day(at)
	midnight, err := activitycalendar.Parse(today)
	if err != nil {
		return nil, errActiveIdentityStoreInput
	}
	if err := activeIdentityPrepareSnapshotDirectory(path); err != nil {
		return nil, err
	}
	raw, exists, err := activeIdentityReadSnapshot(path)
	if err != nil {
		return nil, err
	}
	s.mu.Lock()
	if exists {
		disk, err := activeIdentityDecodeSnapshot(raw)
		if err == nil {
			err = s.restoreLocked(disk, at)
		}
		if err != nil {
			s.mu.Unlock()
			return nil, err
		}
	} else {
		s.measurementStart = at
	}
	// A durable observation within one stats interval bounds a restart gap.
	// Without it, the old sketches are still usable as partial estimates.
	continuous := exists && !s.observedAt.IsZero() && !at.Before(s.observedAt) && at.Sub(s.observedAt) <= activeIdentityObservationPeriod
	if exists {
		previous, _ := activitycalendar.Parse(s.openDay.Day)
		continuous = continuous && !midnight.After(previous.AddDate(0, 0, 1))
		frozen, err := s.missingFinalsLocked(midnight, continuous)
		if err != nil {
			s.mu.Unlock()
			return nil, err
		}
		s.finals = append(s.finals, frozen...)
	}
	if !continuous || s.openDay.Day != today {
		s.startDayLocked(today, at, midnight, continuous)
	}
	s.observedAt = at
	s.pruneLocked(midnight)
	if err := s.nextGenerationLocked(); err != nil {
		s.mu.Unlock()
		return nil, err
	}
	target := s.generation
	s.mu.Unlock()
	if err := s.flushThrough(target); err != nil {
		return nil, err
	}
	return s, nil
}

func (s *activeIdentityStore) admit(day, canonicalAccount string) error {
	if _, err := activitycalendar.Parse(day); err != nil {
		return err
	}
	if canonicalAccount == "" {
		return errActiveIdentityAccount
	}
	for {
		s.mu.Lock()
		at := s.now()
		if day != activitycalendar.Day(at) {
			s.mu.Unlock()
			return errActiveIdentityStoreDay
		}
		if s.rolloverNeedsFlushLocked(at) {
			target := s.generation
			s.mu.Unlock()
			if err := s.flushThrough(target); err != nil {
				return err
			}
			continue
		}
		if err := s.advanceLocked(at); err != nil {
			s.mu.Unlock()
			return err
		}
		if err := s.nextGenerationLocked(); err != nil {
			s.mu.Unlock()
			return err
		}
		if err := s.sketches.insert(day, canonicalAccount); err != nil {
			s.mu.Unlock()
			return err
		}
		if s.engagementEnabled {
			if err := s.weeks[activitycalendar.Week(at)].insert(canonicalAccount, activeEngagementActive); err != nil {
				s.mu.Unlock()
				return err
			}
		}
		target := s.generation
		s.mu.Unlock()
		return s.flushThrough(target)
	}
}

func (s *activeIdentityStore) advance() error {
	return s.advanceAndSave(false)
}

func (s *activeIdentityStore) advanceAndSave(checkpoint bool) error {
	for {
		s.mu.Lock()
		at := s.now()
		if s.rolloverNeedsFlushLocked(at) {
			target := s.generation
			s.mu.Unlock()
			if err := s.flushThrough(target); err != nil {
				return err
			}
			continue
		}
		if err := s.advanceLocked(at); err != nil {
			s.mu.Unlock()
			return err
		}
		if checkpoint && s.saved == s.generation {
			if err := s.nextGenerationLocked(); err != nil {
				s.mu.Unlock()
				return err
			}
		}
		target := s.generation
		s.mu.Unlock()
		return s.flushThrough(target)
	}
}

func (s *activeIdentityStore) flush() error {
	s.mu.Lock()
	target := s.generation
	s.mu.Unlock()
	return s.flushThrough(target)
}

func (s *activeIdentityStore) finalized() ([]activeIdentityFinalized, bool) {
	s.mu.Lock()
	defer s.mu.Unlock()
	today := activitycalendar.Day(s.now())
	if !s.healthy || today < s.openDay.Day {
		return nil, false
	}
	midnight, err := activitycalendar.Parse(today)
	if err != nil {
		return nil, false
	}
	first := midnight.AddDate(0, 0, -7).Format("2006-01-02")
	values := make([]activeIdentityFinalized, 0, len(s.durableFinals))
	for _, value := range s.durableFinals {
		if value.Day >= first && value.Day < today {
			values = append(values, value)
		}
	}
	return values, true
}

func (s *activeIdentityStore) nextGenerationLocked() error {
	if s.generation == ^uint64(0) {
		s.healthy = false
		return errActiveIdentityStoreStorage
	}
	s.generation++
	return nil
}

func (s *activeIdentityStore) rolloverNeedsFlushLocked(at time.Time) bool {
	// A generation may satisfy an admission only if its contribution reached
	// durable storage before any later calendar pruning can remove it.
	return activitycalendar.Day(at) > s.openDay.Day && s.saved < s.generation
}

func (s *activeIdentityStore) advanceLocked(at time.Time) error {
	// Berlin coverage follows wall time, including clock steps and intervals
	// where the process's monotonic clock may stop during system sleep.
	at = at.Round(0)
	today := activitycalendar.Day(at)
	if at.IsZero() || today < s.openDay.Day || at.Before(s.openDay.ObservingFrom) {
		return errActiveIdentityStoreDay
	}
	gap := at.Sub(s.observedAt)
	continuous := !s.observedAt.IsZero() && gap >= 0 && gap <= activeIdentityLiveGapLimit
	if today == s.openDay.Day {
		if !continuous && s.openDay.FullDayEligible {
			if err := s.nextGenerationLocked(); err != nil {
				return err
			}
			s.openDay.FullDayEligible = false
		}
		s.observedAt = at
		return nil
	}
	midnight, err := activitycalendar.Parse(today)
	if err != nil {
		return errActiveIdentityStoreDay
	}
	previous, _ := activitycalendar.Parse(s.openDay.Day)
	continuous = continuous && previous.AddDate(0, 0, 1).Equal(midnight)
	frozen, err := s.missingFinalsLocked(midnight, continuous)
	if err != nil {
		return err
	}
	if err := s.nextGenerationLocked(); err != nil {
		return err
	}
	s.finals = append(s.finals, frozen...)
	s.startDayLocked(today, at, midnight, continuous)
	s.observedAt = at
	s.pruneLocked(midnight)
	return nil
}

func (s *activeIdentityStore) startDayLocked(today string, at, midnight time.Time, continuous bool) {
	observingFrom := at
	if continuous {
		observingFrom = midnight
	}
	s.openDay = activeIdentityOpenDay{today, observingFrom, continuous || at.Equal(midnight)}
}

func (s *activeIdentityStore) missingFinalsLocked(midnight time.Time, continuous bool) ([]activeIdentityFinalized, error) {
	epochDay := activitycalendar.Day(s.measurementStart)
	finalized := make(map[string]bool, len(s.finals))
	for _, value := range s.finals {
		finalized[value.Day] = true
	}
	pending := make([]activeIdentityFinalized, 0, 7)
	for date := midnight.AddDate(0, 0, -7); date.Before(midnight); date = date.AddDate(0, 0, 1) {
		day := date.Format("2006-01-02")
		if day < epochDay || finalized[day] {
			continue
		}
		// Compute unions before dropping the oldest raw sketch. Absent sketches
		// contribute zero observed marks to these lower-bound estimates.
		counts, err := s.sketches.estimate(day)
		if err != nil {
			return nil, errActiveIdentityStoreSnapshot
		}
		fullDay := day == s.openDay.Day && continuous && s.openDay.FullDayEligible
		pending = append(pending, activeIdentityFinalized{Day: day, Counts: counts, Partial: !fullDay})
	}
	return pending, nil
}

func (s *activeIdentityStore) pruneLocked(midnight time.Time) {
	today := midnight.Format("2006-01-02")
	firstRaw := midnight.AddDate(0, 0, -30).Format("2006-01-02")
	for day := range s.sketches.days {
		if day < firstRaw || day > today {
			delete(s.sketches.days, day)
		}
	}
	if s.sketches.days[today] == nil {
		s.sketches.days[today] = hyperloglog.NewNoSparse()
	}
	firstFinal := midnight.AddDate(0, 0, -7).Format("2006-01-02")
	kept := s.finals[:0]
	for _, value := range s.finals {
		if value.Day >= firstFinal && value.Day < today {
			kept = append(kept, value)
		}
	}
	s.finals = kept
	sort.Slice(s.finals, func(i, j int) bool { return s.finals[i].Day < s.finals[j].Day })
	s.pruneEngagementLocked(midnight)
}

func (s *activeIdentityStore) flushThrough(target uint64) error {
	s.flushMu.Lock()
	defer s.flushMu.Unlock()
	s.mu.Lock()
	if s.healthy && s.saved >= target {
		s.mu.Unlock()
		return nil
	}
	observedAt := s.observedAt
	disk := activeIdentityStoreDisk{
		Version: activeIdentityStoreVersion, Calendar: activeIdentityStoreCalendar,
		KeyID: s.keyID, Generation: s.generation, MeasurementStart: s.measurementStart,
		ObservedAt: &observedAt, OpenDay: s.openDay, Finalized: append([]activeIdentityFinalized(nil), s.finals...),
	}
	dates := make([]string, 0, len(s.sketches.days))
	for day := range s.sketches.days {
		dates = append(dates, day)
	}
	sort.Strings(dates)
	clones := make([]*hyperloglog.Sketch, len(dates))
	for i, day := range dates {
		clones[i] = s.sketches.days[day].Clone()
	}
	weeklyClones := s.cloneEngagementLocked()
	path, write := s.path, s.write
	s.mu.Unlock()

	disk.Days = make([]activeIdentityDayDisk, len(dates))
	var err error
	for i, sketch := range clones {
		disk.Days[i].Day = dates[i]
		disk.Days[i].Sketch, err = sketch.MarshalBinary()
		if err != nil {
			break
		}
	}
	var weeklyValues []activeEngagementWeek
	if err == nil {
		disk.Engagement, weeklyValues, err = activeEngagementSnapshot(weeklyClones)
	}
	var raw []byte
	if err == nil {
		raw, err = json.Marshal(disk)
	}
	if err == nil && len(raw) > activeIdentityStoreSnapshotLimit {
		err = errActiveIdentityStoreSnapshot
	}
	if err == nil {
		err = write(path, raw)
	}
	s.mu.Lock()
	defer s.mu.Unlock()
	if err != nil {
		s.healthy = false
		return errActiveIdentityStoreStorage
	}
	s.saved = disk.Generation
	s.durableFinals = append([]activeIdentityFinalized(nil), disk.Finalized...)
	s.durableEngagement = weeklyValues
	s.healthy = true
	return nil
}

func activeIdentityPrepareSnapshotDirectory(path string) error {
	directory := filepath.Dir(path)
	info, err := os.Lstat(directory)
	if errors.Is(err, os.ErrNotExist) {
		if os.MkdirAll(directory, 0700) != nil {
			return errActiveIdentityStoreStorage
		}
		info, err = os.Lstat(directory)
	}
	// Lstat deliberately refuses a final symlink, including one to a directory.
	if err != nil || !info.IsDir() {
		return errActiveIdentityStoreStorage
	}
	dir, err := os.Open(directory)
	if err != nil {
		return errActiveIdentityStoreStorage
	}
	defer dir.Close()
	opened, err := dir.Stat()
	if err != nil || !opened.IsDir() || !os.SameFile(info, opened) {
		return errActiveIdentityStoreStorage
	}
	// Use the verified descriptor so a path replacement cannot redirect chmod.
	if dir.Chmod(0700) != nil {
		return errActiveIdentityStoreStorage
	}
	private, err := dir.Stat()
	if err != nil || private.Mode().Perm() != 0700 {
		return errActiveIdentityStoreStorage
	}
	current, err := os.Lstat(directory)
	if err != nil || !current.IsDir() || !os.SameFile(private, current) || current.Mode().Perm() != 0700 {
		return errActiveIdentityStoreStorage
	}
	return nil
}

func activeIdentityReadSnapshot(path string) ([]byte, bool, error) {
	info, err := os.Lstat(path)
	if errors.Is(err, os.ErrNotExist) {
		return nil, false, nil
	}
	if err != nil {
		return nil, false, errActiveIdentityStoreStorage
	}
	if !info.Mode().IsRegular() || info.Size() > activeIdentityStoreSnapshotLimit {
		return nil, false, errActiveIdentityStoreSnapshot
	}
	file, err := os.Open(path)
	if err != nil {
		return nil, false, errActiveIdentityStoreStorage
	}
	defer file.Close()
	raw, err := io.ReadAll(io.LimitReader(file, activeIdentityStoreSnapshotLimit+1))
	if err != nil {
		return nil, false, errActiveIdentityStoreStorage
	}
	if len(raw) > activeIdentityStoreSnapshotLimit {
		return nil, false, errActiveIdentityStoreSnapshot
	}
	return raw, true, nil
}

// Pointer fields distinguish a required numeric zero/false from missing or null.
// Keep this projection local: the shared estimate type has no store codec policy.
func activeIdentityDecodeSnapshot(raw []byte) (activeIdentityStoreDisk, error) {
	var required struct {
		Version          *int            `json:"version"`
		Calendar         *string         `json:"calendar"`
		KeyID            *string         `json:"key_id"`
		Generation       *uint64         `json:"generation"`
		MeasurementStart *time.Time      `json:"measurement_start"`
		ObservedAt       json.RawMessage `json:"observed_at"`
		OpenDay          *struct {
			Day             *string    `json:"day"`
			ObservingFrom   *time.Time `json:"observing_from"`
			FullDayEligible *bool      `json:"full_day_eligible"`
		} `json:"open_day"`
		Days       json.RawMessage `json:"days"`
		Finalized  json.RawMessage `json:"finalized"`
		Engagement json.RawMessage `json:"engagement"`
	}
	var disk activeIdentityStoreDisk
	if appDiagnosticDecode(raw, &required) != nil || required.Version == nil ||
		required.Calendar == nil || required.KeyID == nil || required.Generation == nil ||
		required.MeasurementStart == nil || required.OpenDay == nil ||
		required.OpenDay.Day == nil || required.OpenDay.ObservingFrom == nil ||
		required.OpenDay.FullDayEligible == nil || len(required.Days) == 0 || len(required.Finalized) == 0 {
		return disk, errActiveIdentityStoreSnapshot
	}
	disk.Version, disk.Calendar, disk.KeyID = *required.Version, *required.Calendar, *required.KeyID
	disk.Generation, disk.MeasurementStart = *required.Generation, *required.MeasurementStart
	if len(required.ObservedAt) != 0 {
		if json.Unmarshal(required.ObservedAt, &disk.ObservedAt) != nil || disk.ObservedAt == nil {
			return disk, errActiveIdentityStoreSnapshot
		}
	}
	disk.OpenDay = activeIdentityOpenDay{*required.OpenDay.Day, *required.OpenDay.ObservingFrom, *required.OpenDay.FullDayEligible}
	var days []struct {
		Day    *string `json:"day"`
		Sketch *[]byte `json:"sketch"`
	}
	var finals []struct {
		Day     *string                             `json:"day"`
		Counts  *struct{ Day, Week, Month *uint64 } `json:"counts"`
		Partial json.RawMessage                     `json:"partial"`
	}
	if appDiagnosticDecode(required.Days, &days) != nil || appDiagnosticDecode(required.Finalized, &finals) != nil ||
		len(days) > 31 || len(finals) > 7 {
		return disk, errActiveIdentityStoreSnapshot
	}
	for _, day := range days {
		if day.Day == nil || day.Sketch == nil {
			return disk, errActiveIdentityStoreSnapshot
		}
		disk.Days = append(disk.Days, activeIdentityDayDisk{*day.Day, *day.Sketch})
	}
	for _, value := range finals {
		if value.Day == nil || value.Counts == nil || value.Counts.Day == nil || value.Counts.Week == nil || value.Counts.Month == nil {
			return disk, errActiveIdentityStoreSnapshot
		}
		final := activeIdentityFinalized{
			Day: *value.Day, Counts: activeIdentityEstimate{*value.Counts.Day, *value.Counts.Week, *value.Counts.Month},
		}
		if len(value.Partial) != 0 {
			var partial *bool
			if json.Unmarshal(value.Partial, &partial) != nil || partial == nil {
				return disk, errActiveIdentityStoreSnapshot
			}
			final.Partial = *partial
		}
		disk.Finalized = append(disk.Finalized, final)
	}
	var err error
	disk.Engagement, err = activeEngagementDecode(required.Engagement)
	if err != nil {
		return disk, err
	}
	return disk, nil
}

func (s *activeIdentityStore) restoreLocked(disk activeIdentityStoreDisk, at time.Time) error {
	keyID, err := hex.DecodeString(disk.KeyID)
	if disk.Version != activeIdentityStoreVersion || disk.Calendar != activeIdentityStoreCalendar ||
		err != nil || len(keyID) != sha256.Size || disk.Generation == ^uint64(0) {
		return errActiveIdentityStoreSnapshot
	}
	if disk.KeyID != s.keyID {
		return errActiveIdentityStoreKeyEpoch
	}
	open, err := activitycalendar.Parse(disk.OpenDay.Day)
	if err != nil || disk.MeasurementStart.IsZero() || disk.OpenDay.ObservingFrom.IsZero() ||
		disk.MeasurementStart.After(disk.OpenDay.ObservingFrom) || disk.OpenDay.ObservingFrom.After(at) ||
		activitycalendar.Day(disk.OpenDay.ObservingFrom) != disk.OpenDay.Day ||
		(disk.OpenDay.FullDayEligible && !disk.OpenDay.ObservingFrom.Equal(open)) {
		return errActiveIdentityStoreSnapshot
	}
	if disk.ObservedAt != nil {
		observedAt := *disk.ObservedAt
		if observedAt.IsZero() || observedAt.Before(disk.OpenDay.ObservingFrom) ||
			activitycalendar.Day(observedAt) != disk.OpenDay.Day {
			return errActiveIdentityStoreSnapshot
		}
		s.observedAt = observedAt
	}
	// Validate bounds relative to the SAVED calendar first. A valid old snapshot
	// remains valid after long downtime; current-date pruning happens afterward.
	firstRaw := open.AddDate(0, 0, -30).Format("2006-01-02")
	epochDay := activitycalendar.Day(disk.MeasurementStart)
	prototype, err := hyperloglog.NewNoSparse().MarshalBinary()
	if err != nil {
		return errActiveIdentityStoreSnapshot
	}
	for _, day := range disk.Days {
		if _, err := activitycalendar.Parse(day.Day); err != nil || day.Day < firstRaw || day.Day > disk.OpenDay.Day ||
			day.Day < epochDay || s.sketches.days[day.Day] != nil || len(day.Sketch) != len(prototype) ||
			!bytes.Equal(day.Sketch[:8], prototype[:8]) {
			return errActiveIdentityStoreSnapshot
		}
		for _, rank := range day.Sketch[8:] {
			if rank > 51 {
				return errActiveIdentityStoreSnapshot
			}
		}
		sketch := hyperloglog.NewNoSparse()
		if sketch.UnmarshalBinary(day.Sketch) != nil {
			return errActiveIdentityStoreSnapshot
		}
		s.sketches.days[day.Day] = sketch
	}
	firstFinal := open.AddDate(0, 0, -7).Format("2006-01-02")
	firstObserved, err := activitycalendar.Parse(epochDay)
	if err != nil {
		return errActiveIdentityStoreSnapshot
	}
	if !disk.MeasurementStart.Equal(firstObserved) {
		firstObserved = firstObserved.AddDate(0, 0, 1)
	}
	seen := make(map[string]bool, len(disk.Finalized))
	for _, value := range disk.Finalized {
		date, err := activitycalendar.Parse(value.Day)
		if err != nil || value.Day < firstFinal || value.Day < epochDay || value.Day >= disk.OpenDay.Day ||
			(!value.Partial && date.Before(firstObserved)) || seen[value.Day] {
			return errActiveIdentityStoreSnapshot
		}
		seen[value.Day] = true
	}
	if err := s.restoreEngagementLocked(disk.Engagement, open, disk.MeasurementStart); err != nil {
		return err
	}
	s.measurementStart, s.openDay = disk.MeasurementStart, disk.OpenDay
	s.finals = append([]activeIdentityFinalized(nil), disk.Finalized...)
	s.generation, s.saved = disk.Generation, disk.Generation
	return nil
}
