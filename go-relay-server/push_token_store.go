package main

import (
	"crypto/rand"
	"encoding/base64"
	"errors"
	"io"
	"slices"
	"sync"
	"time"
)

// --- In-memory PushTokenBackend ---

// memoryPushTokenStore is the default in-memory push token backend.
type memoryPushTokenStore struct {
	mu       sync.RWMutex
	tokens   map[string]memoryPushTokenRecord // peerId -> private provider record
	entropy  io.Reader
	absences map[string]memoryPushRouteAbsence
	// Test-only marker clock; token UpdatedAt retains its existing clock.
	absenceNow func() time.Time
}

type memoryPushTokenRecord struct {
	entry      tokenEntry
	handle     string
	generation uint64
}

type memoryPushRouteAbsence struct {
	observation missingPushRouteObservation
	expiresAt   time.Time
}

func newMemoryPushTokenStore() *memoryPushTokenStore {
	return &memoryPushTokenStore{
		tokens:   make(map[string]memoryPushTokenRecord),
		entropy:  rand.Reader,
		absences: make(map[string]memoryPushRouteAbsence),
	}
}

func newOpaquePushHandle(entropy io.Reader) (string, error) {
	if entropy == nil {
		entropy = rand.Reader
	}
	raw := make([]byte, 32)
	if _, err := io.ReadFull(entropy, raw); err != nil {
		return "", err
	}
	return base64.RawURLEncoding.EncodeToString(raw), nil
}

func copyPushRouteLease(route pushRouteLease) pushRouteLease {
	route.Capabilities = append([]string(nil), route.Capabilities...)
	return route
}

func (s *memoryPushTokenStore) RegisterToken(
	peerId string,
	token string,
	platform string,
	capabilities ...string,
) error {
	return s.registerToken(peerId, token, platform, nil, capabilities...)
}

func (s *memoryPushTokenStore) RegisterTokenWithThoughtNotifications(
	peerId, token, platform string,
	enabled bool,
	capabilities ...string,
) error {
	return s.registerToken(peerId, token, platform, &enabled, capabilities...)
}

func (s *memoryPushTokenStore) registerToken(
	peerId, token, platform string,
	thoughtNotificationsEnabled *bool,
	capabilities ...string,
) error {
	s.mu.Lock()
	defer s.mu.Unlock()

	capabilities = canonicalPushCapabilities(capabilities)
	current, exists := s.tokens[peerId]
	handle := current.handle
	generation := current.generation
	if !exists || current.entry.Token != token || current.entry.Platform != platform {
		var err error
		handle, err = newOpaquePushHandle(s.entropy)
		if err != nil {
			return err
		}
		generation++
		if generation == 0 {
			return errors.New("push route generation overflow")
		}
	}
	s.tokens[peerId] = memoryPushTokenRecord{
		entry: tokenEntry{
			Token:                       token,
			Platform:                    platform,
			Capabilities:                capabilities,
			UpdatedAt:                   time.Now(),
			ThoughtNotificationsEnabled: thoughtNotificationsEnabled,
		},
		handle:     handle,
		generation: generation,
	}
	s.pruneAbsencesLocked()
	delete(s.absences, peerId)
	return nil
}

func (s *memoryPushTokenStore) UnregisterToken(peerId string) error {
	s.mu.Lock()
	defer s.mu.Unlock()
	if record, exists := s.tokens[peerId]; exists {
		s.recordAbsenceLocked(peerId, pushMissingRouteUnregistered, record.entry.Platform)
	} else {
		s.pruneAbsencesLocked()
	}
	delete(s.tokens, peerId)
	return nil
}

