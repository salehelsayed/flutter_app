package callaudiooracle

import (
	"encoding/json"
	"errors"
	"os"
	"path/filepath"
	"reflect"
	"sort"
	"strconv"
	"testing"
	"time"
)

func TestLoadCredentialConfigRejectsRestSecretField(t *testing.T) {
	now := time.Unix(1_800_000_000, 0).UTC()
	valid := validCredentialDocument(now)
	encoded, err := json.Marshal(valid)
	if err != nil {
		t.Fatal(err)
	}
	var raw map[string]any
	if err := json.Unmarshal(encoded, &raw); err != nil {
		t.Fatal(err)
	}
	raw["rest_secret"] = "must-never-enter-the-oracle"
	path := writePrivateJSON(t, raw)

	_, err = LoadCredentialConfig(path, now)
	if !errors.Is(err, errCredentialDocument) {
		t.Fatalf("expected strict unknown-field rejection, got %v", err)
	}
}

func TestLoadCredentialConfigRequiresPrivateFreshDistinctBundles(t *testing.T) {
	now := time.Unix(1_800_000_000, 0).UTC()
	valid := validCredentialDocument(now)
	path := writePrivateJSON(t, valid)
	loaded, err := LoadCredentialConfig(path, now)
	if err != nil {
		t.Fatalf("load valid credentials: %v", err)
	}
	if !hasFixtureInstanceRuntimeProvenance(loaded) {
		t.Fatal("loaded credential omitted runtime fixture provenance")
	}
	loaded.fixtureInstanceSHA256Proof = ""
	if !reflect.DeepEqual(loaded, valid) {
		t.Fatal("loaded credential document changed")
	}

	if err := os.Chmod(path, 0o644); err != nil {
		t.Fatal(err)
	}
	if _, err := LoadCredentialConfig(path, now); !errors.Is(err, errPrivateFileRequired) {
		t.Fatalf("expected mode-0600 requirement, got %v", err)
	}

	duplicate := valid
	duplicate.PeerB = duplicate.PeerA
	duplicatePath := writePrivateJSON(t, duplicate)
	if _, err := LoadCredentialConfig(duplicatePath, now); !errors.Is(err, errCredentialFreshness) {
		t.Fatalf("expected distinct credential requirement, got %v", err)
	}

	expired := valid
	expired.PeerA.ExpiresAtUnixMs = now.Add(-time.Second).UnixMilli()
	expired.PeerA.Username = expiryUsername(expired.PeerA.ExpiresAtUnixMs, "a")
	expiredPath := writePrivateJSON(t, expired)
	if _, err := LoadCredentialConfig(expiredPath, now); !errors.Is(err, errCredentialFreshness) {
		t.Fatalf("expected freshness requirement, got %v", err)
	}

	missingInstance := valid
	missingInstance.FixtureInstanceSHA256 = ""
	missingInstancePath := writePrivateJSON(t, missingInstance)
	if _, err := LoadCredentialConfig(missingInstancePath, now); !errors.Is(err, errCredentialFreshness) {
		t.Fatalf("expected fixture-instance binding requirement, got %v", err)
	}

	uppercaseInstance := valid
	uppercaseInstance.FixtureInstanceSHA256 =
		"AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA"
	uppercaseInstancePath := writePrivateJSON(t, uppercaseInstance)
	if _, err := LoadCredentialConfig(uppercaseInstancePath, now); !errors.Is(err, errCredentialFreshness) {
		t.Fatalf("expected lowercase fixture-instance digest, got %v", err)
	}
}

func TestLoadedCredentialRejectsFixtureInstanceSubstitution(t *testing.T) {
	now := time.Unix(1_800_000_000, 0).UTC()
	path := writePrivateJSON(t, validCredentialDocument(now))
	loaded, err := LoadCredentialConfig(path, now)
	if err != nil {
		t.Fatalf("load valid credentials: %v", err)
	}
	loaded.FixtureInstanceSHA256 =
		"2222222222222222222222222222222222222222222222222222222222222222"
	if hasFixtureInstanceRuntimeProvenance(loaded) {
		t.Fatal("substituted credential retained runtime fixture provenance")
	}
}

