package main

import (
	"context"
	"errors"
	"os"
	"path/filepath"
	"testing"
	"time"

	"github.com/alicebob/miniredis/v2"
)

func TestLoadBackendConfigFromEnv_DefaultsToMemory(t *testing.T) {
	t.Setenv("RELAY_BACKEND", "")
	t.Setenv("REDIS_URL", "")
	t.Setenv("REDIS_PREFIX", "")

	cfg := loadBackendConfigFromEnv()
	if cfg.Kind != backendKindMemory {
		t.Fatalf("expected default backend kind %q, got %q", backendKindMemory, cfg.Kind)
	}
	if cfg.RedisPrefix != "relay:" {
		t.Fatalf("expected default Redis prefix relay:, got %q", cfg.RedisPrefix)
	}
}

func TestLoadBackendConfigFromEnv_NormalizesRedisPrefix(t *testing.T) {
	t.Setenv("RELAY_BACKEND", "redis")
	t.Setenv("REDIS_URL", "redis://127.0.0.1:6379")
	t.Setenv("REDIS_PREFIX", "phase2")

	cfg := loadBackendConfigFromEnv()
	if cfg.Kind != backendKindRedis {
		t.Fatalf("expected backend kind %q, got %q", backendKindRedis, cfg.Kind)
	}
	if cfg.RedisURL != "redis://127.0.0.1:6379" {
		t.Fatalf("expected Redis URL to round-trip, got %q", cfg.RedisURL)
	}
	if cfg.RedisPrefix != "phase2:" {
		t.Fatalf("expected normalized prefix phase2:, got %q", cfg.RedisPrefix)
	}
}

func TestNewControlPlaneStores_SelectsRedisBackends(t *testing.T) {
	server := miniredis.RunT(t)
	limits := DefaultServerLimits()

	storesA, err := newControlPlaneStores(context.Background(), backendConfig{
		Kind:        backendKindRedis,
		RedisURL:    "redis://" + server.Addr(),
		RedisPrefix: "bootstrap:",
	}, limits, "/path/that/does/not/exist.json")
	if err != nil {
		t.Fatalf("newControlPlaneStores() error: %v", err)
	}
	defer func() { _ = storesA.Close() }()

	storesB, err := newControlPlaneStores(context.Background(), backendConfig{
		Kind:        backendKindRedis,
		RedisURL:    "redis://" + server.Addr(),
		RedisPrefix: "bootstrap:",
	}, limits, "/path/that/does/not/exist.json")
	if err != nil {
		t.Fatalf("newControlPlaneStores() second instance error: %v", err)
	}
	defer func() { _ = storesB.Close() }()

	if _, ok := storesA.RendezvousBackend.(*redisRendezvousBackend); !ok {
		t.Fatalf("expected Redis rendezvous backend, got %T", storesA.RendezvousBackend)
	}
	if _, ok := storesA.InboxBackend.(*redisInboxBackend); !ok {
		t.Fatalf("expected Redis inbox backend, got %T", storesA.InboxBackend)
	}
	if _, ok := storesA.GroupInboxBackend.(*redisGroupInboxBackend); !ok {
		t.Fatalf("expected Redis group inbox backend, got %T", storesA.GroupInboxBackend)
	}
	if _, ok := storesA.PushTokenBackend.(*redisPushTokenBackend); !ok {
		t.Fatalf("expected Redis push token backend, got %T", storesA.PushTokenBackend)
	}

	storesA.Rendezvous.Register("ns-1", "peer-1", []byte("record-1"), 60)
	results := storesB.Rendezvous.Discover("ns-1", "other-peer", 10)
	if len(results) != 1 {
		t.Fatalf("expected Redis-backed bootstrap instances to share state, got %d result(s)", len(results))
	}
}

func TestLoadServerLimitsFromEnv_Defaults(t *testing.T) {
	t.Setenv(relayMaxReservationsEnv, "")
	t.Setenv(relayMaxConnectionsPerPeerEnv, "")
	t.Setenv(relayMaxInboxMessagesEnv, "")
	t.Setenv(relayMaxGroupInboxMessagesEnv, "")

	limits := loadServerLimitsFromEnv()

	if limits != DefaultServerLimits() {
		t.Fatalf("expected default server limits, got %+v", limits)
	}
}

func TestLoadServerLimitsFromEnv_Overrides(t *testing.T) {
	t.Setenv(relayMaxReservationsEnv, "64")
	t.Setenv(relayMaxConnectionsPerPeerEnv, "3")
	t.Setenv(relayMaxInboxMessagesEnv, "11")
	t.Setenv(relayMaxGroupInboxMessagesEnv, "22")

	limits := loadServerLimitsFromEnv()

	if limits.MaxRelayReservations != 64 {
		t.Fatalf("expected MaxRelayReservations=64, got %d", limits.MaxRelayReservations)
	}
	if limits.MaxConnectionsPerPeer != 3 {
		t.Fatalf("expected MaxConnectionsPerPeer=3, got %d", limits.MaxConnectionsPerPeer)
	}
	if limits.MaxInboxMessagesPerPeer != 11 {
		t.Fatalf("expected MaxInboxMessagesPerPeer=11, got %d", limits.MaxInboxMessagesPerPeer)
	}
	if limits.MaxGroupInboxMessages != 22 {
		t.Fatalf("expected MaxGroupInboxMessages=22, got %d", limits.MaxGroupInboxMessages)
	}
}

