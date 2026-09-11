package main

import (
	"context"
	"encoding/base64"
	"encoding/json"
	"errors"
	"fmt"
	"go/ast"
	"go/parser"
	"go/token"
	"io"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"reflect"
	"sort"
	"strings"
	"sync"
	"sync/atomic"
	"testing"
	"time"

	firebase "firebase.google.com/go/v4"
	"firebase.google.com/go/v4/messaging"
	"github.com/alicebob/miniredis/v2"
	"google.golang.org/api/option"
)

const plan367FleetReceipt = "3673673673673673673673673673673673673673673673673673673673673673"

// plan367Entropy is deterministic but produces a different stream for every
// read, so tests can assert rotation without relying on crypto/rand timing.
type plan367Entropy struct {
	mu    sync.Mutex
	state uint64
}

func (r *plan367Entropy) Read(p []byte) (int, error) {
	r.mu.Lock()
	defer r.mu.Unlock()
	if r.state == 0 {
		r.state = 0x3673673673673673
	}
	for i := range p {
		r.state ^= r.state << 13
		r.state ^= r.state >> 7
		r.state ^= r.state << 17
		p[i] = byte(r.state >> 56)
	}
	return len(p), nil
}

func plan367Key(fill byte) []byte {
	return []byte(strings.Repeat(string([]byte{fill}), 32))
}

func plan367Config(activeKeyID, environment string, keys map[string][]byte) *pushTokenVaultConfig {
	copied := make(map[string][]byte, len(keys))
	for keyID, key := range keys {
		copied[keyID] = append([]byte(nil), key...)
	}
	return &pushTokenVaultConfig{
		activeKeyID:         activeKeyID,
		providerEnvironment: environment,
		keys:                copied,
	}
}

func plan367RedisBackend(
	t *testing.T,
	prefix string,
	config *pushTokenVaultConfig,
) (*miniredis.Miniredis, *redisPushTokenBackend) {
	t.Helper()
	server := miniredis.RunT(t)
	backend := newRedisPushTokenBackend(newTestRedisClient(t, server), prefix)
	backend.vaultConfig = config
	backend.entropy = &plan367Entropy{}
	return server, backend
}

func plan367Migrate(t *testing.T, backend *redisPushTokenBackend) {
	t.Helper()
	if err := backend.Migrate(plan367FleetReceipt); err != nil {
		t.Fatalf("Migrate() error: %v", err)
	}
}

func plan367Route(t *testing.T, backend PushTokenBackend, peerID string) pushRouteLease {
	t.Helper()
	route, err := backend.LookupRoute(peerID)
	if err != nil {
		t.Fatalf("LookupRoute(%q) error: %v", peerID, err)
	}
	if route == nil {
		t.Fatalf("LookupRoute(%q) returned nil", peerID)
	}
	return copyPushRouteLease(*route)
}

func plan367Target(t *testing.T, backend PushTokenBackend, route pushRouteLease) resolvedPushTarget {
	t.Helper()
	target, err := backend.ResolveRoute(route)
	if err != nil {
		t.Fatalf("ResolveRoute(%q/%d) error: %v", route.Handle, route.Generation, err)
	}
	if target == nil {
		t.Fatalf("ResolveRoute(%q/%d) returned nil", route.Handle, route.Generation)
	}
	return *target
}

func plan367Keys(t *testing.T, backend *redisPushTokenBackend, pattern string) []string {
	t.Helper()
	keys, err := scanRedisKeys(backend.client, pattern)
	if err != nil {
		t.Fatalf("scan %q: %v", pattern, err)
	}
	return keys
}

func plan367OnlyKey(t *testing.T, backend *redisPushTokenBackend, pattern string) string {
	t.Helper()
	keys := plan367Keys(t, backend, pattern)
	if len(keys) != 1 {
		t.Fatalf("keys matching %q = %#v, want exactly one", pattern, keys)
	}
	return keys[0]
}

func plan367AssertPairCardinality(
	t *testing.T,
	backend *redisPushTokenBackend,
	wantDirectories int,
	wantVaults int,
) {
	t.Helper()
	directories := plan367Keys(t, backend, backend.prefix+"push-token-directory:*")
	vaults := plan367Keys(t, backend, backend.prefix+"push-token-vault:*")
	if len(directories) != wantDirectories || len(vaults) != wantVaults {
		t.Fatalf("directory/vault cardinality = %d/%d, want %d/%d; directories=%#v vaults=%#v",
			len(directories), len(vaults), wantDirectories, wantVaults, directories, vaults)
	}
}

func plan367ReadJSONMap(t *testing.T, backend *redisPushTokenBackend, key string) map[string]any {
	t.Helper()
	raw, err := backend.client.Get(context.Background(), key).Bytes()
	if err != nil {
		t.Fatalf("GET %q: %v", key, err)
	}
	var decoded map[string]any
	if err := json.Unmarshal(raw, &decoded); err != nil {
		t.Fatalf("decode %q as JSON: %v (raw=%q)", key, err, raw)
	}
	return decoded
}

func plan367WriteJSONMap(
	t *testing.T,
	backend *redisPushTokenBackend,
	key string,
	decoded map[string]any,
) {
	t.Helper()
	raw, err := json.Marshal(decoded)
	if err != nil {
		t.Fatalf("encode mutation for %q: %v", key, err)
	}
	if err := backend.client.Set(context.Background(), key, raw, 0).Err(); err != nil {
		t.Fatalf("SET mutation for %q: %v", key, err)
	}
}

func plan367MapKey(t *testing.T, decoded map[string]any, fragment string) string {
	t.Helper()
	fragment = strings.ToLower(fragment)
	for key := range decoded {
		normalized := strings.NewReplacer("_", "", "-", "").Replace(strings.ToLower(key))
		if strings.Contains(normalized, strings.NewReplacer("_", "", "-", "").Replace(fragment)) {
			return key
		}
	}
	t.Fatalf("JSON object %#v has no key containing %q", decoded, fragment)
	return ""
}

func plan367JSONValue(t *testing.T, decoded map[string]any, fragment string) any {
	t.Helper()
	return decoded[plan367MapKey(t, decoded, fragment)]
}

func plan367RegisterEncrypted(
	t *testing.T,
	backend *redisPushTokenBackend,
	peerID string,
	tokenValue string,
	platform string,
	capabilities ...string,
) pushRouteLease {
	t.Helper()
	if err := backend.RegisterToken(peerID, tokenValue, platform, capabilities...); err != nil {
		t.Fatalf("RegisterToken(%q) error: %v", peerID, err)
	}
	return plan367Route(t, backend, peerID)
}

func plan367NewEncryptedFixture(
	t *testing.T,
	prefix string,
) (*miniredis.Miniredis, *redisPushTokenBackend, *pushTokenVaultConfig) {
	t.Helper()
	config := plan367Config("key-a", "test", map[string][]byte{
		"key-a": plan367Key('a'),
		"key-b": plan367Key('b'),
	})
	server, backend := plan367RedisBackend(t, prefix, config)
	plan367Migrate(t, backend)
	return server, backend, config
}

func plan367WriteKeyring(t *testing.T, raw string) string {
	t.Helper()
	path := filepath.Join(t.TempDir(), "push-token-keyring.json")
	if err := os.WriteFile(path, []byte(raw), 0o600); err != nil {
		t.Fatalf("write keyring: %v", err)
	}
	return path
}

func plan367SetVaultEnv(t *testing.T, keyringPath, activeKeyID, environment string) {
	t.Helper()
	t.Setenv("PUSH_TOKEN_KEYRING_FILE", keyringPath)
	t.Setenv("PUSH_TOKEN_ACTIVE_KEY_ID", activeKeyID)
	t.Setenv("PUSH_PROVIDER_ENVIRONMENT", environment)
}