func (s *memoryPushTokenStore) LookupRoute(peerId string) (*pushRouteLease, error) {
	s.mu.RLock()
	defer s.mu.RUnlock()
	record, ok := s.tokens[peerId]
	if !ok {
		return nil, nil
	}
	return &pushRouteLease{
		Handle:                       record.handle,
		Generation:                   record.generation,
		Capabilities:                 append([]string(nil), record.entry.Capabilities...),
		thoughtNotificationsDisabled: thoughtNotificationsDisabled(record.entry.ThoughtNotificationsEnabled),
		lookupKey:                    peerId,
	}, nil
}

func (s *memoryPushTokenStore) ResolveRoute(route pushRouteLease) (*resolvedPushTarget, error) {
	s.mu.RLock()
	defer s.mu.RUnlock()
	record, ok := s.tokens[route.lookupKey]
	if !ok || route.Handle == "" || route.Generation == 0 ||
		record.handle != route.Handle || record.generation != route.Generation ||
		thoughtNotificationsDisabled(record.entry.ThoughtNotificationsEnabled) != route.thoughtNotificationsDisabled ||
		!slices.Equal(record.entry.Capabilities, route.Capabilities) {
		return nil, ErrPushRouteStale
	}
	return &resolvedPushTarget{
		Route:    copyPushRouteLease(route),
		Token:    record.entry.Token,
		Platform: record.entry.Platform,
	}, nil
}

func (s *memoryPushTokenStore) RevokeIfCurrent(route pushRouteLease) (bool, error) {
	s.mu.Lock()
	defer s.mu.Unlock()
	record, ok := s.tokens[route.lookupKey]
	if !ok || route.Handle == "" || route.Generation == 0 ||
		record.handle != route.Handle || record.generation != route.Generation ||
		thoughtNotificationsDisabled(record.entry.ThoughtNotificationsEnabled) != route.thoughtNotificationsDisabled ||
		!slices.Equal(record.entry.Capabilities, route.Capabilities) {
		return false, nil
	}
	delete(s.tokens, route.lookupKey)
	s.recordAbsenceLocked(route.lookupKey, pushMissingRouteRevoked, record.entry.Platform)
	return true, nil
}

func (s *memoryPushTokenStore) absenceTime() time.Time {
	if s.absenceNow != nil {
		return s.absenceNow()
	}
	return time.Now()
}

func (s *memoryPushTokenStore) pruneAbsencesLocked() {
	now := s.absenceTime()
	for peerID, marker := range s.absences {
		if !now.Before(marker.expiresAt) {
			delete(s.absences, peerID)
		}
	}
}

func (s *memoryPushTokenStore) recordAbsenceLocked(peerID string, reason pushMissingRouteReason, platform string) {
	s.pruneAbsencesLocked()
	if s.absences == nil {
		s.absences = make(map[string]memoryPushRouteAbsence)
	}
	s.absences[peerID] = memoryPushRouteAbsence{
		observation: (missingPushRouteObservation{reason: reason, platform: platform}).normalized(),
		expiresAt:   s.absenceTime().Add(pushRouteAbsenceTTL),
	}
}

func (s *memoryPushTokenStore) ObserveMissingRoute(peerID string) missingPushRouteObservation {
	s.mu.Lock()
	defer s.mu.Unlock()
	s.pruneAbsencesLocked()
	if _, exists := s.tokens[peerID]; exists {
		return missingPushRouteObservation{}.normalized()
	}
	return s.absences[peerID].observation.normalized()
}

func (s *memoryPushTokenStore) TokenCount() int {
	s.mu.RLock()
	defer s.mu.RUnlock()
	return len(s.tokens)
}

func (s *memoryPushTokenStore) PlatformCounts() map[string]int {
	s.mu.RLock()
	defer s.mu.RUnlock()
	counts := make(map[string]int)
	for _, record := range s.tokens {
		counts[record.entry.Platform]++
	}
	return counts
}

// --- Shared in-memory PushTokenBackend (for simulating shared state in tests) ---

// sharedPushTokenStore wraps a memoryPushTokenStore pointer so multiple
// PushService instances share the same token map.
type sharedPushTokenStore = memoryPushTokenStore
