//go:build integration

package main

import (
	"bytes"
	"encoding/base64"
	"encoding/json"
	"os"
	"path/filepath"
	"reflect"
	"strings"
	"testing"

	"github.com/alicebob/miniredis/v2"
)

// redisPushRouteDTO is the complete process-boundary representation of the
// package-private lease. In particular, lookupKey and legacyDigest must survive
// the handoff: reconstructing a route from its public projection would make a
// stale revoke vacuously fail instead of exercising the persisted generation.
type redisPushRouteDTO struct {
	Handle       string   `json:"handle"`
	Generation   uint64   `json:"generation"`
	Capabilities []string `json:"capabilities"`
	LookupKey    string   `json:"lookupKey"`
	LegacyDigest [32]byte `json:"legacyDigest"`
}

func redisPushRouteDTOFromLease(route *pushRouteLease) *redisPushRouteDTO {
	if route == nil {
		return nil
	}
	return &redisPushRouteDTO{
		Handle:       route.Handle,
		Generation:   route.Generation,
		Capabilities: append([]string(nil), route.Capabilities...),
		LookupKey:    route.lookupKey,
		LegacyDigest: route.legacyDigest,
	}
}

func (route *redisPushRouteDTO) lease() pushRouteLease {
	return pushRouteLease{
		Handle:       route.Handle,
		Generation:   route.Generation,
		Capabilities: append([]string(nil), route.Capabilities...),
		lookupKey:    route.LookupKey,
		legacyDigest: route.LegacyDigest,
	}
}

func TestRedisPushRouteVaultEncryptedStateSurvivesProcessHandoff(t *testing.T) {
	server := miniredis.RunT(t)
	keyringFile := writeRedisProcessPushKeyring(t)

	base := redisHelperRequest{
		RedisURL:                "redis://" + server.Addr(),
		RedisPrefix:             "push-vault-process:",
		PeerID:                  "peer-process-recipient",
		PushTokenKeyringFile:    keyringFile,
		PushTokenActiveKeyID:    "retained-key",
		PushProviderEnvironment: "production-eu",
		FleetReceiptSHA256:      strings.Repeat("a", 64),
	}

	migrated := runRedisHelper(t, withOp(base, "migrate_push_vault", nil))
	if migrated.State != "encrypted" {
		t.Fatalf("empty-vault migration state = %q, want encrypted", migrated.State)
	}

	const (
		predecessorToken = "provider-token-from-process-a"
		successorToken   = "provider-token-from-process-c"
	)
	processA := runRedisHelper(t, withOp(base, "register_push_route", func(req *redisHelperRequest) {
		req.Token = predecessorToken
		req.Platform = "android"
		req.Capabilities = []string{directReactionCapability}
	}))
	assertRedisProcessRoute(t, "process A encrypted registration", processA.Route)
	assertRedisProcessVaultKeyID(t, server, base.RedisPrefix, base.PushTokenActiveKeyID)

	// Process B changes the active key but retains process A's key in the same
	// keyring. Resolving the exact persisted lease proves retained-key decrypt
	// (and permits lazy rewrap) without changing its handle or generation.
	currentKeyBase := base
	currentKeyBase.PushTokenActiveKeyID = "active-key"
	processB := runRedisHelper(t, withOp(currentKeyBase, "lookup_resolve_push_route", nil))
	assertRedisProcessResolvedTarget(
		t,
		"process B retained-key resolve",
		processB,
		predecessorToken,
		"android",
	)
	if !reflect.DeepEqual(processB.Route, processA.Route) {
		t.Fatalf("process B route = %#v, want process A exact route %#v", processB.Route, processA.Route)
	}
	assertRedisProcessVaultKeyID(t, server, base.RedisPrefix, currentKeyBase.PushTokenActiveKeyID)

	// Process C refreshes to a different provider token. The successor is a new
	// persisted generation/handle and the predecessor vault row must disappear
	// atomically.
	processC := runRedisHelper(t, withOp(currentKeyBase, "register_push_route", func(req *redisHelperRequest) {
		req.Token = successorToken
		req.Platform = "android"
		req.Capabilities = []string{directReactionCapability}
	}))
	assertRedisProcessRoute(t, "process C successor refresh", processC.Route)
	if processC.Route.Handle == processB.Route.Handle {
		t.Fatalf("successor refresh retained predecessor handle %q", processC.Route.Handle)
	}
	if processC.Route.Generation != processB.Route.Generation+1 {
		t.Fatalf(
			"successor generation = %d, want predecessor %d + 1",
			processC.Route.Generation,
			processB.Route.Generation,
		)
	}

	staleRevocation := runRedisHelper(t, withOp(currentKeyBase, "revoke_push_route", func(req *redisHelperRequest) {
		req.Route = processB.Route
	}))
	if staleRevocation.Revoked {
		t.Fatal("stale process-B lease revoked the process-C successor")
	}

	final := runRedisHelper(t, withOp(currentKeyBase, "lookup_resolve_push_route", nil))
	assertRedisProcessResolvedTarget(
		t,
		"final successor resolve",
		final,
		successorToken,
		"android",
	)
	if !reflect.DeepEqual(final.Route, processC.Route) {
		t.Fatalf("final route = %#v, want process C exact successor %#v", final.Route, processC.Route)
	}

	stats := runRedisHelper(t, withOp(currentKeyBase, "push_route_stats", nil))
	if stats.Count != 1 || stats.PlatformCounts["android"] != 1 || len(stats.PlatformCounts) != 1 {
		t.Fatalf("final aggregate stats = count %d platforms %#v, want one android route", stats.Count, stats.PlatformCounts)
	}

	assertRedisProcessPushVaultCardinality(
		t,
		server,
		base.RedisPrefix,
		final.Route,
		currentKeyBase.PushTokenActiveKeyID,
		currentKeyBase.PushProviderEnvironment,
		predecessorToken,
		successorToken,
	)
}

