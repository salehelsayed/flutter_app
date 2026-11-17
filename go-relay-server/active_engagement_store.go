package main

import (
	"bytes"
	"encoding/json"
	"sort"
	"time"

	"github.com/axiomhq/hyperloglog"
	"github.com/mknoon/go-mknoon/activitycalendar"
)

type activeEngagementWeek struct {
	Week   string
	Counts activeEngagementEstimate
}

type activeEngagementWeekDisk struct {
	Week   string `json:"week"`
	Active []byte `json:"active"`
	Chat   []byte `json:"chat"`
	Call   []byte `json:"call"`
	Group  []byte `json:"group"`
}

type activeEngagementDisk struct {
	Weeks []activeEngagementWeekDisk `json:"weeks"`
}

func newActiveIdentityStore(path string, key []byte, now func() time.Time) (*activeIdentityStore, error) {
	return newActiveIdentityStoreWithEngagement(path, key, now, false)
}

func (s *activeIdentityStore) admitEngagement(week, account string, kinds activeEngagementKinds) error {
	if _, err := activitycalendar.ParseWeek(week); err != nil {
		return err
	}
	const allowed = activeEngagementActive | activeEngagementChat | activeEngagementCall | activeEngagementGroup
	if kinds == 0 || kinds&^allowed != 0 {
		return errActiveEngagementKinds
	}
	if account == "" {
		return errActiveIdentityAccount
	}
	for {
		s.mu.Lock()
		at := s.now()
		if !s.engagementEnabled || week != activitycalendar.Week(at) {
			s.mu.Unlock()
			return errActiveIdentityStoreInput
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
		// A same-week retry may describe yesterday. Never add daily membership.
		if err := s.weeks[week].insert(account, kinds); err != nil {
			s.mu.Unlock()
			return err
		}
		target := s.generation
		s.mu.Unlock()
		return s.flushThrough(target)
	}
}

func (s *activeIdentityStore) engagement() ([]activeEngagementWeek, bool) {
	s.mu.Lock()
	defer s.mu.Unlock()
	at := s.now()
	if !s.engagementEnabled || !s.healthy || at.IsZero() ||
		activitycalendar.Day(at) < s.openDay.Day || at.Before(s.openDay.ObservingFrom) {
		return nil, false
	}
	week := activitycalendar.Week(at)
	window, err := activitycalendar.WeekWindowEnding(week, 8)
	if err != nil {
		return nil, false
	}
	values := make([]activeEngagementWeek, 0, len(s.durableEngagement))
	for _, value := range s.durableEngagement {
		if value.Week >= window[0] && value.Week <= week {
			values = append(values, value)
		}
	}
	return values, true
}

func (s *activeIdentityStore) pruneEngagementLocked(at time.Time) {
	week := activitycalendar.Week(at)
	monday, _ := activitycalendar.ParseWeek(week)
	first := activitycalendar.Week(monday.AddDate(0, 0, -7*7))
	for savedWeek := range s.weeks {
		if savedWeek < first || savedWeek > week {
			delete(s.weeks, savedWeek)
		}
	}
	if s.engagementEnabled {
		if s.weeks == nil {
			s.weeks = make(map[string]*activeEngagementSketches)
		}
		if s.weeks[week] == nil {
			// The enclosing daily store has already validated and copied this key.
			s.weeks[week], _ = newActiveEngagementSketches(s.sketches.key)
		}
	}
}

func (s *activeIdentityStore) cloneEngagementLocked() map[string]*activeEngagementSketches {
	if s.weeks == nil {
		return nil
	}
	clones := make(map[string]*activeEngagementSketches, len(s.weeks))
	for week, sets := range s.weeks {
		clone := &activeEngagementSketches{}
		for i, sketch := range sets.sketches {
			clone.sketches[i] = sketch.Clone()
		}
		clones[week] = clone
	}
	return clones
}

// Encode and estimate the same captured generation, outside the store mutex.
func activeEngagementSnapshot(clones map[string]*activeEngagementSketches) (*activeEngagementDisk, []activeEngagementWeek, error) {
	if clones == nil {
		return nil, nil, nil
	}
	weeks := make([]string, 0, len(clones))
	for week := range clones {
		weeks = append(weeks, week)
	}
	sort.Strings(weeks)
	disk := &activeEngagementDisk{Weeks: make([]activeEngagementWeekDisk, 0, len(weeks))}
	values := make([]activeEngagementWeek, 0, len(weeks))
	for _, week := range weeks {
		sets := clones[week]
		row := activeEngagementWeekDisk{Week: week}
		for i, target := range []*[]byte{&row.Active, &row.Chat, &row.Call, &row.Group} {
			data, err := sets.sketches[i].MarshalBinary()
			if err != nil {
				return nil, nil, err
			}
			*target = data
		}
		counts, err := sets.estimate()
		if err != nil {
			return nil, nil, err
		}
		disk.Weeks = append(disk.Weeks, row)
		values = append(values, activeEngagementWeek{Week: week, Counts: counts})
	}
	return disk, values, nil
}

func activeEngagementDecode(raw json.RawMessage) (*activeEngagementDisk, error) {
	if len(raw) == 0 {
		return nil, nil
	}
	var required struct {
		Weeks *[]struct {
			Week   *string `json:"week"`
			Active *[]byte `json:"active"`
			Chat   *[]byte `json:"chat"`
			Call   *[]byte `json:"call"`
			Group  *[]byte `json:"group"`
		} `json:"weeks"`
	}
	if appDiagnosticDecode(raw, &required) != nil || required.Weeks == nil || len(*required.Weeks) > 8 {
		return nil, errActiveIdentityStoreSnapshot
	}
	disk := &activeEngagementDisk{Weeks: make([]activeEngagementWeekDisk, 0, len(*required.Weeks))}
	for _, row := range *required.Weeks {
		if row.Week == nil || row.Active == nil || row.Chat == nil || row.Call == nil || row.Group == nil {
			return nil, errActiveIdentityStoreSnapshot
		}
		disk.Weeks = append(disk.Weeks, activeEngagementWeekDisk{*row.Week, *row.Active, *row.Chat, *row.Call, *row.Group})
	}
	return disk, nil
}

func (s *activeIdentityStore) restoreEngagementLocked(disk *activeEngagementDisk, savedDay, measurementStart time.Time) error {
	if disk == nil {
		return nil
	}
	last := activitycalendar.Week(savedDay)
	window, err := activitycalendar.WeekWindowEnding(last, 8)
	if err != nil || len(disk.Weeks) > 8 {
		return errActiveIdentityStoreSnapshot
	}
	firstObserved := activitycalendar.Week(measurementStart)
	prototype, err := hyperloglog.NewNoSparse().MarshalBinary()
	if err != nil {
		return errActiveIdentityStoreSnapshot
	}
	s.weeks = make(map[string]*activeEngagementSketches, len(disk.Weeks))
	for _, row := range disk.Weeks {
		if _, err := activitycalendar.ParseWeek(row.Week); err != nil || row.Week < window[0] ||
			row.Week > last || row.Week < firstObserved || s.weeks[row.Week] != nil {
			return errActiveIdentityStoreSnapshot
		}
		sets, _ := newActiveEngagementSketches(s.sketches.key)
		for i, data := range [][]byte{row.Active, row.Chat, row.Call, row.Group} {
			if len(data) != len(prototype) || !bytes.Equal(data[:8], prototype[:8]) {
				return errActiveIdentityStoreSnapshot
			}
			for register, rank := range data[8:] {
				if rank > 51 || (i > 0 && rank > row.Active[register+8]) {
					return errActiveIdentityStoreSnapshot
				}
			}
			if sets.sketches[i].UnmarshalBinary(data) != nil {
				return errActiveIdentityStoreSnapshot
			}
		}
		s.weeks[row.Week] = sets
	}
	return nil
}