func TestRelayNotificationClosure_PushRouteLegacyCoexistenceAndMigrationAdmission(t *testing.T) {
	const (
		prefix = "plan367-admission:"
		peerID = "peer-legacy-coexistence"
	)
	config := plan367Config("key-a", "test", map[string][]byte{"key-a": plan367Key('a')})
	_, backend := plan367RedisBackend(t, prefix, config)
	ctx := context.Background()

	// A configured keyring is deliberately inert while the marker is absent.
	legacyRaw := []byte(`{"Token":"legacy-token-exact","Platform":"android","Capabilities":["direct_reaction_v1"],"UpdatedAt":"2026-08-15T00:00:00Z"}`)
	if err := backend.client.Set(ctx, backend.key(peerID), legacyRaw, 0).Err(); err != nil {
		t.Fatalf("seed exact legacy bytes: %v", err)
	}
	if err := backend.ValidateStartup(); err != nil {
		t.Fatalf("ValidateStartup() in configured absent mode: %v", err)
	}
	gotLegacy, err := backend.client.Get(ctx, backend.key(peerID)).Bytes()
	if err != nil || string(gotLegacy) != string(legacyRaw) {
		t.Fatalf("keyring-only startup changed legacy bytes: got=%q err=%v want=%q", gotLegacy, err, legacyRaw)
	}
	legacyRoute := plan367Route(t, backend, peerID)
	if legacyRoute.Handle != "" || legacyRoute.Generation != 0 {
		t.Fatalf("absent legacy route = %#v, want compatibility handle/generation", legacyRoute)
	}
	legacyTarget := plan367Target(t, backend, legacyRoute)
	if legacyTarget.Token != "legacy-token-exact" || legacyTarget.Platform != "android" {
		t.Fatalf("legacy resolution = %#v, want exact persisted provider row", legacyTarget)
	}

	t.Run("ambiguous or unmatched legacy schema fails loudly", func(t *testing.T) {
		invalidRows := map[string]string{
			"duplicate token":   `{"Token":"first","Token":"second","Platform":"android","UpdatedAt":"2026-08-15T00:00:00Z"}`,
			"unknown field":     `{"Token":"token","Platform":"android","UpdatedAt":"2026-08-15T00:00:00Z","Unexpected":true}`,
			"missing timestamp": `{"Token":"token","Platform":"android"}`,
			"null timestamp":    `{"Token":"token","Platform":"android","UpdatedAt":null}`,
		}
		for name, raw := range invalidRows {
			t.Run(name, func(t *testing.T) {
				_, invalidBackend := plan367RedisBackend(t, "plan367-invalid-legacy:"+strings.ReplaceAll(name, " ", "-")+":", config)
				const invalidPeer = "peer-invalid-legacy"
				if err := invalidBackend.client.Set(context.Background(), invalidBackend.key(invalidPeer), raw, 0).Err(); err != nil {
					t.Fatalf("seed invalid legacy row: %v", err)
				}
				if route, err := invalidBackend.LookupRoute(invalidPeer); err == nil || route != nil {
					t.Fatalf("invalid legacy LookupRoute() = (%#v, %v), want loud decode error", route, err)
				}
				if err := invalidBackend.Migrate(plan367FleetReceipt); err == nil {
					t.Fatal("invalid legacy row migrated successfully")
				}
				after, err := invalidBackend.client.Get(context.Background(), invalidBackend.key(invalidPeer)).Result()
				if err != nil || after != raw {
					t.Fatalf("failed migration changed invalid legacy authority: after=%q err=%v", after, err)
				}
				plan367AssertPairCardinality(t, invalidBackend, 0, 0)
			})
		}
	})

	// A Plan-367 writer remains an exact legacy writer before admission.
	if err := backend.RegisterToken(peerID, "legacy-token-refreshed", "ios", "future", "future"); err != nil {
		t.Fatalf("absent RegisterToken(): %v", err)
	}
	if got := plan367Keys(t, backend, prefix+"push-token-directory:*"); len(got) != 0 {
		t.Fatalf("keyring alone created directory state: %#v", got)
	}
	if got := plan367Keys(t, backend, prefix+"push-token-vault:*"); len(got) != 0 {
		t.Fatalf("keyring alone created vault state: %#v", got)
	}
	if exists := backend.client.Exists(ctx, backend.markerKey()).Val(); exists != 0 {
		t.Fatalf("keyring alone created marker, EXISTS=%d", exists)
	}

	for _, invalid := range []string{
		"",
		"abc",
		strings.Repeat("g", 64),
		strings.Repeat("a", 63),
		strings.Repeat("a", 65),
	} {
		t.Run("receipt_"+fmt.Sprintf("%d", len(invalid)), func(t *testing.T) {
			before, getErr := backend.client.Get(ctx, backend.key(peerID)).Bytes()
			if getErr != nil {
				t.Fatalf("read pre-migration legacy row: %v", getErr)
			}
			if err := backend.Migrate(invalid); err == nil {
				t.Fatalf("Migrate(%q) succeeded", invalid)
			}
			after, getErr := backend.client.Get(ctx, backend.key(peerID)).Bytes()
			if getErr != nil || string(after) != string(before) {
				t.Fatalf("invalid receipt changed legacy row: before=%q after=%q err=%v", before, after, getErr)
			}
			if exists := backend.client.Exists(ctx, backend.markerKey()).Val(); exists != 0 {
				t.Fatalf("invalid receipt created marker, EXISTS=%d", exists)
			}
		})
	}

	migratingReached := make(chan uint64, 1)
	releaseMigration := make(chan struct{})
	backend.migrationBeforeCutover = func(revision uint64) error {
		migratingReached <- revision
		<-releaseMigration
		return nil
	}
	migrationDone := make(chan error, 1)
	go func() { migrationDone <- backend.Migrate(plan367FleetReceipt) }()
	select {
	case <-migratingReached:
		migratingMarker := plan367ReadJSONMap(t, backend, backend.markerKey())
		if got := fmt.Sprint(plan367JSONValue(t, migratingMarker, "state")); got != string(pushTokenStateMigrating) {
			t.Fatalf("admitted marker state = %q, want migrating", got)
		}
		if got := fmt.Sprint(plan367JSONValue(t, migratingMarker, "fleetreceiptsha256")); got != plan367FleetReceipt {
			t.Fatalf("migrating receipt identifier = %q, want exact input", got)
		}
	case <-time.After(3 * time.Second):
		t.Fatal("explicit migration never reached admitted migrating state")
	}
	close(releaseMigration)
	if err := <-migrationDone; err != nil {
		t.Fatalf("Migrate() after explicit admission: %v", err)
	}
	backend.migrationBeforeCutover = nil
	marker := plan367ReadJSONMap(t, backend, backend.markerKey())
	if got := fmt.Sprint(plan367JSONValue(t, marker, "state")); got != string(pushTokenStateEncrypted) {
		t.Fatalf("marker state = %q, want %q", got, pushTokenStateEncrypted)
	}
	if got := fmt.Sprint(plan367JSONValue(t, marker, "fleetreceiptsha256")); got != plan367FleetReceipt {
		t.Fatalf("persisted receipt identifier = %q, want exact operator input", got)
	}
	encryptedRoute := plan367Route(t, backend, peerID)
	if encryptedRoute.Handle == "" || encryptedRoute.Generation == 0 {
		t.Fatalf("migrated route lacks opaque generation: %#v", encryptedRoute)
	}
	if got := plan367Target(t, backend, encryptedRoute); got.Token != "legacy-token-refreshed" || got.Platform != "ios" {
		t.Fatalf("migrated resolution = %#v, want refreshed legacy authority", got)
	}

	// Startup state decides whether vault configuration is mandatory.
	absentNoConfig := newRedisPushTokenBackend(backend.client, "plan367-absent-no-config:")
	if err := absentNoConfig.ValidateStartup(); err != nil {
		t.Fatalf("unconfigured absent legacy mode unavailable: %v", err)
	}
	encryptedNoConfig := newRedisPushTokenBackend(backend.client, prefix)
	if err := encryptedNoConfig.ValidateStartup(); err == nil {
		t.Fatal("encrypted state started without a keyring/environment")
	}

	validKey := base64.StdEncoding.EncodeToString(plan367Key('v'))
	loaderCases := []struct {
		name        string
		raw         string
		active      string
		environment string
		missingPath bool
	}{
		{name: "malformed JSON", raw: `{`, active: "key-a", environment: "test"},
		{name: "wrong version", raw: `{"version":2,"keys":{"key-a":"` + validKey + `"}}`, active: "key-a", environment: "test"},
		{name: "duplicate key id", raw: `{"version":1,"keys":{"key-a":"` + validKey + `","key-a":"` + validKey + `"}}`, active: "key-a", environment: "test"},
		{name: "bad base64", raw: `{"version":1,"keys":{"key-a":"%%%"}}`, active: "key-a", environment: "test"},
		{name: "wrong key length", raw: `{"version":1,"keys":{"key-a":"` + base64.StdEncoding.EncodeToString([]byte("short")) + `"}}`, active: "key-a", environment: "test"},
		{name: "unknown active key", raw: `{"version":1,"keys":{"key-a":"` + validKey + `"}}`, active: "key-b", environment: "test"},
		{name: "empty active key", raw: `{"version":1,"keys":{"key-a":"` + validKey + `"}}`, active: "", environment: "test"},
		{name: "empty environment", raw: `{"version":1,"keys":{"key-a":"` + validKey + `"}}`, active: "key-a", environment: ""},
		{name: "invalid environment", raw: `{"version":1,"keys":{"key-a":"` + validKey + `"}}`, active: "key-a", environment: "test environment"},
		{name: "missing file", active: "key-a", environment: "test", missingPath: true},
	}
	for _, tc := range loaderCases {
		t.Run("startup_"+tc.name, func(t *testing.T) {
			path := filepath.Join(t.TempDir(), "missing-keyring.json")
			if !tc.missingPath {
				path = plan367WriteKeyring(t, tc.raw)
			}
			plan367SetVaultEnv(t, path, tc.active, tc.environment)
			if _, err := loadPushTokenVaultConfigFromEnv(); err == nil {
				t.Fatal("invalid vault configuration was accepted")
			}
		})
	}
	validPath := plan367WriteKeyring(t, `{"version":1,"keys":{"key-a":"`+validKey+`"}}`)
	plan367SetVaultEnv(t, validPath, "key-a", "test")
	if _, err := loadPushTokenVaultConfigFromEnv(); err != nil {
		t.Fatalf("valid exact keyring rejected: %v", err)
	}
	if _, err := decodePushTokenStateMarker([]byte(fmt.Sprintf(
		`{"state":"migrating","revision":null,"fleet_receipt_sha256":%q}`,
		plan367FleetReceipt,
	))); err == nil {
		t.Fatal("state marker accepted null revision as zero")
	}
	nullDigestDirectory := fmt.Sprintf(
		`{"handle":%q,"generation":1,"platform":"android","capabilities":[],"provider_environment":"test","source_legacy_digest":null}`,
		base64.RawURLEncoding.EncodeToString([]byte(strings.Repeat("d", 32))),
	)
	if _, err := decodePushTokenDirectoryRecord([]byte(nullDigestDirectory)); err == nil {
		t.Fatal("directory accepted null source digest as an absent digest")
	}

	t.Run("operator CLI preserves admission syntax and state", func(t *testing.T) {
		server := miniredis.RunT(t)
		const cliPrefix = "plan367-cli:"
		t.Setenv("RELAY_BACKEND", "redis")
		t.Setenv("REDIS_URL", "redis://"+server.Addr())
		t.Setenv("REDIS_PREFIX", cliPrefix)
		cliKey := base64.StdEncoding.EncodeToString(plan367Key('c'))
		cliKeyring := plan367WriteKeyring(
			t,
			`{"version":1,"keys":{"cli-key":"`+cliKey+`"}}`,
		)
		plan367SetVaultEnv(t, cliKeyring, "cli-key", "test")

		client := newTestRedisClient(t, server)
		backend := newRedisPushTokenBackend(client, cliPrefix)
		const cliPeer = "peer-cli-admission"
		legacyRow := []byte(`{"Token":"cli-legacy-token","Platform":"android","UpdatedAt":"2026-08-15T00:00:00Z"}`)
		if err := client.Set(context.Background(), backend.key(cliPeer), legacyRow, 0).Err(); err != nil {
			t.Fatalf("seed CLI legacy row: %v", err)
		}

		invalidCommands := []struct {
			name string
			args []string
		}{
			{name: "missing receipt", args: []string{"migrate"}},
			{name: "wrong receipt flag", args: []string{"migrate", "--receipt", plan367FleetReceipt}},
			{name: "malformed receipt", args: []string{"migrate", "--fleet-receipt-sha256", "not-a-sha256"}},
			{name: "cleanup extra argument", args: []string{"cleanup-legacy", "now"}},
			{name: "unknown subcommand", args: []string{"rotate"}},
		}
		for _, tc := range invalidCommands {
			t.Run(tc.name, func(t *testing.T) {
				before, err := client.Get(context.Background(), backend.key(cliPeer)).Bytes()
				if err != nil {
					t.Fatalf("read CLI legacy row before invalid command: %v", err)
				}
				if err := runPushTokenVaultCLI(tc.args); err == nil {
					t.Fatalf("runPushTokenVaultCLI(%#v) succeeded", tc.args)
				}
				after, err := client.Get(context.Background(), backend.key(cliPeer)).Bytes()
				if err != nil || string(after) != string(before) {
					t.Fatalf("invalid CLI command changed legacy state: before=%q after=%q err=%v", before, after, err)
				}
				if exists := client.Exists(context.Background(), backend.markerKey()).Val(); exists != 0 {
					t.Fatalf("invalid CLI command created marker, EXISTS=%d", exists)
				}
			})
		}

		if err := runPushTokenVaultCLI([]string{
			"migrate", "--fleet-receipt-sha256", plan367FleetReceipt,
		}); err != nil {
			t.Fatalf("exact CLI migrate: %v", err)
		}
		marker := plan367ReadJSONMap(t, backend, backend.markerKey())
		if got := fmt.Sprint(plan367JSONValue(t, marker, "state")); got != string(pushTokenStateEncrypted) {
			t.Fatalf("CLI marker state = %q, want encrypted", got)
		}
		if got := fmt.Sprint(plan367JSONValue(t, marker, "fleetreceiptsha256")); got != plan367FleetReceipt {
			t.Fatalf("CLI marker receipt = %q, want exact input", got)
		}
		if exists := client.Exists(context.Background(), backend.key(cliPeer)).Val(); exists != 1 {
			t.Fatalf("CLI migrate cleaned legacy state automatically, EXISTS=%d", exists)
		}
		backend.vaultConfig = plan367Config(
			"cli-key",
			"test",
			map[string][]byte{"cli-key": plan367Key('c')},
		)
		if got := plan367Target(t, backend, plan367Route(t, backend, cliPeer)); got.Token != "cli-legacy-token" {
			t.Fatalf("CLI-migrated target = %#v", got)
		}
	})

	t.Run("encrypted state never falls back to a retained legacy row", func(t *testing.T) {
		_, backend := plan367RedisBackend(t, "plan367-no-legacy-fallback:", plan367Config(
			"key-a", "test", map[string][]byte{"key-a": plan367Key('a')},
		))
		const peerID = "peer-no-legacy-fallback"
		if err := backend.RegisterToken(peerID, "legacy-token", "android"); err != nil {
			t.Fatalf("legacy register: %v", err)
		}
		legacyLease := plan367Route(t, backend, peerID)
		plan367Migrate(t, backend)
		if err := backend.UnregisterToken(peerID); err != nil {
			t.Fatalf("encrypted unregister: %v", err)
		}
		if exists := backend.client.Exists(context.Background(), backend.key(peerID)).Val(); exists != 1 {
			t.Fatalf("migration unexpectedly removed retained legacy row, EXISTS=%d", exists)
		}
		if route, err := backend.LookupRoute(peerID); err != nil || route != nil {
			t.Fatalf("encrypted lookup fell back to legacy row: route=%#v err=%v", route, err)
		}
		if target, err := backend.ResolveRoute(legacyLease); !errors.Is(err, ErrPushRouteStale) || target != nil {
			t.Fatalf("encrypted resolve fell back to legacy row: target=%#v err=%v", target, err)
		}
	})

	t.Run("absent writer watches admission marker and joins migrating revision", func(t *testing.T) {
		_, backend := plan367RedisBackend(t, "plan367-admission-watch:", plan367Config(
			"key-a", "test", map[string][]byte{"key-a": plan367Key('a')},
		))
		if err := backend.RegisterToken("peer-existing", "existing-token", "android"); err != nil {
			t.Fatalf("seed legacy row: %v", err)
		}

		writerEntered := make(chan struct{})
		allowWriter := make(chan struct{})
		var writerAttempts atomic.Int32
		backend.legacyMutationBeforeCommit = func() error {
			if writerAttempts.Add(1) == 1 {
				close(writerEntered)
				<-allowWriter
			}
			return nil
		}
		writerDone := make(chan error, 1)
		go func() {
			writerDone <- backend.RegisterToken("peer-crossing", "crossing-token", "ios", "cap-a")
		}()
		select {
		case <-writerEntered:
		case <-time.After(3 * time.Second):
			t.Fatal("absent writer did not reach marker-watched transaction")
		}

		cutoverReached := make(chan struct{})
		allowCutover := make(chan struct{})
		var cutoverAttempts atomic.Int32
		backend.migrationBeforeCutover = func(uint64) error {
			if cutoverAttempts.Add(1) == 1 {
				close(cutoverReached)
			}
			<-allowCutover
			return nil
		}
		migrationDone := make(chan error, 1)
		go func() { migrationDone <- backend.Migrate(plan367FleetReceipt) }()
		select {
		case <-cutoverReached:
		case <-time.After(3 * time.Second):
			t.Fatal("migration did not reconcile the pre-admission snapshot")
		}

		close(allowWriter)
		if err := <-writerDone; err != nil {
			t.Fatalf("crossing legacy writer: %v", err)
		}
		close(allowCutover)
		if err := <-migrationDone; err != nil {
			t.Fatalf("migration after crossing writer: %v", err)
		}
		if writerAttempts.Load() < 2 {
			t.Fatalf("legacy writer attempts = %d, want WATCH retry after admission", writerAttempts.Load())
		}
		if cutoverAttempts.Load() < 2 {
			t.Fatalf("cutover attempts = %d, want revision retry after crossing write", cutoverAttempts.Load())
		}
		crossing := plan367Target(t, backend, plan367Route(t, backend, "peer-crossing"))
		if crossing.Token != "crossing-token" || crossing.Platform != "ios" {
			t.Fatalf("crossing writer missing after cutover: %#v", crossing)
		}
	})

	t.Run("legacy resolve crossing cutover rechecks encrypted authority", func(t *testing.T) {
		_, backend := plan367RedisBackend(t, "plan367-resolve-cutover:", plan367Config(
			"key-a", "test", map[string][]byte{"key-a": plan367Key('a')},
		))
		const peerID = "peer-resolve-cutover"
		if err := backend.RegisterToken(peerID, "legacy-token", "android"); err != nil {
			t.Fatalf("legacy register: %v", err)
		}
		legacyLease := plan367Route(t, backend, peerID)

		cutoverReached := make(chan struct{})
		allowCutover := make(chan struct{})
		var cutoverOnce sync.Once
		backend.migrationBeforeCutover = func(uint64) error {
			cutoverOnce.Do(func() { close(cutoverReached) })
			<-allowCutover
			return nil
		}
		migrationDone := make(chan error, 1)
		go func() { migrationDone <- backend.Migrate(plan367FleetReceipt) }()
		select {
		case <-cutoverReached:
		case <-time.After(3 * time.Second):
			t.Fatal("migration did not reach cutover fence")
		}

		legacyRead := make(chan struct{})
		allowResolve := make(chan struct{})
		var resolveOnce sync.Once
		backend.legacyResolveAfterRead = func() {
			resolveOnce.Do(func() { close(legacyRead) })
			<-allowResolve
		}
		type resolveResult struct {
			target *resolvedPushTarget
			err    error
		}
		resolved := make(chan resolveResult, 1)
		go func() {
			target, err := backend.ResolveRoute(legacyLease)
			resolved <- resolveResult{target: target, err: err}
		}()
		select {
		case <-legacyRead:
		case <-time.After(3 * time.Second):
			t.Fatal("legacy resolve did not reach row-read interleaving")
		}

		close(allowCutover)
		if err := <-migrationDone; err != nil {
			t.Fatalf("migration cutover: %v", err)
		}
		encryptedLease := plan367Route(t, backend, peerID)
		if err := backend.client.Del(
			context.Background(),
			backend.directoryKey(peerID),
			backend.vaultKey(encryptedLease.Handle),
		).Err(); err != nil {
			t.Fatalf("remove encrypted authority for crossing resolve: %v", err)
		}
		close(allowResolve)
		result := <-resolved
		if !errors.Is(result.err, ErrPushRouteStale) || result.target != nil {
			t.Fatalf("cross-cutover legacy resolve = (%#v, %v), want encrypted-authority stale", result.target, result.err)
		}
	})
}