func writeRedisProcessPushKeyring(t *testing.T) string {
	t.Helper()
	keyring := struct {
		Version int               `json:"version"`
		Keys    map[string]string `json:"keys"`
	}{
		Version: 1,
		Keys: map[string]string{
			"retained-key": base64.StdEncoding.EncodeToString(bytes.Repeat([]byte{0x41}, 32)),
			"active-key":   base64.StdEncoding.EncodeToString(bytes.Repeat([]byte{0x52}, 32)),
		},
	}
	payload, err := json.Marshal(keyring)
	if err != nil {
		t.Fatalf("marshal process keyring: %v", err)
	}
	path := filepath.Join(t.TempDir(), "push-token-keyring.json")
	if err := os.WriteFile(path, payload, 0o600); err != nil {
		t.Fatalf("write process keyring: %v", err)
	}
	return path
}

func assertRedisProcessRoute(t *testing.T, label string, route *redisPushRouteDTO) {
	t.Helper()
	if route == nil || route.Handle == "" || route.Generation == 0 || route.LookupKey == "" {
		t.Fatalf("%s returned incomplete exact route DTO: %#v", label, route)
	}
	if route.LegacyDigest != ([32]byte{}) {
		t.Fatalf("%s retained a legacy digest after encrypted registration: %#v", label, route.LegacyDigest)
	}
	if !reflect.DeepEqual(route.Capabilities, []string{directReactionCapability}) {
		t.Fatalf("%s capabilities = %#v, want exact reaction capability", label, route.Capabilities)
	}
}

func assertRedisProcessResolvedTarget(
	t *testing.T,
	label string,
	response redisHelperResponse,
	wantToken string,
	wantPlatform string,
) {
	t.Helper()
	assertRedisProcessRoute(t, label, response.Route)
	if response.Token != wantToken || response.Platform != wantPlatform {
		t.Fatalf(
			"%s target = token %q platform %q, want token %q platform %q",
			label,
			response.Token,
			response.Platform,
			wantToken,
			wantPlatform,
		)
	}
}

