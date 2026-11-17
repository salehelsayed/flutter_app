package main

import (
	"bytes"
	"crypto/hmac"
	"crypto/sha256"
	"errors"

	"github.com/axiomhq/hyperloglog"
	"github.com/mknoon/go-mknoon/activitycalendar"
)

var (
	errActiveIdentityKey     = errors.New("active identity key must be 32 bytes")
	errActiveIdentityAccount = errors.New("active identity account is empty")
)

type activeIdentityEstimate struct {
	Day, Week, Month uint64
}

// Admission, synchronization and durability belong to the subsequent store unit.
type activeDailySketches struct {
	key  []byte
	days map[string]*hyperloglog.Sketch
}

func newActiveDailySketches(key []byte) (*activeDailySketches, error) {
	if len(key) != 32 {
		return nil, errActiveIdentityKey
	}
	return &activeDailySketches{
		key:  bytes.Clone(key),
		days: make(map[string]*hyperloglog.Sketch),
	}, nil
}

func activeIdentityDigest(key []byte, account string) []byte {
	mac := hmac.New(sha256.New, key)
	_, _ = mac.Write([]byte("mknoon/active-identities/v1/account\x00"))
	_, _ = mac.Write([]byte(account))
	return mac.Sum(nil)
}

func (s *activeDailySketches) insert(day, account string) error {
	if _, err := activitycalendar.Parse(day); err != nil {
		return err
	}
	if account == "" {
		return errActiveIdentityAccount
	}
	sketch := s.days[day]
	if sketch == nil {
		sketch = hyperloglog.NewNoSparse()
		s.days[day] = sketch
	}
	sketch.Insert(activeIdentityDigest(s.key, account))
	return nil
}

func (s *activeDailySketches) estimate(day string) (activeIdentityEstimate, error) {
	days, err := activitycalendar.WindowEnding(day, 30)
	if err != nil {
		return activeIdentityEstimate{}, err
	}
	daily := hyperloglog.NewNoSparse()
	weekly := hyperloglog.NewNoSparse()
	monthly := hyperloglog.NewNoSparse()
	for i, date := range days {
		sketch := s.days[date]
		if sketch == nil {
			continue
		}
		if err := monthly.Merge(sketch); err != nil {
			return activeIdentityEstimate{}, err
		}
		if i >= len(days)-7 {
			if err := weekly.Merge(sketch); err != nil {
				return activeIdentityEstimate{}, err
			}
		}
		if date == day {
			if err := daily.Merge(sketch); err != nil {
				return activeIdentityEstimate{}, err
			}
		}
	}
	return activeIdentityEstimate{Day: daily.Estimate(), Week: weekly.Estimate(), Month: monthly.Estimate()}, nil
}