func TestRelayNotificationClosure_PushRouteDirectoryCiphertextAndGenerationContract(t *testing.T) {
	t.Run("privacy rotation and cardinality", func(t *testing.T) {
		_, backend, _ := plan367NewEncryptedFixture(t, "plan367-directory:")
		const (
			peerID        = "peer-social-identity-must-not-enter-vault"
			providerToken = "provider-plaintext-must-not-enter-redis"
		)
		route := plan367RegisterEncrypted(t, backend, peerID, providerToken, "android", "zeta", "alpha", "alpha")
		if route.Handle == "" || route.Generation == 0 || strings.Contains(route.Handle, peerID) {
			t.Fatalf("opaque route = %#v", route)
		}
		if !reflect.DeepEqual(route.Capabilities, []string{"alpha", "zeta"}) {
			t.Fatalf("canonical capabilities = %#v", route.Capabilities)
		}
		plan367AssertPairCardinality(t, backend, 1, 1)
		directoryKey := plan367OnlyKey(t, backend, backend.prefix+"push-token-directory:*")
		vaultKey := plan367OnlyKey(t, backend, backend.prefix+"push-token-vault:*")
		directoryRaw, _ := backend.client.Get(context.Background(), directoryKey).Result()
		vaultRaw, _ := backend.client.Get(context.Background(), vaultKey).Result()
		for _, forbidden := range []string{providerToken, peerID} {
			if strings.Contains(directoryRaw, forbidden) || strings.Contains(vaultRaw, forbidden) || strings.Contains(vaultKey, forbidden) {
				t.Fatalf("Redis route material exposes %q: directory=%q vault-key=%q vault=%q", forbidden, directoryRaw, vaultKey, vaultRaw)
			}
		}
		if strings.Contains(vaultRaw, "android") || strings.Contains(vaultRaw, "alpha") || strings.Contains(vaultRaw, "test") {
			t.Fatalf("vault envelope exposes AAD metadata instead of ciphertext only: %q", vaultRaw)
		}
		if got := plan367Target(t, backend, route); got.Token != providerToken || got.Platform != "android" || !reflect.DeepEqual(got.Route, route) {
			t.Fatalf("resolved target = %#v, want exact route/private provider material", got)
		}

		// Lease capabilities are defensive snapshots.
		mutated := route
		mutated.Capabilities[0] = "promoted"
		again := plan367Route(t, backend, peerID)
		if !reflect.DeepEqual(again.Capabilities, []string{"alpha", "zeta"}) {
			t.Fatalf("caller mutated backend capabilities: %#v", again.Capabilities)
		}

		firstVaultRaw := vaultRaw
		if err := backend.RegisterToken(peerID, providerToken, "android", "zeta", "alpha"); err != nil {
			t.Fatalf("same destination refresh: %v", err)
		}
		refreshed := plan367Route(t, backend, peerID)
		if refreshed.Handle != route.Handle || refreshed.Generation != route.Generation {
			t.Fatalf("same destination refresh rotated route: before=%#v after=%#v", route, refreshed)
		}
		refreshedVaultKey := plan367OnlyKey(t, backend, backend.prefix+"push-token-vault:*")
		refreshedVaultRaw, _ := backend.client.Get(context.Background(), refreshedVaultKey).Result()
		if refreshedVaultRaw == firstVaultRaw {
			t.Fatal("refresh did not reseal with fresh nonce")
		}

		if err := backend.RegisterToken(peerID, providerToken, "android", "beta"); err != nil {
			t.Fatalf("capability change: %v", err)
		}
		capabilityChanged := plan367Route(t, backend, peerID)
		if capabilityChanged.Handle != route.Handle || capabilityChanged.Generation != route.Generation ||
			!reflect.DeepEqual(capabilityChanged.Capabilities, []string{"beta"}) {
			t.Fatalf("capability change route = %#v, want stable handle/generation with new AAD", capabilityChanged)
		}
		if _, err := backend.ResolveRoute(refreshed); !errors.Is(err, ErrPushRouteStale) {
			t.Fatalf("pre-capability lease ResolveRoute() error = %v, want stale", err)
		}

		if err := backend.RegisterToken(peerID, "provider-token-rotated", "android", "beta"); err != nil {
			t.Fatalf("token rotation: %v", err)
		}
		tokenRotated := plan367Route(t, backend, peerID)
		if tokenRotated.Handle == capabilityChanged.Handle || tokenRotated.Generation <= capabilityChanged.Generation {
			t.Fatalf("token rotation did not advance opaque identity: before=%#v after=%#v", capabilityChanged, tokenRotated)
		}
		if _, err := backend.ResolveRoute(capabilityChanged); !errors.Is(err, ErrPushRouteStale) {
			t.Fatalf("old token route ResolveRoute() error = %v, want stale", err)
		}
		plan367AssertPairCardinality(t, backend, 1, 1)

		if err := backend.RegisterToken(peerID, "provider-token-rotated", "ios", "beta"); err != nil {
			t.Fatalf("platform rotation: %v", err)
		}
		platformRotated := plan367Route(t, backend, peerID)
		if platformRotated.Handle == tokenRotated.Handle || platformRotated.Generation <= tokenRotated.Generation {
			t.Fatalf("platform rotation did not advance opaque identity: before=%#v after=%#v", tokenRotated, platformRotated)
		}
		plan367AssertPairCardinality(t, backend, 1, 1)

		rotatedEnvironmentBackend := newRedisPushTokenBackend(backend.client, backend.prefix)
		rotatedEnvironmentBackend.vaultConfig = plan367Config("key-a", "staging", map[string][]byte{
			"key-a": plan367Key('a'),
			"key-b": plan367Key('b'),
		})
		if err := rotatedEnvironmentBackend.ValidateStartup(); err != nil {
			t.Fatalf("changed-environment startup rejected replaceable prior pair: %v", err)
		}
		if target, err := rotatedEnvironmentBackend.ResolveRoute(platformRotated); err == nil || target != nil {
			t.Fatalf("old-environment route resolved in changed environment: target=%#v err=%v", target, err)
		}
		if err := rotatedEnvironmentBackend.RegisterToken(peerID, "provider-token-rotated", "ios", "beta"); err != nil {
			t.Fatalf("trusted environment rotation: %v", err)
		}
		environmentRotated := plan367Route(t, rotatedEnvironmentBackend, peerID)
		if environmentRotated.Handle == platformRotated.Handle || environmentRotated.Generation <= platformRotated.Generation {
			t.Fatalf("environment rotation did not advance opaque identity: before=%#v after=%#v", platformRotated, environmentRotated)
		}
		if _, err := rotatedEnvironmentBackend.ResolveRoute(platformRotated); !errors.Is(err, ErrPushRouteStale) {
			t.Fatalf("old-environment route ResolveRoute() error = %v, want stale", err)
		}
		plan367AssertPairCardinality(t, rotatedEnvironmentBackend, 1, 1)
	})

	t.Run("retained key lazy rewrap", func(t *testing.T) {
		_, backend, _ := plan367NewEncryptedFixture(t, "plan367-rewrap:")
		route := plan367RegisterEncrypted(t, backend, "peer-rewrap", "token-rewrap", "android")
		vaultKey := plan367OnlyKey(t, backend, backend.prefix+"push-token-vault:*")
		before := plan367ReadJSONMap(t, backend, vaultKey)
		if got := fmt.Sprint(plan367JSONValue(t, before, "keyid")); got != "key-a" {
			t.Fatalf("initial key id = %q, want key-a", got)
		}
		backend.vaultConfig = plan367Config("key-b", "test", map[string][]byte{
			"key-a": plan367Key('a'),
			"key-b": plan367Key('b'),
		})
		got := plan367Target(t, backend, route)
		if got.Route.Handle != route.Handle || got.Route.Generation != route.Generation || got.Token != "token-rewrap" {
			t.Fatalf("retained-key resolution changed route: %#v", got)
		}
		after := plan367ReadJSONMap(t, backend, vaultKey)
		if keyID := fmt.Sprint(plan367JSONValue(t, after, "keyid")); keyID != "key-b" {
			t.Fatalf("lazy rewrap key id = %q, want key-b", keyID)
		}
		backend.vaultConfig = plan367Config("key-b", "test", map[string][]byte{"key-b": plan367Key('b')})
		_ = plan367Target(t, backend, route)
		plan367AssertPairCardinality(t, backend, 1, 1)
	})

	t.Run("startup validation tolerates atomic refresh between namespace scans", func(t *testing.T) {
		_, backend, _ := plan367NewEncryptedFixture(t, "plan367-startup-snapshot:")
		const peerID = "peer-startup-snapshot"
		plan367RegisterEncrypted(t, backend, peerID, "token-before-startup", "android")
		backend.startupValidationBetweenSnapshots = func() {
			for generation := 0; generation < 20; generation++ {
				if err := backend.RegisterToken(peerID, fmt.Sprintf("token-after-startup-%02d", generation), "android"); err != nil {
					t.Errorf("crossing startup refresh %d: %v", generation, err)
					return
				}
			}
		}
		if err := backend.ValidateStartup(); err != nil {
			t.Fatalf("ValidateStartup() rejected an atomically changing valid inventory: %v", err)
		}
		backend.startupValidationBetweenSnapshots = nil
		if got := plan367Target(t, backend, plan367Route(t, backend, peerID)); got.Token != "token-after-startup-19" {
			t.Fatalf("startup snapshot lost concurrent refresh: %#v", got)
		}
		plan367AssertPairCardinality(t, backend, 1, 1)
	})

	t.Run("startup validation rejects a malformed vault namespace handle", func(t *testing.T) {
		_, backend, _ := plan367NewEncryptedFixture(t, "plan367-startup-vault-key:")
		plan367RegisterEncrypted(t, backend, "peer-startup-vault-key", "token", "android")
		vaultKey := plan367OnlyKey(t, backend, backend.prefix+"push-token-vault:*")
		payload, err := backend.client.Get(context.Background(), vaultKey).Bytes()
		if err != nil {
			t.Fatalf("read valid vault envelope: %v", err)
		}
		if err := backend.client.Set(context.Background(), backend.prefix+"push-token-vault:not-an-opaque-handle", payload, 0).Err(); err != nil {
			t.Fatalf("seed malformed vault namespace key: %v", err)
		}
		if err := backend.ValidateStartup(); err == nil {
			t.Fatal("ValidateStartup() accepted a malformed vault namespace handle")
		}
	})

	t.Run("capability refresh crossing Redis resolve is stale not integrity failure", func(t *testing.T) {
		_, backend, _ := plan367NewEncryptedFixture(t, "plan367-resolve-capability-race:")
		const peerID = "peer-resolve-capability-race"
		oldRoute := plan367RegisterEncrypted(t, backend, peerID, "same-token", "android", "cap-a")
		directoryRead := make(chan struct{})
		allowResolve := make(chan struct{})
		var blockOnce sync.Once
		backend.encryptedResolveAfterDirectoryRead = func() {
			blockOnce.Do(func() {
				close(directoryRead)
				<-allowResolve
			})
		}
		type resolveResult struct {
			target *resolvedPushTarget
			err    error
		}
		resolved := make(chan resolveResult, 1)
		go func() {
			target, err := backend.ResolveRoute(oldRoute)
			resolved <- resolveResult{target: target, err: err}
		}()
		select {
		case <-directoryRead:
		case <-time.After(3 * time.Second):
			t.Fatal("encrypted resolve did not reach directory/vault interleaving")
		}
		if err := backend.RegisterToken(peerID, "same-token", "android", "cap-b"); err != nil {
			t.Fatalf("crossing capability refresh: %v", err)
		}
		close(allowResolve)
		result := <-resolved
		if !errors.Is(result.err, ErrPushRouteStale) || result.target != nil {
			t.Fatalf("crossing capability resolve = (%#v, %v), want stale", result.target, result.err)
		}
		backend.encryptedResolveAfterDirectoryRead = nil
		newRoute := plan367Route(t, backend, peerID)
		if newRoute.Handle != oldRoute.Handle || newRoute.Generation != oldRoute.Generation ||
			!reflect.DeepEqual(newRoute.Capabilities, []string{"cap-b"}) {
			t.Fatalf("capability refresh changed route identity incorrectly: old=%#v new=%#v", oldRoute, newRoute)
		}
		if got := plan367Target(t, backend, newRoute); got.Token != "same-token" {
			t.Fatalf("refreshed capability route did not resolve: %#v", got)
		}
	})

	t.Run("AAD tamper environment and key faults fail closed", func(t *testing.T) {
		cases := []struct {
			name   string
			legacy bool
			mutate func(t *testing.T, backend *redisPushTokenBackend, directoryKey, vaultKey string)
		}{
			{
				name: "vault schema",
				mutate: func(t *testing.T, backend *redisPushTokenBackend, _, vaultKey string) {
					row := plan367ReadJSONMap(t, backend, vaultKey)
					row[plan367MapKey(t, row, "schema")] = float64(2)
					plan367WriteJSONMap(t, backend, vaultKey, row)
				},
			},
			{
				name: "ciphertext",
				mutate: func(t *testing.T, backend *redisPushTokenBackend, _, vaultKey string) {
					row := plan367ReadJSONMap(t, backend, vaultKey)
					row[plan367MapKey(t, row, "ciphertext")] = "AA"
					plan367WriteJSONMap(t, backend, vaultKey, row)
				},
			},
			{
				name: "nonce",
				mutate: func(t *testing.T, backend *redisPushTokenBackend, _, vaultKey string) {
					row := plan367ReadJSONMap(t, backend, vaultKey)
					row[plan367MapKey(t, row, "nonce")] = "AA"
					plan367WriteJSONMap(t, backend, vaultKey, row)
				},
			},
			{
				name: "unknown key id",
				mutate: func(t *testing.T, backend *redisPushTokenBackend, _, vaultKey string) {
					row := plan367ReadJSONMap(t, backend, vaultKey)
					row[plan367MapKey(t, row, "keyid")] = "missing-key"
					plan367WriteJSONMap(t, backend, vaultKey, row)
				},
			},
			{
				name: "retained wrong key id",
				mutate: func(t *testing.T, backend *redisPushTokenBackend, _, vaultKey string) {
					row := plan367ReadJSONMap(t, backend, vaultKey)
					row[plan367MapKey(t, row, "keyid")] = "key-b"
					plan367WriteJSONMap(t, backend, vaultKey, row)
				},
			},
			{
				name: "generation",
				mutate: func(t *testing.T, backend *redisPushTokenBackend, directoryKey, _ string) {
					row := plan367ReadJSONMap(t, backend, directoryKey)
					generationKey := plan367MapKey(t, row, "generation")
					row[generationKey] = row[generationKey].(float64) + 1
					plan367WriteJSONMap(t, backend, directoryKey, row)
				},
			},
			{
				name: "platform",
				mutate: func(t *testing.T, backend *redisPushTokenBackend, directoryKey, _ string) {
					row := plan367ReadJSONMap(t, backend, directoryKey)
					row[plan367MapKey(t, row, "platform")] = "ios"
					plan367WriteJSONMap(t, backend, directoryKey, row)
				},
			},
			{
				name: "handle",
				mutate: func(t *testing.T, backend *redisPushTokenBackend, directoryKey, vaultKey string) {
					row := plan367ReadJSONMap(t, backend, directoryKey)
					replacement := base64.RawURLEncoding.EncodeToString([]byte(strings.Repeat("h", 32)))
					row[plan367MapKey(t, row, "handle")] = replacement
					plan367WriteJSONMap(t, backend, directoryKey, row)
					raw, err := backend.client.Get(context.Background(), vaultKey).Bytes()
					if err != nil {
						t.Fatalf("read vault before handle substitution: %v", err)
					}
					if err := backend.client.Set(context.Background(), backend.vaultKey(replacement), raw, 0).Err(); err != nil {
						t.Fatalf("write substituted-handle vault: %v", err)
					}
					if err := backend.client.Del(context.Background(), vaultKey).Err(); err != nil {
						t.Fatalf("delete original-handle vault: %v", err)
					}
				},
			},
			{
				name: "capability promotion",
				mutate: func(t *testing.T, backend *redisPushTokenBackend, directoryKey, _ string) {
					row := plan367ReadJSONMap(t, backend, directoryKey)
					row[plan367MapKey(t, row, "capabilities")] = []any{"cap-a", "promoted"}
					plan367WriteJSONMap(t, backend, directoryKey, row)
				},
			},
			{
				name: "capability removal",
				mutate: func(t *testing.T, backend *redisPushTokenBackend, directoryKey, _ string) {
					row := plan367ReadJSONMap(t, backend, directoryKey)
					row[plan367MapKey(t, row, "capabilities")] = []any{}
					plan367WriteJSONMap(t, backend, directoryKey, row)
				},
			},
			{
				name: "provider environment",
				mutate: func(t *testing.T, backend *redisPushTokenBackend, directoryKey, _ string) {
					row := plan367ReadJSONMap(t, backend, directoryKey)
					row[plan367MapKey(t, row, "providerenvironment")] = "production"
					plan367WriteJSONMap(t, backend, directoryKey, row)
				},
			},
			{
				name:   "source legacy digest",
				legacy: true,
				mutate: func(t *testing.T, backend *redisPushTokenBackend, directoryKey, _ string) {
					row := plan367ReadJSONMap(t, backend, directoryKey)
					row[plan367MapKey(t, row, "sourcelegacydigest")] = strings.Repeat("0", 64)
					plan367WriteJSONMap(t, backend, directoryKey, row)
				},
			},
		}
		for _, tc := range cases {
			t.Run(tc.name, func(t *testing.T) {
				_, backend := plan367RedisBackend(t, "plan367-tamper:"+strings.ReplaceAll(tc.name, " ", "-")+":", plan367Config(
					"key-a", "test", map[string][]byte{"key-a": plan367Key('a')},
				))
				const peerID = "peer-tamper"
				if tc.legacy {
					if err := backend.RegisterToken(peerID, "token-tamper", "android", "cap-a"); err != nil {
						t.Fatalf("legacy RegisterToken(): %v", err)
					}
					plan367Migrate(t, backend)
				} else {
					plan367Migrate(t, backend)
					plan367RegisterEncrypted(t, backend, peerID, "token-tamper", "android", "cap-a")
				}
				directoryKey := plan367OnlyKey(t, backend, backend.prefix+"push-token-directory:*")
				vaultKey := plan367OnlyKey(t, backend, backend.prefix+"push-token-vault:*")
				tc.mutate(t, backend, directoryKey, vaultKey)
				if route, err := backend.LookupRoute(peerID); err == nil || route != nil {
					t.Fatalf("tampered LookupRoute() = (%#v, %v), want integrity error", route, err)
				}
				// Resolve a route reconstructed from the current directory so metadata
				// substitutions exercise AEAD authority rather than merely comparing a
				// pre-tamper stale lease.
				directoryRaw, err := backend.client.Get(context.Background(), directoryKey).Bytes()
				if err != nil {
					t.Fatalf("read tampered directory: %v", err)
				}
				directory, err := decodePushTokenDirectoryRecord(directoryRaw)
				if err != nil {
					t.Fatalf("decode structurally valid tampered directory: %v", err)
				}
				route := pushRouteLease{
					Handle:       directory.Handle,
					Generation:   directory.Generation,
					Capabilities: append([]string(nil), directory.Capabilities...),
					lookupKey:    directoryKey,
				}
				if target, err := backend.ResolveRoute(route); err == nil || target != nil {
					t.Fatalf("tampered ResolveRoute() = (%#v, %v), want finite integrity error", target, err)
				}
				plan367AssertPairCardinality(t, backend, 1, 1)
			})
		}

		t.Run("cross environment replay", func(t *testing.T) {
			_, backend, _ := plan367NewEncryptedFixture(t, "plan367-cross-env:")
			route := plan367RegisterEncrypted(t, backend, "peer-env", "token-env", "android")
			backend.vaultConfig = plan367Config("key-a", "production", map[string][]byte{
				"key-a": plan367Key('a'), "key-b": plan367Key('b'),
			})
			if lookedUp, err := backend.LookupRoute("peer-env"); err == nil || lookedUp != nil {
				t.Fatalf("cross-environment LookupRoute() = (%#v, %v), want closed", lookedUp, err)
			}
			if target, err := backend.ResolveRoute(route); err == nil || target != nil {
				t.Fatalf("cross-environment ResolveRoute() = (%#v, %v), want closed", target, err)
			}
		})

		t.Run("missing retained key", func(t *testing.T) {
			_, backend, _ := plan367NewEncryptedFixture(t, "plan367-missing-key:")
			route := plan367RegisterEncrypted(t, backend, "peer-key", "token-key", "android")
			backend.vaultConfig = plan367Config("key-b", "test", map[string][]byte{"key-b": plan367Key('b')})
			if lookedUp, err := backend.LookupRoute("peer-key"); err == nil || lookedUp != nil {
				t.Fatalf("missing retained key LookupRoute() = (%#v, %v), want closed", lookedUp, err)
			}
			if target, err := backend.ResolveRoute(route); err == nil || target != nil {
				t.Fatalf("missing retained key ResolveRoute() = (%#v, %v), want closed", target, err)
			}
		})

		t.Run("vault row swap", func(t *testing.T) {
			_, backend, _ := plan367NewEncryptedFixture(t, "plan367-swap:")
			routeA := plan367RegisterEncrypted(t, backend, "peer-a", "token-a", "android", "cap-a")
			routeB := plan367RegisterEncrypted(t, backend, "peer-b", "token-b", "ios", "cap-b")
			keyA := backend.vaultKey(routeA.Handle)
			keyB := backend.vaultKey(routeB.Handle)
			rawA, errA := backend.client.Get(context.Background(), keyA).Bytes()
			rawB, errB := backend.client.Get(context.Background(), keyB).Bytes()
			if errA != nil || errB != nil {
				t.Fatalf("read rows before swap: errA=%v errB=%v", errA, errB)
			}
			if err := backend.client.Set(context.Background(), keyA, rawB, 0).Err(); err != nil {
				t.Fatalf("swap A: %v", err)
			}
			if err := backend.client.Set(context.Background(), keyB, rawA, 0).Err(); err != nil {
				t.Fatalf("swap B: %v", err)
			}
			for _, route := range []pushRouteLease{routeA, routeB} {
				if target, err := backend.ResolveRoute(route); err == nil || target != nil {
					t.Fatalf("swapped row ResolveRoute(%q) = (%#v, %v), want closed", route.Handle, target, err)
				}
			}
			for _, peerID := range []string{"peer-a", "peer-b"} {
				if route, err := backend.LookupRoute(peerID); err == nil || route != nil {
					t.Fatalf("swapped row LookupRoute(%q) = (%#v, %v), want closed", peerID, route, err)
				}
			}
			plan367AssertPairCardinality(t, backend, 2, 2)
		})
	})

	t.Run("peer digest independently binds an otherwise intact pair", func(t *testing.T) {
		_, backend, _ := plan367NewEncryptedFixture(t, "plan367-peer-aad:")
		const (
			peerA = "peer-aad-source"
			peerB = "peer-aad-destination"
		)
		routeA := plan367RegisterEncrypted(t, backend, peerA, "token-peer-bound", "android", "cap-a")
		directoryRaw, err := backend.client.Get(context.Background(), backend.directoryKey(peerA)).Bytes()
		if err != nil {
			t.Fatalf("read source directory: %v", err)
		}
		if err := backend.client.Set(context.Background(), backend.directoryKey(peerB), directoryRaw, 0).Err(); err != nil {
			t.Fatalf("copy intact directory to another peer: %v", err)
		}
		if route, err := backend.LookupRoute(peerB); err == nil || route != nil {
			t.Fatalf("cross-peer intact-pair LookupRoute() = (%#v, %v), want peer-digest authentication failure", route, err)
		}
		directory, err := decodePushTokenDirectoryRecord(directoryRaw)
		if err != nil {
			t.Fatalf("decode copied directory: %v", err)
		}
		routeB := pushRouteLease{
			Handle:       directory.Handle,
			Generation:   directory.Generation,
			Capabilities: append([]string(nil), directory.Capabilities...),
			lookupKey:    backend.directoryKey(peerB),
		}
		if routeB.Handle != routeA.Handle || routeB.Generation != routeA.Generation ||
			!reflect.DeepEqual(routeB.Capabilities, routeA.Capabilities) {
			t.Fatalf("copied route changed non-peer AAD fields: source=%#v destination=%#v", routeA, routeB)
		}
		if target, err := backend.ResolveRoute(routeB); err == nil || target != nil {
			t.Fatalf("cross-peer intact-pair replay = (%#v, %v), want peer-digest authentication failure", target, err)
		}
	})

	routeType := reflect.TypeOf(pushRouteLease{})
	fields := make([]string, 0, routeType.NumField())
	for index := 0; index < routeType.NumField(); index++ {
		field := routeType.Field(index)
		fields = append(fields, field.Name)
		lower := strings.ToLower(field.Name)
		for _, forbidden := range []string{"token", "platform", "entry", "updatedat"} {
			if strings.Contains(lower, forbidden) {
				t.Fatalf("pushRouteLease exposes forbidden field %q", field.Name)
			}
		}
		if field.IsExported() && field.Name != "Handle" && field.Name != "Generation" && field.Name != "Capabilities" {
			t.Fatalf("pushRouteLease unexpectedly exports %q", field.Name)
		}
	}
	sort.Strings(fields)
	wantFields := []string{"Capabilities", "Generation", "Handle", "legacyDigest", "lookupKey"}
	if !reflect.DeepEqual(fields, wantFields) {
		t.Fatalf("pushRouteLease fields = %#v, want exact privacy boundary %#v", fields, wantFields)
	}
}

