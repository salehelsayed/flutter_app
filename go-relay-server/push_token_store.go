package main

import (
	"sync"
	"time"
)

// --- In-memory PushTokenBackend ---

// memoryPushTokenStore is the default in-memory push token backend.
type memoryPushTokenStore struct {
	mu     sync.RWMutex
	tokens map[string]tokenEntry // peerId -> tokenEntry
}

func newMemoryPushTokenStore() *memoryPushTokenStore {
	return &memoryPushTokenStore{
		tokens: make(map[string]tokenEntry),
	}
}

func (s *memoryPushTokenStore) RegisterToken(peerId string, token string, platform string) {
	s.mu.Lock()
	defer s.mu.Unlock()
	s.tokens[peerId] = tokenEntry{
		Token:     token,
		Platform:  platform,
		UpdatedAt: time.Now(),
	}
}

func (s *memoryPushTokenStore) UnregisterToken(peerId string) {
	s.mu.Lock()
	defer s.mu.Unlock()
	delete(s.tokens, peerId)
}

func (s *memoryPushTokenStore) LookupToken(peerId string) *tokenEntry {
	s.mu.RLock()
	defer s.mu.RUnlock()
	entry, ok := s.tokens[peerId]
	if !ok {
		return nil
	}
	return &entry
}

func (s *memoryPushTokenStore) TokenCount() int {
	s.mu.RLock()
	defer s.mu.RUnlock()
	return len(s.tokens)
}

// --- Shared in-memory PushTokenBackend (for simulating shared state in tests) ---

// sharedPushTokenStore wraps a memoryPushTokenStore pointer so multiple
// PushService instances share the same token map.
type sharedPushTokenStore = memoryPushTokenStore
