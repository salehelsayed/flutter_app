package main

import "sync"

// --- In-memory wake-token store (FDC-09 §12 access-token anti-spam gate) ---
//
// Holds, per recipient, the SET of opaque wake-tokens that recipient has
// authorized to wake it ("only contacts can wake you"). The recipient mints one
// opaque token per contact and registers the whole set; a sender presents ITS
// token when storing a user-visible message, and the relay checks membership.
// The relay never learns the contact graph (opaque tokens, not peer IDs —
// unlinkable).
//
// FAIL-OPEN: a recipient that has registered NO set is un-gated, so existing
// push delivery keeps working for already-paired contacts (NET-REL-07) and the
// gate only ENGAGES once a recipient opts in by registering a set. This makes
// the rollout safe: until both halves are live (recipients register sets AND
// senders present tokens), no recipient has a set and every wake fails open.
//
// In-memory like memoryPushTokenStore; durability (survive a relay bounce) is
// FDC-10's gap. A lost set fails OPEN (back to existing push), so a bounce never
// silences contacts.
// wakeTokenGateEnforced controls whether the §12 access-token wake gate actually
// SUPPRESSES unauthorized wakes (vs. recording sets but always pushing). It is
// OFF BY DEFAULT and MUST stay off until the SEND-SIDE token presentation ships —
// i.e. until the go-mknoon store path (InboxStoreDetailed) attaches the
// recipient-issued token to its `store` request. Until then EVERY real sender
// presents an empty token, so enforcing the gate the instant a recipient
// registers a set would hard-silence ALL of that recipient's 1:1 pushes (the
// message is still stored — delivery preserved — but no wake fires). With the
// gate un-enforced, a registered set is RECORDED but never suppresses, so
// recipients can pre-provision tokens safely. Flip on (deploy-time, e.g. wired to
// an env flag) ONLY once BOTH halves are live. STRICT SHIP-ORDER — see FDC-09 H1.
var wakeTokenGateEnforced = false

type memoryWakeTokenStore struct {
	mu     sync.RWMutex
	tokens map[string]map[string]struct{} // recipientPeerId -> set of authorized wake-tokens
}

func newMemoryWakeTokenStore() *memoryWakeTokenStore {
	return &memoryWakeTokenStore{tokens: make(map[string]map[string]struct{})}
}

// RegisterWakeTokens REPLACES the recipient's authorized wake-token set. An empty
// list clears the set (back to fail-open). Empty token strings are ignored.
func (s *memoryWakeTokenStore) RegisterWakeTokens(peerId string, tokens []string) {
	s.mu.Lock()
	defer s.mu.Unlock()
	if len(tokens) == 0 {
		delete(s.tokens, peerId)
		return
	}
	set := make(map[string]struct{}, len(tokens))
	for _, t := range tokens {
		if t != "" {
			set[t] = struct{}{}
		}
	}
	if len(set) == 0 {
		delete(s.tokens, peerId)
		return
	}
	s.tokens[peerId] = set
}

// HasRegisteredSet reports whether the recipient has opted in to the wake gate.
func (s *memoryWakeTokenStore) HasRegisteredSet(peerId string) bool {
	s.mu.RLock()
	defer s.mu.RUnlock()
	set, ok := s.tokens[peerId]
	return ok && len(set) > 0
}

// IsAuthorized reports whether `token` may wake `peerId`. FAIL-OPEN when the
// recipient has registered no set (legacy / un-opted-in). When a set exists,
// ONLY a member token authorizes the wake — an absent or non-member token is
// blocked (the §12 anti-spam enforcement).
func (s *memoryWakeTokenStore) IsAuthorized(peerId, token string) bool {
	s.mu.RLock()
	defer s.mu.RUnlock()
	set, ok := s.tokens[peerId]
	if !ok || len(set) == 0 {
		return true // fail-open: recipient has not opted in to the wake gate
	}
	_, authorized := set[token]
	return authorized
}

// ClearWakeTokens removes a recipient's authorized set (e.g. on unregister_token)
// so no orphaned wake authorization survives a deregistration.
func (s *memoryWakeTokenStore) ClearWakeTokens(peerId string) {
	s.mu.Lock()
	defer s.mu.Unlock()
	delete(s.tokens, peerId)
}