func TestRelayNotificationClosure_PushRouteMigrationRevisionFenceConvergesWithoutWriteDowntime(t *testing.T) {
	mutations := []struct {
		name      string
		prepare   func(t *testing.T, backend *redisPushTokenBackend, peerID string) pushRouteLease
		cross     func(backend *redisPushTokenBackend, peerID string, legacyRoute pushRouteLease) error
		assertEnd func(t *testing.T, backend *redisPushTokenBackend, peerID string)
	}{
		{
			name: "register crosses reconciled revision",
			prepare: func(t *testing.T, backend *redisPushTokenBackend, peerID string) pushRouteLease {
				if err := backend.RegisterToken(peerID, "token-before", "android", "cap-before"); err != nil {
					t.Fatalf("prepare register: %v", err)
				}
				return plan367Route(t, backend, peerID)
			},
			cross: func(backend *redisPushTokenBackend, peerID string, _ pushRouteLease) error {
				return backend.RegisterToken(peerID, "token-after", "ios", "cap-after")
			},
			assertEnd: func(t *testing.T, backend *redisPushTokenBackend, peerID string) {
				route := plan367Route(t, backend, peerID)
				target := plan367Target(t, backend, route)
				if target.Token != "token-after" || target.Platform != "ios" || !reflect.DeepEqual(route.Capabilities, []string{"cap-after"}) {
					t.Fatalf("register crossing resurrected snapshot: route=%#v target=%#v", route, target)
				}
				plan367AssertPairCardinality(t, backend, 1, 1)
			},
		},
		{
			name: "unregister crosses reconciled revision",
			prepare: func(t *testing.T, backend *redisPushTokenBackend, peerID string) pushRouteLease {
				if err := backend.RegisterToken(peerID, "token-before", "android"); err != nil {
					t.Fatalf("prepare register: %v", err)
				}
				return plan367Route(t, backend, peerID)
			},
			cross: func(backend *redisPushTokenBackend, peerID string, _ pushRouteLease) error {
				return backend.UnregisterToken(peerID)
			},
			assertEnd: func(t *testing.T, backend *redisPushTokenBackend, peerID string) {
				route, err := backend.LookupRoute(peerID)
				if err != nil || route != nil {
					t.Fatalf("unregister crossing resurrected route: route=%#v err=%v", route, err)
				}
				plan367AssertPairCardinality(t, backend, 0, 0)
			},
		},
		{
			name: "compare revoke crosses reconciled revision",
			prepare: func(t *testing.T, backend *redisPushTokenBackend, peerID string) pushRouteLease {
				if err := backend.RegisterToken(peerID, "token-before", "android"); err != nil {
					t.Fatalf("prepare register: %v", err)
				}
				return plan367Route(t, backend, peerID)
			},
			cross: func(backend *redisPushTokenBackend, _ string, legacyRoute pushRouteLease) error {
				revoked, err := backend.RevokeIfCurrent(legacyRoute)
				if err != nil {
					return err
				}
				if !revoked {
					return errors.New("crossing RevokeIfCurrent did not revoke exact legacy row")
				}
				return nil
			},
			assertEnd: func(t *testing.T, backend *redisPushTokenBackend, peerID string) {
				route, err := backend.LookupRoute(peerID)
				if err != nil || route != nil {
					t.Fatalf("compare revoke crossing resurrected route: route=%#v err=%v", route, err)
				}
				plan367AssertPairCardinality(t, backend, 0, 0)
			},
		},
	}

	for _, tc := range mutations {
		t.Run(tc.name, func(t *testing.T) {
			_, backend := plan367RedisBackend(t, "plan367-revision:"+strings.ReplaceAll(tc.name, " ", "-")+":", plan367Config(
				"key-a", "test", map[string][]byte{"key-a": plan367Key('a')},
			))
			const peerID = "peer-revision-crossing"
			legacyRoute := tc.prepare(t, backend, peerID)
			atCutover := make(chan uint64, 1)
			release := make(chan struct{})
			var hookCalls atomic.Int32
			backend.migrationBeforeCutover = func(revision uint64) error {
				if hookCalls.Add(1) == 1 {
					atCutover <- revision
					<-release
				}
				return nil
			}
			migrationDone := make(chan error, 1)
			go func() { migrationDone <- backend.Migrate(plan367FleetReceipt) }()

			select {
			case <-atCutover:
			case <-time.After(3 * time.Second):
				t.Fatal("migration never reached the pre-cutover reconciliation hook")
			}
			mutationDone := make(chan error, 1)
			go func() {
				mutationDone <- tc.cross(backend, peerID, legacyRoute)
			}()
			select {
			case err := <-mutationDone:
				if err != nil {
					t.Fatalf("crossing legacy mutation: %v", err)
				}
				// Write availability is part of the contract: migration does not hold
				// a process-wide lock while the stable revision is being selected.
			case <-time.After(2 * time.Second):
				t.Fatal("legacy mutation blocked during migration")
			}
			close(release)
			select {
			case err := <-migrationDone:
				if err != nil {
					t.Fatalf("Migrate() after revision drift: %v", err)
				}
			case <-time.After(5 * time.Second):
				t.Fatal("migration did not converge after revision drift")
			}
			if hookCalls.Load() < 2 {
				t.Fatalf("migration hook calls = %d, want reconciliation retry after revision crossing", hookCalls.Load())
			}
			tc.assertEnd(t, backend, peerID)
		})
	}

	t.Run("register refresh crossing verification retries semantic mismatches", func(t *testing.T) {
		_, backend := plan367RedisBackend(t, "plan367-verification-crossing:", plan367Config(
			"key-a", "test", map[string][]byte{"key-a": plan367Key('a')},
		))
		const peerID = "peer-verification-crossing"
		if err := backend.RegisterToken(peerID, "token-before", "android", "cap-before"); err != nil {
			t.Fatalf("seed verification row: %v", err)
		}
		verificationScanned := make(chan struct{})
		allowVerification := make(chan struct{})
		var blockOnce sync.Once
		backend.migrationVerificationAfterScans = func() {
			blockOnce.Do(func() {
				close(verificationScanned)
				<-allowVerification
			})
		}
		migrationDone := make(chan error, 1)
		go func() { migrationDone <- backend.Migrate(plan367FleetReceipt) }()
		select {
		case <-verificationScanned:
		case <-time.After(3 * time.Second):
			t.Fatal("migration verification did not reach the scanned snapshot")
		}
		if err := backend.RegisterToken(peerID, "token-after", "ios", "cap-after"); err != nil {
			t.Fatalf("refresh crossing verification: %v", err)
		}
		close(allowVerification)
		select {
		case err := <-migrationDone:
			if err != nil {
				t.Fatalf("Migrate() treated revision drift as corruption: %v", err)
			}
		case <-time.After(5 * time.Second):
			t.Fatal("migration did not converge after verification drift")
		}
		backend.migrationVerificationAfterScans = nil
		route := plan367Route(t, backend, peerID)
		target := plan367Target(t, backend, route)
		if target.Token != "token-after" || target.Platform != "ios" ||
			!reflect.DeepEqual(route.Capabilities, []string{"cap-after"}) {
			t.Fatalf("verification drift resurrected stale authority: route=%#v target=%#v", route, target)
		}
		plan367AssertPairCardinality(t, backend, 1, 1)
	})

	for _, tc := range mutations[1:] {
		t.Run(tc.name+" crosses verification scan", func(t *testing.T) {
			_, backend := plan367RedisBackend(t, "plan367-verification-delete:"+strings.ReplaceAll(tc.name, " ", "-")+":", plan367Config(
				"key-a", "test", map[string][]byte{"key-a": plan367Key('a')},
			))
			const peerID = "peer-verification-delete"
			legacyRoute := tc.prepare(t, backend, peerID)
			verificationScanned := make(chan struct{})
			allowVerification := make(chan struct{})
			var blockOnce sync.Once
			backend.migrationVerificationAfterScans = func() {
				blockOnce.Do(func() {
					close(verificationScanned)
					<-allowVerification
				})
			}
			migrationDone := make(chan error, 1)
			go func() { migrationDone <- backend.Migrate(plan367FleetReceipt) }()
			select {
			case <-verificationScanned:
			case <-time.After(3 * time.Second):
				t.Fatal("migration verification did not reach deletion snapshot")
			}
			if err := tc.cross(backend, peerID, legacyRoute); err != nil {
				t.Fatalf("mutation crossing verification: %v", err)
			}
			close(allowVerification)
			select {
			case err := <-migrationDone:
				if err != nil {
					t.Fatalf("Migrate() treated deletion drift as corruption: %v", err)
				}
			case <-time.After(5 * time.Second):
				t.Fatal("migration did not converge after verification deletion")
			}
			backend.migrationVerificationAfterScans = nil
			tc.assertEnd(t, backend, peerID)
		})
	}

	t.Run("crash resume is idempotent", func(t *testing.T) {
		_, backend := plan367RedisBackend(t, "plan367-resume:", plan367Config(
			"key-a", "test", map[string][]byte{"key-a": plan367Key('a')},
		))
		if err := backend.RegisterToken("peer-resume", "token-resume", "android"); err != nil {
			t.Fatalf("legacy RegisterToken(): %v", err)
		}
		crash := errors.New("test crash after reconcile")
		backend.migrationBeforeCutover = func(uint64) error { return crash }
		if err := backend.Migrate(plan367FleetReceipt); !errors.Is(err, crash) {
			t.Fatalf("first Migrate() error = %v, want injected crash", err)
		}
		marker := plan367ReadJSONMap(t, backend, backend.markerKey())
		if got := fmt.Sprint(plan367JSONValue(t, marker, "state")); got != string(pushTokenStateMigrating) {
			t.Fatalf("crash marker state = %q, want migrating", got)
		}
		backend.migrationBeforeCutover = nil
		plan367Migrate(t, backend)
		plan367Migrate(t, backend)
		route := plan367Route(t, backend, "peer-resume")
		if got := plan367Target(t, backend, route); got.Token != "token-resume" {
			t.Fatalf("resumed target = %#v", got)
		}
		plan367AssertPairCardinality(t, backend, 1, 1)
	})
}