func TestOracleResultRejectsDirectAndSingleDirectionMutations(t *testing.T) {
	base := completeOracleResult()
	mutations := map[string]func(*OracleResult){
		"direct route": func(result *OracleResult) {
			result.PeerARoute.RelaySelected = false
		},
		"single direction": func(result *OracleResult) {
			result.BToA.PayloadHashExact = false
		},
		"transport drift": func(result *OracleResult) {
			result.PeerBRoute.TransportMatch = false
		},
		"unclean shutdown": func(result *OracleResult) {
			result.CleanupComplete = false
		},
		"Pion drift": func(result *OracleResult) {
			result.PionVersion = "v4.2.20"
		},
		"TURN authority replay": func(result *OracleResult) {
			result.TurnAuthoritySHA256 =
				"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
		},
	}
	for name, mutate := range mutations {
		t.Run(name, func(t *testing.T) {
			candidate := base
			mutate(&candidate)
			if err := candidate.Validate(); !errors.Is(err, errResultIncomplete) {
				t.Fatalf("expected mutation rejection, got %v", err)
			}
		})
	}
}

func TestTurnAuthorityDigestUsesCanonicalCredentialURL(t *testing.T) {
	got, err := canonicalTurnAuthoritySHA256(
		"turn:LOCALHOST:3478?transport=udp",
	)
	if err != nil {
		t.Fatalf("canonicalize TURN URL: %v", err)
	}
	want := "c1bab0d1b228ff7200d890bd757271f2235fdce5b0a512663f242a3c463d825e"
	if got != want {
		t.Fatalf("TURN authority digest = %s, want %s", got, want)
	}
}

func TestOracleResultRejectsStaleSameURLDifferentFixtureInstance(t *testing.T) {
	current := completeOracleResult()
	stale := current
	stale.FixtureInstanceSHA256 =
		"2222222222222222222222222222222222222222222222222222222222222222"
	if stale.TurnAuthoritySHA256 != current.TurnAuthoritySHA256 ||
		!stale.coreProofComplete() || !stale.CleanupComplete || !stale.Passed {
		t.Fatal("stale-result fixture did not preserve its all-true same-URL proof")
	}
	if err := stale.Validate(); !errors.Is(err, errResultIncomplete) {
		t.Fatalf("stale same-URL result was not rejected: %v", err)
	}
}

func TestCommittedFixtureMatchesImmutableProvenance(t *testing.T) {
	fixture, err := loadKnownFixture(committedFixturePath(t))
	if err != nil {
		t.Fatalf("load committed fixture: %v", err)
	}
	if len(fixture.payloads) == 0 || !validLowerHexSHA256(fixture.fileDigestHex) {
		t.Fatal("committed fixture proof is incomplete")
	}

	reversed := clonePayloads(fixture.payloads)
	for left, right := 0, len(reversed)-1; left < right; left, right = left+1, right-1 {
		reversed[left], reversed[right] = reversed[right], reversed[left]
	}
	if hashPayloadSequence(reversed) == fixture.payloadDigest {
		t.Fatal("payload order mutation did not change sequence digest")
	}
}

func TestWriteSanitizedResultIsExclusivePrivateAllowlist(t *testing.T) {
	result := completeOracleResult()
	path := filepath.Join(t.TempDir(), "result.json")
	if err := WriteSanitizedResultExclusive(path, result); err != nil {
		t.Fatalf("write result: %v", err)
	}
	info, err := os.Stat(path)
	if err != nil {
		t.Fatal(err)
	}
	if info.Mode().Perm() != 0o600 {
		t.Fatalf("result mode = %o, want 600", info.Mode().Perm())
	}
	if err := WriteSanitizedResultExclusive(path, result); !errors.Is(err, errResultFile) {
		t.Fatalf("expected exclusive-create rejection, got %v", err)
	}
	encoded, err := os.ReadFile(path)
	if err != nil {
		t.Fatal(err)
	}
	var document map[string]any
	if err := json.Unmarshal(encoded, &document); err != nil {
		t.Fatal(err)
	}
	got := make([]string, 0, len(document))
	for key := range document {
		got = append(got, key)
	}
	sort.Strings(got)
	want := []string{
		"a_to_b",
		"b_to_a",
		"cleanup_complete",
		"coturn",
		"expected_transport",
		"fixture_instance_sha256",
		"fixture_sha256",
		"passed",
		"peer_a_route",
		"peer_b_route",
		"pion_version",
		"schema",
		"turn_authority_sha256",
		"version",
	}
	if !reflect.DeepEqual(got, want) {
		t.Fatalf("durable result keys = %v, want %v", got, want)
	}
}

