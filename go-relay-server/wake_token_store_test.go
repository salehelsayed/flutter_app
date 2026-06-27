package main

import (
	"sync"
	"testing"
)

// FDC-09 §12 — the in-memory wake-token store: fail-open until a recipient
// registers a set, then member-only authorization, with an empty registration
// clearing back to fail-open.
func TestWakeTokenStore_FailOpenUntilRegisteredThenMemberOnly(t *testing.T) {
	s := newMemoryWakeTokenStore()

	// No set registered -> fail OPEN (any/absent token authorized; existing push).
	if !s.IsAuthorized("peer-a", "") || !s.IsAuthorized("peer-a", "whatever") {
		t.Fatal("an unregistered recipient must fail open (existing push preserved)")
	}
	if s.HasRegisteredSet("peer-a") {
		t.Fatal("no set should be registered yet")
	}

	// Register a set -> ONLY member tokens authorized; absent/non-member blocked.
	s.RegisterWakeTokens("peer-a", []string{"tok-1", "tok-2", ""})
	if !s.HasRegisteredSet("peer-a") {
		t.Fatal("a set should now be registered")
	}
	if !s.IsAuthorized("peer-a", "tok-1") || !s.IsAuthorized("peer-a", "tok-2") {
		t.Fatal("member tokens must be authorized")
	}
	if s.IsAuthorized("peer-a", "tok-WRONG") || s.IsAuthorized("peer-a", "") {
		t.Fatal("a non-member / absent token must be blocked once a set exists")
	}

	// A DIFFERENT recipient with no set still fails open (per-recipient isolation).
	if !s.IsAuthorized("peer-b", "anything") {
		t.Fatal("a different unregistered recipient must still fail open")
	}

	// An empty registration clears the set -> fail open again.
	s.RegisterWakeTokens("peer-a", nil)
	if s.HasRegisteredSet("peer-a") || !s.IsAuthorized("peer-a", "anything") {
		t.Fatal("an empty registration must clear back to fail-open")
	}

	// ClearWakeTokens also clears.
	s.RegisterWakeTokens("peer-a", []string{"tok-3"})
	s.ClearWakeTokens("peer-a")
	if s.HasRegisteredSet("peer-a") {
		t.Fatal("ClearWakeTokens must drop the set")
	}
}

// Concurrency: register/authorize/clear race must be -race clean.
func TestWakeTokenStore_RaceClean(t *testing.T) {
	s := newMemoryWakeTokenStore()
	var wg sync.WaitGroup
	for i := 0; i < 16; i++ {
		wg.Add(3)
		go func() {
			defer wg.Done()
			for j := 0; j < 200; j++ {
				s.RegisterWakeTokens("peer", []string{"tok-1", "tok-2"})
			}
		}()
		go func() {
			defer wg.Done()
			for j := 0; j < 200; j++ {
				_ = s.IsAuthorized("peer", "tok-1")
				_ = s.HasRegisteredSet("peer")
			}
		}()
		go func() {
			defer wg.Done()
			for j := 0; j < 200; j++ {
				s.ClearWakeTokens("peer")
			}
		}()
	}
	wg.Wait()
}