type plan367BackendProbe struct {
	delegate PushTokenBackend

	mu             sync.Mutex
	lookupCalls    int
	resolveCalls   int
	revokeCalls    int
	onResolve      func(call int, route pushRouteLease)
	forceStaleCall func(call int) bool
}

func (p *plan367BackendProbe) RegisterToken(peerID, tokenValue, platform string, capabilities ...string) error {
	return p.delegate.RegisterToken(peerID, tokenValue, platform, capabilities...)
}

func (p *plan367BackendProbe) UnregisterToken(peerID string) error {
	return p.delegate.UnregisterToken(peerID)
}

func (p *plan367BackendProbe) LookupRoute(peerID string) (*pushRouteLease, error) {
	p.mu.Lock()
	p.lookupCalls++
	p.mu.Unlock()
	return p.delegate.LookupRoute(peerID)
}

func (p *plan367BackendProbe) ResolveRoute(route pushRouteLease) (*resolvedPushTarget, error) {
	p.mu.Lock()
	p.resolveCalls++
	call := p.resolveCalls
	onResolve := p.onResolve
	forceStale := p.forceStaleCall
	p.mu.Unlock()
	if onResolve != nil {
		onResolve(call, copyPushRouteLease(route))
	}
	if forceStale != nil && forceStale(call) {
		return nil, ErrPushRouteStale
	}
	return p.delegate.ResolveRoute(route)
}

func (p *plan367BackendProbe) RevokeIfCurrent(route pushRouteLease) (bool, error) {
	p.mu.Lock()
	p.revokeCalls++
	p.mu.Unlock()
	return p.delegate.RevokeIfCurrent(route)
}

func (p *plan367BackendProbe) TokenCount() int { return p.delegate.TokenCount() }

