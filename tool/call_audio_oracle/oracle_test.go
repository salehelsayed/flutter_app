//go:build integration

package callaudiooracle

import (
	"context"
	"os"
	"path/filepath"
	"testing"
	"time"

	"go.uber.org/goleak"
)

func TestKnownOpusBothDirectionsOverRestAuthenticatedCoturn(t *testing.T) {
	defer goleak.VerifyNone(t, goleak.IgnoreCurrent())

	credentialsPath := requiredEnvironmentPath(
		t,
		"CALL_AUDIO_ORACLE_CREDENTIALS_FILE",
	)
	resultPath := requiredEnvironmentPath(t, "CALL_AUDIO_ORACLE_RESULT_FILE")
	moduleRoot, err := os.Getwd()
	if err != nil {
		t.Fatal("resolve oracle module root")
	}

	now := time.Now().UTC()
	credentials, err := LoadCredentialConfig(credentialsPath, now)
	if err != nil {
		t.Fatalf("load ephemeral TURN credentials: %v", err)
	}
	fixturePath := filepath.Clean(filepath.Join(
		moduleRoot,
		"..",
		"..",
		"test",
		"shared",
		"fixtures",
		"call",
		"known_signal_48khz_mono.ogg",
	))

	ctx, cancel := context.WithTimeout(context.Background(), 8*time.Minute)
	t.Cleanup(cancel)
	result, err := RunKnownOpusBothDirections(
		ctx,
		credentials,
		fixturePath,
		filepath.Join(moduleRoot, "coturn.lock.json"),
	)
	if err != nil {
		t.Fatalf("run relay-only known-Opus oracle: %v", err)
	}
	wantAuthoritySHA256, err := canonicalTurnAuthoritySHA256(
		credentials.TurnURL,
	)
	if err != nil {
		t.Fatal("canonicalize configured TURN authority")
	}
	if result.TurnAuthoritySHA256 != wantAuthoritySHA256 {
		t.Fatal("oracle result is not bound to its configured TURN authority")
	}
	if result.FixtureInstanceSHA256 != credentials.FixtureInstanceSHA256 {
		t.Fatal("oracle result is not bound to its coturn fixture instance")
	}
	if err := result.Validate(); err != nil {
		t.Fatalf("validate relay-only known-Opus oracle result: %v", err)
	}
	if err := WriteSanitizedResultExclusive(resultPath, result); err != nil {
		t.Fatalf("write sanitized oracle result: %v", err)
	}

	assertResultContainsNoCredentials(t, resultPath, credentials)
	t.Log("CALL_AUDIO_ORACLE_PASS result_schema=mknoon.call_audio_oracle.result.v1")
}

func requiredEnvironmentPath(t *testing.T, name string) string {
	t.Helper()
	value := os.Getenv(name)
	if value == "" {
		t.Fatalf("%s must point to an ephemeral private file", name)
	}
	return value
}

func assertResultContainsNoCredentials(
	t *testing.T,
	resultPath string,
	credentials CredentialConfig,
) {
	t.Helper()
	encoded, err := os.ReadFile(resultPath)
	if err != nil {
		t.Fatal("read sanitized oracle result")
	}
	for _, forbidden := range []string{
		credentials.TurnURL,
		credentials.PeerA.Username,
		credentials.PeerA.Password,
		credentials.PeerB.Username,
		credentials.PeerB.Password,
	} {
		if forbidden != "" && containsBytes(encoded, []byte(forbidden)) {
			t.Fatal("sanitized oracle result contains private invocation material")
		}
	}
}