func validCredentialDocument(now time.Time) CredentialConfig {
	expiresAt := now.Add(10 * time.Minute).UnixMilli()
	return CredentialConfig{
		Schema:                credentialSchema,
		TurnURL:               "turn:127.0.0.1:3478?transport=udp",
		ExpectedTransport:     "udp",
		FixtureInstanceSHA256: "1111111111111111111111111111111111111111111111111111111111111111",
		PeerA: EphemeralCredential{
			Username:        expiryUsername(expiresAt, "a"),
			Password:        "credential-a",
			IssuedAtUnixMs:  now.UnixMilli(),
			ExpiresAtUnixMs: expiresAt,
		},
		PeerB: EphemeralCredential{
			Username:        expiryUsername(expiresAt, "b"),
			Password:        "credential-b",
			IssuedAtUnixMs:  now.UnixMilli(),
			ExpiresAtUnixMs: expiresAt,
		},
	}
}

func expiryUsername(expiresAtUnixMs int64, suffix string) string {
	return strconv.FormatInt(time.UnixMilli(expiresAtUnixMs).Unix(), 10) + ":" + suffix
}

func writePrivateJSON(t *testing.T, value any) string {
	t.Helper()
	path := filepath.Join(t.TempDir(), "credentials.json")
	file, err := os.OpenFile(path, os.O_CREATE|os.O_EXCL|os.O_WRONLY, 0o600)
	if err != nil {
		t.Fatal(err)
	}
	if err := json.NewEncoder(file).Encode(value); err != nil {
		_ = file.Close()
		t.Fatal(err)
	}
	if err := file.Close(); err != nil {
		t.Fatal(err)
	}
	return path
}

func completeOracleResult() OracleResult {
	direction := DirectionResult{
		CodecValid:        true,
		PayloadCountExact: true,
		PayloadOrderExact: true,
		PayloadHashExact:  true,
	}
	route := RouteResult{RelaySelected: true, TransportMatch: true}
	return OracleResult{
		Schema:        resultSchema,
		Version:       resultVersion,
		Passed:        true,
		PionVersion:   pionVersion,
		FixtureSHA256: knownFixtureSHA256,
		Coturn: CoturnDependency{
			Image:  lockedCoturnImage,
			Digest: lockedCoturnDigest,
		},
		ExpectedTransport:          "udp",
		TurnAuthoritySHA256:        "c1bab0d1b228ff7200d890bd757271f2235fdce5b0a512663f242a3c463d825e",
		turnAuthoritySHA256Proof:   "c1bab0d1b228ff7200d890bd757271f2235fdce5b0a512663f242a3c463d825e",
		FixtureInstanceSHA256:      "1111111111111111111111111111111111111111111111111111111111111111",
		fixtureInstanceSHA256Proof: "1111111111111111111111111111111111111111111111111111111111111111",
		AToB:                       direction,
		BToA:                       direction,
		PeerARoute:                 route,
		PeerBRoute:                 route,
		CleanupComplete:            true,
	}
}

func committedFixturePath(t *testing.T) string {
	t.Helper()
	moduleRoot, err := os.Getwd()
	if err != nil {
		t.Fatal(err)
	}
	return filepath.Clean(filepath.Join(
		moduleRoot,
		"..",
		"..",
		"test",
		"shared",
		"fixtures",
		"call",
		"known_signal_48khz_mono.ogg",
	))
}