func (p *plan367BackendProbe) PlatformCounts() map[string]int {
	return p.delegate.PlatformCounts()
}

func (p *plan367BackendProbe) counts() (lookups, resolves, revokes int) {
	p.mu.Lock()
	defer p.mu.Unlock()
	return p.lookupCalls, p.resolveCalls, p.revokeCalls
}

func plan367AssertMessageEquivalent(t *testing.T, got, want *messaging.Message) {
	t.Helper()
	if !reflect.DeepEqual(got, want) {
		gotJSON, _ := json.Marshal(got)
		wantJSON, _ := json.Marshal(want)
		t.Fatalf("provider message changed across route gateway:\n got: %s\nwant: %s", gotJSON, wantJSON)
	}
}

func TestRelayNotificationClosure_PushRouteEncryptedResolutionFeedsEveryRichSender(t *testing.T) {
	const (
		peerID   = "peer-rich-recipient"
		tokenID  = "private-provider-token"
		platform = "android"
	)
	directMessage := ordinaryChatCiphertextEnvelope(8, 16)
	groupMessage := ordinaryGroupCiphertextEnvelope(16)
	directReaction := ordinaryDirectReactionEnvelope(8, 16)
	groupReaction := `{"kind":"group_offline_replay","version":1,"payloadType":"group_reaction","messageId":"group-base-367","keyEpoch":7,"ciphertext":"group-cipher","nonce":"group-nonce"}`
	groupMetadata := groupReactionPushMetadata{
		TransitionID:              "group-event-367",
		Action:                    "add",
		TargetMessageID:           "target-367",
		ReactorPeerID:             "reactor-account",
		ReactorTransportPeerID:    "reactor-transport",
		BaseEnvelopeHash:          "base-hash",
		NotificationExtensionJSON: `{"version":1}`,
		SenderPublicKey:           "sender-public-key",
	}

	cases := []struct {
		name         string
		capabilities []string
		invoke       func(*PushService)
		want         func() *messaging.Message
	}{
		{
			name: "direct",
			invoke: func(push *PushService) {
				push.SendNotification(context.Background(), peerID, "direct-sender", directMessage)
			},
			want: func() *messaging.Message {
				return projectPushMessageForPlatform(buildPushMessage(tokenID, "direct-sender", directMessage), platform)
			},
		},
		{
			name:         "direct reaction",
			capabilities: []string{directReactionCapability},
			invoke: func(push *PushService) {
				push.SendReactionNotification(context.Background(), peerID, "reactor-peer", directReaction)
			},
			want: func() *messaging.Message {
				return projectPushMessageForPlatform(buildReactionPushMessage(tokenID, "reactor-peer", directReaction), platform)
			},
		},
		{
			name: "group",
			invoke: func(push *PushService) {
				push.SendGroupNotification(context.Background(), peerID, "group-367", "group-sender", "group-mid-367", groupMessage)
			},
			want: func() *messaging.Message {
				return projectPushMessageForPlatform(buildGroupPushMessage(tokenID, "group-367", "group-sender", "group-mid-367", groupMessage), platform)
			},
		},
		{
			name:         "group reaction",
			capabilities: []string{groupReactionCapability},
			invoke: func(push *PushService) {
				push.SendGroupReactionNotification(context.Background(), peerID, "group-367", groupReaction, groupMetadata)
			},
			want: func() *messaging.Message {
				return projectPushMessageForPlatform(buildGroupReactionPushMessage(tokenID, "group-367", groupReaction, groupMetadata), platform)
			},
		},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			_, store, _ := plan367NewEncryptedFixture(
				t,
				"plan367-rich-"+strings.ReplaceAll(tc.name, " ", "-")+":",
			)
			if err := store.RegisterToken(peerID, tokenID, platform, tc.capabilities...); err != nil {
				t.Fatalf("RegisterToken(): %v", err)
			}
			probe := &plan367BackendProbe{delegate: store}
			push := NewPushServiceWithBackend(probe)
			push.retryDelays = nil
			recorder := newRecordingPushSender()
			push.sender = recorder.Send
			tc.invoke(push)
			if recorder.SendCallCount() != 1 {
				t.Fatalf("provider sends = %d, want one", recorder.SendCallCount())
			}
			plan367AssertMessageEquivalent(t, recorder.LastMessage(), tc.want())
			lookups, resolves, _ := probe.counts()
			if lookups != 1 || resolves != 1 {
				t.Fatalf("route snapshot calls = lookup %d resolve %d, want happy-path 1/1", lookups, resolves)
			}
		})
	}

	t.Run("one bounded stale re-selection uses refreshed target", func(t *testing.T) {
		store := newMemoryPushTokenStore()
		if err := store.RegisterToken(peerID, "token-old", platform); err != nil {
			t.Fatalf("old register: %v", err)
		}
		probe := &plan367BackendProbe{delegate: store}
		probe.onResolve = func(call int, _ pushRouteLease) {
			if call == 1 {
				if err := store.RegisterToken(peerID, "token-new", platform); err != nil {
					t.Errorf("refresh register: %v", err)
				}
			}
		}
		push := NewPushServiceWithBackend(probe)
		recorder := newRecordingPushSender()
		push.sender = recorder.Send
		push.SendNotification(context.Background(), peerID, "direct-sender", directMessage)
		if recorder.SendCallCount() != 1 || recorder.LastMessage().Token != "token-new" {
			t.Fatalf("stale re-selection sends=%d message=%#v, want refreshed target", recorder.SendCallCount(), recorder.LastMessage())
		}
		lookups, resolves, _ := probe.counts()
		if lookups != 2 || resolves != 2 {
			t.Fatalf("stale call bound = lookup %d resolve %d, want exactly 2/2", lookups, resolves)
		}
	})

	t.Run("second stale terminates", func(t *testing.T) {
		store := newMemoryPushTokenStore()
		_ = store.RegisterToken(peerID, "token-stale", platform)
		probe := &plan367BackendProbe{
			delegate:       store,
			forceStaleCall: func(int) bool { return true },
		}
		push := NewPushServiceWithBackend(probe)
		recorder := newRecordingPushSender()
		push.sender = recorder.Send
		push.SendNotification(context.Background(), peerID, "direct-sender", directMessage)
		if recorder.SendCallCount() != 0 {
			t.Fatalf("second stale sent %d provider messages", recorder.SendCallCount())
		}
		lookups, resolves, _ := probe.counts()
		if lookups != 2 || resolves != 2 {
			t.Fatalf("second-stale call bound = lookup %d resolve %d, want exactly 2/2", lookups, resolves)
		}
	})

	t.Run("stale re-selection rechecks capability", func(t *testing.T) {
		store := newMemoryPushTokenStore()
		_ = store.RegisterToken(peerID, "reaction-old", platform, directReactionCapability)
		probe := &plan367BackendProbe{delegate: store}
		probe.onResolve = func(call int, _ pushRouteLease) {
			if call == 1 {
				if err := store.RegisterToken(peerID, "reaction-new-incapable", platform); err != nil {
					t.Errorf("incapable refresh: %v", err)
				}
			}
		}
		push := NewPushServiceWithBackend(probe)
		recorder := newRecordingPushSender()
		push.sender = recorder.Send
		push.SendReactionNotification(context.Background(), peerID, "reactor-peer", directReaction)
		if recorder.SendCallCount() != 0 {
			t.Fatalf("capability-lost stale route sent %d provider messages", recorder.SendCallCount())
		}
		lookups, resolves, _ := probe.counts()
		if lookups != 2 || resolves != 1 {
			t.Fatalf("capability recheck calls = lookup %d resolve %d, want 2/1", lookups, resolves)
		}
	})

	t.Run("production source has one private resolver and synchronous group accounting", func(t *testing.T) {
		files, err := filepath.Glob("*.go")
		if err != nil {
			t.Fatalf("glob production Go: %v", err)
		}
		var lookupOwners, resolveOwners, legacyLookupOwners, gatewayCallers, admissionGatewayCallers, groupGatewayCallers, directAdapterCallers []string
		retryOwners := make(map[string]bool)
		providerSendOwners := make(map[string]bool)
		fset := token.NewFileSet()
		var groupSelect, groupAttempted, groupGo token.Pos
		for _, path := range files {
			if strings.HasSuffix(path, "_test.go") {
				continue
			}
			parsed, parseErr := parser.ParseFile(fset, path, nil, 0)
			if parseErr != nil {
				t.Fatalf("parse %s: %v", path, parseErr)
			}
			for _, declaration := range parsed.Decls {
				function, ok := declaration.(*ast.FuncDecl)
				if !ok || function.Body == nil {
					continue
				}
				pushServiceReceiver := ""
				if function.Recv != nil && len(function.Recv.List) == 1 {
					receiver := function.Recv.List[0]
					if pointer, ok := receiver.Type.(*ast.StarExpr); ok && len(receiver.Names) == 1 {
						if receiverType, ok := pointer.X.(*ast.Ident); ok && receiverType.Name == "PushService" {
							pushServiceReceiver = receiver.Names[0].Name
						}
					}
				}
				ast.Inspect(function.Body, func(node ast.Node) bool {
					switch typed := node.(type) {
					case *ast.CallExpr:
						if selector, ok := typed.Fun.(*ast.SelectorExpr); ok {
							switch selector.Sel.Name {
							case "LookupRoute":
								lookupOwners = append(lookupOwners, function.Name.Name)
							case "ResolveRoute":
								resolveOwners = append(resolveOwners, function.Name.Name)
							case "LookupToken":
								legacyLookupOwners = append(legacyLookupOwners, function.Name.Name)
							case "sendSelectedPushThroughGateway":
								gatewayCallers = append(gatewayCallers, function.Name.Name)
							case "sendSelectedPushThroughGatewayWithAdmission":
								admissionGatewayCallers = append(admissionGatewayCallers, function.Name.Name)
							case "sendSelectedGroupPushThroughGateway":
								groupGatewayCallers = append(groupGatewayCallers, function.Name.Name)
							case "sendRichNotification":
								directAdapterCallers = append(directAdapterCallers, function.Name.Name)
							case "sendWithRetry":
								retryOwners[function.Name.Name] = true
							case "send":
								if receiver, ok := selector.X.(*ast.Ident); ok &&
									pushServiceReceiver != "" && receiver.Name == pushServiceReceiver {
									providerSendOwners[function.Name.Name] = true
								}
							}
						} else if identifier, ok := typed.Fun.(*ast.Ident); ok && identifier.Name == "sendSelectedPushThroughGateway" {
							gatewayCallers = append(gatewayCallers, function.Name.Name)
						}
						if function.Name.Name == "fanOutGroupReactionPush" {
							if selector, ok := typed.Fun.(*ast.SelectorExpr); ok && selector.Sel.Name == "selectPushRoute" {
								groupSelect = typed.Pos()
							}
						}
					case *ast.BasicLit:
						if function.Name.Name == "fanOutGroupReactionPush" && typed.Value == `"attempted"` {
							groupAttempted = typed.Pos()
						}
					case *ast.GoStmt:
						if function.Name.Name == "fanOutGroupReactionPush" {
							groupGo = typed.Pos()
						}
					}
					return true
				})
			}
		}
		if !reflect.DeepEqual(lookupOwners, []string{"selectPushRoute"}) {
			t.Fatalf("production LookupRoute callers = %#v, want shared selector only", lookupOwners)
		}
		if !reflect.DeepEqual(resolveOwners, []string{"sendPushRouteThroughGateway"}) {
			t.Fatalf("production ResolveRoute callers = %#v, want private gateway only", resolveOwners)
		}
		if len(legacyLookupOwners) != 0 {
			t.Fatalf("production still calls LookupToken from %#v", legacyLookupOwners)
		}
		if len(retryOwners) != 1 || !retryOwners["sendPushRouteThroughGateway"] {
			t.Fatalf("provider retry owners = %#v, want private route/admission gateway only", retryOwners)
		}
		if len(providerSendOwners) != 1 || !providerSendOwners["sendWithRetry"] {
			t.Fatalf("provider send owners = %#v, want shared outcome/retry loop only", providerSendOwners)
		}
		sort.Strings(gatewayCallers)
		wantCallers := []string{
			"sendGroupReactionNotificationForRoute",
			"sendOpaqueWakeThroughGateway",
			"sendReactionNotificationForRoute",
			"sendSelectedGroupPushThroughGateway",
		}
		if !reflect.DeepEqual(gatewayCallers, wantCallers) {
			t.Fatalf("selection gateway callers = %#v, want shared adapters plus group admission wrapper %#v", gatewayCallers, wantCallers)
		}
		// Direct replays and group wakes both carry admission through the shared
		// selector; neither path may resolve tokens or call the provider itself.
		sort.Strings(admissionGatewayCallers)
		wantAdmissionGatewayCallers := []string{
			"sendDirectOpaqueWakeThroughGateway",
			"sendGroupWakeOutcomeThroughGateway",
			"sendRichNotification",
			"sendSelectedGroupPushThroughGateway",
			"sendSelectedPushThroughGateway",
		}
		if !reflect.DeepEqual(admissionGatewayCallers, wantAdmissionGatewayCallers) {
			t.Fatalf("admission gateway callers = %#v, want shared direct/group/outcome adapters %#v",
				admissionGatewayCallers, wantAdmissionGatewayCallers)
		}
		sort.Strings(groupGatewayCallers)
		wantGroupGatewayCallers := []string{
			"SendGroupNotification",
			"sendGroupContentNotificationForRoute",
			"sendGroupOpaqueWakeThroughGateway",
		}
		if !reflect.DeepEqual(groupGatewayCallers, wantGroupGatewayCallers) {
			t.Fatalf("group selection gateway callers = %#v, want exact group entrypoints %#v", groupGatewayCallers, wantGroupGatewayCallers)
		}
		sort.Strings(directAdapterCallers)
		wantDirectAdapterCallers := []string{"SendNotification", "sendStoredNotification"}
		if !reflect.DeepEqual(directAdapterCallers, wantDirectAdapterCallers) {
			t.Fatalf(
				"direct rich adapter callers = %#v, want public plus stored-custody entrypoints %#v",
				directAdapterCallers,
				wantDirectAdapterCallers,
			)
		}
		if groupSelect == token.NoPos || groupAttempted == token.NoPos || groupGo == token.NoPos ||
			!(groupSelect < groupAttempted && groupAttempted < groupGo) {
			t.Fatalf("group accounting order = select %v attempted %v go %v, want synchronous selection/count before goroutine",
				groupSelect, groupAttempted, groupGo)
		}
	})
}