func TestResolveStorageConfig_UsesExplicitRoot(t *testing.T) {
	var ensured []string
	cfg, fallbackReason, err := resolveStorageConfig(
		"/custom/relay-data",
		func(path string, _ os.FileMode) error {
			ensured = append(ensured, path)
			return nil
		},
		func() (string, error) {
			t.Fatal("getwd should not be called for explicit root")
			return "", nil
		},
	)
	if err != nil {
		t.Fatalf("resolveStorageConfig() error: %v", err)
	}
	if fallbackReason != "" {
		t.Fatalf("expected no fallback reason, got %q", fallbackReason)
	}
	if cfg.RootDir != "/custom/relay-data" {
		t.Fatalf("expected explicit root, got %q", cfg.RootDir)
	}
	if cfg.MediaDir != "/custom/relay-data/media" {
		t.Fatalf("unexpected media dir %q", cfg.MediaDir)
	}
	if cfg.ProfileDir != "/custom/relay-data/profiles" {
		t.Fatalf("unexpected profile dir %q", cfg.ProfileDir)
	}
	if len(ensured) != 1 || ensured[0] != "/custom/relay-data" {
		t.Fatalf("expected explicit root mkdir, got %#v", ensured)
	}
}

func TestResolveStorageConfig_FallsBackToWorkingDirectoryWhenDefaultUnavailable(t *testing.T) {
	var ensured []string
	cfg, fallbackReason, err := resolveStorageConfig(
		"",
		func(path string, _ os.FileMode) error {
			ensured = append(ensured, path)
			if path == defaultRelayDataDir {
				return errors.New("read-only file system")
			}
			return nil
		},
		func() (string, error) {
			return "/repo/go-relay-server", nil
		},
	)
	if err != nil {
		t.Fatalf("resolveStorageConfig() error: %v", err)
	}
	expectedRoot := filepath.Join("/repo/go-relay-server", "data")
	if cfg.RootDir != expectedRoot {
		t.Fatalf("expected fallback root %q, got %q", expectedRoot, cfg.RootDir)
	}
	if cfg.MediaDir != filepath.Join(expectedRoot, "media") {
		t.Fatalf("unexpected media dir %q", cfg.MediaDir)
	}
	if cfg.ProfileDir != filepath.Join(expectedRoot, "profiles") {
		t.Fatalf("unexpected profile dir %q", cfg.ProfileDir)
	}
	if fallbackReason == "" {
		t.Fatal("expected fallback reason when /data is unavailable")
	}
	expectedEnsured := []string{defaultRelayDataDir, expectedRoot}
	if len(ensured) != len(expectedEnsured) {
		t.Fatalf("expected mkdir calls %#v, got %#v", expectedEnsured, ensured)
	}
	for i, path := range expectedEnsured {
		if ensured[i] != path {
			t.Fatalf("expected mkdir calls %#v, got %#v", expectedEnsured, ensured)
		}
	}
}

func TestServerBootstrap_UsesServerLimitsInsteadOfInfiniteRelayLimits(t *testing.T) {
	limits := DefaultServerLimits()
	limits.MaxRelayReservations = 32
	limits.MaxConnectionsPerPeer = 2

	resources := relayResourcesFromServerLimits(limits)

	if resources.MaxReservations != 32 {
		t.Fatalf("expected MaxReservations=32, got %d", resources.MaxReservations)
	}
	if resources.MaxCircuits != 2 {
		t.Fatalf("expected MaxCircuits=2, got %d", resources.MaxCircuits)
	}
	if resources.Limit == nil {
		t.Fatal("expected finite relay limit configuration")
	}
}

func TestNewControlPlaneStores_UsesConfiguredServerLimits(t *testing.T) {
	limits := DefaultServerLimits()
	limits.MaxInboxMessagesPerPeer = 2
	limits.MaxGroupInboxMessages = 3

	stores, err := newControlPlaneStores(context.Background(), backendConfig{
		Kind: backendKindMemory,
	}, limits, "/path/that/does/not/exist.json")
	if err != nil {
		t.Fatalf("newControlPlaneStores() error: %v", err)
	}

	now := time.Now().UnixMilli()
	requireInboxStoreResult(t, stores.Inbox, "peer-1", inboxMessage{From: "a", Message: "1", Timestamp: now}, InboxStoreResultStored)
	requireInboxStoreResult(t, stores.Inbox, "peer-1", inboxMessage{From: "a", Message: "2", Timestamp: now}, InboxStoreResultStored)
	requireInboxStoreResult(t, stores.Inbox, "peer-1", inboxMessage{From: "a", Message: "3", Timestamp: now}, InboxStoreResultStored)
	if count := stores.Inbox.Count("peer-1"); count != 2 {
		t.Fatalf("expected inbox cap 2, got %d", count)
	}

	for i := 0; i < 4; i++ {
		if err := stores.GroupInbox.Store("group-1", "a", "msg"); err != nil {
			t.Fatalf("group store %d: %v", i, err)
		}
	}
	if _, total := stores.GroupInbox.Stats(); total != 3 {
		t.Fatalf("expected group inbox cap 3, got %d", total)
	}
}