func assertRedisProcessVaultKeyID(
	t *testing.T,
	server *miniredis.Miniredis,
	prefix string,
	wantKeyID string,
) {
	t.Helper()
	var vaultKeys []string
	for _, key := range server.Keys() {
		if strings.HasPrefix(key, prefix+"push-token-vault:") {
			vaultKeys = append(vaultKeys, key)
		}
	}
	if len(vaultKeys) != 1 {
		t.Fatalf("vault keys = %v, want exactly one for key-id check", vaultKeys)
	}
	payload, err := server.Get(vaultKeys[0])
	if err != nil {
		t.Fatalf("read vault envelope for key-id check: %v", err)
	}
	envelope, err := decodePushTokenVaultEnvelope([]byte(payload))
	if err != nil || envelope.KeyID != wantKeyID {
		t.Fatalf("vault envelope = %#v error %v, want key %q", envelope, err, wantKeyID)
	}
}

func assertRedisProcessPushVaultCardinality(
	t *testing.T,
	server *miniredis.Miniredis,
	prefix string,
	finalRoute *redisPushRouteDTO,
	wantKeyID string,
	wantProviderEnvironment string,
	forbiddenTokens ...string,
) {
	t.Helper()
	markerPayload, err := server.Get(prefix + "push-token-state")
	if err != nil {
		t.Fatalf("read encrypted state marker: %v", err)
	}
	marker, err := decodePushTokenStateMarker([]byte(markerPayload))
	if err != nil || marker.State != pushTokenStateEncrypted {
		t.Fatalf("final marker = %#v error %v, want encrypted", marker, err)
	}

	var directoryKeys, vaultKeys, legacyKeys []string
	for _, key := range server.Keys() {
		switch {
		case strings.HasPrefix(key, prefix+"push-token-directory:"):
			directoryKeys = append(directoryKeys, key)
		case strings.HasPrefix(key, prefix+"push-token-vault:"):
			vaultKeys = append(vaultKeys, key)
		case strings.HasPrefix(key, prefix+"push:"):
			legacyKeys = append(legacyKeys, key)
		}
	}
	if len(directoryKeys) != 1 || len(vaultKeys) != 1 || len(legacyKeys) != 0 {
		t.Fatalf(
			"encrypted cardinality = directory %v vault %v legacy %v, want one/one/zero",
			directoryKeys,
			vaultKeys,
			legacyKeys,
		)
	}
	if want := prefix + "push-token-vault:" + finalRoute.Handle; vaultKeys[0] != want {
		t.Fatalf("successor vault key = %q, want exact handle key %q", vaultKeys[0], want)
	}
	directoryPayload, err := server.Get(directoryKeys[0])
	if err != nil {
		t.Fatalf("read successor directory: %v", err)
	}
	directory, err := decodePushTokenDirectoryRecord([]byte(directoryPayload))
	if err != nil {
		t.Fatalf("decode successor directory: %v", err)
	}
	if directory.Handle != finalRoute.Handle ||
		directory.Generation != finalRoute.Generation ||
		directory.ProviderEnvironment != wantProviderEnvironment {
		t.Fatalf("successor directory = %#v, want exact final route/environment", directory)
	}
	vaultPayload, err := server.Get(vaultKeys[0])
	if err != nil {
		t.Fatalf("read successor vault: %v", err)
	}
	envelope, err := decodePushTokenVaultEnvelope([]byte(vaultPayload))
	if err != nil || envelope.KeyID != wantKeyID {
		t.Fatalf("successor vault envelope = %#v error %v, want key %q", envelope, err, wantKeyID)
	}
	for _, key := range append(directoryKeys, vaultKeys...) {
		value, err := server.Get(key)
		if err != nil {
			t.Fatalf("read encrypted state key %q: %v", key, err)
		}
		for _, token := range forbiddenTokens {
			if strings.Contains(value, token) {
				t.Fatalf("encrypted state key %q exposed provider token", key)
			}
		}
	}
}