func plan367FirebaseClient(t *testing.T, handler http.Handler) *messaging.Client {
	t.Helper()
	server := httptest.NewServer(handler)
	t.Cleanup(server.Close)
	app, err := firebase.NewApp(
		context.Background(),
		&firebase.Config{ProjectID: "plan367-project"},
		option.WithEndpoint(server.URL),
		option.WithoutAuthentication(),
	)
	if err != nil {
		t.Fatalf("firebase app: %v", err)
	}
	client, err := app.Messaging(context.Background())
	if err != nil {
		t.Fatalf("firebase messaging client: %v", err)
	}
	return client
}

func plan367WritePermanentFCMError(w http.ResponseWriter) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(http.StatusNotFound)
	_, _ = fmt.Fprint(w, `{"error":{"code":404,"status":"NOT_FOUND","message":"opaque provider message","details":[{"@type":"type.googleapis.com/google.firebase.fcm.v1.FcmError","errorCode":"UNREGISTERED"}]}}`)
}

func TestRelayNotificationClosure_PushRoutePermanentErrorCompareRevokesExactLease(t *testing.T) {
	t.Run("memory exact stale refresh and ABA", func(t *testing.T) {
		store := newMemoryPushTokenStore()
		_ = store.RegisterToken("peer-exact", "token-exact", "android")
		exact := plan367Route(t, store, "peer-exact")
		revoked, err := store.RevokeIfCurrent(exact)
		if err != nil || !revoked {
			t.Fatalf("exact RevokeIfCurrent() = (%t, %v)", revoked, err)
		}
		if route, lookupErr := store.LookupRoute("peer-exact"); lookupErr != nil || route != nil {
			t.Fatalf("exact revoke left route %#v err=%v", route, lookupErr)
		}

		_ = store.RegisterToken("peer-refresh", "token-old", "android")
		old := plan367Route(t, store, "peer-refresh")
		_ = store.RegisterToken("peer-refresh", "token-new", "android")
		if revoked, err = store.RevokeIfCurrent(old); err != nil || revoked {
			t.Fatalf("stale refresh RevokeIfCurrent() = (%t, %v), want no-op", revoked, err)
		}
		if got := plan367Target(t, store, plan367Route(t, store, "peer-refresh")); got.Token != "token-new" {
			t.Fatalf("stale revoke removed refresh: %#v", got)
		}

		_ = store.RegisterToken("peer-aba", "token-a", "android")
		abaOld := plan367Route(t, store, "peer-aba")
		_ = store.RegisterToken("peer-aba", "token-b", "android")
		_ = store.RegisterToken("peer-aba", "token-a", "android")
		abaCurrent := plan367Route(t, store, "peer-aba")
		if abaCurrent.Generation <= abaOld.Generation || abaCurrent.Handle == abaOld.Handle {
			t.Fatalf("ABA did not advance route identity: old=%#v current=%#v", abaOld, abaCurrent)
		}
		if revoked, err = store.RevokeIfCurrent(abaOld); err != nil || revoked {
			t.Fatalf("ABA-old RevokeIfCurrent() = (%t, %v), want no-op", revoked, err)
		}
	})

	t.Run("legacy digest binds exact persisted refresh bytes across cutover", func(t *testing.T) {
		_, backend := plan367RedisBackend(t, "plan367-exact-legacy-digest:", plan367Config(
			"key-a", "test", map[string][]byte{"key-a": plan367Key('a')},
		))
		base := time.Date(2026, 8, 15, 10, 0, 0, 0, time.UTC)
		var ticks atomic.Int64
		backend.now = func() time.Time {
			return base.Add(time.Duration(ticks.Add(1)) * time.Second)
		}
		const peerID = "peer-exact-legacy-digest"
		if err := backend.RegisterToken(peerID, "same-token", "android", "cap-a"); err != nil {
			t.Fatalf("first exact legacy register: %v", err)
		}
		oldLease := plan367Route(t, backend, peerID)
		if err := backend.RegisterToken(peerID, "same-token", "android", "cap-a"); err != nil {
			t.Fatalf("timestamp-only legacy refresh: %v", err)
		}
		currentLease := plan367Route(t, backend, peerID)
		if oldLease.legacyDigest == currentLease.legacyDigest {
			t.Fatal("timestamp-only persisted refresh did not invalidate exact-row digest")
		}
		if target, err := backend.ResolveRoute(oldLease); !errors.Is(err, ErrPushRouteStale) || target != nil {
			t.Fatalf("pre-cutover stale exact-row lease = (%#v, %v)", target, err)
		}
		plan367Migrate(t, backend)
		if target, err := backend.ResolveRoute(oldLease); !errors.Is(err, ErrPushRouteStale) || target != nil {
			t.Fatalf("post-cutover stale exact-row lease = (%#v, %v)", target, err)
		}
		if revoked, err := backend.RevokeIfCurrent(oldLease); err != nil || revoked {
			t.Fatalf("post-cutover old exact-row revoke = (%t, %v), want no-op", revoked, err)
		}
		if got := plan367Target(t, backend, currentLease); got.Token != "same-token" || got.Platform != "android" {
			t.Fatalf("current exact-row lease after cutover = %#v", got)
		}
	})

	t.Run("real Firebase permanent response cannot delete concurrent refresh", func(t *testing.T) {
		store := newMemoryPushTokenStore()
		const peerID = "peer-sdk-refresh"
		_ = store.RegisterToken(peerID, "token-sdk-old", "android")
		var hits atomic.Int32
		client := plan367FirebaseClient(t, http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
			hits.Add(1)
			if err := store.RegisterToken(peerID, "token-sdk-fresh", "android"); err != nil {
				t.Errorf("concurrent refresh: %v", err)
			}
			plan367WritePermanentFCMError(w)
		}))
		push := NewPushServiceWithBackend(store)
		push.client = client
		push.retryDelays = []time.Duration{0, 0}
		push.SendNotification(context.Background(), peerID, "sender", ordinaryChatCiphertextEnvelope(8, 16))
		if hits.Load() != 1 {
			t.Fatalf("Firebase hits = %d, want exactly one permanent attempt", hits.Load())
		}
		if got := plan367Target(t, store, plan367Route(t, store, peerID)); got.Token != "token-sdk-fresh" {
			t.Fatalf("delayed permanent failure removed concurrent refresh: %#v", got)
		}
	})

	t.Run("strict fallback permanent response conditionally revokes", func(t *testing.T) {
		store := newMemoryPushTokenStore()
		_ = store.RegisterToken("peer-strict", "token-strict", "android")
		push := NewPushServiceWithBackend(store)
		push.retryDelays = []time.Duration{0, 0}
		recorder := newRecordingPushSender()
		var calls atomic.Int32
		recorder.onSend = func(context.Context, *messaging.Message) (string, error) {
			if calls.Add(1) == 1 {
				return "", errors.New("messaging/invalid-argument: Message is too large. The maximum is 4K")
			}
			return "", errors.New("NotRegistered")
		}
		push.sender = recorder.Send
		push.SendNotification(context.Background(), "peer-strict", "sender", ordinaryChatCiphertextEnvelope(8, 16))
		if calls.Load() != 2 {
			t.Fatalf("strict fallback calls = %d, want initial plus one fallback", calls.Load())
		}
		if route, err := store.LookupRoute("peer-strict"); err != nil || route != nil {
			t.Fatalf("strict permanent failure left route=%#v err=%v", route, err)
		}
	})

	t.Run("strict fallback permanent response cannot delete concurrent refresh", func(t *testing.T) {
		store := newMemoryPushTokenStore()
		const peerID = "peer-strict-refresh"
		_ = store.RegisterToken(peerID, "token-strict-old", "android")
		push := NewPushServiceWithBackend(store)
		push.retryDelays = []time.Duration{0, 0}
		recorder := newRecordingPushSender()
		var calls atomic.Int32
		recorder.onSend = func(context.Context, *messaging.Message) (string, error) {
			if calls.Add(1) == 1 {
				return "", errors.New("messaging/invalid-argument: Message is too large. The maximum is 4K")
			}
			if err := store.RegisterToken(peerID, "token-strict-fresh", "android"); err != nil {
				t.Errorf("concurrent strict-fallback refresh: %v", err)
			}
			return "", errors.New("NotRegistered")
		}
		push.sender = recorder.Send
		push.SendNotification(context.Background(), peerID, "sender", ordinaryChatCiphertextEnvelope(8, 16))
		if calls.Load() != 2 {
			t.Fatalf("strict refresh calls = %d, want initial plus one fallback", calls.Load())
		}
		if got := plan367Target(t, store, plan367Route(t, store, peerID)); got.Token != "token-strict-fresh" {
			t.Fatalf("strict-fallback permanent failure removed concurrent refresh: %#v", got)
		}
	})

	t.Run("Redis exact pair stale refresh and migrated source fence", func(t *testing.T) {
		_, backend, _ := plan367NewEncryptedFixture(t, "plan367-revoke-redis:")
		current := plan367RegisterEncrypted(t, backend, "peer-redis", "token-redis", "android")
		revoked, err := backend.RevokeIfCurrent(current)
		if err != nil || !revoked {
			t.Fatalf("Redis exact RevokeIfCurrent() = (%t, %v)", revoked, err)
		}
		plan367AssertPairCardinality(t, backend, 0, 0)

		first := plan367RegisterEncrypted(t, backend, "peer-redis", "token-first", "android")
		_ = plan367RegisterEncrypted(t, backend, "peer-redis", "token-second", "android")
		if revoked, err = backend.RevokeIfCurrent(first); err != nil || revoked {
			t.Fatalf("Redis stale RevokeIfCurrent() = (%t, %v), want no-op", revoked, err)
		}
		if got := plan367Target(t, backend, plan367Route(t, backend, "peer-redis")); got.Token != "token-second" {
			t.Fatalf("Redis stale revoke removed refresh: %#v", got)
		}
		plan367AssertPairCardinality(t, backend, 1, 1)

		_, cutover := plan367RedisBackend(t, "plan367-cutover-revoke:", plan367Config(
			"key-a", "test", map[string][]byte{"key-a": plan367Key('a')},
		))
		if err := cutover.RegisterToken("peer-cutover", "token-cutover", "android"); err != nil {
			t.Fatalf("legacy register: %v", err)
		}
		legacyLease := plan367Route(t, cutover, "peer-cutover")
		plan367Migrate(t, cutover)
		if revoked, err = cutover.RevokeIfCurrent(legacyLease); err != nil || !revoked {
			t.Fatalf("pre-CAS lease conditional revoke after cutover = (%t, %v), want exact revoke", revoked, err)
		}
		plan367AssertPairCardinality(t, cutover, 0, 0)

		_, refreshedCutover := plan367RedisBackend(t, "plan367-cutover-refresh:", plan367Config(
			"key-a", "test", map[string][]byte{"key-a": plan367Key('a')},
		))
		_ = refreshedCutover.RegisterToken("peer-cutover", "token-cutover", "android")
		preCAS := plan367Route(t, refreshedCutover, "peer-cutover")
		plan367Migrate(t, refreshedCutover)
		// Even an exact post-cutover refresh clears the retained source digest.
		if err := refreshedCutover.RegisterToken("peer-cutover", "token-cutover", "android"); err != nil {
			t.Fatalf("post-cutover exact refresh: %v", err)
		}
		if revoked, err = refreshedCutover.RevokeIfCurrent(preCAS); err != nil || revoked {
			t.Fatalf("pre-CAS lease after post-cutover refresh = (%t, %v), want no-op", revoked, err)
		}
		if got := plan367Target(t, refreshedCutover, plan367Route(t, refreshedCutover, "peer-cutover")); got.Token != "token-cutover" {
			t.Fatalf("post-cutover refresh was removed: %#v", got)
		}
		plan367AssertPairCardinality(t, refreshedCutover, 1, 1)
	})
}

type plan367UnregisterBackend struct {
	PushTokenBackend
	err     error
	entered chan struct{}
	release chan struct{}
	once    sync.Once
	peerID  string
}

