package main

import (
	"crypto/hmac"
	"crypto/sha256"
	"log"
	"os"
	"path/filepath"
	"strings"
	"time"

	"github.com/mknoon/go-mknoon/activitycalendar"
)

const activeDevicesEnabledEnv = "MKNOON_RELAY_ACTIVE_DEVICES_ENABLED"

type activeDeviceStore struct {
	*activeIdentityStore
	requests int
	stopped  bool
}

func initActiveDevicesFromEnvironment() *activeDeviceStore {
	enabled := strings.ToLower(strings.TrimSpace(os.Getenv(activeDevicesEnabledEnv)))
	if enabled == "" || enabled == "false" {
		return nil
	}
	path := os.Getenv("MKNOON_RELAY_ACTIVE_IDENTITIES_SNAPSHOT_PATH")
	if enabled != "true" || !filepath.IsAbs(path) || strings.HasSuffix(path, string(os.PathSeparator)) || filepath.Base(path) == "." {
		log.Print("[ACTIVE_DEVICES] Counter unavailable")
		return nil
	}
	s, err := newActiveDeviceStore(filepath.Clean(path)+".active-devices", []byte(os.Getenv("MKNOON_RELAY_ACTIVE_IDENTITIES_KEY")), time.Now)
	if err != nil {
		log.Print("[ACTIVE_DEVICES] Counter unavailable")
		return nil
	}
	return s
}

func newActiveDeviceStore(path string, key []byte, now func() time.Time) (*activeDeviceStore, error) {
	if len(key) != 32 {
		return nil, errActiveIdentityKey
	}
	mac := hmac.New(sha256.New, key)
	_, _ = mac.Write([]byte("mknoon/relay/active-devices/v1\x00"))
	store, err := newActiveWindowStore(path, mac.Sum(nil), now, false, true)
	if err != nil {
		return nil, err
	}
	return &activeDeviceStore{activeIdentityStore: store}, nil
}

func (s *activeDeviceStore) beginRequest() {
	s.mu.Lock()
	s.requests++
	s.mu.Unlock()
}

func (s *activeDeviceStore) endRequest() {
	s.mu.Lock()
	s.requests--
	s.mu.Unlock()
}

func (s *activeDeviceStore) observe(device string) {
	s.observeAdmission(device, nil)
}

func (s *activeDeviceStore) observeAdmission(device string, authoredAt *time.Time) {
	s.mu.Lock()
	defer s.mu.Unlock()
	if s.stopped || device == "" {
		return
	}
	at := s.now()
	day := activitycalendar.Day(at)
	if authoredAt != nil && activitycalendar.Day(*authoredAt) != day {
		return
	}
	if s.advanceLocked(at) != nil || s.nextGenerationLocked() != nil {
		return
	}
	_ = s.sketches.insert(day, device)
}

func (s *activeDeviceStore) advance() error {
	s.mu.Lock()
	if s.stopped {
		s.mu.Unlock()
		return nil
	}
	err := s.advanceLocked(s.now())
	target := s.generation
	s.mu.Unlock()
	if err != nil {
		return err
	}
	return s.flushThrough(target)
}

func (s *activeDeviceStore) finish(hostClosed bool) error {
	s.mu.Lock()
	s.stopped = true
	checkpoint := hostClosed && s.requests == 0
	err := s.advanceLocked(s.now())
	target := s.generation
	s.mu.Unlock()
	if err != nil {
		return err
	}
	return s.saveThrough(target, checkpoint)
}

func activeDeviceInboxAdmission(recipient string, entry inboxMessage) (authoredAt *time.Time, eligible bool) {
	if entry.QuietRecovery || directNotificationCustodyOnly(recipient, entry) {
		return nil, false
	}
	envelope, ok := decodeJSONObjectPreservingNumbers(entry.Message)
	if !ok {
		return nil, false
	}
	switch exactString(envelope["type"]) {
	case "post_create":
		thought, ok := eligibleThoughtMetricEnvelope(entry)
		if !ok {
			return nil, false
		}
		return &thought.created, true
	case "chat_message":
		_, ok := extractAckCustodyDedupeKeyForRecipient(ackCustodyDirectTextKind, entry.Message, entry.From, recipient)
		return nil, ok
	default:
		return nil, false
	}
}