func (b *plan367UnregisterBackend) UnregisterToken(peerID string) error {
	b.peerID = peerID
	if b.entered != nil {
		b.once.Do(func() { close(b.entered) })
	}
	if b.release != nil {
		<-b.release
	}
	if b.err != nil {
		return b.err
	}
	return b.PushTokenBackend.UnregisterToken(peerID)
}

func plan367ReadInboxResponse(reader io.Reader) (inboxResponse, error) {
	raw, err := readFrame(reader)
	if err != nil {
		return inboxResponse{}, err
	}
	var response inboxResponse
	if err := json.Unmarshal(raw, &response); err != nil {
		return inboxResponse{}, err
	}
	return response, nil
}

func plan367UnregisterRequest(t *testing.T, env *inboxStreamEnv) inboxResponse {
	t.Helper()
	stream, err := env.sender.NewStream(context.Background(), env.server.ID(), InboxProtocol)
	if err != nil {
		t.Fatalf("open unregister stream: %v", err)
	}
	defer stream.Close()
	sendInboxReq(t, stream, inboxRequest{Action: "unregister_token", To: env.recipient.ID().String()})
	return recvInboxResp(t, stream)
}

func TestRelayNotificationClosure_PushRouteExplicitUnregisterAcknowledgesOnlyAtomicDelete(t *testing.T) {
	t.Run("ACK waits for authenticated durable delete", func(t *testing.T) {
		store := newMemoryPushTokenStore()
		blocking := &plan367UnregisterBackend{
			PushTokenBackend: store,
			entered:          make(chan struct{}),
			release:          make(chan struct{}),
		}
		inbox := NewInboxStore(NewPushServiceWithBackend(blocking))
		env := setupInboxStreamEnv(t, inbox, NewGroupInboxStore(500, 0))
		authenticatedPeer := env.sender.ID().String()
		otherPeer := env.recipient.ID().String()
		_ = store.RegisterToken(authenticatedPeer, "authenticated-token", "android")
		_ = store.RegisterToken(otherPeer, "other-token", "android")
		inbox.RegisterWakeTokens(authenticatedPeer, []string{"wake-token"})

		stream, err := env.sender.NewStream(context.Background(), env.server.ID(), InboxProtocol)
		if err != nil {
			t.Fatalf("open unregister stream: %v", err)
		}
		defer stream.Close()
		sendInboxReq(t, stream, inboxRequest{Action: "unregister_token", To: otherPeer})
		responses := make(chan struct {
			response inboxResponse
			err      error
		}, 1)
		go func() {
			response, readErr := plan367ReadInboxResponse(stream)
			responses <- struct {
				response inboxResponse
				err      error
			}{response, readErr}
		}()
		select {
		case <-blocking.entered:
		case <-time.After(2 * time.Second):
			t.Fatal("unregister backend was not called")
		}
		select {
		case premature := <-responses:
			t.Fatalf("stream acknowledged before durable delete: response=%#v err=%v", premature.response, premature.err)
		case <-time.After(100 * time.Millisecond):
		}
		close(blocking.release)
		select {
		case result := <-responses:
			if result.err != nil || result.response.Status != "OK" || result.response.Error != "" {
				t.Fatalf("post-delete response=%#v err=%v, want OK", result.response, result.err)
			}
		case <-time.After(2 * time.Second):
			t.Fatal("no ACK after durable delete")
		}
		if blocking.peerID != authenticatedPeer {
			t.Fatalf("unregister peer = %q, want authenticated stream peer %q", blocking.peerID, authenticatedPeer)
		}
		if route, lookupErr := store.LookupRoute(authenticatedPeer); lookupErr != nil || route != nil {
			t.Fatalf("authenticated route after unregister = %#v err=%v", route, lookupErr)
		}
		if got := plan367Target(t, store, plan367Route(t, store, otherPeer)); got.Token != "other-token" {
			t.Fatalf("request-controlled peer was deleted: %#v", got)
		}
		if inbox.wakeTokens.HasRegisteredSet(authenticatedPeer) {
			t.Fatal("successful push unregister left orphaned wake authorization")
		}
	})

	t.Run("backend failure returns finite ERROR and preserves route", func(t *testing.T) {
		store := newMemoryPushTokenStore()
		failure := errors.New("durable delete unavailable")
		backend := &plan367UnregisterBackend{PushTokenBackend: store, err: failure}
		inbox := NewInboxStore(NewPushServiceWithBackend(backend))
		env := setupInboxStreamEnv(t, inbox, NewGroupInboxStore(500, 0))
		peerID := env.sender.ID().String()
		_ = store.RegisterToken(peerID, "token-preserved", "android")
		inbox.RegisterWakeTokens(peerID, []string{"wake-preserved"})
		response := plan367UnregisterRequest(t, env)
		if response.Status != "ERROR" || response.Error != "Push token deletion failed" {
			t.Fatalf("failure response = %#v, want finite deletion error", response)
		}
		if got := plan367Target(t, store, plan367Route(t, store, peerID)); got.Token != "token-preserved" {
			t.Fatalf("failed unregister changed route: %#v", got)
		}
		if !inbox.wakeTokens.HasRegisteredSet(peerID) {
			t.Fatal("failed push unregister cleared wake authorization")
		}
	})

	t.Run("encrypted Redis deletes exact pair atomically and propagates Redis failure", func(t *testing.T) {
		server, backend, _ := plan367NewEncryptedFixture(t, "plan367-unregister-redis:")
		inbox := NewInboxStore(NewPushServiceWithBackend(backend))
		env := setupInboxStreamEnv(t, inbox, NewGroupInboxStore(500, 0))
		peerID := env.sender.ID().String()
		plan367RegisterEncrypted(t, backend, peerID, "redis-token", "android")
		plan367AssertPairCardinality(t, backend, 1, 1)

		server.SetError("LOADING Redis is loading the dataset in memory")
		failed := plan367UnregisterRequest(t, env)
		server.SetError("")
		if failed.Status != "ERROR" || failed.Error != "Push token deletion failed" {
			t.Fatalf("Redis failure response = %#v", failed)
		}
		if got := plan367Target(t, backend, plan367Route(t, backend, peerID)); got.Token != "redis-token" {
			t.Fatalf("failed Redis unregister changed pair: %#v", got)
		}
		plan367AssertPairCardinality(t, backend, 1, 1)

		backend.encryptedDeleteBeforeCommit = func() error {
			return errors.New("injected atomic-delete precommit failure")
		}
		precommitFailed := plan367UnregisterRequest(t, env)
		if precommitFailed.Status != "ERROR" || precommitFailed.Error != "Push token deletion failed" {
			t.Fatalf("precommit failure response = %#v", precommitFailed)
		}
		if got := plan367Target(t, backend, plan367Route(t, backend, peerID)); got.Token != "redis-token" {
			t.Fatalf("precommit failure split encrypted pair: %#v", got)
		}
		plan367AssertPairCardinality(t, backend, 1, 1)
		backend.encryptedDeleteBeforeCommit = nil

		succeeded := plan367UnregisterRequest(t, env)
		if succeeded.Status != "OK" || succeeded.Error != "" {
			t.Fatalf("Redis success response = %#v", succeeded)
		}
		if route, err := backend.LookupRoute(peerID); err != nil || route != nil {
			t.Fatalf("Redis route after ACK = %#v err=%v", route, err)
		}
		plan367AssertPairCardinality(t, backend, 0, 0)
	})
}

func TestRelayNotificationClosure_PushRouteExplicitLegacyCleanupIsIdempotent(t *testing.T) {
	t.Run("refuses absent and migrating states", func(t *testing.T) {
		_, absent := plan367RedisBackend(t, "plan367-cleanup-absent:", plan367Config(
			"key-a", "test", map[string][]byte{"key-a": plan367Key('a')},
		))
		if err := absent.RegisterToken("peer-legacy", "legacy-token", "android"); err != nil {
			t.Fatalf("legacy register: %v", err)
		}
		before, _ := absent.client.Get(context.Background(), absent.key("peer-legacy")).Result()
		if err := absent.CleanupLegacy(); err == nil {
			t.Fatal("CleanupLegacy() succeeded before migration admission")
		}
		after, _ := absent.client.Get(context.Background(), absent.key("peer-legacy")).Result()
		if after != before {
			t.Fatalf("pre-marker cleanup changed legacy row: before=%q after=%q", before, after)
		}

		_, migrating := plan367RedisBackend(t, "plan367-cleanup-migrating:", plan367Config(
			"key-a", "test", map[string][]byte{"key-a": plan367Key('a')},
		))
		_ = migrating.RegisterToken("peer-legacy", "legacy-token", "android")
		pause := make(chan struct{})
		reached := make(chan struct{})
		migrating.migrationBeforeCutover = func(uint64) error {
			close(reached)
			<-pause
			return errors.New("stop before encrypted marker")
		}
		done := make(chan error, 1)
		go func() { done <- migrating.Migrate(plan367FleetReceipt) }()
		select {
		case <-reached:
		case <-time.After(3 * time.Second):
			t.Fatal("migration did not enter migrating state")
		}
		if err := migrating.CleanupLegacy(); err == nil {
			t.Fatal("CleanupLegacy() succeeded while marker was migrating")
		}
		if exists := migrating.client.Exists(context.Background(), migrating.key("peer-legacy")).Val(); exists != 1 {
			t.Fatalf("migrating cleanup removed legacy authority, EXISTS=%d", exists)
		}
		close(pause)
		if err := <-done; err == nil {
			t.Fatal("injected pre-cutover stop unexpectedly succeeded")
		}
	})

	t.Run("encrypted cleanup is bounded preserving and idempotent", func(t *testing.T) {
		_, backend := plan367RedisBackend(t, "plan367-cleanup:", plan367Config(
			"key-a", "test", map[string][]byte{"key-a": plan367Key('a')},
		))
		_ = backend.RegisterToken("peer-one", "token-one", "android")
		_ = backend.RegisterToken("peer-two", "token-two", "ios")
		plan367Migrate(t, backend)
		routeOne := plan367Route(t, backend, "peer-one")
		routeTwo := plan367Route(t, backend, "peer-two")
		ctx := context.Background()
		preserved := map[string]string{
			backend.prefix + "unrelated":                        "unrelated-value",
			backend.prefix + "push-not-a-legacy-row":            "similar-prefix-value",
			"other-prefix:push:" + encodeRedisComponent("peer"): "other-tenant-value",
		}
		for key, value := range preserved {
			if err := backend.client.Set(ctx, key, value, 0).Err(); err != nil {
				t.Fatalf("seed preserved key %q: %v", key, err)
			}
		}
		// Model remnants from every legacy peer, including one no longer present
		// in the encrypted directory. Cleanup is an explicit namespace operation.
		if err := backend.client.Set(ctx, backend.key("orphaned-legacy-peer"), `{"Token":"old"}`, 0).Err(); err != nil {
			t.Fatalf("seed legacy remnant: %v", err)
		}
		if got := len(plan367Keys(t, backend, backend.allPattern())); got != 3 {
			t.Fatalf("legacy rows before cleanup = %d, want 3", got)
		}
		markerBefore, _ := backend.client.Get(ctx, backend.markerKey()).Result()
		directoriesBefore := append([]string(nil), plan367Keys(t, backend, backend.prefix+"push-token-directory:*")...)
		vaultsBefore := append([]string(nil), plan367Keys(t, backend, backend.prefix+"push-token-vault:*")...)

		if err := backend.CleanupLegacy(); err != nil {
			t.Fatalf("first CleanupLegacy(): %v", err)
		}
		if got := plan367Keys(t, backend, backend.allPattern()); len(got) != 0 {
			t.Fatalf("legacy rows after cleanup = %#v", got)
		}
		for key, want := range preserved {
			if got, err := backend.client.Get(ctx, key).Result(); err != nil || got != want {
				t.Fatalf("cleanup changed preserved key %q: got=%q err=%v want=%q", key, got, err, want)
			}
		}
		markerAfter, _ := backend.client.Get(ctx, backend.markerKey()).Result()
		if markerAfter != markerBefore {
			t.Fatalf("cleanup changed encrypted marker: before=%q after=%q", markerBefore, markerAfter)
		}
		if got := plan367Keys(t, backend, backend.prefix+"push-token-directory:*"); !reflect.DeepEqual(got, directoriesBefore) {
			t.Fatalf("cleanup changed directories: before=%#v after=%#v", directoriesBefore, got)
		}
		if got := plan367Keys(t, backend, backend.prefix+"push-token-vault:*"); !reflect.DeepEqual(got, vaultsBefore) {
			t.Fatalf("cleanup changed vaults: before=%#v after=%#v", vaultsBefore, got)
		}
		if got := plan367Target(t, backend, routeOne); got.Token != "token-one" {
			t.Fatalf("peer one after cleanup = %#v", got)
		}
		if got := plan367Target(t, backend, routeTwo); got.Token != "token-two" {
			t.Fatalf("peer two after cleanup = %#v", got)
		}
		plan367AssertPairCardinality(t, backend, 2, 2)

		if err := backend.CleanupLegacy(); err != nil {
			t.Fatalf("second CleanupLegacy(): %v", err)
		}
		if got := plan367Keys(t, backend, backend.allPattern()); len(got) != 0 {
			t.Fatalf("idempotent cleanup recreated legacy rows: %#v", got)
		}
		plan367AssertPairCardinality(t, backend, 2, 2)
	})
}
